import 'dart:io';

import 'package:flutter/material.dart';

import '../app/controller.dart';
import '../app/format.dart';
import '../app/theme.dart';
import '../core/models.dart';
import 'soft.dart';

Future<void> showScanReport(BuildContext context) {
  final p = context.soft;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: p.bg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => const _ReportBody(),
  );
}

class _Row {
  final String label;
  final int count;
  final int bytes;
  _Row(this.label, this.count, this.bytes);
}

class _ReportBody extends StatefulWidget {
  const _ReportBody();

  @override
  State<_ReportBody> createState() => _ReportBodyState();
}

class _ReportBodyState extends State<_ReportBody> {
  List<_Row>? _wa;
  List<_Row>? _buckets;
  String? _saved;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final c = AppScope.read(context);
    final stats = await c.store.folderStats('whatsapp', Status.pending);
    final wa = stats.entries
        .map((e) => _Row(e.key.replaceFirst('/storage/emulated/0/', ''),
            e.value[0], e.value[1]))
        .toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    final counts = await c.store.counts();
    final buckets = <_Row>[];
    counts.byBucket.forEach((b, v) {
      buckets.add(_Row('${b.name} (unreviewed)', v.pending, 0));
    });
    var text = StringBuffer('Phone Cleaner scan report\n\n');
    for (final r in buckets) {
      text.writeln('${r.label}: ${r.count}');
    }
    text.writeln('\nWhatsApp folders (unreviewed):');
    for (final r in wa) {
      text.writeln('${r.count}\t${formatBytes(r.bytes)}\t${r.label}');
    }
    String? saved;
    try {
      final f = File('/storage/emulated/0/Download/phone-cleaner-report.txt');
      await f.writeAsString(text.toString());
      saved = 'Saved to Download/phone-cleaner-report.txt';
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _wa = wa;
      _buckets = buckets;
      _saved = saved;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.soft;
    final h = MediaQuery.of(context).size.height * 0.85;
    return SafeArea(
      child: SizedBox(
        height: h,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: _wa == null
              ? Center(child: CircularProgressIndicator(color: p.accent))
              : ListView(
                  children: [
                    Text('Scan report', style: ts(context, 22)),
                    if (_saved != null) ...[
                      const SizedBox(height: 6),
                      Text(_saved!, style: ts(context, 12, color: p.muted)),
                    ],
                    const SizedBox(height: 16),
                    for (final r in _buckets!)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(r.label, style: ts(context, 14)),
                            Text(formatInt(r.count),
                                style: ts(context, 14, color: p.muted)),
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),
                    Text('WHATSAPP FOLDERS (UNREVIEWED)',
                        style: ts(context, 12, color: p.muted, letterSpacing: 1)),
                    const SizedBox(height: 10),
                    for (final r in _wa!.take(30))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r.label,
                                style: ts(context, 13, color: p.text)),
                            Text('${formatInt(r.count)} files · ${formatBytes(r.bytes)}',
                                style: ts(context, 12, color: p.muted)),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}
