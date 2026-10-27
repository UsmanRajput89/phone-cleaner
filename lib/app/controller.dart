import 'dart:async';

import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/mover.dart';
import '../core/scanner.dart';
import '../core/store.dart';
import '../native.dart';

class AppController extends ChangeNotifier {
  static const String rootPath = '/storage/emulated/0';
  static const String trashPath = '/storage/emulated/0/ToDelete';

  final Store store;
  final Mover mover;
  final MediaRescanner rescanner = MediaRescanner();

  String themeMode = 'system';
  bool includeWhatsApp = false;
  Counts? counts;
  bool scanning = false;
  Timer? _countsTimer;

  AppController._(this.store) : mover = Mover(trashPath);

  static Future<AppController> create() async {
    final store = await Store.open();
    final c = AppController._(store);
    c.themeMode = (await store.getSetting('theme')) ?? 'system';
    c.includeWhatsApp = (await store.getSetting('whatsapp')) == '1';
    await store.purgeStickers();
    return c;
  }

  ThemeMode get flutterThemeMode {
    switch (themeMode) {
      case 'dark':
        return ThemeMode.dark;
      case 'light':
        return ThemeMode.light;
      default:
        return ThemeMode.system;
    }
  }

  Future<void> setThemeMode(String mode) async {
    themeMode = mode;
    notifyListeners();
    await store.setSetting('theme', mode);
  }

  Future<void> setIncludeWhatsApp(bool value) async {
    includeWhatsApp = value;
    notifyListeners();
    await store.setSetting('whatsapp', value ? '1' : '0');
  }

  Future<void> refreshCounts() async {
    counts = await store.counts();
    notifyListeners();
  }

  void refreshCountsSoon() {
    _countsTimer?.cancel();
    _countsTimer = Timer(const Duration(milliseconds: 500), refreshCounts);
  }

  Future<void> rescan() async {
    if (scanning) return;
    scanning = true;
    notifyListeners();
    try {
      final found = await scanInBackground(const ScanConfig(root: rootPath));
      await store.insertScanned(found);
    } finally {
      scanning = false;
    }
    await refreshCounts();
  }

  Future<void> keep(FileEntry e) => store.markKept(e.path);

  Future<void> unkeep(FileEntry e) => store.setPending(e.path);

  /// Moves the file into ToDelete. Returns the new path.
  Future<String> moveToTrash(FileEntry e) async {
    final newPath = await mover.moveToTrash(e.path);
    await store.markMoved(e.path, newPath);
    rescanner.add([e.path, newPath]);
    return newPath;
  }

  /// Moves a file from ToDelete back to [origPath]. Returns the new path.
  Future<String> restore(String currentPath, String origPath, int status) async {
    final newPath = await mover.restore(currentPath, origPath);
    await store.markRestored(currentPath, newPath, status);
    rescanner.add([currentPath, newPath]);
    return newPath;
  }

  @override
  void dispose() {
    _countsTimer?.cancel();
    super.dispose();
  }
}

class AppScope extends InheritedNotifier<AppController> {
  const AppScope({
    super.key,
    required AppController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppController of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
  }

  static AppController read(BuildContext context) {
    return context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
  }
}
