import 'package:flutter_test/flutter_test.dart';
import 'package:phone_cleaner/core/classify.dart';
import 'package:phone_cleaner/core/models.dart';

void main() {
  test('extOf handles normal, uppercase, hidden and extension-less names', () {
    expect(extOf('a.JPG'), 'jpg');
    expect(extOf('archive.tar.gz'), 'gz');
    expect(extOf('.nomedia'), '');
    expect(extOf('README'), '');
    expect(extOf('trailing.'), '');
  });

  test('kindForExt', () {
    expect(kindForExt('jpg'), Kind.image);
    expect(kindForExt('mp4'), Kind.video);
    expect(kindForExt('pdf'), Kind.other);
    expect(kindForExt(''), Kind.other);
  });

  test('bucketForRelPath', () {
    expect(bucketForRelPath('DCIM/Camera/a.jpg'), Bucket.camera);
    expect(bucketForRelPath('DCIM/Screenshots/a.png'), Bucket.screenshots);
    expect(bucketForRelPath('Pictures/Screenshots/a.png'), Bucket.screenshots);
    expect(bucketForRelPath('Download/a.zip'), Bucket.downloads);
    expect(bucketForRelPath('Downloads/a.zip'), Bucket.downloads);
    expect(
        bucketForRelPath(
            'Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Images/a.jpg'),
        Bucket.whatsapp);
    expect(bucketForRelPath('WhatsApp/Media/WhatsApp Video/a.mp4'),
        Bucket.whatsapp);
    expect(bucketForRelPath('Documents/a.pdf'), Bucket.other);
  });

  test('extLabel', () {
    expect(extLabel('pdf'), 'PDF');
    expect(extLabel(''), 'FILE');
    expect(extLabel('torrent'), 'TORR');
  });
}
