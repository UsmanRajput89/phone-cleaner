import 'package:flutter_test/flutter_test.dart';
import 'package:phone_cleaner/core/models.dart';
import 'package:phone_cleaner/core/store.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

ScannedFile f(String path,
    {int size = 1,
    int mtime = 1,
    Bucket bucket = Bucket.camera,
    Kind kind = Kind.image,
    String ext = 'jpg'}) {
  return ScannedFile(
      path: path, size: size, mtime: mtime, bucket: bucket, kind: kind, ext: ext);
}

void main() {
  late Store store;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    store = await Store.open(path: inMemoryDatabasePath);
    await store.insertScanned([
      f('/a/1.jpg', size: 10, mtime: 300),
      f('/a/2.jpg', size: 30, mtime: 100),
      f('/a/3.mp4', size: 20, mtime: 200, kind: Kind.video, ext: 'mp4'),
      f('/w/4.jpg', size: 5, mtime: 50, bucket: Bucket.whatsapp),
      f('/d/5.zip',
          size: 99,
          mtime: 10,
          bucket: Bucket.downloads,
          kind: Kind.other,
          ext: 'zip'),
      f('/d/6.pdf',
          size: 7,
          mtime: 20,
          bucket: Bucket.downloads,
          kind: Kind.other,
          ext: 'pdf'),
    ]);
  });

  tearDown(() async {
    await store.close();
  });

  test('sorting oldest / newest / largest', () async {
    const media = [Kind.image, Kind.video];
    final oldest =
        await store.query(const FileQuery(kinds: media, sort: SortMode.oldest));
    expect(oldest.map((e) => e.path).toList(),
        ['/w/4.jpg', '/a/2.jpg', '/a/3.mp4', '/a/1.jpg']);
    final newest =
        await store.query(const FileQuery(kinds: media, sort: SortMode.newest));
    expect(newest.first.path, '/a/1.jpg');
    final largest =
        await store.query(const FileQuery(kinds: media, sort: SortMode.largest));
    expect(largest.first.path, '/a/2.jpg');
  });

  test('bucket and ext filters', () async {
    final noWa = await store.query(const FileQuery(
      kinds: [Kind.image, Kind.video],
      buckets: [Bucket.camera],
    ));
    expect(noWa.length, 3);

    final zips = await store.query(
        const FileQuery(kinds: [Kind.other], exts: ['zip'], sort: SortMode.largest));
    expect(zips.single.path, '/d/5.zip');

    final notZip = await store.query(
        const FileQuery(kinds: [Kind.other], notExts: ['zip']));
    expect(notZip.single.path, '/d/6.pdf');

    final none = await store.query(const FileQuery(buckets: []));
    expect(none, isEmpty);
  });

  test('paging with offset and excludePaths', () async {
    const q = FileQuery(kinds: [Kind.image, Kind.video], sort: SortMode.oldest);
    final page1 = await store.query(q.copyWith(limit: 2));
    final page2 = await store.query(q.copyWith(limit: 2, offset: 2));
    expect(page1.length, 2);
    expect(page2.length, 2);
    expect(page1.map((e) => e.path).toSet().intersection(
        page2.map((e) => e.path).toSet()), isEmpty);

    final rest = await store.query(
        q.copyWith(excludePaths: page1.map((e) => e.path).toList()));
    expect(rest.map((e) => e.path).toList(), ['/a/3.mp4', '/a/1.jpg']);
  });

  test('keep removes a file from the pending queue', () async {
    await store.markKept('/a/2.jpg');
    final pending = await store.query(
        const FileQuery(kinds: [Kind.image, Kind.video], sort: SortMode.oldest));
    expect(pending.any((e) => e.path == '/a/2.jpg'), false);
    final kept = await store.query(const FileQuery(status: Status.kept));
    expect(kept.single.path, '/a/2.jpg');

    await store.setPending('/a/2.jpg');
    expect(await store.count(const FileQuery()), 6);
  });

  test('move and restore update path, status and original path', () async {
    await store.markMoved('/a/1.jpg', '/trash/1.jpg');
    final moved = await store.query(const FileQuery(status: Status.todelete));
    expect(moved.single.path, '/trash/1.jpg');
    expect(moved.single.origPath, '/a/1.jpg');

    await store.markRestored('/trash/1.jpg', '/a/1.jpg', Status.kept);
    final kept = await store.query(const FileQuery(status: Status.kept));
    expect(kept.single.path, '/a/1.jpg');
    expect(kept.single.origPath, isNull);
  });

  test('rescanning keeps existing status', () async {
    await store.markKept('/a/1.jpg');
    await store.insertScanned([f('/a/1.jpg', size: 999), f('/a/new.jpg')]);
    final kept = await store.query(const FileQuery(status: Status.kept));
    expect(kept.single.size, 10);
    expect(await store.count(const FileQuery()), 6);
  });

  test('counts and sums', () async {
    await store.markKept('/a/2.jpg');
    await store.markMoved('/d/5.zip', '/trash/5.zip');
    final c = await store.counts();
    expect(c.total, 6);
    expect(c.kept, 1);
    expect(c.trash, 1);
    expect(c.pending, 4);
    expect(c.reviewed, 2);
    expect(c.trashBytes, 99);
    expect(c.byBucket[Bucket.downloads]!.trash, 1);
    expect(await store.sumSize(const FileQuery(status: Status.todelete)), 99);
  });

  test('remove and settings', () async {
    await store.remove('/a/1.jpg');
    expect(await store.count(const FileQuery()), 5);
    expect(await store.getSetting('theme'), isNull);
    await store.setSetting('theme', 'dark');
    await store.setSetting('theme', 'light');
    expect(await store.getSetting('theme'), 'light');
  });
}
