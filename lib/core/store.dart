import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models.dart';

class _Where {
  final String sql;
  final List<Object?> args;
  _Where(this.sql, this.args);
}

const String _baseName =
    "REPLACE(path, RTRIM(path, REPLACE(path, '/', '')), '')";

String _ph(int n) => List.filled(n, '?').join(',');

String _order(SortMode s) {
  return switch (s) {
    SortMode.oldest => 'mtime ASC, path ASC',
    SortMode.newest => 'mtime DESC, path ASC',
    SortMode.largest => 'size DESC, path ASC',
  };
}

class Store {
  final Database db;

  Store(this.db);

  static Future<Store> open({String? path}) async {
    final dbPath = path ?? p.join(await getDatabasesPath(), 'phone_cleaner.db');
    final db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('CREATE TABLE files('
            'path TEXT PRIMARY KEY, '
            'size INTEGER NOT NULL, '
            'mtime INTEGER NOT NULL, '
            'bucket TEXT NOT NULL, '
            'kind TEXT NOT NULL, '
            'ext TEXT NOT NULL, '
            'status INTEGER NOT NULL DEFAULT 0, '
            'orig_path TEXT)');
        await db.execute('CREATE INDEX idx_files_q ON files(status, kind, bucket)');
        await db.execute(
            'CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)');
      },
    );
    return Store(db);
  }

  Future<void> close() => db.close();

  /// Adds newly found files. Existing rows (and their status) are untouched.
  Future<void> insertScanned(List<ScannedFile> files) async {
    const chunk = 500;
    for (var i = 0; i < files.length; i += chunk) {
      final end = (i + chunk) > files.length ? files.length : i + chunk;
      final batch = db.batch();
      for (var j = i; j < end; j++) {
        final f = files[j];
        batch.insert(
          'files',
          {
            'path': f.path,
            'size': f.size,
            'mtime': f.mtime,
            'bucket': f.bucket.name,
            'kind': f.kind.name,
            'ext': f.ext,
            'status': Status.pending,
            'orig_path': null,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      await batch.commit(noResult: true);
    }
  }

  _Where _where(FileQuery q) {
    final parts = <String>['status = ?'];
    final args = <Object?>[q.status];

    if (q.kinds.isEmpty) {
      parts.add('1 = 0');
    } else {
      parts.add('kind IN (${_ph(q.kinds.length)})');
      args.addAll(q.kinds.map((k) => k.name));
    }
    if (q.buckets.isEmpty) {
      parts.add('1 = 0');
    } else {
      parts.add('bucket IN (${_ph(q.buckets.length)})');
      args.addAll(q.buckets.map((b) => b.name));
    }
    final exts = q.exts;
    if (exts != null && exts.isNotEmpty) {
      parts.add('ext IN (${_ph(exts.length)})');
      args.addAll(exts);
    }
    final notExts = q.notExts;
    if (notExts != null && notExts.isNotEmpty) {
      parts.add('ext NOT IN (${_ph(notExts.length)})');
      args.addAll(notExts);
    }
    if (q.excludePaths.isNotEmpty) {
      parts.add('path NOT IN (${_ph(q.excludePaths.length)})');
      args.addAll(q.excludePaths);
    }
    final prefix = q.pathPrefix;
    if (prefix != null) {
      final esc = prefix
          .replaceAll('\\', '\\\\')
          .replaceAll('%', '\\%')
          .replaceAll('_', '\\_');
      parts.add("path LIKE ? ESCAPE '\\'");
      args.add('$esc/%');
    }
    final month = q.month;
    if (month != null) {
      parts.add("strftime('%Y-%m', mtime / 1000, 'unixepoch', 'localtime') = ?");
      args.add(month);
    }
    if (q.duplicatesOnly) {
      parts.add('(size, $_baseName) IN (SELECT size, $_baseName FROM files '
          "WHERE status = 0 AND kind = 'other' GROUP BY 1, 2 HAVING COUNT(*) > 1)");
    }
    return _Where(parts.join(' AND '), args);
  }

  /// Months (newest first) with counts and sizes under a folder prefix.
  Future<List<Map<String, Object?>>> monthsUnder(String prefix, String bucket,
      {int status = 0}) async {
    final esc = prefix
        .replaceAll('\\', '\\\\')
        .replaceAll('%', '\\%')
        .replaceAll('_', '\\_');
    return db.rawQuery(
        "SELECT strftime('%Y-%m', mtime / 1000, 'unixepoch', 'localtime') AS m, "
        'COUNT(*) AS c, COALESCE(SUM(size), 0) AS s FROM files '
        "WHERE status = ? AND bucket = ? AND path LIKE ? ESCAPE '\\' "
        'GROUP BY m ORDER BY m DESC',
        [status, bucket, '$esc/%']);
  }

  Future<List<FileEntry>> query(FileQuery q) async {
    final w = _where(q);
    final rows = await db.query(
      'files',
      where: w.sql,
      whereArgs: w.args,
      orderBy: _order(q.sort),
      limit: q.limit,
      offset: q.offset,
    );
    return rows.map(FileEntry.fromRow).toList();
  }

  Future<int> count(FileQuery q) async {
    final w = _where(q);
    final rows = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM files WHERE ${w.sql}', w.args);
    return (rows.first['c'] as num).toInt();
  }

  Future<int> sumSize(FileQuery q) async {
    final w = _where(q);
    final rows = await db.rawQuery(
        'SELECT COALESCE(SUM(size), 0) AS s FROM files WHERE ${w.sql}', w.args);
    return (rows.first['s'] as num).toInt();
  }

  Future<void> markKept(String path) async {
    await db.update('files', {'status': Status.kept},
        where: 'path = ?', whereArgs: [path]);
  }

  Future<void> setPending(String path) async {
    await db.update('files', {'status': Status.pending, 'orig_path': null},
        where: 'path = ?', whereArgs: [path]);
  }

  /// File moved into a Safe folder: counts as kept, remembers where it came from.
  Future<void> markMovedKept(String oldPath, String newPath) async {
    await db.update(
      'files',
      {'path': newPath, 'status': Status.kept, 'orig_path': oldPath},
      where: 'path = ?',
      whereArgs: [oldPath],
    );
  }

  Future<void> markMoved(String oldPath, String newPath) async {
    await db.update(
      'files',
      {'path': newPath, 'status': Status.todelete, 'orig_path': oldPath},
      where: 'path = ?',
      whereArgs: [oldPath],
    );
  }

  Future<void> markRestored(String currentPath, String newPath, int status) async {
    await db.update(
      'files',
      {'path': newPath, 'status': status, 'orig_path': null},
      where: 'path = ?',
      whereArgs: [currentPath],
    );
  }

  /// Drops sticker / animated-gif rows (from earlier scans) that are not in ToDelete.
  Future<void> purgeStickers() async {
    await db.delete(
      'files',
      where: "status != 2 AND (lower(path) LIKE '%/whatsapp stickers/%' "
          "OR lower(path) LIKE '%/whatsapp animated gifs/%' "
          "OR lower(path) LIKE '%/whatsapp/%/stickers/%')",
    );
  }

  /// Folder / extension breakdown of one bucket, for the scan report.
  Future<Map<String, List<int>>> folderStats(String bucket, int status) async {
    final out = <String, List<int>>{};
    var offset = 0;
    const page = 5000;
    while (true) {
      final rows = await db.rawQuery(
          'SELECT path, size FROM files WHERE bucket = ? AND status = ? '
          'LIMIT $page OFFSET $offset',
          [bucket, status]);
      for (final r in rows) {
        final path = r['path'] as String;
        final segs = p.split(path);
        segs.removeLast();
        var cut = -1;
        var seenWa = false;
        for (var i = 0; i < segs.length; i++) {
          final l = segs[i].toLowerCase();
          if (l.contains('whatsapp')) seenWa = true;
          if (seenWa && l == 'media' && i + 1 < segs.length) {
            cut = i + 2;
            break;
          }
        }
        if (cut < 0 || cut > segs.length) cut = segs.length;
        final key = p.joinAll(segs.sublist(0, cut));
        final e = out.putIfAbsent(key, () => [0, 0]);
        e[0] += 1;
        e[1] += (r['size'] as num).toInt();
      }
      if (rows.length < page) break;
      offset += page;
    }
    return out;
  }

  Future<List<Map<String, Object?>>> stateRows() => db.query('files',
      columns: ['path', 'status', 'orig_path'], where: 'status IN (1, 2)');

  Future<bool> hasAny() async {
    final r = await db.rawQuery('SELECT 1 FROM files LIMIT 1');
    return r.isNotEmpty;
  }

  Future<void> remove(String path) async {
    await db.delete('files', where: 'path = ?', whereArgs: [path]);
  }

  Future<Counts> counts({bool whatsappOff = false}) async {
    final rows = await db.rawQuery(
        'SELECT bucket, status, COUNT(*) AS c, COALESCE(SUM(size), 0) AS s '
        'FROM files GROUP BY bucket, status');
    final map = <Bucket, BucketCount>{
      for (final b in Bucket.values) b: BucketCount(),
    };
    var trashBytes = 0;
    for (final r in rows) {
      final b = Bucket.values.byName(r['bucket'] as String);
      final status = (r['status'] as num).toInt();
      final c = (r['c'] as num).toInt();
      final s = (r['s'] as num).toInt();
      final bc = map[b]!;
      bc.total += c;
      if (status == Status.pending) bc.pending += c;
      if (status == Status.kept) bc.kept += c;
      if (status == Status.todelete) {
        bc.trash += c;
        trashBytes += s;
      }
    }
    return Counts(map, trashBytes, whatsappOff: whatsappOff);
  }

  Future<String?> getSetting(String key) async {
    final rows = await db.query('settings', where: 'key = ?', whereArgs: [key]);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String;
  }

  Future<void> setSetting(String key, String value) async {
    await db.insert('settings', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
