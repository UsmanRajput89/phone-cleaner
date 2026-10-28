import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../app/controller.dart';
import '../app/format.dart';
import '../app/theme.dart';
import '../core/models.dart';
import '../native.dart';
import 'media.dart';
import 'soft.dart';

/// Short, human label for where a copy lives.
String dupSource(String path, {String safeRoot = AppController.safePath}) {
  final l = path.toLowerCase();
  if (p.isWithin(safeRoot, path)) return 'Safe';
  if (l.contains('/android/media/com.whatsapp')) {
    return l.contains('/sent/') ? 'WhatsApp sent' : 'WhatsApp';
  }
  if (l.contains('/whatsapp/media/')) return 'WhatsApp (old)';
  if (l.contains('/dcim/')) return 'Camera';
  if (l.contains('/download/') || l.contains('/downloads/')) return 'Downloads';
  return p.basename(p.dirname(path));
}

Future<bool> _confirm(BuildContext context,
    {required String title, required String body, required String action}) async {
  final pal = context.soft;
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: pal.bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(color: pal.ring),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: ts(ctx, 20)),
            const SizedBox(height: 10),
            Text(body, style: ts(ctx, 14, color: pal.muted, height: 1.5)),
            const SizedBox(height: 20),
            SoftPill(
                label: action,
                color: pal.remove,
                onTap: () => Navigator.of(ctx).pop(true)),
            const SizedBox(height: 12),
            SoftPill(
                label: 'Cancel',
                color: pal.muted,
                onTap: () => Navigator.of(ctx).pop(false)),
          ],
        ),
      ),
    ),
  );
  return r == true;
}

class DuplicatesPage extends StatelessWidget {
  const DuplicatesPage({super.key});

