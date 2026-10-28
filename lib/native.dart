import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Thin wrapper over the Kotlin side (see android_overlay/MainActivity.kt).
class Native {
  static const MethodChannel _ch = MethodChannel('phone_cleaner/native');

  static Future<bool> hasAllFilesAccess() async {
    try {
      return (await _ch.invokeMethod<bool>('hasAllFilesAccess')) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> requestAllFilesAccess() async {
    try {
      await _ch.invokeMethod<void>('requestAllFilesAccess');
    } catch (_) {}
  }

  static Future<void> scanFiles(List<String> paths) async {
    try {
      await _ch.invokeMethod<void>('scanFiles', {'paths': paths});
    } catch (_) {}
  }

  static Future<Uint8List?> pdfThumb(String path, {int size = 160}) async {
    try {
      return await _ch
          .invokeMethod<Uint8List>('pdfThumb', {'path': path, 'size': size});
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, String>?> apkInfo(String path) async {
    try {
      final r = await _ch.invokeMethod<Map<Object?, Object?>>('apkInfo', {'path': path});
      return r?.map((k, v) => MapEntry(k as String, v as String));
    } catch (_) {
      return null;
    }
  }

  static Future<bool> openFile(String path) async {
    try {
      return (await _ch.invokeMethod<bool>('openFile', {'path': path})) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<Uint8List?> thumbnail(String path, {int size = 400}) async {
    try {
      return await _ch
          .invokeMethod<Uint8List>('thumbnail', {'path': path, 'size': size});
    } catch (_) {
      return null;
    }
  }
}

/// Batches "please refresh the gallery for these paths" calls so we do not hit
/// the media scanner on every single swipe.
class MediaRescanner {
  final Set<String> _pending = {};
  Timer? _timer;

  void add(Iterable<String> paths) {
    _pending.addAll(paths);
    _timer ??= Timer(const Duration(seconds: 3), flush);
  }

  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    if (_pending.isEmpty) return;
    final list = _pending.toList();
    _pending.clear();
    await Native.scanFiles(list);
  }
}

/// Small LRU of video thumbnails (futures, so repeated builds reuse them).
class ThumbCache {
  static final Map<String, Future<Uint8List?>> _m = {};

  static Future<Uint8List?> get(String path) {
    final existing = _m.remove(path);
    if (existing != null) {
      _m[path] = existing;
      return existing;
    }
    final f = Native.thumbnail(path);
    _m[path] = f;
    if (_m.length > 80) _m.remove(_m.keys.first);
    return f;
  }
}

/// LRU of PDF first-page thumbnails and APK info (futures, reused on rebuild).
class FileInfoCache {
  static final Map<String, Future<Uint8List?>> _pdf = {};
  static final Map<String, Future<Map<String, String>?>> _apk = {};

  static Future<Uint8List?> pdf(String path) {
    final existing = _pdf.remove(path);
    if (existing != null) {
      _pdf[path] = existing;
      return existing;
    }
    final f = Native.pdfThumb(path);
    _pdf[path] = f;
    if (_pdf.length > 60) _pdf.remove(_pdf.keys.first);
    return f;
  }

  static Future<Map<String, String>?> apk(String path) {
    final existing = _apk.remove(path);
    if (existing != null) {
      _apk[path] = existing;
      return existing;
    }
    final f = Native.apkInfo(path);
    _apk[path] = f;
    if (_apk.length > 60) _apk.remove(_apk.keys.first);
    return f;
  }
}
