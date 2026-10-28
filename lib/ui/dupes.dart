import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../app/controller.dart';
import '../app/format.dart';
import '../app/theme.dart';
import '../core/models.dart';
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
                        onPick: (e) => _setKeeper(i, e),
                        onMove: () => _moveGroup(i),
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
  final void Function(FileEntry) onPick;
  final VoidCallback onMove;

  const _GroupCard({
    required this.group,
    required this.enabled,
    required this.onPick,
    required this.onMove,
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
          Text('Tap a copy to keep that one instead',
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
                  onTap: enabled ? () => onPick(e) : null,
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
        ],
      ),
    );
  }
}
