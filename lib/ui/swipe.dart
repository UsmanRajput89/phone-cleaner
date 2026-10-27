import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as pth;

import '../app/controller.dart';
import '../app/format.dart';
import '../app/theme.dart';
import '../core/classify.dart';
import '../core/models.dart';
import 'media.dart';
import 'soft.dart';

class _Act {
  final FileEntry entry;
  final bool keep;
  final String? trashPath;

  _Act(this.entry, this.keep, this.trashPath);
}

class SwipePage extends StatefulWidget {
  const SwipePage({super.key});

  @override
  State<SwipePage> createState() => _SwipePageState();
}

class _SwipePageState extends State<SwipePage>
    with SingleTickerProviderStateMixin {
  static const int batchSize = 100;
  static const int cardCacheWidth = 900;

  final List<FileEntry> _queue = [];
  final List<_Act> _history = [];
  final Set<Bucket> _buckets = {};
  SortMode _sort = SortMode.oldest;

  int _batch = 0;
  bool _loading = true;
  bool _busy = false;

  double _dx = 0;
  double _from = 0;
  double _to = 0;
  VoidCallback? _after;
  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 180));
    _anim.addListener(() {
      final t = Curves.easeOut.transform(_anim.value);
      setState(() => _dx = _from + (_to - _from) * t);
    });
    _anim.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        final cb = _after;
        _after = null;
        cb?.call();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _refill());
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  List<Bucket> _activeBuckets(AppController c) {
    if (_buckets.isNotEmpty) return _buckets.toList();
    return Bucket.values
        .where((b) => b != Bucket.whatsapp || c.includeWhatsApp)
        .toList();
  }

  Future<void> _refill({bool reset = false}) async {
    final c = AppScope.read(context);
    if (reset) _queue.clear();
    for (var attempt = 0; attempt < 5; attempt++) {
      final rows = await c.store.query(FileQuery(
        kinds: const [Kind.image, Kind.video],
        buckets: _activeBuckets(c),
        sort: _sort,
        limit: 40,
        excludePaths: _queue.map((e) => e.path).toList(),
      ));
      final fresh = <FileEntry>[];
      for (final e in rows) {
        if (File(e.path).existsSync()) {
          fresh.add(e);
        } else {
          await c.store.remove(e.path);
        }
      }
      if (!mounted) return;
      if (fresh.isNotEmpty || rows.isEmpty) {
        setState(() {
          _queue.addAll(fresh);
          _loading = false;
        });
        _precacheNext();
        return;
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  void _precacheNext() {
    if (_queue.length > 1 && _queue[1].kind == Kind.image) {
      precacheImage(
        ResizeImage(FileImage(File(_queue[1].path)), width: cardCacheWidth),
        context,
      ).catchError((_) {});
    }
  }

  void _animateTo(double to, {VoidCallback? after}) {
    _from = _dx;
    _to = to;
    _after = after;
    _anim.forward(from: 0);
  }

  void _onDragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (_dx > 110 || v > 900) {
      _commit(true);
    } else if (_dx < -110 || v < -900) {
      _commit(false);
    } else {
      _animateTo(0);
    }
  }

  void _commit(bool keep) {
    if (_busy || _queue.isEmpty) return;
    setState(() => _busy = true);
    final w = MediaQuery.of(context).size.width;
    _animateTo(keep ? w : -w, after: () => _finish(keep));
  }

  Future<void> _finish(bool keep) async {
    final c = AppScope.read(context);
    final entry = _queue.first;
    try {
      if (keep) {
        await c.keep(entry);
        _history.add(_Act(entry, true, null));
      } else {
        final trashPath = await c.moveToTrash(entry);
        _history.add(_Act(entry, false, trashPath));
      }
      if (_history.length > 20) _history.removeAt(0);
      HapticFeedback.selectionClick();
      if (!mounted) return;
      setState(() {
        _queue.removeAt(0);
        _dx = 0;
        _batch++;
        _busy = false;
      });
      c.refreshCountsSoon();
      if (_queue.length < 12) _refill();
      _precacheNext();
      if (_batch >= batchSize) _batchDone();
    } catch (_) {
      if (!mounted) return;
      final stillThere = File(entry.path).existsSync();
      if (!stillThere) {
        await c.store.remove(entry.path);
      }
      if (!mounted) return;
      setState(() {
        if (!stillThere && _queue.isNotEmpty) _queue.removeAt(0);
        _dx = 0;
        _busy = false;
      });
      if (stillThere) showSoftSnack(context, 'Could not move that file');
    }
  }

  Future<void> _undo() async {
    if (_busy || _history.isEmpty) return;
    final c = AppScope.read(context);
    setState(() => _busy = true);
    final a = _history.removeLast();
    try {
      FileEntry back;
      if (a.keep) {
        await c.unkeep(a.entry);
        back = a.entry.copyWith(status: Status.pending);
      } else {
        final newPath =
            await c.restore(a.trashPath!, a.entry.path, Status.pending);
        back = a.entry.copyWith(path: newPath, status: Status.pending);
      }
      if (!mounted) return;
      setState(() {
        _queue.insert(0, back);
        _batch = _batch > 0 ? _batch - 1 : 0;
        _busy = false;
        _dx = 0;
      });
      c.refreshCountsSoon();
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      showSoftSnack(context, 'Could not undo that');
    }
  }

  Future<void> _batchDone() async {
    final p = context.soft;
    final more = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
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
              Text('Batch done', style: ts(ctx, 22)),
              const SizedBox(height: 8),
              Text('You reviewed $batchSize files. Take a break or keep going.',
                  style: ts(ctx, 14, color: p.muted, height: 1.4)),
              const SizedBox(height: 20),
              SoftPill(
                  label: 'Next 100',
                  onTap: () => Navigator.of(ctx).pop(true)),
              const SizedBox(height: 12),
              SoftPill(
                  label: 'Done for now',
                  color: p.muted,
                  onTap: () => Navigator.of(ctx).pop(false)),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (more == true) {
      setState(() => _batch = 0);
    } else {
      Navigator.of(context).pop();
    }
  }

  void _openFilters() {
    final p = context.soft;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: p.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheet) {
          void apply(VoidCallback change) {
            setSheet(change);
            setState(() {
              _loading = true;
              _queue.clear();
            });
            _refill();
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Sort', style: ts(ctx, 13, color: p.muted)),
                  const SizedBox(height: 10),
                  Wrap(spacing: 12, runSpacing: 12, children: [
                    for (final s in SortMode.values)
                      SoftChip(
                        label: _sortLabel(s),
                        selected: _sort == s,
                        onTap: () => apply(() => _sort = s),
                      ),
                  ]),
                  const SizedBox(height: 20),
                  Text('Folders', style: ts(ctx, 13, color: p.muted)),
                  const SizedBox(height: 10),
                  Wrap(spacing: 12, runSpacing: 12, children: [
                    SoftChip(
                      label: 'All',
                      selected: _buckets.isEmpty,
                      onTap: () => apply(() => _buckets.clear()),
                    ),
                    for (final b in Bucket.values)
                      SoftChip(
                        label: bucketLabel(b),
                        selected: _buckets.contains(b),
                        onTap: () => apply(() {
                          if (_buckets.contains(b)) {
                            _buckets.remove(b);
                          } else {
                            _buckets.add(b);
                          }
                        }),
                      ),
                  ]),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  String _sortLabel(SortMode s) {
    switch (s) {
      case SortMode.oldest:
        return 'Oldest first';
      case SortMode.newest:
        return 'Newest first';
      case SortMode.largest:
        return 'Largest first';
    }
  }

  String _subtitle() {
    final folders = _buckets.isEmpty
        ? 'All folders'
        : _buckets.map(bucketLabel).join(', ');
    return '$folders, ${_sortLabel(_sort).toLowerCase()}';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.soft;
    final canAct = !_busy && _queue.isNotEmpty;
    return SoftScaffold(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          children: [
            SizedBox(
              height: 56,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  SoftIconButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    label: 'Back',
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('$_batch / $batchSize',
                            style: ts(context, 18, weight: FontWeight.w500)),
                        Text(_subtitle(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: ts(context, 12, color: p.muted)),
                      ],
                    ),
                  ),
                  SoftIconButton(
                    icon: Icons.tune_rounded,
                    label: 'Sort and filter',
                    color: p.muted,
                    onTap: _openFilters,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SoftSlot(value: _batch / batchSize),
            const SizedBox(height: 24),
            Expanded(child: _body(context)),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ActionColumn(
                  label: 'To delete',
                  child: SoftIconButton(
                    icon: Icons.close_rounded,
                    label: 'Move to ToDelete',
                    size: 68,
                    iconSize: 28,
                    color: p.remove,
                    onTap: canAct ? () => _commit(false) : null,
                  ),
                ),
                const SizedBox(width: 30),
                _ActionColumn(
                  label: 'Undo',
                  topPad: 10,
                  child: SoftIconButton(
                    icon: Icons.undo_rounded,
                    label: 'Undo',
                    size: 48,
                    onTap: (!_busy && _history.isNotEmpty) ? _undo : null,
                  ),
                ),
                const SizedBox(width: 30),
                _ActionColumn(
                  label: 'Keep',
                  child: SoftIconButton(
                    icon: Icons.check_rounded,
                    label: 'Keep',
                    size: 68,
                    iconSize: 28,
                    color: p.keep,
                    onTap: canAct ? () => _commit(true) : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final p = context.soft;
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: p.accent));
    }
    if (_queue.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('All caught up', style: ts(context, 22, weight: FontWeight.w300)),
            const SizedBox(height: 8),
            Text('Nothing left to review in this selection.',
                textAlign: TextAlign.center,
                style: ts(context, 14, color: p.muted)),
            const SizedBox(height: 20),
            SoftPill(
                label: 'Change filters',
                expand: false,
                onTap: _openFilters),
          ],
        ),
      );
    }
    final entry = _queue.first;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate:
          _busy ? null : (d) => setState(() => _dx += d.delta.dx),
      onHorizontalDragEnd: _busy ? null : _onDragEnd,
      onTap: entry.kind == Kind.video
          ? () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => VideoPage(path: entry.path)))
          : null,
      child: Transform.translate(
        offset: Offset(_dx, 0),
        child: Transform.rotate(
          angle: (_dx / 700).clamp(-0.4, 0.4).toDouble(),
          alignment: Alignment.bottomCenter,
          child: _PhotoCard(
            key: ValueKey(entry.path),
            entry: entry,
            dx: _dx,
            cacheWidth: cardCacheWidth,
          ),
        ),
      ),
    );
  }
}

