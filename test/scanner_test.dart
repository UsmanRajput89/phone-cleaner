import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:phone_cleaner/core/models.dart';
import 'package:phone_cleaner/core/scanner.dart';

void _touch(String root, String rel, {int bytes = 3}) {
  final f = File(p.join(root, rel));
  f.parent.createSync(recursive: true);
  f.writeAsBytesSync(List<int>.filled(bytes, 1));
}

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('scan_test');
  });

  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  test('shouldSkipDir rules', () {
    expect(shouldSkipDir(['.thumbnails']), true);
    expect(shouldSkipDir(['DCIM', '.thumbnails']), true);
    expect(shouldSkipDir(['App', 'cache']), true);
    expect(shouldSkipDir(['DCIM']), false);
    expect(shouldSkipDir(['Android']), false);
    expect(shouldSkipDir(['Android', 'data']), true);
    expect(shouldSkipDir(['Android', 'obb']), true);
    expect(shouldSkipDir(['Android', 'media', 'com.other']), true);
    expect(shouldSkipDir(['Android', 'media', 'com.whatsapp']), false);
    expect(
        shouldSkipDir(['Android', 'media', 'com.whatsapp', 'WhatsApp']), false);
    expect(
        shouldSkipDir(
            ['Android', 'media', 'com.whatsapp', 'WhatsApp', 'Databases']),
        true);
    expect(
        shouldSkipDir(
            ['Android', 'media', 'com.whatsapp', 'WhatsApp', 'Backups']),
        true);
    expect(
        shouldSkipDir(
            ['Android', 'media', 'com.whatsapp', 'WhatsApp', 'Media']),
        false);
    expect(shouldSkipDir(['WhatsApp', 'Databases']), true);
    expect(shouldSkipDir(['WhatsApp', 'Backups']), true);
    expect(shouldSkipDir(['WhatsApp', 'Media']), false);
    expect(shouldSkipDir(['WhatsApp', 'Media', 'WhatsApp Stickers']), true);
    expect(shouldSkipDir(['WhatsApp', 'Media', 'WhatsApp Animated Gifs']), true);
    expect(
        shouldSkipDir([
          'Android', 'media', 'com.whatsapp', 'WhatsApp', 'Media',
          'WhatsApp Stickers'
        ]),
        true);
    expect(
        shouldSkipDir([
          'Android', 'media', 'com.whatsapp', 'WhatsApp', 'Media',
          'WhatsApp Voice Notes'
        ]),
        true);
    expect(shouldSkipDir(['FMWhatsApp', 'Media', 'WhatsApp Voice Notes']), true);
    expect(
        shouldSkipDir(['YoWhatsApp Backup', 'Media', 'YoWhatsApp Voice Notes']),
        true);
    expect(shouldSkipDir(['DCIM', 'Camera']), false);
  });

  test('scanTree finds the right files and skips the wrong ones', () {
    final root = tmp.path;
    _touch(root, 'DCIM/Camera/a.jpg');
    _touch(root, 'DCIM/Camera/.hidden.jpg');
    _touch(root, 'DCIM/.thumbnails/t.jpg');
    _touch(root, 'DCIM/Screenshots/s.png');
    _touch(root, 'Download/b.zip', bytes: 10);
    _touch(root, 'Documents/doc.pdf');
    _touch(root, 'Android/data/com.x/f.txt');
    _touch(root, 'Android/obb/com.x/main.obb');
    _touch(root, 'Android/media/com.other/o.jpg');
    _touch(root,
        'Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Images/w.jpg');
    _touch(root, 'Android/media/com.whatsapp/WhatsApp/Databases/msgstore.db');
    _touch(root, 'WhatsApp/Backups/b.crypt14');
    _touch(root, 'ToDelete/t.jpg');

    final found = scanTree(ScanConfig(root: root));
    final rels = found.map((f) => p.relative(f.path, from: root)).toSet();

    expect(rels, {
      'DCIM/Camera/a.jpg',
      'DCIM/Screenshots/s.png',
      'Download/b.zip',
      'Documents/doc.pdf',
      'Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Images/w.jpg',
    });

    final zip = found.firstWhere((f) => f.ext == 'zip');
    expect(zip.size, 10);
    expect(zip.bucket, Bucket.downloads);
    expect(zip.kind, Kind.other);

    final wa = found.firstWhere((f) => f.path.contains('w.jpg'));
    expect(wa.bucket, Bucket.whatsapp);
    expect(wa.kind, Kind.image);
  });

  test('scanTree on a missing root returns empty', () {
    expect(scanTree(ScanConfig(root: p.join(tmp.path, 'nope'))), isEmpty);
  });
}
