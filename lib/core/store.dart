import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'dupes.dart';
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

  /// When true, extra copies of duplicate files are left out of the review
  /// lists (Swipe, Browse, Files). Set by the app controller.
  bool hideDupes = false;

  /// Files you filed into Safe are always the copy that stays.
  String safeRoot = '/storage/emulated/0/Safe';

  Store(this.db);

  String get _hideSql => hideDupes ? ' AND dup != 2' : '';

  static Future<Store> open({String? path}) async {
    final dbPath = path ?? p.join(await getDatabasesPath(), 'phone_cleaner.db');
    final db = await openDatabase(
      dbPath,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('CREATE TABLE files('
            'path TEXT PRIMARY KEY, '
            'size INTEGER NOT NULL, '
            'mtime INTEGER NOT NULL, '
            'bucket TEXT NOT NULL, '
            'kind TEXT NOT NULL, '
            'ext TEXT NOT NULL, '
            'status INTEGER NOT NULL DEFAULT 0, '
            'orig_path TEXT, '
            'hash TEXT, '
            'dup INTEGER NOT NULL DEFAULT 0)');
        await db.execute('CREATE INDEX idx_files_q ON files(status, kind, bucket)');
        await db.execute(
            'CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)');
        await db.execute('CREATE INDEX idx_files_hash ON files(hash)');
        await db.execute('CREATE INDEX idx_files_size ON files(size)');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE files ADD COLUMN hash TEXT');
          await db.execute(
              'ALTER TABLE files ADD COLUMN dup INTEGER NOT NULL DEFAULT 0');
          await db.execute('CREATE INDEX idx_files_hash ON files(hash)');
          await db.execute('CREATE INDEX idx_files_size ON files(size)');
        }
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
    if (hideDupes && q.status == Status.pending) {
      parts.add('dup != 2');
    }
    if (q.twinsOnly) {
      parts.add('hash IS NOT NULL AND hash IN (SELECT hash FROM files '
          'WHERE hash IS NOT NULL GROUP BY hash HAVING COUNT(*) > 1)');
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
        '${status == Status.pending ? _hideSql : ''} '
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
    final before = await db.query('files',
        columns: ['hash', 'dup'], where: 'path = ?', whereArgs: [oldPath]);
    await db.update(
      'files',
      {
        'path': newPath,
        'status': Status.todelete,
        'orig_path': oldPath,
        'dup': 0,
      },
      where: 'path = ?',
      whereArgs: [oldPath],
    );
    if (before.isNotEmpty && before.first['hash'] != null) {
      final dup = ((before.first['dup'] as num?) ?? 0).toInt();
      // The copy that stays was removed: promote another one.
      if (dup == 1) await reassignGroup(before.first['hash'] as String);
    }
  }

  Future<void> markRestored(String currentPath, String newPath, int status) async {
    await db.update(
      'files',
      {'path': newPath, 'status': status, 'orig_path': null},
      where: 'path = ?',
      whereArgs: [currentPath],
    );
    final r = await db.query('files',
        columns: ['hash'], where: 'path = ?', whereArgs: [newPath]);
    if (r.isNotEmpty && r.first['hash'] != null) {
      await reassignGroup(r.first['hash'] as String);
    }
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
          '${status == Status.pending ? _hideSql : ''} '
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
        'FROM files ${hideDupes ? 'WHERE NOT (status = 0 AND dup = 2) ' : ''}'
        'GROUP BY bucket, status');
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

  // ---- duplicates ----

  /// Same-size files that still need a content hash.
  Future<List<Map<String, Object?>>> dupCandidates({int limit = 100000}) {
    return db.rawQuery(
        'SELECT path, size FROM files WHERE status IN (0, 1) AND size > 0 '
        'AND hash IS NULL AND size IN (SELECT size FROM files '
        'WHERE status IN (0, 1) AND size > 0 GROUP BY size HAVING COUNT(*) > 1) '
        'ORDER BY size ASC, path ASC LIMIT ?',
        [limit]);
  }

  Future<void> setHashes(Map<String, String> hashes) async {
    final batch = db.batch();
    hashes.forEach((path, hash) {
      batch.update('files', {'hash': hash}, where: 'path = ?', whereArgs: [path]);
    });
    await batch.commit(noResult: true);
  }

  List<DupCandidate> _cands(List<Map<String, Object?>> rows) => [
        for (final r in rows)
          DupCandidate(r['path'] as String, (r['mtime'] as num).toInt(),
              ((r['dup'] as num?) ?? 0).toInt())
      ];

  /// Marks one keeper and the extras for every group of identical files.
  Future<void> assignDupRoles() async {
    final rows = await db.rawQuery(
        'SELECT path, hash, mtime, dup FROM files WHERE hash IS NOT NULL '
        'AND status IN (0, 1) AND hash IN (SELECT hash FROM files '
        'WHERE hash IS NOT NULL AND status IN (0, 1) '
        'GROUP BY hash HAVING COUNT(*) > 1) ORDER BY hash');
    final groups = <String, List<Map<String, Object?>>>{};
    for (final r in rows) {
      groups.putIfAbsent(r['hash'] as String, () => []).add(r);
    }
    final roles = <String, int>{};
    groups.forEach((hash, list) {
      final keep = pickKeeper(_cands(list), safeRoot: safeRoot);
      for (final r in list) {
        final path = r['path'] as String;
        roles[path] = path == keep ? 1 : 2;
      }
    });
    await db.transaction((txn) async {
      await txn.rawUpdate('UPDATE files SET dup = 0 WHERE dup != 0');
      final batch = txn.batch();
      roles.forEach((path, role) {
        batch.update('files', {'dup': role}, where: 'path = ?', whereArgs: [path]);
      });
      await batch.commit(noResult: true);
    });
  }

  /// Re-decides the keeper for one group (after a copy left or came back).
  Future<void> reassignGroup(String hash) async {
    final rows = await db.rawQuery(
        'SELECT path, mtime, dup FROM files WHERE hash = ? AND status IN (0, 1)',
        [hash]);
    final batch = db.batch();
    if (rows.length < 2) {
      batch.update('files', {'dup': 0}, where: 'hash = ?', whereArgs: [hash]);
    } else {
      final keep = pickKeeper(_cands(rows), safeRoot: safeRoot);
      for (final r in rows) {
        final path = r['path'] as String;
        batch.update('files', {'dup': path == keep ? 1 : 2},
            where: 'path = ?', whereArgs: [path]);
      }
    }
    await batch.commit(noResult: true);
  }

  /// Makes [path] the copy that stays in its group.
  Future<void> setKeeper(String hash, String path) async {
    final batch = db.batch();
    batch.update('files', {'dup': 2},
        where: 'hash = ? AND status IN (0, 1)', whereArgs: [hash]);
    batch.update('files', {'dup': 1}, where: 'path = ?', whereArgs: [path]);
    await batch.commit(noResult: true);
  }

  Future<DupStats> dupStats() async {
    final r = await db.rawQuery(
        'SELECT COUNT(*) AS g, COALESCE(SUM(c - 1), 0) AS e, '
        'COALESCE(SUM((c - 1) * size), 0) AS b FROM ('
        'SELECT size, COUNT(*) AS c FROM files WHERE hash IS NOT NULL '
        'AND status IN (0, 1) GROUP BY hash HAVING COUNT(*) > 1)');
    final row = r.first;
    return DupStats((row['g'] as num).toInt(), (row['e'] as num).toInt(),
        (row['b'] as num).toInt());
  }

  /// Groups of identical files, biggest savings first.
  Future<List<DupGroup>> dupGroups({int limit = 20, int offset = 0}) async {
    final heads = await db.rawQuery(
        'SELECT hash, size, COUNT(*) AS c FROM files WHERE hash IS NOT NULL '
        'AND status IN (0, 1) GROUP BY hash HAVING COUNT(*) > 1 '
        'ORDER BY (COUNT(*) - 1) * size DESC, hash ASC LIMIT ? OFFSET ?',
        [limit, offset]);
    return _buildGroups(heads);
  }

  /// One group, freshly read; null once fewer than two copies are left.
  Future<DupGroup?> dupGroupOf(String hash) async {
    final heads = await db.rawQuery(
        'SELECT hash, size, COUNT(*) AS c FROM files WHERE hash = ? '
        'AND status IN (0, 1) GROUP BY hash HAVING COUNT(*) > 1',
        [hash]);
    final g = await _buildGroups(heads);
    return g.isEmpty ? null : g.first;
  }

  Future<List<DupGroup>> _buildGroups(List<Map<String, Object?>> heads) async {
    if (heads.isEmpty) return [];
    final hashes = [for (final h in heads) h['hash'] as String];
    final rows = await db.rawQuery(
        'SELECT * FROM files WHERE status IN (0, 1) AND hash IN (${_ph(hashes.length)}) '
        'ORDER BY CASE dup WHEN 1 THEN 0 ELSE 1 END, mtime ASC, path ASC',
        hashes);
    final by = <String, List<FileEntry>>{};
    for (final r in rows) {
      by.putIfAbsent(r['hash'] as String, () => []).add(FileEntry.fromRow(r));
    }
    return [
      for (final h in heads)
        DupGroup(h['hash'] as String, (h['size'] as num).toInt(),
            by[h['hash'] as String] ?? const [])
    ];
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
