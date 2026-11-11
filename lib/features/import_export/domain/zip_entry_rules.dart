/// The rules a ZIP entry has to keep BEFORE a reader unpacks it
/// (import/export domain, ADR 0009).
///
/// WHY THIS FILE EXISTS (beginner note): a ZIP file's directory makes
/// claims about every entry: its name, its sizes, how it is packed. A
/// reader that trusts those claims can be led to write outside its folder
/// (a name like `../../file`) or to unpack far more than the file's size
/// suggests. The rules here look at the claims only. They read no content
/// and touch no disk, so they are plain Dart that a test can run on a
/// record made by hand.
///
/// Since BR5 the app has two ZIP readers until the older one is removed
/// (BR7): `BoundedZipExtractor`, which holds the archive in memory, and
/// `BoundedZipFile`, which works from a file. Both use the name rule
/// ([zipLeafName]) and the exception of this file.
///
/// The rest of the file is for the reader that works from a file:
///  - [ZipEntryRule] and [ZipEntryPolicy]: what the CALLER wants done with
///    an entry of a given name (unpack it up to a size, leave it out when
///    it is larger, or ignore it);
///  - [checkZipEndRecord] and [checkZipEntries]: every check that can be
///    made from declared values, for the whole archive, before anything is
///    unpacked.
/// The in-memory reader keeps its own copy of these checks, in the order
/// the released app ran them, until it is removed. The tests in
/// `bounded_zip_extractor_test.dart` and
/// `bounded_zip_extractor_container_test.dart` ask every case of both
/// readers, so a difference between the two shows.
///
/// Three rules here are STRICTER than the in-memory reader (`PLAN.md`,
/// "BR5 in detail", rules N1 to N3; ADR 0009, amendment of 2026-11-11).
/// No file an honest writer makes breaks them.
library;

import 'package:pitaka/features/import_export/domain/zip_container.dart';
import 'package:pitaka/features/import_export/domain/zip_limits.dart';

/// Thrown on any limit violation or structural anomaly (zip-slip, empty name,
/// nested name, duplicate, directory entry). Distinct from IO errors so callers
/// can show "archive looks corrupt or hostile" without conflating causes.
class BoundedExtractionException implements Exception {
  /// Creates the exception with a human-readable [message].
  const BoundedExtractionException(this.message);

  /// Why extraction was rejected.
  final String message;

  @override
  String toString() => 'BoundedExtractionException: $message';
}

