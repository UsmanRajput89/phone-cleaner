import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/controller.dart';
import '../app/format.dart';
import '../app/theme.dart';
import '../core/models.dart';
import 'dupes.dart';
import 'swipe.dart';
import 'settings.dart';
import 'soft.dart';

class HomePage extends StatelessWidget {
  final VoidCallback onOpenSwipe;

  const HomePage({super.key, required this.onOpenSwipe});

  @override
  Widget build(BuildContext context) {
    final p = context.soft;
    final c = AppScope.of(context);
    final counts = c.counts;
    if (counts == null) {
      return Center(child: CircularProgressIndicator(color: p.accent));
    }

    final total = counts.total;
    final reviewed = counts.reviewed;
    final frac = total == 0 ? 0.0 : reviewed / total;

    final rows = <_BucketRow>[
      _BucketRow('Camera', [Bucket.camera], false),
      _BucketRow('Screenshots', [Bucket.screenshots], false),
      _BucketRow('WhatsApp', [Bucket.whatsapp], !c.includeWhatsApp),
      _BucketRow('Downloads and files', [Bucket.downloads, Bucket.other], false),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 110),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 56,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Phone Cleaner', style: ts(context, 22)),
                SoftIconButton(
                  icon: Icons.settings_outlined,
                  label: 'Settings',
                  color: p.muted,
                  onTap: () => showSettingsSheet(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 184,
              height: 184,
              alignment: Alignment.center,
              decoration: raisedDeco(p, circle: true),
              child: Container(
                width: 150,
                height: 150,
                decoration: pressedDeco(p, circle: true),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _RingPainter(progress: frac, color: p.accent),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(formatInt(reviewed),
                            style: ts(context, 32,
                                weight: FontWeight.w300, height: 1.1)),
                        const SizedBox(height: 2),
                        Text('of ${formatInt(total)}',
                            style: ts(context, 12, color: p.muted)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  label: 'In ToDelete',
                  value: formatInt(counts.trash),
                  sub: formatBytes(counts.trashBytes),
                  color: p.remove,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _StatCard(
                  label: 'Kept',
                  value: formatInt(counts.kept),
                  sub: 'files',
                  color: p.keep,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SoftPill(label: 'Continue swiping', onTap: onOpenSwipe),
          const SizedBox(height: 14),
          _DupCard(c: c),
          const SizedBox(height: 14),
          _VideoCard(c: c),
          const SizedBox(height: 22),
          Text(
            'LEFT TO REVIEW',
            style: ts(context, 12, color: p.muted, letterSpacing: 1),
          ),
          const SizedBox(height: 12),
          for (final r in rows) ...[
            _BucketTile(row: r, counts: counts),
            const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }
}

class _BucketRow {
  final String label;
  final List<Bucket> buckets;
  final bool off;

  const _BucketRow(this.label, this.buckets, this.off);
}

class _BucketTile extends StatelessWidget {
  final _BucketRow row;
  final Counts counts;

  const _BucketTile({required this.row, required this.counts});

  @override
  Widget build(BuildContext context) {
    final p = context.soft;
    var total = 0;
    var pending = 0;
    for (final b in row.buckets) {
      final bc = counts.byBucket[b];
      if (bc == null) continue;
      total += bc.total;
      pending += bc.pending;
    }
    final frac = total == 0 ? 0.0 : (total - pending) / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(row.label, style: ts(context, 15)),
                if (row.off) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
                    decoration: pressedDeco(p, radius: 10),
                    child: Text('Off',
                        style: ts(context, 11,
                            weight: FontWeight.w500, color: p.muted)),
                  ),
                ],
              ],
            ),
            Text(formatInt(pending), style: ts(context, 13, color: p.muted)),
          ],
        ),
        const SizedBox(height: 8),
        SoftSlot(value: frac),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String sub;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.sub,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.soft;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: raisedDeco(p),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: ts(context, 12, color: p.muted)),
          const SizedBox(height: 2),
          Text(value,
              style: ts(context, 24, weight: FontWeight.w300, color: color)),
          const SizedBox(height: 2),
          Text(sub, style: ts(context, 12, color: p.muted)),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;

  _RingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    const stroke = 8.0;
    final radius = (size.shortestSide - stroke) / 2 - 3;
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress.clamp(0.0, 1.0).toDouble(),
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress || old.color != color;
}

class _DupCard extends StatelessWidget {
  final AppController c;

  const _DupCard({required this.c});

  @override
  Widget build(BuildContext context) {
    final p = context.soft;
    final s = c.dupStats;
    final String title;
    final String sub;
    if (c.dupScanning) {
      title = 'Checking for duplicates';
      sub = '${formatInt(c.dupDone)} of ${formatInt(c.dupTotal)} files';
    } else if (!c.dupEverScanned) {
      title = 'Find duplicates';
      sub = 'Spot identical copies, mostly WhatsApp';
    } else if (s.extras == 0) {
      title = 'Duplicates';
      sub = 'No identical files found';
    } else {
      title = 'Duplicates: ${formatInt(s.extras)} extra copies';
      sub = '${formatBytes(s.bytes)} you can free';
    }
    return SoftTap(
      label: 'Duplicates',
      onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const DuplicatesPage())),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: raisedDeco(p),
        child: Row(
          children: [
            Icon(Icons.copy_all_rounded, color: p.accent, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: ts(context, 15)),
                  const SizedBox(height: 2),
                  Text(sub, style: ts(context, 12, color: p.muted)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: p.muted),
          ],
        ),
      ),
    );
  }
}

class _VideoCard extends StatelessWidget {
  final AppController c;

  const _VideoCard({required this.c});

  @override
  Widget build(BuildContext context) {
    final p = context.soft;
    return SoftTap(
      label: 'Videos, largest first',
      onTap: c.videoCount == 0
          ? null
          : () async {
              await Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const SwipePage(
                      initialKinds: {Kind.video},
                      initialSort: SortMode.largest)));
              c.refreshCountsSoon();
            },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: raisedDeco(p),
        child: Row(
          children: [
            Icon(Icons.videocam_outlined, color: p.accent, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Videos, largest first', style: ts(context, 15)),
                  const SizedBox(height: 2),
                  Text(
                      '${formatInt(c.videoCount)} to review · ${formatBytes(c.videoBytes)}',
                      style: ts(context, 12, color: p.muted)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: p.muted),
          ],
        ),
      ),
    );
  }
}
