import 'dart:io';

import 'package:path/path.dart' as p;

/// Moves files into the ToDelete folder and back. This is the only place that
/// touches user files, and it never deletes anything except the source half of
/// a verified copy when a plain rename is impossible (different volume).
class Mover {
  final String trashDir;

  Mover(this.trashDir);

  Future<String> moveToTrash(String path) => moveInto(path, trashDir);

  /// True only for a path strictly inside [dir] (after normalising `..`).
  static bool isInside(String dir, String path) =>
      p.isWithin(p.normalize(dir), p.normalize(path));

  /// Permanently deletes a regular file, but ONLY if it lives inside the
  /// ToDelete folder. Returns true if the file is gone afterwards.
  Future<bool> deleteFromTrash(String path) async {
    if (!isInside(trashDir, path)) {
      throw ArgumentError('Refusing to delete outside ToDelete: $path');
    }
    final type = FileSystemEntity.typeSync(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return true;
    if (type != FileSystemEntityType.file) return false;
    await File(path).delete();
    return !File(path).existsSync();
  }

  /// Moves a file into [dir] (created if missing). Returns the new path.
  Future<String> moveInto(String path, String dir) async {
    await Directory(dir).create(recursive: true);
    final target = await _uniquePath(dir, p.basename(path));
    await _moveFile(path, target);
    return target;
  }

  Future<String> restore(String current, String orig) async {
    final parent = p.dirname(orig);
    await Directory(parent).create(recursive: true);
    final target = await _uniquePath(parent, p.basename(orig));
    await _moveFile(current, target);
    return target;
  }

  Future<String> _uniquePath(String dir, String name) async {
    var candidate = p.join(dir, name);
    if (!await File(candidate).exists()) return candidate;
    final base = p.basenameWithoutExtension(name);
    final ext = p.extension(name);
    for (var i = 1; i < 10000; i++) {
      candidate = p.join(dir, '$base ($i)$ext');
      if (!await File(candidate).exists()) return candidate;
    }
    throw FileSystemException('No free file name', dir);
  }

  Future<void> _moveFile(String from, String to) async {
    final src = File(from);
    try {
      await src.rename(to);
      return;
    } on FileSystemException {
      // Fall through to copy + verify.
    }
    final len = await src.length();
    await src.copy(to);
    final copied = await File(to).length();
    if (copied != len) {
      try {
        await File(to).delete();
      } catch (_) {}
      throw FileSystemException('Copy size mismatch', to);
    }
    await src.delete();
  }
}
