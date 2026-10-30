/// Exact, validated writes and deletes for a GitHub retirement.
library;

import 'package:pitaka/features/publish/domain/git_blob_sha.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/pending_move.dart';
import 'package:pitaka/features/publish/domain/site/publish_file.dart';
import 'package:pitaka/features/publish/domain/site/publish_section.dart';

/// Builds the moved page outside the pure domain (implemented with rootBundle).
typedef MovedHtmlBuilderFn =
    Future<List<int>> Function({
      required String libraryName,
      required PublishTarget newTarget,
    });

/// Re-renders the persisted schema/name and authenticates both stored documents
/// before any retirement write or already-retired adoption.
typedef MovedHtmlValidationFn = Future<bool> Function(PendingMove pending);

/// Normalizes the immutable library name stored with a moved-page descriptor.
///
/// This is a TOTAL rule (fix-plan M9/D6): the pending-move record rejects C0
/// controls, DEL, surrounding whitespace and more than 256 UTF-16 units, and a
/// rejected name has no Retry — every move attempt would republish and then
/// fail at the same point. Replacing a rejected unit is therefore safer than
/// refusing the name, and doing it here (before any write) is what makes the
/// failure impossible rather than merely visible.
///
/// Every name the record accepts today is returned unchanged, so existing
/// pending records still validate and already-rendered moved pages still match.
String normalizeMovedLibraryName(String value) {
  const maxUnits = 256;
  final buffer = StringBuffer();
  for (final unit in value.codeUnits) {
    // C0 controls and DEL become one space. A pasted tab in a library name is
    // a formatting accident, not content the moved page needs.
    buffer.writeCharCode(unit < 0x20 || unit == 0x7f ? 0x20 : unit);
  }
  final cleaned = buffer.toString().trim();
  if (cleaned.isEmpty) return 'My Library';
  if (cleaned.length <= maxUnits) return cleaned;

  var end = maxUnits;
  // Never cut a surrogate pair in half: 255 units keeps the last code point
  // whole, because a lone surrogate is not text the renderer can escape.
  if (_isHighSurrogate(cleaned.codeUnitAt(end - 1)) &&
      _isLowSurrogate(cleaned.codeUnitAt(end))) {
    end = maxUnits - 1;
  }
  final capped = cleaned.substring(0, end).trim();
  return capped.isEmpty ? 'My Library' : capped;
}

bool _isHighSurrogate(int unit) => unit >= 0xd800 && unit <= 0xdbff;

bool _isLowSurrogate(int unit) => unit >= 0xdc00 && unit <= 0xdfff;

/// The one retirement plan derived from a pending move's immutable descriptor.
final class MovePlan {
  const MovePlan._({required this.files, required this.deletePaths});

  /// Moved `index.html` and `404.html`, always uploaded as fresh bytes.
  final List<PublishFile> files;

  /// Every other exact app-owned path from the validated source manifest.
  final List<String> deletePaths;

  /// The retired manifest's complete file set.
  Map<String, String> get fileShas => {
    for (final file in files) file.path: file.gitSha,
  };

  /// Builds a GitHub plan. Cloudflare uses the same moved bytes plus its fresh
  /// marker, but its complete-snapshot deployment needs no deletion list.
  static MovePlan? forGitHub(PendingMove pending) {
    if (pending.oldTarget is! GitHubPublishTarget) return null;
    final descriptor = pending.retirement;
    final files = <PublishFile>[
      _file('index.html', descriptor.indexHtml),
      _file('404.html', descriptor.notFoundHtml),
    ];
    final writes = files.map((file) => file.path).toSet();
    final deletes = descriptor.deletePaths;
    if (deletes.toSet().length != deletes.length ||
        deletes.any(
          (path) => writes.contains(path) || !_ownedByPublishSection(path),
        )) {
      return null;
    }
    return MovePlan._(
      files: List.unmodifiable(files),
      deletePaths: List.unmodifiable(deletes),
    );
  }

  static PublishFile _file(String path, List<int> bytes) => PublishFile(
    path: path,
    bytes: bytes,
    gitSha: GitBlobSha.of(bytes),
    upload: true,
  );
}

bool _ownedByPublishSection(String path) =>
    SiteSection.catalogue.owns(path) ||
    SiteSection.events.owns(path) ||
    SiteSection.retirement.owns(path);
