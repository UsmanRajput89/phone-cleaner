import 'models.dart';

const Set<String> imageExts = {
  'jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'heic', 'heif',
};

const Set<String> videoExts = {
  'mp4', 'mkv', '3gp', 'mov', 'avi', 'webm', 'm4v', 'mpg', 'mpeg', 'wmv', 'flv',
};

/// Extension groups used by the Files screen chips.
const Map<String, List<String>> extGroups = {
  'zip': ['zip', 'rar', '7z', 'tar', 'gz', 'tgz', 'bz2'],
  'apk': ['apk', 'xapk', 'apks'],
  'pdf': ['pdf'],
  'docs': ['doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'csv', 'rtf', 'odt'],
};

String extOf(String fileName) {
  final i = fileName.lastIndexOf('.');
  if (i <= 0 || i == fileName.length - 1) return '';
  return fileName.substring(i + 1).toLowerCase();
}

Kind kindForExt(String ext) {
  if (imageExts.contains(ext)) return Kind.image;
  if (videoExts.contains(ext)) return Kind.video;
  return Kind.other;
}

/// [rel] is the path relative to the storage root, e.g. `DCIM/Camera/a.jpg`.
Bucket bucketForRelPath(String rel) {
  final lower = rel.toLowerCase().replaceAll('\\', '/');
  if (lower.contains('whatsapp')) return Bucket.whatsapp;
  if (lower.contains('screenshot')) return Bucket.screenshots;
  if (lower.startsWith('dcim/')) return Bucket.camera;
  if (lower.startsWith('download')) return Bucket.downloads;
  return Bucket.other;
}

String extLabel(String ext) {
  if (ext.isEmpty) return 'FILE';
  final up = ext.toUpperCase();
  return up.length > 4 ? up.substring(0, 4) : up;
}

String bucketLabel(Bucket b) {
  switch (b) {
    case Bucket.camera:
      return 'Camera';
    case Bucket.screenshots:
      return 'Screenshots';
    case Bucket.whatsapp:
      return 'WhatsApp';
    case Bucket.downloads:
      return 'Downloads';
    case Bucket.other:
      return 'Other';
  }
}
