import 'package:flutter/material.dart';

import '../app/controller.dart';
import '../app/theme.dart';
import 'report.dart';
import 'soft.dart';

const String appVersion =
    String.fromEnvironment('APP_VERSION', defaultValue: 'dev');

Future<void> showSettingsSheet(BuildContext context) {
  final p = context.soft;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: p.bg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => const _SettingsBody(),
  );
}

class _SettingsBody extends StatelessWidget {
  const _SettingsBody();

  @override
  Widget build(BuildContext context) {
    final p = context.soft;
    final c = AppScope.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Settings', style: ts(context, 22)),
            const SizedBox(height: 20),
            Text('Theme', style: ts(context, 13, color: p.muted)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SoftChip(
                    label: 'System',
                    selected: c.themeMode == 'system',
                    onTap: () => c.setThemeMode('system')),
                SoftChip(
                    label: 'Dark',
                    selected: c.themeMode == 'dark',
                    onTap: () => c.setThemeMode('dark')),
                SoftChip(
                    label: 'Light',
                    selected: c.themeMode == 'light',
                    onTap: () => c.setThemeMode('light')),
              ],
            ),
            const SizedBox(height: 20),
            Text('WhatsApp media in review',
                style: ts(context, 13, color: p.muted)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SoftChip(
                    label: 'Off',
                    selected: !c.includeWhatsApp,
                    onTap: () => c.setIncludeWhatsApp(false)),
                SoftChip(
                    label: 'On',
                    selected: c.includeWhatsApp,
                    onTap: () => c.setIncludeWhatsApp(true)),
              ],
            ),
            const SizedBox(height: 24),
            SoftPill(
              label: c.scanning ? 'Scanning...' : 'Rescan files',
              icon: Icons.refresh_rounded,
              onTap: c.scanning
                  ? null
                  : () async {
                      Navigator.of(context).pop();
                      await c.rescan();
                    },
            ),
            const SizedBox(height: 12),
            SoftPill(
              label: 'Scan report',
              icon: Icons.list_alt_rounded,
              onTap: () {
                Navigator.of(context).pop();
                showScanReport(context);
              },
            ),
            const SizedBox(height: 16),
            Text(
              'This app only moves files into the ToDelete folder. It never '
              'deletes anything. Delete from the Gallery or the Files app.',
              style: ts(context, 12, color: p.muted, height: 1.5),
            ),
            const SizedBox(height: 10),
            Text('Version $appVersion', style: ts(context, 12, color: p.muted)),
          ],
        ),
      ),
    );
  }
}
