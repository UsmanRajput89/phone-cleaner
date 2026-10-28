import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:phone_cleaner/core/dupes.dart';
import 'package:phone_cleaner/ui/dupes.dart' show dupType;
import 'package:phone_cleaner/core/models.dart';
import 'package:phone_cleaner/core/store.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const safe = '/storage/emulated/0/Safe';
const wa = '/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Images';
const old = '/storage/emulated/0/WhatsApp/Media/WhatsApp Images';

ScannedFile f(String path, {int size = 100, int mtime = 1, Bucket b = Bucket.whatsapp}) =>
    ScannedFile(
        path: path, size: size, mtime: mtime, bucket: b, kind: Kind.image, ext: 'jpg');

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('rank order: safe, live WhatsApp, camera, downloads, other, old WhatsApp', () {
    final ranks = [
      '$safe/Ann/a.jpg',
      '$wa/a.jpg',
      '$wa/Sent/a.jpg',
      '/storage/emulated/0/DCIM/Camera/a.jpg',
      '/storage/emulated/0/Download/a.jpg',
      '/storage/emulated/0/Pictures/a.jpg',
      '$old/a.jpg',
    ].map((x) => dupRank(x, safeRoot: safe)).toList();
    expect(ranks, [0, 1, 2, 3, 4, 5, 6]);
  });

  test('pickKeeper prefers live WhatsApp over old, then oldest', () {
    expect(
        pickKeeper([
          DupCandidate('$old/a.jpg', 1, 0),
          DupCandidate('$wa/a.jpg', 9, 0),
        ], safeRoot: safe),
        '$wa/a.jpg');
    expect(
        pickKeeper([
          DupCandidate('$wa/b.jpg', 9, 0),
          DupCandidate('$wa/a.jpg', 3, 0),
        ], safeRoot: safe),
        '$wa/a.jpg');
  });

  test('an existing keeper choice sticks', () {
    expect(
        pickKeeper([
          DupCandidate('$old/a.jpg', 1, 1),
          DupCandidate('$wa/a.jpg', 9, 2),
        ], safeRoot: safe),
        '$old/a.jpg');
  });

  test('hashFiles matches identical content only', () {
    final dir = Directory.systemTemp.createTempSync('dupes');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/a').writeAsBytesSync([1, 2, 3, 4]);
    File('${dir.path}/b').writeAsBytesSync([1, 2, 3, 4]);
    File('${dir.path}/c').writeAsBytesSync([1, 2, 3, 5]);
    final h = hashFiles(['${dir.path}/a', '${dir.path}/b', '${dir.path}/c', '${dir.path}/nope']);
    expect(h[0], h[1]);
    expect(h[0], isNot(h[2]));
    expect(h[3], startsWith('e:'));
  });

  test('dupType buckets files by type', () {
    FileEntry e(String ext, Kind k) => FileEntry(
        path: '/x/a.$ext', size: 1, mtime: 1, bucket: Bucket.other, kind: k, ext: ext);
    expect(dupType(e('jpg', Kind.image)), 'photos');
    expect(dupType(e('mp4', Kind.video)), 'videos');
    expect(dupType(e('pdf', Kind.other)), 'pdf');
    expect(dupType(e('docx', Kind.other)), 'docs');
    expect(dupType(e('zip', Kind.other)), 'zip');
    expect(dupType(e('apk', Kind.other)), 'apk');
    expect(dupType(e('opus', Kind.other)), 'other');
  });

  test('voice notes rows are purged but ToDelete rows are kept', () async {
    sqfliteFfiInit();
    final st = await Store.open(path: inMemoryDatabasePath);
    await st.insertScanned([
      f('/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Voice Notes/2024/a.opus'),
      f('/storage/emulated/0/FMWhatsApp/Media/WhatsApp Voice Notes/b.opus'),
      f('/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Images/c.jpg'),
    ]);
    await st.purgeStickers();
    final rows = await st.query(const FileQuery(limit: 10));
    expect(rows.map((r) => r.name), ['c.jpg']);
    await st.close();
  });

  group('store', () {
    late Store store;

    setUp(() async {
      store = await Store.open(path: inMemoryDatabasePath);
      store.safeRoot = safe;
      await store.insertScanned([
        f('$wa/a.jpg'),
        f('$old/a.jpg'),
        f('/storage/emulated/0/DCIM/Camera/a.jpg', b: Bucket.camera),
        f('$wa/solo.jpg', size: 55),
        f('$wa/b.jpg', size: 100, mtime: 5),
      ]);
      await store.setHashes({
        '$wa/a.jpg': '100-x',
        '$old/a.jpg': '100-x',
        '/storage/emulated/0/DCIM/Camera/a.jpg': '100-x',
        '$wa/b.jpg': '100-y',
      });
      await store.assignDupRoles();
    });

    tearDown(() => store.close());

    test('candidates are same-size files without a hash', () async {
      final c = await store.dupCandidates();
      expect(c, isEmpty);
    });

    test('stats count extras and bytes', () async {
      final s = await store.dupStats();
      expect(s.groups, 1);
      expect(s.extras, 2);
      expect(s.bytes, 200);
    });

    test('live WhatsApp copy is kept, others are extras', () async {
      final g = (await store.dupGroups()).single;
      expect(g.keeper.path, '$wa/a.jpg');
      expect(g.extras.length, 2);
    });

    test('hiding extras removes them from pending queries', () async {
      const q = FileQuery(limit: 100);
      expect((await store.query(q)).length, 5);
      store.hideDupes = true;
      final shown = (await store.query(q)).map((e) => e.path).toSet();
      expect(shown, {'$wa/a.jpg', '$wa/solo.jpg', '$wa/b.jpg'});
      expect(await store.count(q), 3);
    });

    test('moving the keeper to ToDelete promotes another copy', () async {
      await store.markMoved('$wa/a.jpg', '/storage/emulated/0/ToDelete/a.jpg');
      final g = (await store.dupGroups()).single;
      expect(g.members.length, 2);
      expect(g.keeper.path, '/storage/emulated/0/DCIM/Camera/a.jpg');
    });

    test('last remaining copy is no longer a duplicate', () async {
      await store.markMoved('$old/a.jpg', '/storage/emulated/0/ToDelete/o.jpg');
      await store.markMoved('/storage/emulated/0/DCIM/Camera/a.jpg',
          '/storage/emulated/0/ToDelete/c.jpg');
      await store.reassignGroup('100-x');
      expect(await store.dupGroups(), isEmpty);
      store.hideDupes = true;
      expect(await store.count(const FileQuery(limit: 100)), 3);
    });

    test('twinsOnly finds files with an identical twin, trashed or not', () async {
      await store.markMoved('$old/a.jpg', '/storage/emulated/0/ToDelete/o.jpg');
      final rows = await store.query(const FileQuery(
          status: Status.todelete, twinsOnly: true, limit: 100));
      expect(rows.length, 1);
      final none = await store.query(const FileQuery(
          status: Status.pending, kinds: [Kind.image], twinsOnly: true,
          buckets: [Bucket.whatsapp], limit: 100));
      expect(none.map((e) => e.path).contains('$wa/solo.jpg'), isFalse);
    });

    test('dupGroupOf reads one group and is null when only one copy is left', () async {
      expect((await store.dupGroupOf('100-x'))!.members.length, 3);
      await store.markMoved('$old/a.jpg', '/storage/emulated/0/ToDelete/o.jpg');
      await store.markMoved('/storage/emulated/0/DCIM/Camera/a.jpg',
          '/storage/emulated/0/ToDelete/c.jpg');
      expect(await store.dupGroupOf('100-x'), isNull);
    });

    test('releaseGroup stops kept copies counting as duplicates', () async {
      await store.releaseGroup('100-x');
      expect(await store.dupGroupOf('100-x'), isNull);
      expect((await store.dupStats()).groups, 0);
      store.hideDupes = true;
      expect(await store.count(const FileQuery(limit: 100)), 5);
    });

    test('setKeeper switches the kept copy', () async {
      await store.setKeeper('100-x', '$old/a.jpg');
      final g = (await store.dupGroups()).single;
      expect(g.keeper.path, '$old/a.jpg');
    });
  });
}