/// The name under which the entry [header] is handed out: its LEAF, checked.
///
/// Name checks: leaf-only, non-empty, no separators/NUL, unique, a file.
/// [isTaken] says whether an earlier entry of the same archive already has
/// that leaf name.
///
/// Uses the CENTRAL directory name (spoof-safe; the local header's name is
/// ignored, cf. archive issue #266). "Directory" here means either a
/// trailing slash or a UNIX mode that is not a regular file (symlink,
/// device, ...), mirroring what `ZipDecoder` would have classified — but
/// refused instead of followed.
///
/// Throws [BoundedExtractionException] for a name that breaks a rule.
String zipLeafName(
  ZipDirectoryEntry header, {
  required bool Function(String leaf) isTaken,
}) {
  final rawName = header.name;
  if (!_isRegularFile(header)) {
    throw BoundedExtractionException(
      "Archive contains a directory entry: '$rawName'",
    );
  }

  // Reduce to leaf; strip any directory component (zip-slip defence).
  final leaf = rawName.split('/').last.split(r'\').last;
  if (leaf.trim().isEmpty) {
    throw BoundedExtractionException(
      "Archive entry has an empty filename: '$rawName'",
    );
  }
  if (leaf.contains('/') || leaf.contains(r'\') || leaf.contains('\u0000')) {
    throw BoundedExtractionException(
      "Archive entry has an unsafe filename: '$rawName'",
    );
  }
  if (isTaken(leaf)) {
    throw BoundedExtractionException(
      "Archive has duplicate entry name: '$leaf'",
    );
  }
  return leaf;
}

/// Same classification `ZipDecoder.decodeBuffer` applies: for UNIX-made
/// entries (`versionMadeBy` high byte 3) the file type lives in the high
/// 16 bits of the external attributes; anything but "regular" (0x8000) or
/// "unspecified" (0x0000) is not a plain file. For other hosts only a
/// trailing slash marks a directory.
bool _isRegularFile(ZipDirectoryEntry header) {
  if (header.name.endsWith('/')) return false;
  if ((header.versionMadeBy >> 8) == 3) {
    final mode = header.externalAttributes >> 16;
    final fileType = mode & 0xF000;
    return fileType == 0x8000 || fileType == 0x0000;
  }
  return true;
}

/// What a reader does when an entry DECLARES more bytes than its rule
/// allows.
enum ZipTooLarge {
  /// The whole archive is refused. For an entry nothing works without.
  refuseArchive,

  /// The entry is left out and the rest of the archive is read. For an
  /// entry the rest can do without (backup rework, decision D18).
  leaveOut,
}

/// What a reader does with ONE entry, decided by the entry's name alone.
///
/// A value object: the caller of a reader hands it a function "name in,
/// rule out" ([ZipEntryPolicy]). So the reader knows nothing about backups
/// or covers, and the table of names lives with the feature that owns the
/// names.
final class ZipEntryRule {
  /// The entry is unpacked when it declares at most [maxBytes]. An entry
  /// exactly AT the cap is fine. Above it, [tooLarge] decides; the default
  /// is the safe one, to refuse the archive.
  const ZipEntryRule.take({
    required int maxBytes,
    this.tooLarge = ZipTooLarge.refuseArchive,
  }) : assert(maxBytes >= 0, 'maxBytes must not be negative'),
       _maxBytes = maxBytes;

  /// The entry is never unpacked, whatever it holds: a name the caller does
  /// not know. It still counts as an entry, and its name and headers are
  /// checked like any other.
  const ZipEntryRule.ignore()
    : _maxBytes = null,
      tooLarge = ZipTooLarge.refuseArchive;

  final int? _maxBytes;

  /// What happens to an entry that declares more than [maxBytes].
  final ZipTooLarge tooLarge;

  /// True for [ZipEntryRule.ignore].
  bool get ignores => _maxBytes == null;

  /// The most bytes the entry may declare, or null when it is ignored.
  int? get maxBytes => _maxBytes;
}

/// Gives the rule for the entry with the leaf name [leaf].
typedef ZipEntryPolicy = ZipEntryRule Function(String leaf);

/// What the rules decided for one entry.
enum ZipEntryVerdict {
  /// It may be unpacked.
  take,

  /// It declares more than its rule allows, and its rule says to leave it
  /// out ([ZipTooLarge.leaveOut]). It is never unpacked.
  leftOut,

  /// Its rule is [ZipEntryRule.ignore]. It is never unpacked.
  ignored,
}

/// One entry that passed [checkZipEntries]: its checked leaf name, the
/// verdict, and the directory record the two came from.
final class CheckedZipEntry {
  /// Creates the result for one entry.
  const CheckedZipEntry({
    required this.leaf,
    required this.verdict,
    required this.record,
  });

  /// The name the entry is handed out under: a leaf, never a path.
  final String leaf;

  /// Whether the entry may be unpacked.
  final ZipEntryVerdict verdict;

  /// The directory record. Its sizes are what the entry DECLARES; a reader
  /// holds the content to them.
  final ZipDirectoryEntry record;
}

/// ZIP general-purpose flag bit 0: the entry is encrypted.
const int _flagEncrypted = 0x1;

/// The two ways of packing an entry that a reader accepts.
const int _methodStore = 0;
const int _methodDeflate = 8;

/// True when [record] says its content is deflated (compressed); false when
/// it is stored as it is. [checkZipEntries] has refused every other method.
bool zipEntryIsDeflated(ZipDirectoryEntry record) =>
    record.method == _methodDeflate;

/// Checks the end record [end] of an archive against [limits].
///
/// Refuses zip64 (no archive of this app needs it), more entries or a
/// larger directory than allowed, and a directory that does not lie inside
/// the file in front of the end record. Run BEFORE the directory is read:
/// these numbers decide how much is read.
///
/// Throws [BoundedExtractionException].
void checkZipEndRecord(ZipEndRecord end, ZipLimits limits) {
  if (end.isZip64) {
    throw const BoundedExtractionException(
      'Archive uses zip64, which Pitak archives never do',
    );
  }
  if (end.entryCount > limits.maxEntries) {
    throw BoundedExtractionException(
      'Archive has too many entries (>${limits.maxEntries})',
    );
  }
  if (end.centralDirectorySize > limits.maxCentralDirectoryBytes) {
    throw BoundedExtractionException(
      'Archive central directory is too large '
      '(>${limits.maxCentralDirectoryBytes} bytes)',
    );
  }
  if (end.centralDirectoryOffset + end.centralDirectorySize >
      end.recordOffset) {
    throw const BoundedExtractionException(
      'Archive central directory lies outside the file',
    );
  }
}

/// Runs every check that needs DECLARED values only, for all [records] of a
/// directory, and says for each entry whether it may be unpacked.
///
/// Nothing is unpacked or read here, and that is the point: a file that
/// breaks a rule is refused before one byte of content is touched.
///
/// For every entry, whatever its rule:
///  - the name rules of [zipLeafName] (a plain file, a leaf, no duplicate);
///  - not encrypted, and stored or deflated;
///  - no size or offset from a zip64 record (rule N3 of BR5: no cap of this
///    app comes near the 4 GB where one is needed);
///  - a stored entry declares the same size packed and unpacked (the first
///    half of rule N1 of BR5; a reader checks the other half, that what
///    comes out of a deflated entry is the declared size).
///
/// Then [policy] gives the rule for the entry's name; without a policy
/// every entry is taken up to [ZipLimits.maxEntryBytes] and the archive is
/// refused above it. The declared sizes of the entries that are TAKEN are
/// added up against [ZipLimits.maxTotalBytes]: an entry that is left out or
/// ignored is never unpacked and adds nothing.
///
/// The caller has counted the records against [ZipLimits.maxEntries] while
/// reading them; the count is checked here once more.
///
/// Throws [BoundedExtractionException] when the archive is refused.
List<CheckedZipEntry> checkZipEntries(
  List<ZipDirectoryEntry> records, {
  required ZipLimits limits,
  ZipEntryPolicy? policy,
}) {
  if (records.length > limits.maxEntries) {
    throw BoundedExtractionException(
      'Archive has too many entries (>${limits.maxEntries})',
    );
  }
  final checked = <CheckedZipEntry>[];
  final leaves = <String>{};
  var declaredTotal = 0;
  for (final record in records) {
    final leaf = zipLeafName(record, isTaken: leaves.contains);
    leaves.add(leaf);

    // Features this app never writes and therefore refuses to read.
    if ((record.flags & _flagEncrypted) != 0) {
      throw BoundedExtractionException("Archive entry '$leaf' is encrypted");
    }
    final method = record.method;
    if (method != _methodStore && method != _methodDeflate) {
      throw BoundedExtractionException(
        "Archive entry '$leaf' uses unsupported compression method $method",
      );
    }
    if (record.hasZip64Marker) {
      throw BoundedExtractionException(
        "Archive entry '$leaf' uses zip64, which Pitak archives never do",
      );
    }
    if (method == _methodStore &&
        record.compressedSize != record.uncompressedSize) {
      throw BoundedExtractionException(
        "Archive entry '$leaf' is stored, but declares two different sizes",
      );
    }

    final rule =
        policy?.call(leaf) ?? ZipEntryRule.take(maxBytes: limits.maxEntryBytes);
    final cap = rule.maxBytes;
    if (cap == null) {
      checked.add(
        CheckedZipEntry(
          leaf: leaf,
          verdict: ZipEntryVerdict.ignored,
          record: record,
        ),
      );
      continue;
    }
    if (record.uncompressedSize > cap) {
      if (rule.tooLarge == ZipTooLarge.leaveOut) {
        checked.add(
          CheckedZipEntry(
            leaf: leaf,
            verdict: ZipEntryVerdict.leftOut,
            record: record,
          ),
        );
        continue;
      }
      throw BoundedExtractionException(
        "Archive entry '$leaf' exceeds per-entry cap ($cap bytes)",
      );
    }
    // Added only after the cap check, so the sum stays far from overflow:
    // each part is at most `cap`.
    declaredTotal += record.uncompressedSize;
    if (declaredTotal > limits.maxTotalBytes) {
      throw BoundedExtractionException(
        'Archive total exceeds cap (${limits.maxTotalBytes} bytes)',
      );
    }
    checked.add(
      CheckedZipEntry(
        leaf: leaf,
        verdict: ZipEntryVerdict.take,
        record: record,
      ),
    );
  }
  return checked;
}
