import 'package:flutter/material.dart';

import '../app/controller.dart';
import '../app/theme.dart';
import 'files.dart';
import 'home.dart';
import 'soft.dart';
import 'swipe.dart';
import 'todelete.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  // 0 Home, 1 Files, 2 ToDelete. Swipe is a full-screen flow, not a tab.
  int _tab = 0;
  bool _selecting = false;

  Future<void> _openSwipe() async {
    final c = AppScope.read(context);
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const SwipePage()));
    await c.refreshCounts();
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    switch (_tab) {
      case 1:
        body = FilesPage(
          key: const ValueKey('files'),
          onSelectionChanged: (v) => setState(() => _selecting = v),
        );
        break;
      case 2:
        body = const ToDeletePage(key: ValueKey('todelete'));
        break;
      default:
        body = HomePage(key: const ValueKey('home'), onOpenSwipe: _openSwipe);
    }

    return SoftScaffold(
      child: Stack(
        children: [
          Positioned.fill(child: body),
          if (!_selecting)
            Positioned(
              left: 24,
              right: 24,
              bottom: 20,
              child: _NavBar(
                selected: _tab,
                onHome: () => setState(() {
                  _tab = 0;
                  _selecting = false;
                }),
                onSwipe: _openSwipe,
                onFiles: () => setState(() => _tab = 1),
                onToDelete: () => setState(() {
                  _tab = 2;
                  _selecting = false;
                }),
              ),
            ),
        ],
      ),
    );
  }
}

class _NavBar extends StatelessWidget {
  final int selected;
  final VoidCallback onHome;
  final VoidCallback onSwipe;
  final VoidCallback onFiles;
  final VoidCallback onToDelete;

  const _NavBar({
    required this.selected,
    required this.onHome,
    required this.onSwipe,
    required this.onFiles,
    required this.onToDelete,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.soft;
    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: raisedDeco(p, radius: 34),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _NavItem(
              icon: Icons.home_outlined,
              label: 'Home',
              active: selected == 0,
              onTap: onHome),
          _NavItem(
              icon: Icons.layers_outlined,
              label: 'Swipe',
              active: false,
              onTap: onSwipe),
          _NavItem(
              icon: Icons.view_list_outlined,
              label: 'Files',
              active: selected == 1,
              onTap: onFiles),
          _NavItem(
              icon: Icons.folder_outlined,
              label: 'ToDelete',
              active: selected == 2,
              onTap: onToDelete),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.soft;
    final color = active ? p.accent : p.muted;
    return SoftTap(
      onTap: onTap,
      label: label,
      child: Container(
        width: 72,
        height: 52,
        decoration: active ? pressedDeco(p, radius: 26) : null,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 2),
            Text(label,
                style: ts(context, 11, weight: FontWeight.w500, color: color)),
          ],
        ),
      ),
    );
  }
}