  Future<void> _moveAll(BuildContext context) async {
    final c = AppScope.read(context);
    final s = c.dupStats;
    final ok = await _confirm(context,
        title: 'Move all extras?',
        body: '${formatInt(s.extras)} extra copies (${formatBytes(s.bytes)}) '
            'from ${formatInt(s.groups)} groups go to ToDelete. One copy of '
            'every file stays, chosen by the app. Nothing is deleted, you can '
            'restore from ToDelete.',
        action: 'Move ${formatInt(s.extras)} to ToDelete');
    if (!ok || !context.mounted) return;
    final r = await c.moveAllExtras();
    if (!context.mounted) return;
    showSoftSnack(context, r[1] == 0
        ? 'Moved ${formatInt(r[0])} to ToDelete'
        : 'Moved ${formatInt(r[0])}, ${r[1]} could not be moved');
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.soft;
    final c = AppScope.of(context);
    final s = c.dupStats;
    final String sub;
    if (c.dupScanning) {
      sub = 'Checking files ${formatInt(c.dupDone)} of ${formatInt(c.dupTotal)}';
    } else if (c.dupMoving) {
      sub = 'Moving ${formatInt(c.dupMoved)} of ${formatInt(c.dupMoveTotal)}';
    } else if (!c.dupEverScanned) {
      sub = 'Not scanned yet';
    } else if (s.extras == 0) {
      sub = 'No duplicates found';
    } else {
      sub = '${formatInt(s.groups)} groups · ${formatInt(s.extras)} extra copies · ${formatBytes(s.bytes)} to free';
    }
    return SoftScaffold(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                SoftIconButton(
                  icon: Icons.arrow_back_rounded,
                  label: 'Back',
                  onTap: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Duplicates', style: ts(context, 20)),
                      const SizedBox(height: 2),
                      Text(sub, style: ts(context, 12, color: pal.muted)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (c.dupScanning) ...[
              SoftSlot(value: c.dupTotal == 0 ? 0 : c.dupDone / c.dupTotal),
              const SizedBox(height: 14),
              SoftPill(
                  label: 'Stop',
                  icon: Icons.stop_rounded,
                  color: pal.muted,
                  onTap: c.cancelDupScan),
            ] else if (c.dupMoving) ...[
              SoftSlot(
                  value: c.dupMoveTotal == 0 ? 0 : c.dupMoved / c.dupMoveTotal),
            ] else ...[
              if (s.extras > 0) ...[
                SoftPill(
                  label: 'Review side by side',
                  icon: Icons.view_agenda_outlined,
                  color: pal.keep,
                  onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                          builder: (_) => const ComparePage())),
                ),
                const SizedBox(height: 14),
                SoftPill(
                  label: 'Move all extras · ${formatBytes(s.bytes)}',
                  icon: Icons.drive_file_move_outlined,
                  color: pal.remove,
                  onTap: () => _moveAll(context),
                ),
                const SizedBox(height: 14),
              ],
              SoftPill(
                label: c.dupEverScanned ? 'Scan again' : 'Find duplicates',
                icon: Icons.search_rounded,
                color: pal.accent,
                onTap: c.findDuplicates,
              ),
            ],
            const SizedBox(height: 20),
            Text(
              'Only files with exactly the same content are matched. Scanning '
              'changes nothing. "Review side by side" lets you choose per '
              'group; "Move all extras" keeps the live WhatsApp copy (or the '
              'Camera one) of each file and sends the rest to ToDelete.',
              style: ts(context, 12, color: pal.muted, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _Applied {
  final DupGroup group;
  final List<_MovedCopy> moved;
  final bool released;

  _Applied(this.group, this.moved, this.released);
}

class _MovedCopy {
  final FileEntry entry;
  final String trashPath;

  _MovedCopy(this.entry, this.trashPath);
}

/// One group at a time, every copy on screen, each marked Keep or Delete.
class ComparePage extends StatefulWidget {
  const ComparePage({super.key});

  @override
  State<ComparePage> createState() => _ComparePageState();
}

class _ComparePageState extends State<ComparePage> {
  final List<DupGroup> _groups = [];
  final List<_Applied> _history = [];
  Set<String> _delete = {};
  int _i = 0;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final c = AppScope.read(context);
    var off = 0;
    while (true) {
      final gs = await c.store.dupGroups(limit: 100, offset: off);
      _groups.addAll(gs);
      off += gs.length;
      if (gs.length < 100) break;
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _resetMarks();
    });
  }

  DupGroup? get _group => _i < _groups.length ? _groups[_i] : null;

  void _resetMarks() {
    final g = _group;
    if (g == null) {
      _delete = {};
      return;
    }
    final keeper = g.keeper;
    _delete = {
      for (final m in g.members)
        if (!identical(m, keeper)) m.path,
    };
  }

  void _toggle(FileEntry e) {
    if (_busy) return;
    setState(() {
      if (!_delete.remove(e.path)) _delete.add(e.path);
    });
  }

  Future<void> _apply() async {
    final g = _group;
    if (g == null || _busy) return;
    setState(() => _busy = true);
    final c = AppScope.read(context);
    final moved = <_MovedCopy>[];
    var failed = 0;
    for (final m in g.members) {
      if (!_delete.contains(m.path)) continue;
      try {
        moved.add(_MovedCopy(m, await c.moveToTrash(m)));
      } catch (_) {
        failed++;
      }
    }
    final keptCount = g.members.length - moved.length;
    var released = false;
    if (keptCount >= 2) {
      await c.store.releaseGroup(g.hash);
      released = true;
    } else {
      await c.store.reassignGroup(g.hash);
    }
    _history.add(_Applied(g, moved, released));
    c.refreshCountsSoon();
    if (!mounted) return;
    setState(() {
      _i++;
      _busy = false;
      _resetMarks();
    });
    if (failed > 0) showSoftSnack(context, '$failed could not be moved');
  }

  Future<void> _undo() async {
    if (_busy || _history.isEmpty) return;
    setState(() => _busy = true);
    final c = AppScope.read(context);
    final a = _history.removeLast();
    try {
      if (a.released) {
        final movedPaths = {for (final m in a.moved) m.entry.path};
        await c.store.setHashes({
          for (final m in a.group.members)
            if (!movedPaths.contains(m.path)) m.path: a.group.hash,
        });
      }
      for (final m in a.moved) {
        try {
          await c.restore(m.trashPath, m.entry.path, Status.pending);
        } catch (_) {}
      }
      await c.store.reassignGroup(a.group.hash);
      final fresh = await c.store.dupGroupOf(a.group.hash);
      if (fresh != null && _i > 0) _groups[_i - 1] = fresh;
      c.refreshCountsSoon();
    } catch (_) {
      if (mounted) showSoftSnack(context, 'Could not undo that');
    }
    if (!mounted) return;
    setState(() {
      if (_i > 0) _i--;
      _busy = false;
      _resetMarks();
    });
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.soft;
    final g = _group;
    return SoftScaffold(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                SoftIconButton(
                  icon: Icons.arrow_back_rounded,
                  label: 'Back',
                  onTap: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          g == null
                              ? 'Duplicates'
                              : '${_i + 1} / ${_groups.length}',
                          style: ts(context, 20)),
                      if (g != null)
                        Text(
                            '${g.members.length} copies · ${formatBytes(g.size)} each',
                            style: ts(context, 12, color: pal.muted)),
                    ],
                  ),
                ),
                SoftIconButton(
                  icon: Icons.undo_rounded,
                  label: 'Undo',
                  onTap: (!_busy && _history.isNotEmpty) ? _undo : null,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(child: _body(context, g)),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, DupGroup? g) {
    final pal = context.soft;
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: pal.accent));
    }
    if (g == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_groups.isEmpty ? 'Nothing to review' : 'All reviewed',
                style: ts(context, 22, weight: FontWeight.w300)),
            const SizedBox(height: 20),
            SoftPill(
                label: 'Back',
                expand: false,
                onTap: () => Navigator.of(context).pop()),
          ],
        ),
      );
    }
    final delCount = g.members.where((m) => _delete.contains(m.path)).length;
    final keepCount = g.members.length - delCount;
    final label = delCount == 0
        ? 'Keep all $keepCount'
        : (keepCount == 0
            ? 'Delete all $delCount'
            : 'Delete $delCount, keep $keepCount');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.78,
            ),
            itemCount: g.members.length,
            itemBuilder: (context, i) {
              final e = g.members[i];
              final del = _delete.contains(e.path);
              final tint = del ? pal.remove : pal.keep;
              return SoftTap(
                label: del ? 'Marked delete' : 'Marked keep',
                onTap: () => _toggle(e),
                child: GestureDetector(
                  onLongPress: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                          builder: (_) => _CopyPage(entry: e))),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: pal.bg,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: tint, width: 3),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                MediaThumb(
                                    entry: e,
                                    cacheWidth: 500,
                                    fit: BoxFit.contain),
                                Positioned(
                                  top: 8,
                                  left: 8,
                                  child: Container(
                                    height: 26,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10),
                                    alignment: Alignment.center,
                                    decoration: raisedDeco(pal, radius: 13),
                                    child: Text(del ? 'DELETE' : 'KEEP',
                                        style: ts(context, 11,
                                            weight: FontWeight.w500,
                                            color: tint)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(dupSource(e.path),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ts(context, 12, weight: FontWeight.w500)),
                      Text('${formatDate(e.mtime)} · ${e.name}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ts(context, 11, color: pal.muted)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Text('Tap a copy to switch Keep / Delete · long press to open',
            textAlign: TextAlign.center,
            style: ts(context, 11, color: pal.muted)),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: SoftPill(
                label: 'Keep all',
                height: 44,
                color: pal.keep,
                onTap: _busy
                    ? null
                    : () => setState(() => _delete = {}),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SoftPill(
                label: 'Delete all',
                height: 44,
                color: pal.remove,
                onTap: _busy
                    ? null
                    : () => setState(
                        () => _delete = {for (final m in g.members) m.path}),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SoftPill(
          label: '$label · next',
          icon: Icons.check_rounded,
          color: delCount == g.members.length ? pal.remove : pal.accent,
          onTap: _busy ? null : _apply,
        ),
      ],
    );
  }
}

