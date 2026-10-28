import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as pth;

import '../app/controller.dart';
import '../app/format.dart';
import '../app/theme.dart';
import '../core/classify.dart';
import '../core/models.dart';
import 'folders.dart';
import 'media.dart';
import 'soft.dart';

enum _Do { keep, trash, folder }

class _Act {
  final FileEntry entry;
  final _Do kind;
  final String? movedPath;

  _Act(this.entry, this.kind, this.movedPath);
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
  double _dy = 0;
  double _from = 0;
  double _to = 0;
  double _fromY = 0;
  double _toY = 0;
  VoidCallback? _after;
  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 180));
    _anim.addListener(() {
      final t = Curves.easeOut.transform(_anim.value);
      setState(() {
        _dx = _from + (_to - _from) * t;
        _dy = _fromY + (_toY - _fromY) * t;
      });
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

  void _animateTo(double to, {double toY = 0, VoidCallback? after}) {
    _from = _dx;
    _to = to;
    _fromY = _dy;
    _toY = toY;
    _after = after;
    _anim.forward(from: 0);
  }

  void _onDragEnd(DragEndDetails d) {
    final vx = d.velocity.pixelsPerSecond.dx;
    final vy = d.velocity.pixelsPerSecond.dy;
    final upward = _dy < 0 && _dy.abs() > _dx.abs() * 1.2;
    if (upward && (_dy < -110 || vy < -900)) {
      _commit(_Do.folder);
    } else if (_dx > 110 || vx > 900) {
      _commit(_Do.keep);
    } else if (_dx < -110 || vx < -900) {
      _commit(_Do.trash);
    } else {
      _animateTo(0);
    }
  }

  /// Makes sure a target folder is set. Returns false if the user cancelled.
  Future<bool> _ensureTarget() async {
    final c = AppScope.read(context);
    if (c.targetFolder != null) return true;
    final f = await pickSafeFolder(context);
    if (f == null || !mounted) return false;
    c.setTargetFolder(f);
    return true;
  }

  Future<void> _chooseTarget() async {
    final c = AppScope.read(context);
    final f = await pickSafeFolder(context);
    if (f == null || !mounted) return;
    c.setTargetFolder(f);
  }

  Future<void> _commit(_Do what) async {
    if (_busy || _queue.isEmpty) return;
    setState(() => _busy = true);
    if (what == _Do.folder) {
      final ok = await _ensureTarget();
      if (!mounted) return;
      if (!ok) {
        setState(() => _busy = false);
        _animateTo(0);
        return;
      }
    }
    final size = MediaQuery.of(context).size;
    switch (what) {
      case _Do.keep:
        _animateTo(size.width, after: () => _finish(what));
        break;
      case _Do.trash:
        _animateTo(-size.width, after: () => _finish(what));
        break;
      case _Do.folder:
        _animateTo(0, toY: -size.height, after: () => _finish(what));
        break;
    }
  }

  Future<void> _finish(_Do what) async {
    final c = AppScope.read(context);
    final entry = _queue.first;
    try {
      switch (what) {
        case _Do.keep:
          await c.keep(entry);
          _history.add(_Act(entry, _Do.keep, null));
          break;
        case _Do.trash:
          final trashPath = await c.moveToTrash(entry);
          _history.add(_Act(entry, _Do.trash, trashPath));
          break;
        case _Do.folder:
          final moved = await c.moveToFolder(entry, c.targetFolder!);
          _history.add(_Act(entry, _Do.folder, moved));
          break;
      }
      if (_history.length > 20) _history.removeAt(0);
      HapticFeedback.selectionClick();
      if (!mounted) return;
      setState(() {
        _queue.removeAt(0);
        _dx = 0;
        _dy = 0;
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
        _dy = 0;
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
      if (a.kind == _Do.keep) {
        await c.unkeep(a.entry);
        back = a.entry.copyWith(status: Status.pending);
      } else {
        final newPath =
            await c.restore(a.movedPath!, a.entry.path, Status.pending);
        back = a.entry.copyWith(path: newPath, status: Status.pending);
      }
      if (!mounted) return;
      setState(() {
        _queue.insert(0, back);
        _batch = _batch > 0 ? _batch - 1 : 0;
        _busy = false;
        _dx = 0;
        _dy = 0;
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
    final c = AppScope.of(context);
    final target = c.targetFolder;
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
            const SizedBox(height: 14),
            SoftTap(
              onTap: _busy ? null : _chooseTarget,
              label: 'Choose target folder',
              child: Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: raisedDeco(p, radius: 18),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.arrow_upward_rounded, size: 16, color: p.accent),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        target == null
                            ? 'Swipe up: choose folder'
                            : 'Swipe up: ${pth.basename(target)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ts(context, 13,
                            weight: FontWeight.w500, color: p.accent),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Expanded(child: _body(context)),
            const SizedBox(height: 22),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ActionColumn(
                  label: 'To delete',
                  child: SoftIconButton(
                    icon: Icons.close_rounded,
                    label: 'Move to ToDelete',
                    size: 64,
                    iconSize: 28,
                    color: p.remove,
                    onTap: canAct ? () => _commit(_Do.trash) : null,
                  ),
                ),
                const SizedBox(width: 16),
                _ActionColumn(
                  label: 'Undo',
                  topPad: 10,
                  child: SoftIconButton(
                    icon: Icons.undo_rounded,
                    label: 'Undo',
                    size: 44,
                    onTap: (!_busy && _history.isNotEmpty) ? _undo : null,
                  ),
                ),
                const SizedBox(width: 16),
                _ActionColumn(
                  label: 'Folder',
                  child: SoftIconButton(
                    icon: Icons.folder_special_outlined,
                    label: 'Move to target folder',
                    size: 64,
                    iconSize: 26,
                    color: p.accent,
                    onTap: canAct ? () => _commit(_Do.folder) : null,
                  ),
                ),
                const SizedBox(width: 16),
                _ActionColumn(
                  label: 'Keep',
                  child: SoftIconButton(
                    icon: Icons.check_rounded,
                    label: 'Keep',
                    size: 64,
                    iconSize: 28,
                    color: p.keep,
                    onTap: canAct ? () => _commit(_Do.keep) : null,
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
    final target = AppScope.of(context).targetFolder;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: _busy
          ? null
          : (d) => setState(() {
                _dx += d.delta.dx;
                _dy = (_dy + d.delta.dy).clamp(-600.0, 40.0).toDouble();
              }),
      onPanEnd: _busy ? null : _onDragEnd,
      onPanCancel: _busy ? null : () => _animateTo(0),
      onTap: entry.kind == Kind.video
          ? () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => VideoPage(path: entry.path)))
          : null,
      child: Transform.translate(
        offset: Offset(_dx, _dy < 0 ? _dy : 0),
        child: Transform.rotate(
          angle: (_dx / 700).clamp(-0.4, 0.4).toDouble(),
          alignment: Alignment.bottomCenter,
          child: _PhotoCard(
            key: ValueKey(entry.path),
            entry: entry,
            dx: _dx,
            dy: _dy,
            folderName: target == null ? null : pth.basename(target),
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
  final double dy;
  final String? folderName;
  final int cacheWidth;

  const _PhotoCard({
    super.key,
    required this.entry,
    required this.dx,
    required this.dy,
    required this.folderName,
    required this.cacheWidth,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.soft;
    final up = dy < -30 && dy.abs() > dx.abs() * 1.2;
    final showRing = up || dx.abs() > 30;
    final toDelete = !up && dx < 0;
    final tint = up ? p.accent : (toDelete ? p.remove : p.keep);
    final chipText = up
        ? (folderName ?? 'Choose folder')
        : (toDelete ? 'To delete' : 'Keep');
    final folder = pth.basename(pth.dirname(entry.path));
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: raisedDeco(p, radius: 32),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          fit: StackFit.expand,
          children: [
            MediaThumb(
                entry: entry,
                cacheWidth: cacheWidth,
                showPlay: true,
                fit: BoxFit.contain),
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
                  child: Text(chipText,
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
