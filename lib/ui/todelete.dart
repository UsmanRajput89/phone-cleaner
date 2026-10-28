import 'package:flutter/material.dart';

import '../app/controller.dart';
import '../app/format.dart';
import '../app/theme.dart';
import '../core/models.dart';
import 'media.dart';
import 'soft.dart';

/// Everything that was moved to the ToDelete folder. Tap a tile to restore it,
/// or long press to select several to restore or delete permanently.
class ToDeletePage extends StatefulWidget {
  final ValueChanged<bool> onSelectionChanged;

  const ToDeletePage({super.key, required this.onSelectionChanged});

  @override
  State<ToDeletePage> createState() => _ToDeletePageState();
}

class _ToDeletePageState extends State<ToDeletePage> {
  static const int pageSize = 60;

  final List<FileEntry> _items = [];
  final Map<String, int> _sizes = {};
  final Set<String> _selected = {};
  final ScrollController _scroll = ScrollController();

  String _filter = 'all';
  bool _loading = false;
  bool _more = true;
  bool _working = false;
  int _done = 0;
  int _workTotal = 0;
  int _count = 0;
  int _bytes = 0;

  bool get _selecting => _selected.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 600) {
        _load();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(reset: true));
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  FileQuery get _query {
    List<Kind> kinds;
    switch (_filter) {
      case 'photos':
        kinds = const [Kind.image];
        break;
      case 'videos':
        kinds = const [Kind.video];
        break;
      case 'files':
        kinds = const [Kind.other];
        break;
      default:
        kinds = const [Kind.image, Kind.video, Kind.other];
    }
    return FileQuery(
      status: Status.todelete,
      kinds: kinds,
      sort: SortMode.newest,
      limit: pageSize,
    );
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    if (!reset && !_more) return;
    _loading = true;
    final c = AppScope.read(context);
    final q = _query;
    if (reset) {
      _items.clear();
      _selected.clear();
      _more = true;
      widget.onSelectionChanged(false);
    }
    final rows = await c.store.query(q.copyWith(offset: _items.length));
    final count = await c.store.count(q);
    final bytes = await c.store.sumSize(q);
    _loading = false;
    if (!mounted) return;
    setState(() {
      _items.addAll(rows);
      for (final e in rows) {
        _sizes[e.path] = e.size;
      }
      _more = rows.length == pageSize;
      _count = count;
      _bytes = bytes;
    });
  }

  void _toggle(FileEntry e) {
    setState(() {
      if (!_selected.remove(e.path)) _selected.add(e.path);
    });
    widget.onSelectionChanged(_selected.isNotEmpty);
  }

  void _clear() {
    setState(_selected.clear);
    widget.onSelectionChanged(false);
  }

  Future<void> _selectAll() async {
    final c = AppScope.read(context);
    final all = await c.store.query(_query.copyWith(limit: 200000, offset: 0));
    if (!mounted) return;
    setState(() {
      for (final e in all) {
        _selected.add(e.path);
        _sizes[e.path] = e.size;
      }
    });
    widget.onSelectionChanged(_selected.isNotEmpty);
  }

  int get _selectedBytes {
    var sum = 0;
    for (final path in _selected) {
      sum += _sizes[path] ?? 0;
    }
    return sum;
  }

  Future<void> _restoreOne(FileEntry e) async {
    final c = AppScope.read(context);
    try {
      final newPath = await c.restoreEntry(e);
      if (!mounted) return;
      setState(() {
        _items.removeWhere((x) => x.path == e.path);
        _count = _count > 0 ? _count - 1 : 0;
        _bytes = _bytes >= e.size ? _bytes - e.size : 0;
      });
      c.refreshCountsSoon();
      showSoftSnack(
        context,
        'Restored ${e.name}',
        actionLabel: 'Undo',
        onAction: () async {
          final back = e.copyWith(path: newPath, status: Status.kept);
          try {
            await c.moveToTrash(back);
          } catch (_) {}
          c.refreshCountsSoon();
          if (mounted) _load(reset: true);
        },
      );
    } catch (_) {
      if (mounted) showSoftSnack(context, 'Could not restore that file');
    }
  }

  /// Runs [action] on every entry of [targets] with progress, then reloads.
  Future<void> _runBatch(
    List<FileEntry> targets,
    Future<bool> Function(AppController c, FileEntry e) action,
    String verb,
  ) async {
    final c = AppScope.read(context);
    setState(() {
      _working = true;
      _done = 0;
      _workTotal = targets.length;
    });
    var ok = 0;
    var failed = 0;
    for (final e in targets) {
      try {
        if (await action(c, e)) {
          ok++;
        } else {
          failed++;
        }
      } catch (_) {
        failed++;
      }
      _done++;
      if (mounted && _done % 10 == 0) setState(() {});
    }
    if (!mounted) return;
    setState(() => _working = false);
    c.refreshCountsSoon();
    showSoftSnack(
      context,
      failed == 0 ? '$verb $ok files' : '$verb $ok files, $failed failed',
    );
    await _load(reset: true);
  }

  Future<List<FileEntry>> _selectedEntries() async {
    final c = AppScope.read(context);
    final all = await c.store.query(_query.copyWith(limit: 200000, offset: 0));
    return all.where((e) => _selected.contains(e.path)).toList();
  }

  Future<void> _restoreSelected() async {
    if (_working || _selected.isEmpty) return;
    final targets = await _selectedEntries();
    if (!mounted) return;
    await _runBatch(targets, (c, e) async {
      await c.restoreEntry(e);
      return true;
    }, 'Restored');
  }

  Future<void> _deleteSelected() async {
    if (_working || _selected.isEmpty) return;
    final targets = await _selectedEntries();
    if (!mounted) return;
    final sum = targets.fold<int>(0, (a, e) => a + e.size);
    final yes = await confirmPermanentDelete(context, targets.length, sum);
    if (!yes || !mounted) return;
    await _runBatch(targets, (c, e) => c.deleteFromTrash(e), 'Deleted');
  }

  Future<void> _emptyAll() async {
    if (_working) return;
    final c = AppScope.read(context);
    final targets = await c.store.query(const FileQuery(
      status: Status.todelete,
      limit: 1000000,
    ));
    if (!mounted || targets.isEmpty) return;
    final sum = targets.fold<int>(0, (a, e) => a + e.size);
    final yes = await confirmPermanentDelete(context, targets.length, sum,
        everything: true);
    if (!yes || !mounted) return;
    await _runBatch(targets, (c, e) => c.deleteFromTrash(e), 'Deleted');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.soft;
    final selecting = _selecting;
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 56,
                child: Row(
                  children: [
                    if (selecting) ...[
                      SoftIconButton(
                        icon: Icons.close_rounded,
                        label: 'Clear selection',
                        onTap: _working ? null : _clear,
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Text(
                        selecting
                            ? '${formatInt(_selected.length)} selected'
                            : 'ToDelete',
                        style: ts(context, selecting ? 18 : 22,
                            weight:
                                selecting ? FontWeight.w500 : FontWeight.w400),
                      ),
                    ),
                    SoftTap(
                      label: selecting ? 'Select all' : 'Empty ToDelete',
                      onTap: _working
                          ? null
                          : (selecting ? _selectAll : _emptyAll),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 12),
                        child: Text(selecting ? 'Select all' : 'Empty',
                            style: ts(context, 14,
                                weight: FontWeight.w500,
                                color: selecting ? p.accent : p.remove)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(formatInt(_count),
                      style: ts(context, 44,
                          weight: FontWeight.w300, color: p.remove, height: 1.1)),
                  const SizedBox(width: 10),
                  Text('files · ${formatBytes(_bytes)}',
                      style: ts(context, 14, color: p.muted)),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: pressedDeco(p),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded, size: 22, color: p.accent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Tap a file to restore it. Long press to select several '
                        'to restore or delete for good. You can also delete from '
                        'the Gallery album or the Files app.',
                        style: ts(context, 13, color: p.muted, height: 1.45),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 56,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  children: [
                    for (final f in const [
                      ['all', 'All'],
                      ['photos', 'Photos'],
                      ['videos', 'Videos'],
                      ['files', 'Files'],
                    ]) ...[
                      SoftChip(
                        label: f[1],
                        selected: _filter == f[0],
                        onTap: () {
                          if (_filter == f[0]) return;
                          setState(() => _filter = f[0]);
                          _load(reset: true);
                        },
                      ),
                      const SizedBox(width: 12),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: _items.isEmpty && !_loading && !_more
                    ? Center(
                        child: Text('Nothing in ToDelete',
                            style: ts(context, 15, color: p.muted)),
                      )
                    : GridView.builder(
                        controller: _scroll,
                        padding: EdgeInsets.only(
                            top: 6, bottom: selecting ? 150 : 110),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                        ),
                        itemCount: _items.length,
                        itemBuilder: (context, i) {
                          final e = _items[i];
                          final sel = _selected.contains(e.path);
                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _working
                                ? null
                                : (selecting ? () => _toggle(e) : () => _restoreOne(e)),
                            onLongPress: _working ? null : () => _toggle(e),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Container(
                                  decoration: e.kind == Kind.other
                                      ? pressedDeco(p)
                                      : raisedDeco(p),
                                  clipBehavior: Clip.antiAlias,
                                  child: MediaThumb(entry: e, cacheWidth: 260),
                                ),
                                if (sel)
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(20),
                                          border: Border.all(
                                              color: p.remove, width: 3),
                                        ),
                                      ),
                                    ),
                                  ),
                                if (sel)
                                  Positioned(
                                    top: 6,
                                    right: 6,
                                    child: Container(
                                      width: 24,
                                      height: 24,
                                      decoration: BoxDecoration(
                                        color: p.remove,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(Icons.check_rounded,
                                          size: 16, color: p.bg),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        if (selecting || _working)
          Positioned(left: 24, right: 24, bottom: 20, child: _bar(context)),
      ],
    );
  }

  Widget _bar(BuildContext context) {
    final p = context.soft;
    if (_working) {
      return Container(
        height: 56,
        alignment: Alignment.center,
        decoration: raisedDeco(p, radius: 28),
        child: Text('Working... $_done / $_workTotal',
            style: ts(context, 15, color: p.muted)),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SoftPill(
          label: 'Restore ${formatInt(_selected.length)}',
          icon: Icons.restore_rounded,
          color: p.keep,
          height: 52,
          onTap: _restoreSelected,
        ),
        const SizedBox(height: 10),
        SoftPill(
          label:
              'Delete ${formatInt(_selected.length)} permanently · ${formatBytes(_selectedBytes)}',
          icon: Icons.delete_outline_rounded,
          color: p.remove,
          height: 52,
          onTap: _deleteSelected,
        ),
      ],
    );
  }
}

/// Asks for confirmation before permanent delete. The user has to HOLD the
/// button for about a second, so a stray tap cannot delete anything.
Future<bool> confirmPermanentDelete(BuildContext context, int count, int bytes,
    {bool everything = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (_) => _DeleteDialog(count: count, bytes: bytes, everything: everything),
  );
  return r == true;
}

class _DeleteDialog extends StatelessWidget {
  final int count;
  final int bytes;
  final bool everything;

  const _DeleteDialog({
    required this.count,
    required this.bytes,
    required this.everything,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.soft;
    return Dialog(
      backgroundColor: p.bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(color: p.ring),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(everything ? 'Empty ToDelete?' : 'Delete permanently?',
                style: ts(context, 22)),
            const SizedBox(height: 10),
            Text(
              '${formatInt(count)} files · ${formatBytes(bytes)} will be deleted '
              'for good. There is no recycle bin and this cannot be undone. '
              'Deleted WhatsApp media can no longer be opened from its chat.',
              style: ts(context, 14, color: p.muted, height: 1.45),
            ),
            const SizedBox(height: 22),
            _HoldButton(
              label: 'Hold to delete',
              onConfirmed: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: 12),
            SoftPill(
              label: 'Cancel',
              color: p.muted,
              onTap: () => Navigator.of(context).pop(false),
            ),
          ],
        ),
      ),
    );
  }
}

class _HoldButton extends StatefulWidget {
  final String label;
  final VoidCallback onConfirmed;

  const _HoldButton({required this.label, required this.onConfirmed});

  @override
  State<_HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<_HoldButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool _fired = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100));
    _ctrl.addListener(() => setState(() {}));
    _ctrl.addStatusListener((s) {
      if (s == AnimationStatus.completed && !_fired) {
        _fired = true;
        widget.onConfirmed();
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.soft;
    return Listener(
      onPointerDown: (_) => _ctrl.forward(),
      onPointerUp: (_) {
        if (!_fired) _ctrl.reverse();
      },
      onPointerCancel: (_) {
        if (!_fired) _ctrl.reverse();
      },
      child: Semantics(
        button: true,
        label: widget.label,
        child: Container(
          height: 52,
          alignment: Alignment.center,
          decoration: raisedDeco(p, radius: 26),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            alignment: Alignment.center,
            fit: StackFit.expand,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: _ctrl.value,
                  child: Container(color: p.pressed),
                ),
              ),
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.delete_outline_rounded,
                        size: 20, color: p.remove),
                    const SizedBox(width: 8),
                    Text(widget.label,
                        style: ts(context, 16,
                            weight: FontWeight.w500, color: p.remove)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
