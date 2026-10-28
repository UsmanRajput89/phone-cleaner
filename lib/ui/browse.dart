import 'package:flutter/material.dart';
import 'package:path/path.dart' as pth;

import '../app/controller.dart';
import '../app/format.dart';
import '../app/theme.dart';
import '../core/classify.dart';
import '../core/models.dart';
import '../native.dart';
import 'folders.dart';
import 'media.dart';
import 'soft.dart';
import 'swipe.dart';

const List<String> _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

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
  bool _bySize = false;

  void _sortRows(List<_FolderRow> rows) {
    rows.sort((a, b) => _bySize
        ? b.bytes.compareTo(a.bytes)
        : b.count.compareTo(a.count));
  }

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
        .toList();
    _sortRows(rows);
    if (!mounted) return;
    setState(() => _rows = rows);
  }

  Future<void> _open(_FolderRow r) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => _FolderPage(bucket: _bucket, prefix: r.path),
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
          Row(
            children: [
              Expanded(
                child: Text('FOLDERS',
                    style: ts(context, 12, color: p.muted, letterSpacing: 1)),
              ),
              SoftChip(
                label: 'Most files',
                selected: !_bySize,
                onTap: () {
                  if (!_bySize) return;
                  setState(() {
                    _bySize = false;
                    if (_rows != null) _sortRows(_rows!);
                  });
                },
              ),
              const SizedBox(width: 8),
              SoftChip(
                label: 'Largest',
                selected: _bySize,
                onTap: () {
                  if (_bySize) return;
                  setState(() {
                    _bySize = true;
                    if (_rows != null) _sortRows(_rows!);
                  });
                },
              ),
            ],
          ),
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

const List<String> _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

class _Group {
  final String key;
  final String label;
  final int ym; // year * 100 + month
  final List<FileEntry> items = [];
  int bytes = 0;

  _Group(this.key, this.label, this.ym);
}

class _Flat {
  final _Group? header;
  final List<FileEntry>? row;

  _Flat.header(_Group g)
      : header = g,
        row = null;
  _Flat.row(List<FileEntry> r)
      : header = null,
        row = r;
}

/// One folder, every date on one scrolling page, grouped by day.
class _FolderPage extends StatefulWidget {
  final Bucket bucket;
  final String prefix;

  const _FolderPage({required this.bucket, required this.prefix});

  @override
  State<_FolderPage> createState() => _FolderPageState();
}

class _FolderPageState extends State<_FolderPage> {
  static const double headerH = 48;
  static const double gap = 6;
  static const double railW = 30;

  List<FileEntry> _all = [];
  final Map<String, FileEntry> _byPath = {};
  final Set<String> _selected = {};
  final ScrollController _scroll = ScrollController();

  List<_Group> _groups = [];
  List<_Flat> _flat = [];
  List<int> _groupFlatIndex = [];
  List<double> _offsets = [];
  double _tile = 0;
  int _activeYm = 0;

