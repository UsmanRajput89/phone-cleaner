import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Lower is better: the copy with the lowest rank is the one that stays.
///
/// Files you already filed into Safe come first, then the live WhatsApp copy
/// (Android/media/com.whatsapp), then DCIM/Camera, Downloads, anything else,
/// and finally the legacy /WhatsApp/Media leftovers.
int dupRank(String path, {required String safeRoot}) {
  if (p.isWithin(safeRoot, path)) return 0;
  final l = path.toLowerCase();
  if (l.contains('/android/media/com.whatsapp')) {
    return l.contains('/sent/') ? 2 : 1;
  }
  if (l.contains('/dcim/')) return 3;
  if (l.contains('/download/') || l.contains('/downloads/')) return 4;
  if (l.contains('/whatsapp/media/')) return 6;
  return 5;
}

class DupCandidate {
  final String path;
  final int mtime;
  final int dup;
  const DupCandidate(this.path, this.mtime, this.dup);
}

/// Picks the path to keep. A copy that is already marked as the keeper wins,
/// so a choice made on the Duplicates screen sticks.
String pickKeeper(List<DupCandidate> group, {required String safeRoot}) {
  for (final c in group) {
    if (c.dup == 1) return c.path;
  }
  final sorted = [...group]..sort((a, b) {
      final ra = dupRank(a.path, safeRoot: safeRoot);
      final rb = dupRank(b.path, safeRoot: safeRoot);
      if (ra != rb) return ra.compareTo(rb);
      if (a.mtime != b.mtime) return a.mtime.compareTo(b.mtime);
      if (a.path.length != b.path.length) {
        return a.path.length.compareTo(b.path.length);
      }
      return a.path.compareTo(b.path);
    });
  return sorted.first.path;
}

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

/// Hashes whole files (MD5 of the full content, prefixed by the size). Runs
/// synchronously, so call it inside an isolate. An unreadable file gets a
/// unique `e:` marker so it never matches anything.
List<String> hashFiles(List<String> paths) {
  final out = <String>[];
  for (final path in paths) {
    RandomAccessFile? raf;
    try {
      raf = File(path).openSync();
      final len = raf.lengthSync();
      final sink = _DigestSink();
      final input = md5.startChunkedConversion(sink);
      while (true) {
        final chunk = raf.readSync(1 << 20);
        if (chunk.isEmpty) break;
        input.add(chunk);
      }
      input.close();
      out.add('$len-${sink.value}');
    } catch (_) {
      out.add('e:$path');
    } finally {
      try {
        raf?.closeSync();
      } catch (_) {}
    }
  }
  return out;
}