class _ActionColumn extends StatelessWidget {
  final String label;
  final Widget child;
  final double topPad;

  const _ActionColumn({
    required this.label,
    required this.child,
    this.topPad = 0,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.soft;
    return Padding(
      padding: EdgeInsets.only(top: topPad),
      child: Column(
        children: [
          child,
          const SizedBox(height: 10),
          Text(label, style: ts(context, 12, color: p.muted)),
        ],
      ),
    );
  }
}

class _PhotoCard extends StatelessWidget {
  final FileEntry entry;
  final double dx;
  final int cacheWidth;

  const _PhotoCard({
    super.key,
    required this.entry,
    required this.dx,
    required this.cacheWidth,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.soft;
    final showRing = dx.abs() > 30;
    final toDelete = dx < 0;
    final tint = toDelete ? p.remove : p.keep;
    final folder = pth.basename(pth.dirname(entry.path));
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: raisedDeco(p, radius: 32),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          fit: StackFit.expand,
          children: [
            MediaThumb(entry: entry, cacheWidth: cacheWidth, showPlay: true),
            if (showRing)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: tint, width: 3),
                    ),
                  ),
                ),
              ),
            if (showRing)
              Positioned(
                top: 16,
                right: toDelete ? 16 : null,
                left: toDelete ? null : 16,
                child: Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: raisedDeco(p, radius: 16),
                  child: Text(toDelete ? 'To delete' : 'Keep',
                      style: ts(context, 13,
                          weight: FontWeight.w500, color: tint)),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                color: p.bg,
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ts(context, 16, weight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    Text(
                      '${formatBytes(entry.size)} · ${formatDate(entry.mtime)} · $folder',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ts(context, 13, color: p.muted),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
