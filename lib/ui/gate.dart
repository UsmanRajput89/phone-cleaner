import 'package:flutter/material.dart';

import '../app/controller.dart';
import '../app/theme.dart';
import '../native.dart';
import 'shell.dart';
import 'soft.dart';

/// Checks the "All files access" permission, runs the first scan, then shows
/// the app.
class Gate extends StatefulWidget {
  const Gate({super.key});

  @override
  State<Gate> createState() => _GateState();
}

class _GateState extends State<Gate> with WidgetsBindingObserver {
  bool _checked = false;
  bool _granted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_granted) _check();
  }

  Future<void> _check() async {
    final c = AppScope.read(context);
    final ok = await Native.hasAllFilesAccess();
    if (!mounted) return;
    setState(() {
      _checked = true;
      _granted = ok;
    });
    if (ok) {
      await c.refreshCounts();
      if ((c.counts?.total ?? 0) == 0) {
        await c.rescan();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final p = context.soft;

    if (!_checked) {
      return SoftScaffold(
        child: Center(child: CircularProgressIndicator(color: p.accent)),
      );
    }
    if (!_granted) {
      return SoftScaffold(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('One permission needed',
                  style: ts(context, 26, weight: FontWeight.w300)),
              const SizedBox(height: 16),
              Text(
                'Phone Cleaner needs "All files access" to see your photos, videos '
                'and documents and to move them into the ToDelete folder. '
                'It never deletes anything itself.',
                style: ts(context, 15, color: p.muted, height: 1.5),
              ),
              const SizedBox(height: 32),
              SoftPill(
                label: 'Allow access',
                onTap: () => Native.requestAllFilesAccess(),
              ),
              const SizedBox(height: 16),
              Text(
                'On the next screen, switch on "Allow access to manage all files", '
                'then come back.',
                textAlign: TextAlign.center,
                style: ts(context, 13, color: p.muted),
              ),
            ],
          ),
        ),
      );
    }
    if (c.scanning || c.counts == null) {
      return SoftScaffold(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: p.accent),
              const SizedBox(height: 24),
              Text('Scanning your files', style: ts(context, 18)),
              const SizedBox(height: 8),
              Text('This only takes a moment the first time.',
                  style: ts(context, 13, color: p.muted)),
            ],
          ),
        ),
      );
    }
    return const Shell();
  }
}
