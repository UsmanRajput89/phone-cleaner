import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:path/path.dart' as p;

import '../core/classify.dart';
import '../core/models.dart';
import '../core/mover.dart';
import '../core/scanner.dart';
import '../core/store.dart';
import '../native.dart';

class AppController extends ChangeNotifier {
  static const String rootPath = '/storage/emulated/0';
  static const String trashPath = '/storage/emulated/0/ToDelete';
  static const String safePath = '/storage/emulated/0/Safe';

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
    await store.setSetting('whatsapp', value ? '1' : '0');
    await refreshCounts();
  }

  Future<void> refreshCounts() async {
    counts = await store.counts(whatsappOff: !includeWhatsApp);
    notifyListeners();
  }

  void refreshCountsSoon() {
    _countsTimer?.cancel();
    _countsTimer = Timer(const Duration(milliseconds: 500), refreshCounts);
    _backupTimer?.cancel();
    _backupTimer = Timer(const Duration(seconds: 8), backupState);
  }

  static const String backupFile = '/storage/emulated/0/.phone_cleaner_state.json';
  Timer? _backupTimer;

  /// Saves kept / ToDelete decisions to a hidden file in shared storage, so a
  /// reinstall of the app does not lose your review progress.
  Future<void> backupState() async {
    try {
      final rows = await store.stateRows();
      final kept = <String>[];
      final trash = <List<String>>[];
      for (final r in rows) {
        final path = r['path'] as String;
        if ((r['status'] as num).toInt() == Status.kept) {
          kept.add(path);
        } else {
          trash.add([path, (r['orig_path'] as String?) ?? '']);
        }
      }
      final tmp = File('$backupFile.tmp');
      await tmp.writeAsString(jsonEncode({'v': 1, 'kept': kept, 'trash': trash}));
      await tmp.rename(backupFile);
    } catch (_) {}
  }

  /// After a fresh scan on a reinstall: re-applies saved decisions.
  Future<int> restoreState() async {
    try {
      final f = File(backupFile);
      if (!await f.exists()) return 0;
      final data = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final kept = (data['kept'] as List).cast<String>();
      final trash = (data['trash'] as List)
          .map((e) => (e as List).cast<String>())
          .toList();
      var n = 0;
      for (var i = 0; i < kept.length; i += 500) {
        final end = i + 500 > kept.length ? kept.length : i + 500;
        final b = store.db.batch();
        for (final path in kept.sublist(i, end)) {
          b.update('files', {'status': Status.kept},
              where: 'path = ? AND status = 0', whereArgs: [path]);
        }
        n += end - i;
        await b.commit(noResult: true);
      }
      final found = <ScannedFile>[];
      final origs = <String, String>{};
      for (final t in trash) {
        final path = t[0];
        final orig = t.length > 1 ? t[1] : '';
        final file = File(path);
        if (!await file.exists()) continue;
        final st = await file.stat();
        final ext = extOf(p.basename(path));
        final rel = orig.isNotEmpty ? p.relative(orig, from: rootPath) : p.basename(path);
        found.add(ScannedFile(
          path: path,
          size: st.size,
          mtime: st.modified.millisecondsSinceEpoch,
          bucket: bucketForRelPath(rel),
          kind: kindForExt(ext),
          ext: ext,
        ));
        origs[path] = orig;
      }
      await store.insertScanned(found);
      for (final f2 in found) {
        final o = origs[f2.path]!;
        await store.db.update(
            'files', {'status': Status.todelete, 'orig_path': o.isEmpty ? null : o},
            where: 'path = ?', whereArgs: [f2.path]);
      }
      return n + found.length;
    } catch (_) {
      return 0;
    }
  }

  Future<void> rescan() async {
    if (scanning) return;
    scanning = true;
    notifyListeners();
    try {
      final found = await scanInBackground(const ScanConfig(root: rootPath));
      final fresh = !(await store.hasAny());
      await store.insertScanned(found);
      if (fresh) await restoreState();
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

  /// Folder that "move to folder" (swipe up) sends files to. Not remembered
  /// between app launches on purpose.
  String? targetFolder;

  void setTargetFolder(String? path) {
    targetFolder = path;
    notifyListeners();
  }

  Future<List<String>> listSafeFolders() async {
    final dir = Directory(safePath);
    if (!await dir.exists()) return [];
    final out = <String>[];
    await for (final e in dir.list(followLinks: false)) {
      if (e is Directory && !p.basename(e.path).startsWith('.')) out.add(e.path);
    }
    out.sort((a, b) => p.basename(a).toLowerCase().compareTo(p.basename(b).toLowerCase()));
    return out;
  }

  /// Cleans a typed folder name. Returns null when nothing usable is left.
  static String? cleanFolderName(String raw) {
    var n = raw.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), ' ');
    n = n.replaceAll(RegExp(r'\s+'), ' ').trim();
    while (n.startsWith('.')) {
      n = n.substring(1).trim();
    }
    if (n.length > 60) n = n.substring(0, 60).trim();
    return n.isEmpty ? null : n;
  }

  /// Creates (or reuses) Safe/<name>. Returns its path, or null for a bad name.
  Future<String?> createSafeFolder(String name) async {
    final clean = cleanFolderName(name);
    if (clean == null) return null;
    final existing = await listSafeFolders();
    for (final f in existing) {
      if (p.basename(f).toLowerCase() == clean.toLowerCase()) return f;
    }
    final path = p.join(safePath, clean);
    await Directory(path).create(recursive: true);
    return path;
  }

  /// Moves the file into [folderPath] and counts it as kept. Returns new path.
  Future<String> moveToFolder(FileEntry e, String folderPath) async {
    final newPath = await mover.moveInto(e.path, folderPath);
    await store.markMovedKept(e.path, newPath);
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
