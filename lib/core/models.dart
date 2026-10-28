import 'package:path/path.dart' as p;

enum Bucket { camera, screenshots, whatsapp, downloads, other }

enum Kind { image, video, other }

enum SortMode { oldest, newest, largest }

class Status {
  static const int pending = 0;
  static const int kept = 1;
  static const int todelete = 2;
}

/// A file found by the scanner, before it is stored.
class ScannedFile {
  final String path;
  final int size;
  final int mtime;
  final Bucket bucket;
  final Kind kind;
  final String ext;

  const ScannedFile({
    required this.path,
    required this.size,
    required this.mtime,
    required this.bucket,
    required this.kind,
    required this.ext,
  });
}

/// A stored file with its review status.
class FileEntry {
  final String path;
  final int size;
  final int mtime;
  final Bucket bucket;
  final Kind kind;
  final String ext;
  final int status;
  final String? origPath;

  /// 0 = not a duplicate, 1 = the copy to keep, 2 = an extra copy.
  final int dup;

  const FileEntry({
    required this.path,
    required this.size,
    required this.mtime,
    required this.bucket,
    required this.kind,
    required this.ext,
    this.status = Status.pending,
    this.origPath,
    this.dup = 0,
  });

  String get name => p.basename(path);

  factory FileEntry.fromRow(Map<String, Object?> r) {
    return FileEntry(
      path: r['path'] as String,
      size: (r['size'] as num).toInt(),
      mtime: (r['mtime'] as num).toInt(),
      bucket: Bucket.values.byName(r['bucket'] as String),
      kind: Kind.values.byName(r['kind'] as String),
      ext: r['ext'] as String,
      status: (r['status'] as num).toInt(),
      origPath: r['orig_path'] as String?,
      dup: ((r['dup'] as num?) ?? 0).toInt(),
    );
  }

  FileEntry copyWith({String? path, int? status, String? origPath, int? dup}) {
    return FileEntry(
      path: path ?? this.path,
      size: size,
      mtime: mtime,
      bucket: bucket,
      kind: kind,
      ext: ext,
      status: status ?? this.status,
      origPath: origPath ?? this.origPath,
      dup: dup ?? this.dup,
    );
  }
}

/// Filter + paging description used by the store.
class FileQuery {
  final int status;
  final List<Kind> kinds;
  final List<Bucket> buckets;
  final List<String>? exts;
  final List<String>? notExts;
  final SortMode sort;
  final int limit;
  final int offset;
  final List<String> excludePaths;
  final String? pathPrefix;
  final String? month; // 'YYYY-MM'
  final bool duplicatesOnly;

  const FileQuery({
    this.status = Status.pending,
    this.kinds = const [Kind.image, Kind.video, Kind.other],
    this.buckets = const [
      Bucket.camera,
      Bucket.screenshots,
      Bucket.whatsapp,
      Bucket.downloads,
      Bucket.other,
    ],
    this.exts,
    this.notExts,
    this.sort = SortMode.oldest,
    this.limit = 50,
    this.offset = 0,
    this.excludePaths = const [],
    this.pathPrefix,
    this.month,
    this.duplicatesOnly = false,
  });

  FileQuery copyWith({
    int? status,
    List<Kind>? kinds,
    List<Bucket>? buckets,
    List<String>? exts,
    List<String>? notExts,
    SortMode? sort,
    int? limit,
    int? offset,
    List<String>? excludePaths,
    String? pathPrefix,
    String? month,
    bool? duplicatesOnly,
  }) {
    return FileQuery(
      status: status ?? this.status,
      kinds: kinds ?? this.kinds,
      buckets: buckets ?? this.buckets,
      exts: exts ?? this.exts,
      notExts: notExts ?? this.notExts,
      sort: sort ?? this.sort,
      limit: limit ?? this.limit,
      offset: offset ?? this.offset,
      excludePaths: excludePaths ?? this.excludePaths,
      pathPrefix: pathPrefix ?? this.pathPrefix,
      month: month ?? this.month,
      duplicatesOnly: duplicatesOnly ?? this.duplicatesOnly,
    );
  }
}

class BucketCount {
  int total = 0;
  int pending = 0;
  int kept = 0;
  int trash = 0;
}

class Counts {
  final Map<Bucket, BucketCount> byBucket;
  final int trashBytes;

  /// When WhatsApp review is off, its unreviewed files don't count in the totals.
  final bool whatsappOff;

  const Counts(this.byBucket, this.trashBytes, {this.whatsappOff = false});

  int _sum(int Function(BucketCount) f) =>
      byBucket.values.fold<int>(0, (a, b) => a + f(b));

  int _sumTotals(bool pending) {
    var n = 0;
    byBucket.forEach((k, b) {
      if (k == Bucket.whatsapp && whatsappOff) {
        n += pending ? 0 : b.kept + b.trash;
      } else {
        n += pending ? b.pending : b.total;
      }
    });
    return n;
  }

  int get total => _sumTotals(false);
  int get pending => _sumTotals(true);
  int get kept => _sum((b) => b.kept);
  int get trash => _sum((b) => b.trash);
  int get reviewed => kept + trash;
}

/// One set of byte-identical files.
class DupGroup {
  final String hash;
  final int size;
  final List<FileEntry> members; // keeper first

  const DupGroup(this.hash, this.size, this.members);

  FileEntry get keeper =>
      members.firstWhere((e) => e.dup == 1, orElse: () => members.first);

  List<FileEntry> get extras =>
      members.where((e) => !identical(e, keeper)).toList();

  int get extraBytes => size * (members.length - 1);
}

class DupStats {
  final int groups;
  final int extras;
  final int bytes;

  const DupStats(this.groups, this.extras, this.bytes);
  static const DupStats none = DupStats(0, 0, 0);
}
