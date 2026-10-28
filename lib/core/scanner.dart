import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import 'classify.dart';
import 'models.dart';

class ScanConfig {
  final String root;
  final String trashName;
  final String safeName;

  const ScanConfig({
    required this.root,
    this.trashName = 'ToDelete',
    this.safeName = 'Safe',
  });
}

/// WhatsApp voice-note folders (also in FM / Aero / Yo variants): not reviewed.
bool isVoiceNotesDirName(String lowerName) =>
    lowerName.contains('voice notes');

bool isStickerDirName(String lowerName) =>
    lowerName == 'whatsapp stickers' ||
    lowerName == 'whatsapp animated gifs' ||
    lowerName == 'stickers';

/// Decides whether a directory (given as path segments relative to the root)
/// must be skipped. Never descends into app data, hidden folders, caches, or
/// WhatsApp's Databases / Backups.
bool shouldSkipDir(List<String> segs) {
  if (segs.isEmpty) return false;
  final lower = segs.map((s) => s.toLowerCase()).toList();
  final last = lower.last;

  if (last.startsWith('.')) return true;
  if (last == 'cache' || last == 'code_cache' || last == 'thumbnails') {
    return true;
  }

  final inWhatsApp = lower.any((s) => s.contains('whatsapp'));
  // Stickers and animated GIFs are never worth reviewing (and are mostly dupes).
  if (inWhatsApp && isStickerDirName(last)) return true;
  if (inWhatsApp && (last == 'databases' || last == 'backups')) return true;
  if (inWhatsApp && isVoiceNotesDirName(last)) return true;

  if (lower[0] == 'android') {
    if (lower.length == 1) return false;
    if (lower[1] != 'media') return true;
    if (lower.length == 2) return false;
    if (!lower[2].startsWith('com.whatsapp')) return true;
    if (lower.length == 3) return false;
    if (!lower[3].startsWith('whatsapp')) return true;
    if (lower.length == 4) return false;
    if (lower[4] != 'media') return true;
    return false;
  }
  return false;
}

/// Walks the tree synchronously. Run it in a background isolate for real use.
List<ScannedFile> scanTree(ScanConfig cfg) {
  final out = <ScannedFile>[];
  final rootDir = Directory(cfg.root);
  if (!rootDir.existsSync()) return out;

  final stack = <Directory>[rootDir];
  while (stack.isNotEmpty) {
    final dir = stack.removeLast();
    List<FileSystemEntity> items;
    try {
      items = dir.listSync(followLinks: false);
    } catch (_) {
      continue;
    }
    for (final e in items) {
      final rel = p.relative(e.path, from: cfg.root);
      final segs = p.split(rel);
      final name = segs.last;
      if (e is Directory) {
        if (segs.length == 1 &&
            (name == cfg.trashName || name == cfg.safeName)) {
          continue;
        }
        if (shouldSkipDir(segs)) continue;
        stack.add(e);
      } else if (e is File) {
        if (name.startsWith('.')) continue;
        FileStat st;
        try {
          st = e.statSync();
        } catch (_) {
          continue;
        }
        final ext = extOf(name);
        out.add(ScannedFile(
          path: e.path,
          size: st.size,
          mtime: st.modified.millisecondsSinceEpoch,
          bucket: bucketForRelPath(rel),
          kind: kindForExt(ext),
          ext: ext,
        ));
      }
    }
  }
  return out;
}

Future<List<ScannedFile>> scanInBackground(ScanConfig cfg) {
  return Isolate.run(() => scanTree(cfg));
}
