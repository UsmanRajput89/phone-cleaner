import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../app/controller.dart';
import '../app/format.dart';
import '../app/theme.dart';
import '../core/models.dart';
import '../native.dart';
import 'media.dart';
import 'soft.dart';
import 'swipe.dart';

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

class DuplicatesPage extends StatefulWidget {
  const DuplicatesPage({super.key});

  @override
  State<DuplicatesPage> createState() => _DuplicatesPageState();
}

class _DuplicatesPageState extends State<DuplicatesPage> {
  final List<DupGroup> _groups = [];
  final ScrollController _scroll = ScrollController();
  bool _loading = false;
  bool _done = false;
  bool _wasBusy = false;

  static const int _page = 20;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 600) {
        _more();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final c = AppScope.read(context);
    _groups.clear();
    _done = false;
    await _more();
    await c.refreshCounts();
  }

  Future<void> _more() async {
    if (_loading || _done) return;
    _loading = true;
    final c = AppScope.read(context);
    final next = await c.store.dupGroups(limit: _page, offset: _groups.length);
    if (!mounted) return;
    setState(() {
      _groups.addAll(next);
      if (next.length < _page) _done = true;
      _loading = false;
    });
  }

  Future<void> _setKeeper(int index, FileEntry e) async {
    final g = _groups[index];
    if (identical(g.keeper, e) || e.dup == 1) return;
    final c = AppScope.read(context);
    await c.store.setKeeper(g.hash, e.path);
    final members = [
      for (final m in g.members) m.copyWith(dup: m.path == e.path ? 1 : 2),
    ]..sort((a, b) => (a.dup == 1 ? 0 : 1).compareTo(b.dup == 1 ? 0 : 1));
    if (!mounted) return;
    setState(() => _groups[index] = DupGroup(g.hash, g.size, members));
    c.refreshCountsSoon();
  }

  Future<void> _moveGroup(int index) async {
    final g = _groups[index];
    final c = AppScope.read(context);
    final n = g.members.length - 1;
    final ok = await _confirm(context,
        title: 'Move $n ${n == 1 ? 'extra copy' : 'extra copies'}?',
        body: '${formatBytes(g.extraBytes)} goes to ToDelete. The copy marked '
            'Keep stays where it is. You can restore from ToDelete.',
        action: 'Move to ToDelete');
    if (!ok || !mounted) return;
    final r = await c.moveExtrasOf([g]);
    if (!mounted) return;
    setState(() => _groups.removeAt(index));
    showSoftSnack(context, r[1] == 0
        ? 'Moved ${r[0]} to ToDelete'
        : 'Moved ${r[0]}, ${r[1]} could not be moved');
  }

  Future<void> _moveGroupAll(int index) async {
    final g = _groups[index];
    final c = AppScope.read(context);
    final ok = await _confirm(context,
        title: 'Move all ${g.members.length} copies?',
        body: 'Every copy of this file goes to ToDelete, including the one '
            'marked Keep (${formatBytes(g.size * g.members.length)}). '
            'You can restore from ToDelete.',
        action: 'Move all ${g.members.length}');
    if (!ok || !mounted) return;
    final r = await c.moveCopies(g.members);
    if (!mounted) return;
    await _refreshGroup(g.hash, index);
    if (!mounted) return;
    showSoftSnack(context, r[1] == 0
        ? 'Moved ${r[0]} to ToDelete'
        : 'Moved ${r[0]}, ${r[1]} could not be moved');
  }

  Future<void> _refreshGroup(String hash, int index) async {
    final c = AppScope.read(context);
    final ng = await c.store.dupGroupOf(hash);
    if (!mounted) return;
    setState(() {
      if (ng == null) {
        _groups.removeAt(index);
      } else {
        _groups[index] = ng;
      }
    });
    c.refreshCountsSoon();
  }

  Future<void> _openCopy(int index, FileEntry e) async {
    final g = _groups[index];
    final isKeeper = identical(g.keeper, e);
    final action = await Navigator.of(context).push<String>(MaterialPageRoute(
        builder: (_) => _CopyPage(entry: e, isKeeper: isKeeper)));
    if (!mounted || action == null) return;
    if (action == 'keep') {
      await _setKeeper(index, e);
    } else if (action == 'move') {
      final c = AppScope.read(context);
      await c.moveCopies([e]);
      if (!mounted) return;
      await _refreshGroup(g.hash, index);
      if (!mounted) return;
      showSoftSnack(context, 'Moved 1 to ToDelete');
    }
  }

  Future<void> _review() async {
    final c = AppScope.read(context);
    final keepers = <FileEntry>[];
    final copies = <String, List<FileEntry>>{};
    var off = 0;
    while (true) {
      final gs = await c.store.dupGroups(limit: 100, offset: off);
      if (gs.isEmpty) break;
      off += gs.length;
      for (final g in gs) {
        final k = g.keeper;
        if (k.kind == Kind.other) continue;
        keepers.add(k);
        copies[k.path] = g.extras;
      }
      if (gs.length < 100) break;
    }
    if (!mounted) return;
    if (keepers.isEmpty) {
      showSoftSnack(context, 'No duplicate photos or videos to review');
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) =>
            SwipePage(entries: keepers, copies: copies, title: 'Duplicates')));
    c.refreshCountsSoon();
    if (mounted) await _reload();
  }

  Future<void> _moveAll() async {
    final c = AppScope.read(context);
    final s = c.dupStats;
    final ok = await _confirm(context,
        title: 'Move all extras?',
        body: '${formatInt(s.extras)} extra copies (${formatBytes(s.bytes)}) '
            'from ${formatInt(s.groups)} groups go to ToDelete. One copy of '
            'every file stays. Nothing is deleted, you can restore from ToDelete.',
        action: 'Move ${formatInt(s.extras)} to ToDelete');
    if (!ok || !mounted) return;
    final r = await c.moveAllExtras();
    if (!mounted) return;
    showSoftSnack(context, r[1] == 0
        ? 'Moved ${formatInt(r[0])} to ToDelete'
        : 'Moved ${formatInt(r[0])}, ${r[1]} could not be moved');
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.soft;
    final c = AppScope.of(context);
    final s = c.dupStats;
    final busy = c.dupScanning || c.dupMoving;
    if (_wasBusy && !busy) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reload();
      });
    }
    _wasBusy = busy;

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
      sub = '${formatInt(s.extras)} extra copies · ${formatBytes(s.bytes)} to free';
    }

    return SoftScaffold(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
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
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (c.dupScanning) ...[
                  SoftSlot(
                      value: c.dupTotal == 0 ? 0 : c.dupDone / c.dupTotal),
                  const SizedBox(height: 12),
                  SoftPill(
                      label: 'Stop',
                      icon: Icons.stop_rounded,
                      height: 46,
                      color: pal.muted,
                      onTap: c.cancelDupScan),
                ] else if (c.dupMoving) ...[
                  SoftSlot(
                      value: c.dupMoveTotal == 0
                          ? 0
                          : c.dupMoved / c.dupMoveTotal),
                ] else ...[
                  SoftPill(
                    label: c.dupEverScanned ? 'Scan again' : 'Find duplicates',
                    icon: Icons.search_rounded,
                    height: 46,
                    onTap: c.findDuplicates,
                  ),
                  if (s.extras > 0) ...[
                    const SizedBox(height: 12),
                    SoftPill(
                      label: 'Review duplicates',
                      icon: Icons.swipe_rounded,
                      height: 46,
                      color: pal.keep,
                      onTap: _review,
                    ),
                    const SizedBox(height: 12),
                    SoftPill(
                      label:
                          'Move all extras · ${formatBytes(s.bytes)}',
                      icon: Icons.drive_file_move_outlined,
                      height: 46,
                      color: pal.remove,
                      onTap: _moveAll,
                    ),
                  ],
                ],
              ],
            ),
          ),
          Expanded(
            child: _groups.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        _loading
                            ? 'Loading...'
                            : (c.dupEverScanned
                                ? 'No identical files found.'
                                : 'Tap Find duplicates. Only files with the exact same content are matched. Nothing is changed by scanning.'),
                        textAlign: TextAlign.center,
                        style: ts(context, 14, color: pal.muted, height: 1.5),
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(24, 10, 24, 40),
                    itemCount: _groups.length,
                    itemBuilder: (context, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _GroupCard(
                        group: _groups[i],
                        enabled: !busy,
                        onOpen: (e) => _openCopy(i, e),
                        onMove: () => _moveGroup(i),
                        onMoveAll: () => _moveGroupAll(i),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  final DupGroup group;
  final bool enabled;
  final void Function(FileEntry) onOpen;
  final VoidCallback onMove;
  final VoidCallback onMoveAll;

  const _GroupCard({
    required this.group,
    required this.enabled,
    required this.onOpen,
    required this.onMove,
    required this.onMoveAll,
  });

  @override
  Widget build(BuildContext context) {
    final pal = context.soft;
    final n = group.members.length;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: raisedDeco(pal),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '$n copies · ${formatBytes(group.size)} each',
            style: ts(context, 14, weight: FontWeight.w500),
          ),
          const SizedBox(height: 2),
          Text('Tap a copy to look at it or choose it as the one to keep',
              style: ts(context, 12, color: pal.muted)),
          const SizedBox(height: 12),
          SizedBox(
            height: 128,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: n,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final e = group.members[i];
                final keep = e.dup == 1 || (i == 0 && group.members.every((m) => m.dup != 1));
                return SoftTap(
                  label: keep ? 'Kept copy' : 'Keep this copy',
                  onTap: enabled ? () => onOpen(e) : null,
                  child: SizedBox(
                    width: 88,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          height: 88,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: keep ? pal.keep : pal.ring,
                                width: keep ? 2 : 1),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: MediaThumb(entry: e, cacheWidth: 200),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(keep ? 'Keep' : 'Extra',
                            style: ts(context, 12,
                                weight: FontWeight.w500,
                                color: keep ? pal.keep : pal.remove)),
                        Text(dupSource(e.path),
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
          const SizedBox(height: 12),
          SoftPill(
            label:
                'Move ${n - 1} ${n - 1 == 1 ? 'extra' : 'extras'} · ${formatBytes(group.extraBytes)}',
            height: 42,
            color: pal.remove,
            onTap: enabled ? onMove : null,
          ),
          const SizedBox(height: 10),
          SoftPill(
            label: 'Move all $n copies',
            height: 42,
            color: pal.muted,
            onTap: enabled ? onMoveAll : null,
          ),
        ],
      ),
    );
  }
}

/// Full-size look at one copy, with the choices for it.
class _CopyPage extends StatelessWidget {
  final FileEntry entry;
  final bool isKeeper;

  const _CopyPage({required this.entry, required this.isKeeper});

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
                  child: Text(isKeeper ? 'Kept copy' : 'Extra copy',
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
            if (!isKeeper) ...[
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
            const SizedBox(height: 10),
            SoftPill(
                label: 'Move this copy to ToDelete',
                color: pal.remove,
                height: 46,
                onTap: () => Navigator.of(context).pop('move')),
          ],
        ),
      ),
    );
  }
}