  bool _loaded = false;
  SortMode _sort = SortMode.newest;
  bool get _bySize => _sort == SortMode.largest;
  bool _working = false;
  int _done = 0;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final c = AppScope.read(context);
    final rows = await c.store.query(FileQuery(
      buckets: [widget.bucket],
      pathPrefix: widget.prefix,
      sort: SortMode.newest,
      limit: 500000,
    ));
    if (!mounted) return;
    _all = rows;
    _byPath
      ..clear()
      ..addEntries(rows.map((e) => MapEntry(e.path, e)));
    _selected.removeWhere((p) => !_byPath.containsKey(p));
    _regroup();
    setState(() => _loaded = true);
  }

  String _labelFor(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    final wd = _weekdays[d.weekday - 1];
    return '$wd, ${formatDate(d.millisecondsSinceEpoch)}';
  }

  void _regroup() {
    final list = List<FileEntry>.of(_all);
    if (_bySize) {
      list.sort((a, b) {
        final c = b.size.compareTo(a.size);
        return c != 0 ? c : a.path.compareTo(b.path);
      });
    } else {
      list.sort((a, b) => _sort == SortMode.newest
          ? b.mtime.compareTo(a.mtime)
          : a.mtime.compareTo(b.mtime));
    }
    final groups = <_Group>[];
    final index = <String, _Group>{};
    for (final e in list) {
      if (_bySize) {
        var g = index['size'];
        if (g == null) {
          g = _Group('size', 'Largest first', 0);
          index['size'] = g;
          groups.add(g);
        }
        g.items.add(e);
        g.bytes += e.size;
        continue;
      }
      final d = DateTime.fromMillisecondsSinceEpoch(e.mtime);
      final key = '${d.year}-${d.month}-${d.day}';
      var g = index[key];
      if (g == null) {
        g = _Group(key, _labelFor(d), d.year * 100 + d.month);
        index[key] = g;
        groups.add(g);
      }
      g.items.add(e);
      g.bytes += e.size;
    }
    final flat = <_Flat>[];
    final gIdx = <int>[];
    for (final g in groups) {
      gIdx.add(flat.length);
      flat.add(_Flat.header(g));
      for (var i = 0; i < g.items.length; i += 4) {
        final end = i + 4 > g.items.length ? g.items.length : i + 4;
        flat.add(_Flat.row(g.items.sublist(i, end)));
      }
    }
    _groups = groups;
    _flat = flat;
    _groupFlatIndex = gIdx;
    _offsets = [];
    _tile = 0;
    _activeYm = groups.isEmpty ? 0 : groups.first.ym;
  }

  void _computeOffsets(double tile) {
    if (_tile == tile && _offsets.length == _flat.length) return;
    _tile = tile;
    final out = List<double>.filled(_flat.length, 0);
    var y = 0.0;
    for (var i = 0; i < _flat.length; i++) {
      out[i] = y;
      y += _flat[i].header != null ? headerH : tile + gap;
    }
    _offsets = out;
  }

  void _onScroll() {
    if (_groups.isEmpty || _offsets.length != _flat.length) return;
    final y = _scroll.offset + 1;
    var lo = 0;
    var hi = _groups.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (_offsets[_groupFlatIndex[mid]] <= y) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    final ym = _groups[lo].ym;
    if (ym != _activeYm) setState(() => _activeYm = ym);
  }

  void _jumpToMonth(int ym) {
    final gi = _groups.indexWhere((g) => g.ym == ym);
    if (gi < 0 || _offsets.length != _flat.length) return;
    final target = _offsets[_groupFlatIndex[gi]];
    final max = _scroll.position.maxScrollExtent;
    _scroll.jumpTo(target > max ? max : target);
  }

  void _toggle(FileEntry e) {
    setState(() {
      if (!_selected.remove(e.path)) _selected.add(e.path);
    });
  }

  /// Opens the swipe reviewer on exactly these files, then refreshes.
  Future<void> _review(List<FileEntry> list, String title) async {
    final media =
        list.where((e) => e.kind == Kind.image || e.kind == Kind.video).toList();
    if (media.isEmpty) {
      showSoftSnack(context, 'No photos or videos to swipe here');
      return;
    }
    final c = AppScope.read(context);
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => SwipePage(entries: media, title: title)));
    c.refreshCountsSoon();
    if (mounted) await _load();
  }

  List<FileEntry> get _inOrder => [for (final g in _groups) ...g.items];

  bool _dayAllSelected(_Group g) =>
      g.items.isNotEmpty && g.items.every((e) => _selected.contains(e.path));

  void _toggleDay(_Group g) {
    setState(() {
      if (_dayAllSelected(g)) {
        for (final e in g.items) {
          _selected.remove(e.path);
        }
      } else {
        for (final e in g.items) {
          _selected.add(e.path);
        }
      }
    });
  }

  int get _selectedBytes {
    var sum = 0;
    for (final p in _selected) {
      sum += _byPath[p]?.size ?? 0;
    }
    return sum;
  }

  int get _allBytes => _all.fold<int>(0, (a, e) => a + e.size);

  Future<void> _apply({required String mode}) async {
    if (_working || _selected.isEmpty) return;
    final c = AppScope.read(context);
    String? folder;
    if (mode == 'folder') {
      folder = await pickSafeFolder(context);
      if (folder == null || !mounted) return;
    }
    final paths = _selected.toList();
    setState(() {
      _working = true;
      _done = 0;
      _total = paths.length;
    });
    final handled = <String>{};
    var failed = 0;
    for (final path in paths) {
      final e = _byPath[path];
      if (e == null) continue;
      try {
        if (mode == 'trash') {
          await c.moveToTrash(e);
        } else if (mode == 'folder') {
          await c.moveToFolder(e, folder!);
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
    _all = _all.where((e) => !handled.contains(e.path)).toList();
    for (final p in handled) {
      _byPath.remove(p);
    }
    _selected.removeAll(handled);
    _regroup();
    setState(() => _working = false);
    c.refreshCountsSoon();
    final verb = mode == 'keep'
        ? 'Kept'
        : (mode == 'folder' ? 'Moved to ${pth.basename(folder!)}:' : 'Moved');
    showSoftSnack(
      context,
      failed == 0
          ? '$verb ${handled.length} files'
          : '$verb ${handled.length} files, $failed failed',
    );
  }

  List<MapEntry<int, String>> _railItems() {
    // (ym, label); a negative key marks a year label.
    final out = <MapEntry<int, String>>[];
    if (_bySize) return out;
    var lastYm = -1;
    var lastYear = -1;
    for (final g in _groups) {
      if (g.ym == lastYm) continue;
      lastYm = g.ym;
      final year = g.ym ~/ 100;
      final month = g.ym % 100;
      if (year != lastYear) {
        lastYear = year;
        out.add(MapEntry(-year, "'${(year % 100).toString().padLeft(2, '0')}"));
      }
      out.add(MapEntry(g.ym, _monthNames[month - 1]));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.soft;
    final selecting = _selected.isNotEmpty;
    return SoftScaffold(
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 64,
                  child: Row(
                    children: [
                      SoftIconButton(
                        icon: selecting
                            ? Icons.close_rounded
                            : Icons.arrow_back_ios_new_rounded,
                        label: selecting ? 'Clear selection' : 'Back',
                        iconSize: 18,
                        onTap: _working
                            ? null
                            : () {
                                if (selecting) {
                                  setState(_selected.clear);
                                } else {
                                  Navigator.of(context).pop();
                                }
                              },
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                selecting
                                    ? '${formatInt(_selected.length)} selected'
                                    : _shortPath(widget.prefix),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: ts(context, 17, weight: FontWeight.w500)),
                            Text(
                                selecting
                                    ? '${formatBytes(_selectedBytes)} selected'
                                    : '${formatInt(_all.length)} files · ${formatBytes(_allBytes)}${_bySize ? ' · by size' : ' · all dates'}',
                                style: ts(context, 12, color: p.muted)),
                          ],
                        ),
                      ),
                      SoftTap(
                        label: 'Select all',
                        onTap: _working
                            ? null
                            : () => setState(
                                () => _selected.addAll(_all.map((e) => e.path))),
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
                SizedBox(
                  height: 44,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                    children: [
                      for (final f in const [
                        [SortMode.newest, 'Newest'],
                        [SortMode.oldest, 'Oldest'],
                        [SortMode.largest, 'Largest'],
                      ]) ...[
                        SoftChip(
                          label: f[1] as String,
                          selected: _sort == (f[0] as SortMode),
                          onTap: () {
                            if (_sort == (f[0] as SortMode)) return;
                            setState(() {
                              _sort = f[0] as SortMode;
                              _regroup();
                            });
                            if (_scroll.hasClients) _scroll.jumpTo(0);
                          },
                        ),
                        const SizedBox(width: 8),
                      ],
                      const SizedBox(width: 8),
                      SoftTap(
                        label: 'Review whole folder one by one',
                        onTap: _working || _all.isEmpty
                            ? null
                            : () => _review(_inOrder, _shortPath(widget.prefix)),
                        child: Container(
                          height: 36,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          alignment: Alignment.center,
                          decoration: raisedDeco(p, radius: 18),
                          child: Text('Review folder',
                              style: ts(context, 13,
                                  weight: FontWeight.w500, color: p.accent)),
                        ),
                      ),
                    ],
                  ),
                  ),
                ),
                Expanded(child: _content(context, selecting)),
              ],
            ),
          ),
          if (selecting)
            Positioned(
              left: 24,
              right: 24,
              bottom: 20,
              child: _working ? _progress(context) : _bar(context),
            ),
        ],
      ),
    );
  }

  Widget _progress(BuildContext context) {
    final p = context.soft;
    return Container(
      height: 56,
      alignment: Alignment.center,
      decoration: raisedDeco(p, radius: 28),
      child: Text('Working... $_done / $_total',
          style: ts(context, 15, color: p.muted)),
    );
  }

  Widget _bar(BuildContext context) {
    final p = context.soft;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: SoftPill(
                label: 'Keep',
                color: p.keep,
                height: 52,
                onTap: () => _apply(mode: 'keep'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SoftPill(
                label: 'Review',
                color: p.accent,
                height: 52,
                onTap: () => _review(
                    _inOrder.where((e) => _selected.contains(e.path)).toList(),
                    '${formatInt(_selected.length)} selected'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SoftPill(
                label: 'Folder',
                color: p.accent,
                height: 52,
                onTap: () => _apply(mode: 'folder'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SoftPill(
          label:
              'Move ${formatInt(_selected.length)} to ToDelete · ${formatBytes(_selectedBytes)}',
          color: p.remove,
          height: 52,
          onTap: () => _apply(mode: 'trash'),
        ),
      ],
    );
  }

  Widget _content(BuildContext context, bool selecting) {
    final p = context.soft;
    if (!_loaded) {
      return Center(child: CircularProgressIndicator(color: p.accent));
    }
    if (_flat.isEmpty) {
      return Center(
          child: Text('Nothing left here',
              style: ts(context, 15, color: p.muted)));
    }
    return LayoutBuilder(builder: (context, box) {
      final hasRail = !_bySize;
      final listW = box.maxWidth - (hasRail ? railW + 10 : 0);
      final tile = ((listW - gap * 3) / 4).floorToDouble();
      _computeOffsets(tile);
      final rail = _railItems();
      return Stack(
        children: [
          Positioned.fill(
            right: hasRail ? railW + 10 : 0,
            child: ListView.builder(
              controller: _scroll,
              padding: EdgeInsets.only(bottom: selecting ? 170 : 40),
              itemCount: _flat.length,
              itemBuilder: (context, i) {
                final f = _flat[i];
                final g = f.header;
                if (g != null) return _header(context, g);
                return SizedBox(
                  height: tile + gap,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: gap),
                    child: Row(
                      children: [
                        for (var k = 0; k < f.row!.length; k++) ...[
                          if (k > 0) const SizedBox(width: gap),
                          SizedBox(
                            width: tile,
                            height: tile,
                            child: _tileFor(context, f.row![k]),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (hasRail)
          Positioned(
            right: 0,
            top: 4,
            bottom: selecting ? 170 : 24,
            width: railW,
            child: Container(
              decoration: raisedDeco(p, radius: 15),
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  for (final r in rail)
                    SoftTap(
                      label: r.key < 0 ? 'Year ${r.value}' : 'Jump to ${r.value}',
                      onTap: r.key < 0 ? null : () => _jumpToMonth(r.key),
                      child: SizedBox(
                        height: 28,
                        child: Center(
                          child: Text(
                            r.value,
                            style: ts(
                              context,
                              10,
                              weight: FontWeight.w500,
                              color: r.key == _activeYm
                                  ? p.accent
                                  : (r.key < 0 ? p.text : p.muted),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      );
    });
  }

  Widget _header(BuildContext context, _Group g) {
    final p = context.soft;
    final all = _dayAllSelected(g);
    return SizedBox(
      height: headerH,
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(g.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ts(context, 14, weight: FontWeight.w500)),
                  Text('${formatInt(g.items.length)} files · ${formatBytes(g.bytes)}',
                      style: ts(context, 11, color: p.muted)),
                ],
              ),
            ),
            SoftTap(
              label: 'Review ${g.label} one by one',
              onTap: _working ? null : () => _review(g.items, g.label),
              child: Container(
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                decoration: raisedDeco(p, radius: 15),
                child: Text('Review',
                    style: ts(context, 12,
                        weight: FontWeight.w500, color: p.accent)),
              ),
            ),
            const SizedBox(width: 8),
            SoftTap(
              label: all ? 'Unselect group' : 'Select group',
              onTap: _working ? null : () => _toggleDay(g),
              child: Container(
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                decoration:
                    all ? pressedDeco(p, radius: 15) : raisedDeco(p, radius: 15),
                child: Text(all ? 'Selected' : 'Select',
                    style: ts(context, 12,
                        weight: FontWeight.w500,
                        color: all ? p.keep : p.accent)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tileFor(BuildContext context, FileEntry e) {
    final p = context.soft;
    final sel = _selected.contains(e.path);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _working ? null : () => _toggle(e),
      onLongPress: _working
          ? null
          : () async {
              final ok = await Native.openFile(e.path);
              if (!ok && context.mounted) {
                showSoftSnack(context, 'No app found to open this file');
              }
            },
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: MediaThumb(entry: e, cacheWidth: 200),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: sel ? p.accent : p.ring,
                    width: sel ? 3 : 1,
                  ),
                ),
              ),
            ),
          ),
          if (_bySize)
            Positioned(
              left: 5,
              bottom: 5,
              child: Container(
                height: 18,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                alignment: Alignment.center,
                decoration: raisedDeco(p, radius: 9),
                child: Text(formatBytes(e.size),
                    style: ts(context, 10, weight: FontWeight.w500)),
              ),
            ),
          if (sel)
            Positioned(
              top: 5,
              right: 5,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: p.accent,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(Icons.check_rounded, size: 13, color: p.bg),
              ),
            ),
        ],
      ),
    );
  }
}
