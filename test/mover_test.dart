import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:phone_cleaner/core/mover.dart';

void main() {
  late Directory tmp;
  late String trash;
  late Mover mover;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('mover_test');
    trash = p.join(tmp.path, 'ToDelete');
    mover = Mover(trash);
  });

  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  File make(String rel, String content) {
    final f = File(p.join(tmp.path, rel));
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(content);
    return f;
  }

  test('moveToTrash moves the file and creates the folder', () async {
    final src = make('DCIM/Camera/a.jpg', 'hello');
    final dest = await mover.moveToTrash(src.path);
    expect(File(src.path).existsSync(), false);
    expect(File(dest).readAsStringSync(), 'hello');
    expect(p.dirname(dest), trash);
    expect(File(p.join(trash, '.nomedia')).existsSync(), false);
  });

  test('name collisions get a numeric suffix', () async {
    final a = make('x/a.jpg', 'one');
    final b = make('y/a.jpg', 'two');
    final d1 = await mover.moveToTrash(a.path);
    final d2 = await mover.moveToTrash(b.path);
    expect(p.basename(d1), 'a.jpg');
    expect(p.basename(d2), 'a (1).jpg');
    expect(File(d2).readAsStringSync(), 'two');
  });

  test('restore puts the file back, recreating folders', () async {
    final src = make('DCIM/Camera/a.jpg', 'hello');
    final orig = src.path;
    final inTrash = await mover.moveToTrash(orig);
    Directory(p.dirname(orig)).deleteSync(recursive: true);
    final back = await mover.restore(inTrash, orig);
    expect(back, orig);
    expect(File(orig).readAsStringSync(), 'hello');
    expect(File(inTrash).existsSync(), false);
  });

  test('restore does not overwrite a file that now exists at the original path',
      () async {
    final src = make('DCIM/a.jpg', 'old');
    final orig = src.path;
    final inTrash = await mover.moveToTrash(orig);
    make('DCIM/a.jpg', 'new');
    final back = await mover.restore(inTrash, orig);
    expect(p.basename(back), 'a (1).jpg');
    expect(File(orig).readAsStringSync(), 'new');
    expect(File(back).readAsStringSync(), 'old');
  });

  test('moving a missing file throws and leaves nothing behind', () async {
    expect(() => mover.moveToTrash(p.join(tmp.path, 'ghost.jpg')),
        throwsA(isA<FileSystemException>()));
    final left = Directory(trash).existsSync()
        ? Directory(trash).listSync().length
        : 0;
    expect(left, 0);
  });
}
