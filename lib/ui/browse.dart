import 'package:flutter/material.dart';

import '../app/controller.dart';
import '../app/format.dart';
import '../app/theme.dart';
import '../core/classify.dart';
import '../core/models.dart';
import '../native.dart';
import 'media.dart';
import 'soft.dart';

const List<String> _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _monthLabel(String ym) {
  final parts = ym.split('-');
  if (parts.length != 2) return ym;
  final m = int.tryParse(parts[1]) ?? 0;
  if (m < 1 || m > 12) return ym;
  return '${_monthNames[m - 1]} ${parts[0]}';
}

String _shortPath(String path) =>
    path.replaceFirst('/storage/emulated/0/', '').replaceFirst('Android/media/', '');

/// Browse tab: pick a bucket, then a folder, then a month, then bulk-select.
/// Works for WhatsApp even while it is switched off in the main review.
class BrowsePage extends StatefulWidget {
  const BrowsePage({super.key});

  @override
  State<BrowsePage> createState() => _BrowsePageState();
}

class _FolderRow {
  final String path;
  final int count;
  final int bytes;
  _FolderRow(this.path, this.count, this.bytes);
}

class _BrowsePageState extends State<BrowsePage> {
  Bucket _bucket = Bucket.whatsapp;
  List<_FolderRow>? _rows;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final c = AppScope.read(context);
    setState(() => _rows = null);
    final stats = await c.store.folderStats(_bucket.name, Status.pending);
    final rows = stats.entries
        .map((e) => _FolderRow(e.key, e.value[0], e.value[1]))
        .toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    if (!mounted) return;
    setState(() => _rows = rows);
  }

  Future<void> _open(_FolderRow r) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => _MonthsPage(bucket: _bucket, prefix: r.path),
    ));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.soft;
    final rows = _rows;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 56,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Browse', style: ts(context, 22)),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(vertical: 6),
              children: [
                for (final b in Bucket.values) ...[
                  SoftChip(
                    label: bucketLabel(b),
                    selected: _bucket == b,
                    onTap: () {
                      if (_bucket == b) return;
                      _bucket = b;
                      _load();
                    },
                  ),
                  const SizedBox(width: 12),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text('FOLDERS · NOT REVIEWED YET',
              style: ts(context, 12, color: p.muted, letterSpacing: 1)),
          const SizedBox(height: 10),
          Expanded(
            child: rows == null
                ? Center(child: CircularProgressIndicator(color: p.accent))
                : rows.isEmpty
                    ? Center(
                        child: Text('Nothing left here',
                            style: ts(context, 15, color: p.muted)))
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 110),
                        itemCount: rows.length,
                        itemBuilder: (context, i) {
                          final r = rows[i];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: SoftTap(
                              onTap: () => _open(r),
                              label: _shortPath(r.path),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 12),
                                decoration: raisedDeco(p, radius: 20),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(_shortPath(r.path),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: ts(context, 14)),
                                          const SizedBox(height: 2),
                                          Text(
                                              '${formatInt(r.count)} files · ${formatBytes(r.bytes)}',
                                              style: ts(context, 12,
                                                  color: p.muted)),
                                        ],
                                      ),
                                    ),
                                    Icon(Icons.chevron_right_rounded,
                                        color: p.muted),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _MonthsPage extends StatefulWidget {
  final Bucket bucket;
  final String prefix;

  const _MonthsPage({required this.bucket, required this.prefix});

  @override
  State<_MonthsPage> createState() => _MonthsPageState();
}

