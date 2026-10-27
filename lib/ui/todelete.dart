import 'package:flutter/material.dart';

import '../app/controller.dart';
import '../app/format.dart';
import '../app/theme.dart';
import '../core/models.dart';
import 'media.dart';
import 'soft.dart';

/// Everything that was moved to the ToDelete folder. Tap a tile to restore it.
class ToDeletePage extends StatefulWidget {
  const ToDeletePage({super.key});

  @override
  State<ToDeletePage> createState() => _ToDeletePageState();
}

class _ToDeletePageState extends State<ToDeletePage> {
  static const int pageSize = 60;

  final List<FileEntry> _items = [];
  final ScrollController _scroll = ScrollController();

  String _filter = 'all';
  bool _loading = false;
  bool _more = true;
  int _count = 0;
  int _bytes = 0;

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
      _more = true;
    }
    final rows = await c.store.query(q.copyWith(offset: _items.length));
    final count = await c.store.count(q);
    final bytes = await c.store.sumSize(q);
    _loading = false;
    if (!mounted) return;
    setState(() {
      _items.addAll(rows);
      _more = rows.length == pageSize;
      _count = count;
      _bytes = bytes;
    });
  }

  Future<void> _restore(FileEntry e) async {
    final c = AppScope.read(context);
    final orig = e.origPath;
    if (orig == null) return;
    try {
      final newPath = await c.restore(e.path, orig, Status.kept);
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

  @override
  Widget build(BuildContext context) {
    final p = context.soft;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 56,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('ToDelete', style: ts(context, 22)),
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: pressedDeco(p),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 22, color: p.accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Nothing here is deleted by this app. Delete from the Gallery '
                    'album or the Files app when you are ready. Tap a file to '
                    'restore it.',
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
                    padding: const EdgeInsets.only(top: 6, bottom: 110),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                    ),
                    itemCount: _items.length,
                    itemBuilder: (context, i) {
                      final e = _items[i];
                      return SoftTap(
                        onTap: () => _restore(e),
                        label: 'Restore ${e.name}',
                        child: Container(
                          decoration: e.kind == Kind.other
                              ? pressedDeco(p)
                              : raisedDeco(p),
                          clipBehavior: Clip.antiAlias,
                          child: MediaThumb(entry: e, cacheWidth: 260),
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
