import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as pth;

import '../app/controller.dart';
import '../app/format.dart';
import '../app/theme.dart';
import '../core/classify.dart';
import '../core/models.dart';
import '../native.dart';
import 'soft.dart';

/// List mode: documents, PDFs, APKs, zips and everything that is not a photo
/// or video. Select many, then move them to ToDelete (or keep them) in one go.
class FilesPage extends StatefulWidget {
  final ValueChanged<bool> onSelectionChanged;

  const FilesPage({super.key, required this.onSelectionChanged});

  @override
  State<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends State<FilesPage> {
  static const int pageSize = 50;

  final List<FileEntry> _items = [];
  final Set<String> _selected = {};
  final ScrollController _scroll = ScrollController();

  String _filter = 'all';
  String _sort = 'largest';
  bool _loading = false;
  bool _more = true;
  bool _working = false;
  int _done = 0;
  int _totalCount = 0;

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

  FileQuery _query(AppController c) {
    List<String>? exts;
    List<String>? notExts;
    if (_filter == 'other') {
      notExts = extGroups.values.expand((e) => e).toList();
    } else if (_filter != 'all' && _filter != 'dups') {
      exts = extGroups[_filter];
    }
    return FileQuery(
      kinds: const [Kind.other],
      buckets: Bucket.values
          .where((b) => b != Bucket.whatsapp || c.includeWhatsApp)
          .toList(),
      exts: exts,
      notExts: notExts,
      sort: _sort == 'oldest' ? SortMode.oldest : SortMode.largest,
      duplicatesOnly: _filter == 'dups',
      limit: pageSize,
    );
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    if (!reset && !_more) return;
    _loading = true;
    final c = AppScope.read(context);
    final q = _query(c);
    if (reset) {
      _items.clear();
      _selected.clear();
      _more = true;
      widget.onSelectionChanged(false);
    }
    final rows = await c.store.query(q.copyWith(offset: _items.length));
    final total = await c.store.count(q);
    _loading = false;
    if (!mounted) return;
    setState(() {
      _items.addAll(rows);
      _more = rows.length == pageSize;
      _totalCount = total;
    });
  }

  void _toggle(FileEntry e) {
    setState(() {
      if (!_selected.remove(e.path)) _selected.add(e.path);
    });
    widget.onSelectionChanged(_selected.isNotEmpty);
  }

  void _selectAll() {
    setState(() => _selected.addAll(_items.map((e) => e.path)));
    widget.onSelectionChanged(_selected.isNotEmpty);
  }

  /// In Duplicates view: selects every copy except the first of each group, so
  /// one copy always stays.
  void _selectExtras() {
    final seen = <String>{};
    setState(() {
      for (final e in _items) {
        final key = '${e.size}|${e.name}';
        if (!seen.add(key)) _selected.add(e.path);
      }
    });
    widget.onSelectionChanged(_selected.isNotEmpty);
  }

  void _clear() {
    setState(_selected.clear);
    widget.onSelectionChanged(false);
  }

  int get _selectedBytes {
    var sum = 0;
    for (final e in _items) {
      if (_selected.contains(e.path)) sum += e.size;
    }
    return sum;
  }

  Future<void> _apply({required bool move}) async {
    if (_working || _selected.isEmpty) return;
    final c = AppScope.read(context);
    final targets = _items.where((e) => _selected.contains(e.path)).toList();
    setState(() {
      _working = true;
      _done = 0;
    });
    final handled = <String>{};
    var failed = 0;
    for (final e in targets) {
      try {
        if (move) {
          await c.moveToTrash(e);
        } else {
          await c.keep(e);
        }
        handled.add(e.path);
      } catch (_) {
        failed++;
      }
      if (mounted) setState(() => _done++);
    }
    if (!mounted) return;
    setState(() {
      _items.removeWhere((e) => handled.contains(e.path));
      _selected.removeAll(handled);
      _totalCount = _totalCount - handled.length;
      _working = false;
    });
    widget.onSelectionChanged(_selected.isNotEmpty);
    c.refreshCountsSoon();
    final verb = move ? 'Moved' : 'Kept';
    showSoftSnack(
      context,
      failed == 0
          ? '$verb ${handled.length} files'
          : '$verb ${handled.length} files, $failed failed',
    );
    if (_items.length < pageSize && _more) _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.soft;
    final selecting = _selected.isNotEmpty;
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
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (selecting)
                      SoftIconButton(
                        icon: Icons.close_rounded,
                        label: 'Clear selection',
                        onTap: _clear,
                      ),
                    if (selecting) const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        selecting ? '${_selected.length} selected' : 'Files',
                        style: ts(context, selecting ? 18 : 22,
                            weight:
                                selecting ? FontWeight.w500 : FontWeight.w400),
                      ),
                    ),
                    SoftTap(
                      label: _filter == 'dups' ? 'Select extras' : 'Select all',
                      onTap: _filter == 'dups' ? _selectExtras : _selectAll,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 12),
                        child: Text(
                            _filter == 'dups' ? 'Select extras' : 'Select all',
                            style: ts(context, 14,
                                weight: FontWeight.w500, color: p.accent)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  children: [
                    for (final f in const [
                      ['all', 'All'],
                      ['zip', 'ZIP'],
                      ['apk', 'APK'],
                      ['pdf', 'PDF'],
                      ['docs', 'Docs'],
                      ['other', 'Other'],
                      ['dups', 'Duplicates'],
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
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final f in const [
                    ['largest', 'Largest first'],
                    ['oldest', 'Oldest first'],
                  ]) ...[
                    SoftChip(
                      label: f[1],
                      selected: _sort == f[0],
                      onTap: () {
                        if (_sort == f[0]) return;
                        setState(() => _sort = f[0]);
                        _load(reset: true);
                      },
                    ),
                    const SizedBox(width: 10),
                  ],
                  const Spacer(),
                  Text('${formatInt(_totalCount)}',
                      style: ts(context, 12, color: p.muted)),
                ],
              ),
              if (_filter == 'dups') ...[
                const SizedBox(height: 8),
                Text(
                  'Same name and size. "Select extras" keeps one copy of each.',
                  style: ts(context, 12, color: p.muted),
                ),
              ],
              const SizedBox(height: 8),
              Expanded(child: _list(context, selecting)),
            ],
          ),
        ),
        if (selecting) Positioned(left: 24, right: 24, bottom: 20, child: _bar(context)),
      ],
    );
  }

  Widget _list(BuildContext context, bool selecting) {
    final p = context.soft;
    if (_items.isEmpty && !_loading && !_more) {
      return Center(
        child: Text('No files here', style: ts(context, 15, color: p.muted)),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: EdgeInsets.only(bottom: selecting ? 100 : 110),
      itemCount: _items.length + (_more ? 1 : 0),
      itemBuilder: (context, i) {
        if (i >= _items.length) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2, color: p.accent),
              ),
            ),
          );
        }
        final e = _items[i];
        return _FileRow(
          entry: e,
          selected: _selected.contains(e.path),
          onTap: () => _toggle(e),
        );
      },
    );
  }

  Widget _bar(BuildContext context) {
    final p = context.soft;
    if (_working) {
      return Container(
        height: 56,
        alignment: Alignment.center,
        decoration: raisedDeco(p, radius: 28),
        child: Text('Working... $_done / ${_selected.length}',
            style: ts(context, 15, color: p.muted)),
      );
    }
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: SoftPill(
            label: 'Keep',
            color: p.keep,
            height: 56,
            onTap: () => _apply(move: false),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 5,
          child: SoftPill(
            label:
                'Move ${_selected.length} to ToDelete · ${formatBytes(_selectedBytes)}',
            color: p.remove,
            height: 56,
            onTap: () => _apply(move: true),
          ),
        ),
      ],
    );
  }
}

