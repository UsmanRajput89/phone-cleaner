import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:phone_cleaner/core/mover.dart';

void main() {
  late Directory tmp;
  late Mover mover;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('delete_test');
    mover = Mover(p.join(tmp.path, 'ToDelete'));
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  test('isInside accepts only paths strictly inside the folder', () {
    final t = p.join(tmp.path, 'ToDelete');
    expect(Mover.isInside(t, p.join(t, 'a.jpg')), true);
    expect(Mover.isInside(t, p.join(t, 'sub', 'a.jpg')), true);
    expect(Mover.isInside(t, t), false);
    expect(Mover.isInside(t, p.join(tmp.path, 'DCIM', 'a.jpg')), false);
    expect(Mover.isInside(t, p.join(t, '..', 'DCIM', 'a.jpg')), false);
    expect(Mover.isInside(t, '${t}2/a.jpg'), false);
  });

  test('deleteFromTrash deletes inside ToDelete only', () async {
    final inside = File(p.join(tmp.path, 'ToDelete', 'a.jpg'))
      ..createSync(recursive: true);
    final outside = File(p.join(tmp.path, 'DCIM', 'b.jpg'))
      ..createSync(recursive: true);

    expect(await mover.deleteFromTrash(inside.path), true);
    expect(inside.existsSync(), false);

    expect(() => mover.deleteFromTrash(outside.path), throwsArgumentError);
    expect(outside.existsSync(), true);
  });

  test('deleteFromTrash treats a missing file as already deleted', () async {
    final missing = p.join(tmp.path, 'ToDelete', 'gone.jpg');
    expect(await mover.deleteFromTrash(missing), true);
  });
}
