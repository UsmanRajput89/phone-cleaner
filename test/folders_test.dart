import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:phone_cleaner/app/controller.dart';
import 'package:phone_cleaner/core/models.dart';
import 'package:phone_cleaner/core/mover.dart';
import 'package:phone_cleaner/core/scanner.dart';
import 'package:phone_cleaner/core/store.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('cleanFolderName strips bad characters', () {
    expect(AppController.cleanFolderName('  Ayesha  '), 'Ayesha');
    expect(AppController.cleanFolderName('a/b\\c:d'), 'a b c d');
    expect(AppController.cleanFolderName('...hidden'), 'hidden');
    expect(AppController.cleanFolderName('   '), isNull);
    expect(AppController.cleanFolderName('///'), isNull);
  });

  test('moveInto moves the file and avoids name clashes', () async {
    final tmp = Directory.systemTemp.createTempSync('folders_test');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final src = File(p.join(tmp.path, 'a', 'x.jpg'))..createSync(recursive: true);
    src.writeAsBytesSync([1, 2, 3]);
    final src2 = File(p.join(tmp.path, 'b', 'x.jpg'))..createSync(recursive: true);
    src2.writeAsBytesSync([4, 5]);
    final mover = Mover(p.join(tmp.path, 'ToDelete'));
    final dest = p.join(tmp.path, 'Safe', 'Ayesha');

    final one = await mover.moveInto(src.path, dest);
    final two = await mover.moveInto(src2.path, dest);

    expect(File(one).existsSync(), true);
    expect(File(two).existsSync(), true);
    expect(one == two, false);
    expect(src.existsSync(), false);
    expect(File(one).readAsBytesSync(), [1, 2, 3]);
  });

  test('scanner skips the top-level Safe folder', () {
    final tmp = Directory.systemTemp.createTempSync('scan_safe');
    addTearDown(() => tmp.deleteSync(recursive: true));
    File(p.join(tmp.path, 'Safe', 'Ayesha', 'a.jpg')).createSync(recursive: true);
    File(p.join(tmp.path, 'DCIM', 'Camera', 'b.jpg')).createSync(recursive: true);
    final found = scanTree(ScanConfig(root: tmp.path));
    expect(found.map((e) => p.basename(e.path)).toList(), ['b.jpg']);
  });

  test('markMovedKept counts as kept and remembers origin', () async {
    final store = await Store.open(path: inMemoryDatabasePath);
    await store.insertScanned([
      ScannedFile(
          path: '/a/1.jpg',
          size: 1,
          mtime: 1,
          bucket: Bucket.camera,
          kind: Kind.image,
          ext: 'jpg'),
    ]);
    await store.markMovedKept('/a/1.jpg', '/Safe/Ayesha/1.jpg');
    final kept = await store.query(const FileQuery(status: Status.kept));
    expect(kept.length, 1);
    expect(kept.first.path, '/Safe/Ayesha/1.jpg');
    expect(kept.first.origPath, '/a/1.jpg');
  });
}