class _FileRow extends StatelessWidget {
  final FileEntry entry;
  final bool selected;
  final VoidCallback onTap;

  const _FileRow({
    required this.entry,
    required this.selected,
    required this.onTap,
  });

  Widget _leading(BuildContext context) {
    final p = context.soft;
    final label = Text(extLabel(entry.ext),
        style: ts(context, 11, weight: FontWeight.w500, color: p.muted));
    if (entry.ext != 'pdf') {
      return Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: raisedDeco(p, radius: 12),
        child: label,
      );
    }
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: raisedDeco(p, radius: 12),
      child: FutureBuilder<Uint8List?>(
        future: FileInfoCache.pdf(entry.path),
        builder: (context, snap) {
          final b = snap.data;
          if (b == null) return label;
          return Image.memory(b,
              width: 44, height: 44, fit: BoxFit.cover, alignment: Alignment.topCenter);
        },
      ),
    );
  }

  Widget _subtitle(BuildContext context) {
    final p = context.soft;
    final dir = pth.dirname(entry.path).replaceFirst('/storage/emulated/0/', '');
    final base = '${formatBytes(entry.size)} · ${formatDate(entry.mtime)}';
    Widget line(String t) => Text(t,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: ts(context, 12, color: p.muted));
    final path = Text(dir,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: ts(context, 11, color: p.muted));
    if (entry.ext != 'apk') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [line(base), path],
      );
    }
    return FutureBuilder<Map<String, String>?>(
      future: FileInfoCache.apk(entry.path),
      builder: (context, snap) {
        final info = snap.data;
        final app = info == null
            ? ''
            : '${info['label']} ${info['version']} · ';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [line('$app$base'), path],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.soft;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SoftTap(
        onTap: onTap,
        label: '${selected ? 'Deselect' : 'Select'} ${entry.name}',
        child: Container(
          height: 78,
          padding: const EdgeInsets.only(left: 14, right: 8),
          decoration:
              selected ? pressedDeco(p, radius: 20) : raisedDeco(p, radius: 20),
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: selected
                    ? BoxDecoration(
                        color: p.accent,
                        borderRadius: BorderRadius.circular(8),
                      )
                    : pressedDeco(p, radius: 8),
                child: selected
                    ? Icon(Icons.check_rounded, size: 16, color: p.bg)
                    : null,
              ),
              const SizedBox(width: 12),
              _leading(context),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ts(context, 15)),
                    const SizedBox(height: 2),
                    _subtitle(context),
                  ],
                ),
              ),
              SoftIconButton(
                icon: Icons.open_in_new_rounded,
                label: 'Open ${entry.name}',
                size: 40,
                iconSize: 18,
                color: p.accent,
                onTap: () async {
                  final ok = await Native.openFile(entry.path);
                  if (!ok && context.mounted) {
                    showSoftSnack(context, 'No app found to open this file');
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