class _MonthsPageState extends State<_MonthsPage> {
  List<Map<String, Object?>>? _months;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final c = AppScope.read(context);
    final rows = await c.store.monthsUnder(widget.prefix, widget.bucket.name);
    if (!mounted) return;
    setState(() => _months = rows);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.soft;
    final months = _months;
    return SoftScaffold(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 64,
              child: Row(
                children: [
                  SoftIconButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    label: 'Back',
                    iconSize: 18,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(_shortPath(widget.prefix),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: ts(context, 16)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text('MONTHS',
                style: ts(context, 12, color: p.muted, letterSpacing: 1)),
            const SizedBox(height: 10),
            Expanded(
              child: months == null
                  ? Center(child: CircularProgressIndicator(color: p.accent))
                  : months.isEmpty
                      ? Center(
                          child: Text('Nothing left here',
                              style: ts(context, 15, color: p.muted)))
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 24),
                          itemCount: months.length,
                          itemBuilder: (context, i) {
                            final m = months[i];
                            final ym = (m['m'] as String?) ?? '';
                            final count = (m['c'] as num).toInt();
                            final bytes = (m['s'] as num).toInt();
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: SoftTap(
                                onTap: () async {
                                  await Navigator.of(context)
                                      .push(MaterialPageRoute<void>(
                                    builder: (_) => _GridPage(
                                      bucket: widget.bucket,
                                      prefix: widget.prefix,
                                      month: ym,
                                    ),
                                  ));
                                  if (mounted) _load();
                                },
                                label: _monthLabel(ym),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 14),
                                  decoration: raisedDeco(p, radius: 20),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(_monthLabel(ym),
                                                style: ts(context, 16)),
                                            const SizedBox(height: 2),
                                            Text(
                                                '${formatInt(count)} files · ${formatBytes(bytes)}',
                                                style: ts(context, 12,
                                                    color: p.muted)),
                                          ],
                                        ),
                                      ),
                                      Icon(Icons.chevron_right_rounded,
                                          color: p.muted),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GridPage extends StatefulWidget {
  final Bucket bucket;
  final String prefix;
  final String month;

  const _GridPage({
    required this.bucket,
    required this.prefix,
    required this.month,
  });

  @override
  State<_GridPage> createState() => _GridPageState();
}

class _GridPageState extends State<_GridPage> {
  static const int pageSize = 90;

  final List<FileEntry> _items = [];
  final Map<String, int> _sizes = {};
  final Set<String> _selected = {};
  final ScrollController _scroll = ScrollController();

  bool _loading = false;
  bool _more = true;
  bool _working = false;
  int _done = 0;
  int _total = 0;

  FileQuery get _query => FileQuery(
        buckets: [widget.bucket],
        pathPrefix: widget.prefix,
        month: widget.month,
        sort: SortMode.newest,
        limit: pageSize,
      );

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 800) {
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

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    if (!reset && !_more) return;
    _loading = true;
    final c = AppScope.read(context);
    if (reset) {
      _items.clear();
      _more = true;
    }
    final rows = await c.store.query(_query.copyWith(offset: _items.length));
    final total = await c.store.count(_query);
    _loading = false;
    if (!mounted) return;
    setState(() {
      _items.addAll(rows);
      for (final e in rows) {
        _sizes[e.path] = e.size;
      }
      _more = rows.length == pageSize;
      _total = total;
    });
  }

  void _toggle(FileEntry e) {
    setState(() {
      if (!_selected.remove(e.path)) _selected.add(e.path);
    });
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
  }

  int get _selectedBytes {
    var sum = 0;
    for (final path in _selected) {
      sum += _sizes[path] ?? 0;
    }
    return sum;
  }

  Future<void> _apply({required bool move}) async {
    if (_working || _selected.isEmpty) return;
    final c = AppScope.read(context);
    final paths = _selected.toList();
    final entries = await c.store.query(_query.copyWith(limit: 200000, offset: 0));
    final byPath = {for (final e in entries) e.path: e};
    setState(() {
      _working = true;
      _done = 0;
      _total = paths.length;
    });
    final handled = <String>{};
    var failed = 0;
    for (final path in paths) {
      final e = byPath[path];
      if (e == null) continue;
      try {
        if (move) {
          await c.moveToTrash(e);
        } else {
          await c.keep(e);
        }
        handled.add(path);
      } catch (_) {
        failed++;
      }
      _done++;
      if (mounted && _done % 10 == 0) setState(() {});
    }
    if (!mounted) return;
    setState(() {
      _items.removeWhere((e) => handled.contains(e.path));
      _selected.removeAll(handled);
      _working = false;
    });
    c.refreshCountsSoon();
    showSoftSnack(
      context,
      failed == 0
          ? '${move ? 'Moved' : 'Kept'} ${handled.length} files'
          : '${move ? 'Moved' : 'Kept'} ${handled.length} files, $failed failed',
    );
    _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.soft;
    final selecting = _selected.isNotEmpty;
    return SoftScaffold(
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 64,
                  child: Row(
                    children: [
                      SoftIconButton(
                        icon: Icons.arrow_back_ios_new_rounded,
                        label: 'Back',
                        iconSize: 18,
                        onTap: _working ? null : () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_monthLabel(widget.month),
                                style: ts(context, 18)),
                            Text(
                                selecting
                                    ? '${formatInt(_selected.length)} selected'
                                    : '${formatInt(_total)} files',
                                style: ts(context, 12, color: p.muted)),
                          ],
                        ),
                      ),
                      SoftTap(
                        label: 'Select all',
                        onTap: _working ? null : _selectAll,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 12),
                          child: Text('Select all',
                              style: ts(context, 14,
                                  weight: FontWeight.w500, color: p.accent)),
                        ),
                      ),
                    ],
                  ),
                ),
                Text('Tap to select · long press to open',
                    style: ts(context, 12, color: p.muted)),
                const SizedBox(height: 10),
                Expanded(
                  child: GridView.builder(
                    controller: _scroll,
                    padding: EdgeInsets.only(bottom: selecting ? 100 : 24),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemCount: _items.length,
                    itemBuilder: (context, i) {
                      final e = _items[i];
                      final sel = _selected.contains(e.path);
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _working ? null : () => _toggle(e),
                        onLongPress: _working
                            ? null
                            : () async {
                                final ok = await Native.openFile(e.path);
                                if (!ok && context.mounted) {
                                  showSoftSnack(
                                      context, 'No app found to open this file');
                                }
                              },
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: MediaThumb(entry: e, cacheWidth: 240),
                            ),
                            Positioned.fill(
                              child: IgnorePointer(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: sel ? p.accent : p.ring,
                                      width: sel ? 3 : 1,
                                    ),
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
                                    color: p.accent,
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
          if (selecting)
            Positioned(
              left: 24,
              right: 24,
              bottom: 20,
              child: _working
                  ? Container(
                      height: 56,
                      alignment: Alignment.center,
                      decoration: raisedDeco(p, radius: 28),
                      child: Text('Working... $_done / $_total',
                          style: ts(context, 15, color: p.muted)),
                    )
                  : Row(
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
                                'Move ${formatInt(_selected.length)} to ToDelete · ${formatBytes(_selectedBytes)}',
                            color: p.remove,
                            height: 56,
                            onTap: () => _apply(move: true),
                          ),
                        ),
                      ],
                    ),
            ),
        ],
      ),
    );
  }
}
