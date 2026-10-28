import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';

import 'package:path/path.dart' as p;

import '../core/classify.dart';
import '../core/dupes.dart';
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
  bool hideDupes = true;
  Counts? counts;
  DupStats dupStats = DupStats.none;
  int videoCount = 0;
  int videoBytes = 0;
  bool dupEverScanned = false;
  bool dupScanning = false;
  int dupDone = 0;
  int dupTotal = 0;
  bool _dupCancel = false;
  bool dupMoving = false;
  int dupMoved = 0;
  int dupMoveTotal = 0;
  bool scanning = false;
  Timer? _countsTimer;

  AppController._(this.store) : mover = Mover(trashPath);

  static Future<AppController> create() async {
    final store = await Store.open();
    final c = AppController._(store);
    c.themeMode = (await store.getSetting('theme')) ?? 'system';
    c.includeWhatsApp = (await store.getSetting('whatsapp')) == '1';
    c.hideDupes = (await store.getSetting('hide_dupes')) != '0';
    store.hideDupes = c.hideDupes;
    c.dupEverScanned = (await store.getSetting('dup_scanned')) == '1';
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

  Future<void> setHideDupes(bool value) async {
    hideDupes = value;
    store.hideDupes = value;
    await store.setSetting('hide_dupes', value ? '1' : '0');
    await refreshCounts();
  }

  Future<void> refreshCounts() async {
    counts = await store.counts(whatsappOff: !includeWhatsApp);
    dupStats = await store.dupStats();
    final vq = FileQuery(
      kinds: const [Kind.video],
      buckets: Bucket.values
          .where((b) => b != Bucket.whatsapp || includeWhatsApp)
          .toList(),
    );
    videoCount = await store.count(vq);
    videoBytes = await store.sumSize(vq);
    notifyListeners();
  }

  void cancelDupScan() => _dupCancel = true;

  /// Finds byte-identical files: groups by size, then hashes only the files
  /// that share a size with another one. Hashes are cached, so a stopped scan
  /// carries on where it left off. Small batches keep the old phone responsive.
  Future<void> findDuplicates() async {
    if (dupScanning || dupMoving) return;
    dupScanning = true;
    _dupCancel = false;
    dupDone = 0;
    dupTotal = 0;
    notifyListeners();
    try {
      final rows = await store.dupCandidates();
      dupTotal = rows.length;
      notifyListeners();
      var i = 0;
      while (i < rows.length && !_dupCancel) {
        final batch = <String>[];
        var bytes = 0;
        while (i < rows.length && batch.length < 40 && (batch.isEmpty || bytes < 48 * 1024 * 1024)) {
          batch.add(rows[i]['path'] as String);
          bytes += (rows[i]['size'] as num).toInt();
          i++;
        }
        final hashes = await Isolate.run(() => hashFiles(batch));
        await store.setHashes({
          for (var k = 0; k < batch.length; k++) batch[k]: hashes[k],
        });
        dupDone = i;
        notifyListeners();
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
      await store.assignDupRoles();
      if (!_dupCancel) {
        dupEverScanned = true;
        await store.setSetting('dup_scanned', '1');
      }
    } finally {
      dupScanning = false;
    }
    await refreshCounts();
  }

  /// Moves the extra copies of [groups] into ToDelete; the keeper stays.
  /// Returns [moved, failed, bytes].
  Future<List<int>> moveExtras(List<DupGroup> groups) async {
    var moved = 0, failed = 0, bytes = 0;
    for (final g in groups) {
      final keeper = g.keeper;
      for (final e in g.members) {
        if (identical(e, keeper)) continue;
        try {
          await moveToTrash(e);
          moved++;
          bytes += e.size;
        } catch (_) {
          failed++;
        }
        dupMoved++;
        if (dupMoved % 10 == 0) notifyListeners();
      }
      await store.reassignGroup(g.hash);
      await Future<void>.delayed(Duration.zero);
    }
    return [moved, failed, bytes];
  }

  Future<List<int>> moveExtrasOf(List<DupGroup> groups) async {
    if (dupMoving || dupScanning) return [0, 0, 0];
    dupMoving = true;
    dupMoved = 0;
    dupMoveTotal = groups.fold<int>(0, (a, g) => a + g.members.length - 1);
    notifyListeners();
    try {
      return await moveExtras(groups);
    } finally {
      dupMoving = false;
      await refreshCounts();
      refreshCountsSoon();
    }
  }

  /// Moves the given files into ToDelete, one by one. Returns [moved, failed, bytes].
  Future<List<int>> moveCopies(List<FileEntry> files) async {
    var moved = 0, failed = 0, bytes = 0;
    for (final e in files) {
      try {
        await moveToTrash(e);
        moved++;
        bytes += e.size;
      } catch (_) {
        failed++;
      }
    }
    refreshCountsSoon();
    return [moved, failed, bytes];
  }

  /// Moves every extra copy, one batch of groups at a time.
  Future<List<int>> moveAllExtras() async {
    if (dupMoving || dupScanning) return [0, 0, 0];
    dupMoving = true;
    dupMoved = 0;
    dupMoveTotal = dupStats.extras;
    notifyListeners();
    var moved = 0, failed = 0, bytes = 0;
    final seen = <String>{};
    try {
      while (true) {
        final groups = await store.dupGroups(limit: 50);
        final fresh = groups.where((g) => seen.add(g.hash)).toList();
        if (fresh.isEmpty) break;
        final r = await moveExtras(fresh);
        moved += r[0];
        failed += r[1];
        bytes += r[2];
      }
    } finally {
      dupMoving = false;
      await refreshCounts();
      refreshCountsSoon();
    }
    return [moved, failed, bytes];
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

  /// Restores a file from ToDelete. Files with no known origin go to Restored/.
  Future<String> restoreEntry(FileEntry e) {
    final orig = e.origPath ?? p.join(rootPath, 'Restored', e.name);
    return restore(e.path, orig, Status.kept);
  }

  /// Permanently deletes a file that is in ToDelete. Returns true if gone.
  Future<bool> deleteFromTrash(FileEntry e) async {
    if (e.status != Status.todelete) return false;
    final gone = await mover.deleteFromTrash(e.path);
    if (gone) {
      await store.remove(e.path);
      rescanner.add([e.path]);
    }
    return gone;
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
