import 'package:flutter_test/flutter_test.dart';
import 'package:phone_cleaner/core/models.dart';
import 'package:phone_cleaner/core/store.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

ScannedFile f(String path,
    {int size = 1,
    int mtime = 0,
    Bucket bucket = Bucket.downloads,
    Kind kind = Kind.other,
    String ext = 'pdf'}) {
  return ScannedFile(
      path: path, size: size, mtime: mtime, bucket: bucket, kind: kind, ext: ext);
}

void main() {
  late Store store;
  // 2024-03-15 12:00 UTC and 2024-05-10 12:00 UTC
  final mar = DateTime.utc(2024, 3, 15, 12).millisecondsSinceEpoch;
  final may = DateTime.utc(2024, 5, 10, 12).millisecondsSinceEpoch;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    store = await Store.open(path: inMemoryDatabasePath);
    await store.insertScanned([
      f('/r/Download/a.pdf', size: 100, mtime: mar),
      f('/r/Download/sub/a.pdf', size: 100, mtime: may),
      f('/r/Download/b.pdf', size: 200, mtime: may),
      f('/r/Download/c.pdf', size: 300, mtime: may),
      f('/r/Other_dir/d.pdf', size: 400, mtime: may),
      f('/r/Download2/e.pdf', size: 500, mtime: may),
    ]);
  });

  test('pathPrefix only matches inside that folder', () async {
    final rows = await store.query(const FileQuery(
      pathPrefix: '/r/Download',
      kinds: [Kind.other],
    ));
    expect(rows.length, 4);
    expect(rows.every((e) => e.path.startsWith('/r/Download/')), true);
  });

  test('underscore in prefix is not a wildcard', () async {
    final rows = await store.query(const FileQuery(pathPrefix: '/r/Other_dir'));
    expect(rows.length, 1);
    final none = await store.query(const FileQuery(pathPrefix: '/r/OtherXdir'));
    expect(none.length, 0);
  });

  test('duplicatesOnly finds same name and size', () async {
    final rows = await store.query(const FileQuery(duplicatesOnly: true));
    expect(rows.map((e) => e.path).toSet(),
        {'/r/Download/a.pdf', '/r/Download/sub/a.pdf'});
  });

  test('monthsUnder groups by month', () async {
    final months = await store.monthsUnder('/r/Download', 'downloads');
    expect(months.length, 2);
    expect(months.first['m'], '2024-05');
    expect((months.first['c'] as num).toInt(), 3);
    expect(months.last['m'], '2024-03');
  });

  test('month filter works', () async {
    final rows = await store.query(const FileQuery(
      pathPrefix: '/r/Download',
      month: '2024-03',
    ));
    expect(rows.length, 1);
  });
}