/// Full-size look at one copy, with the choices for it.
class _CopyPage extends StatelessWidget {
  final FileEntry entry;
  final bool isKeeper;
  final bool viewOnly;

  const _CopyPage(
      {required this.entry, this.isKeeper = false, this.viewOnly = true});

  @override
  Widget build(BuildContext context) {
    final pal = context.soft;
    return SoftScaffold(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                SoftIconButton(
                  icon: Icons.arrow_back_rounded,
                  label: 'Back',
                  onTap: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(viewOnly ? 'Copy' : (isKeeper ? 'Kept copy' : 'Extra copy'),
                      style: ts(context, 20)),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Expanded(
              child: GestureDetector(
                onTap: entry.kind == Kind.video
                    ? () => Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => VideoPage(path: entry.path)))
                    : null,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: raisedDeco(pal, radius: 24),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: MediaThumb(
                        entry: entry,
                        cacheWidth: 1200,
                        showPlay: true,
                        fit: BoxFit.contain),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(entry.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ts(context, 15, weight: FontWeight.w500)),
            const SizedBox(height: 2),
            Text(
                '${formatBytes(entry.size)} · ${formatDate(entry.mtime)} · ${dupSource(entry.path)}',
                style: ts(context, 12, color: pal.muted)),
            const SizedBox(height: 14),
            if (!viewOnly && !isKeeper) ...[
              SoftPill(
                  label: 'Keep this one',
                  color: pal.keep,
                  height: 46,
                  onTap: () => Navigator.of(context).pop('keep')),
              const SizedBox(height: 10),
            ],
            SoftPill(
                label: 'Open in app',
                color: pal.accent,
                height: 46,
                onTap: () => Native.openFile(entry.path)),
            if (!viewOnly) ...[
              const SizedBox(height: 10),
              SoftPill(
                  label: 'Move this copy to ToDelete',
                  color: pal.remove,
                  height: 46,
                  onTap: () => Navigator.of(context).pop('move')),
            ],
          ],
        ),
      ),
    );
  }
}
