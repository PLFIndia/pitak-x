/// Crash-safe pending-move identity and immutable retirement instructions.
library;

import 'package:pitaka/features/publish/domain/github_branch_name.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/publish_host.dart';
import 'package:pitaka/features/publish/domain/site/publish_marker.dart';
import 'package:pitaka/features/publish/domain/site/publish_section.dart';

/// The source publication proved before a move starts.
final class MoveSourceAnchor {
  MoveSourceAnchor._({
    required this.value,
    required this.branch,
    required List<String> ownedPaths,
  }) : ownedPaths = List.unmodifiable(ownedPaths);

  /// Expected GitHub head SHA or Cloudflare live publish id.
  final String value;

  /// Exact Pages branch for a GitHub source; null for Cloudflare.
  final GitHubBranchName? branch;

  /// Sorted, validated app-owned paths in the source's last live manifest.
  final List<String> ownedPaths;

  /// Validates source evidence for [source].
  static MoveSourceAnchor? tryCreate({
    required PublishTarget source,
    required String value,
    required Iterable<String> ownedPaths,
    GitHubBranchName? branch,
  }) {
    final validAnchor = switch (source) {
      GitHubPublishTarget() => _gitSha.hasMatch(value) && branch != null,
      CloudflarePublishTarget() =>
        branch == null && PublishMarker.isValidPublishId(value),
    };
    if (!validAnchor) return null;
    final input = ownedPaths.toList();
    final unique = input.toSet();
    if (unique.length != input.length ||
        !unique.contains('index.html') ||
        !unique.contains('books.json') ||
        unique.any((path) => !_ownsAnySection(path))) {
      return null;
    }
    final paths = input..sort();
    return MoveSourceAnchor._(value: value, branch: branch, ownedPaths: paths);
  }

  /// True only for the same remote anchor, branch, and owned deletion set.
  bool samePublication(MoveSourceAnchor other) {
    if (value != other.value ||
        branch?.value != other.branch?.value ||
        ownedPaths.length != other.ownedPaths.length) {
      return false;
    }
    for (var i = 0; i < ownedPaths.length; i++) {
      if (ownedPaths[i] != other.ownedPaths[i]) return false;
    }
    return true;
  }

  static final RegExp _gitSha = RegExp(r'^[0-9a-fA-F]{40}$');
}

/// The only pending phase in S9: destination verified, retirement unfinished.
enum PendingMovePhase {
  /// Keep the old active/share target until retirement and its read-back pass.
  retirementPending,
}

/// Immutable instructions persisted BEFORE the first retirement write.
final class RetirementDescriptor {
  RetirementDescriptor._({
    required List<int> indexHtml,
    required List<int> notFoundHtml,
    required this.movedPageSchema,
    required this.libraryName,
    required this.sourceBranch,
    required List<String> deletePaths,
    required this.marker,
  }) : indexHtml = List.unmodifiable(indexHtml),
       notFoundHtml = List.unmodifiable(notFoundHtml),
       deletePaths = List.unmodifiable(deletePaths);

  /// Exact bytes for the old site's moved root.
  final List<int> indexHtml;

  /// Exact bytes for the old site's moved 404 page.
  final List<int> notFoundHtml;

  /// Versioned renderer used to validate those bytes before every Retry.
  final int movedPageSchema;

  /// Immutable normalized name; current settings are never consulted on Retry.
  final String libraryName;

  /// Recorded Pages branch for a GitHub source.
  final GitHubBranchName? sourceBranch;

  /// Exact app-owned GitHub paths to remove; empty for Cloudflare.
  final List<String> deletePaths;

  /// Fresh retired marker for a Cloudflare source; null for GitHub.
  final PublishMarker? marker;

  /// Maximum size of either small public moved-page document.
  static const int maxMovedPageBytes = 64 * 1024;

  /// Current moved-page renderer. Old versions remain supported by the builder.
  static const int currentMovedPageSchema = 1;

  static RetirementDescriptor? _tryCreate({
    required PublishTarget oldTarget,
    required MoveSourceAnchor sourceAnchor,
    required List<int> indexHtml,
    required List<int> notFoundHtml,
    required int movedPageSchema,
    required String libraryName,
    required PublishMarker? marker,
  }) {
    if (!_validPage(indexHtml) ||
        !_validPage(notFoundHtml) ||
        movedPageSchema <= 0 ||
        !_validLibraryName(libraryName)) {
      return null;
    }
    final paths = <String>[];
    switch (oldTarget) {
      case GitHubPublishTarget():
        if (marker != null || sourceAnchor.branch == null) return null;
        final writes = {'index.html', '404.html'};
        paths.addAll(
          sourceAnchor.ownedPaths.where((path) => !writes.contains(path)),
        );
      case CloudflarePublishTarget():
        final retired = marker;
        if (retired == null ||
            retired.state != PublishMarkerState.retired ||
            retired.publishId == sourceAnchor.value ||
            sourceAnchor.branch != null) {
          return null;
        }
    }
    paths.sort();
    if (paths.any((path) => !_ownsAnySection(path))) return null;
    return RetirementDescriptor._(
      indexHtml: indexHtml,
      notFoundHtml: notFoundHtml,
      movedPageSchema: movedPageSchema,
      libraryName: libraryName,
      sourceBranch: sourceAnchor.branch,
      deletePaths: paths,
      marker: marker,
    );
  }

  static bool _validPage(List<int> bytes) {
    if (bytes.isEmpty || bytes.length > maxMovedPageBytes) return false;
    return bytes.every((byte) => byte >= 0 && byte <= 255);
  }

  static bool _validLibraryName(String value) {
    if (value.isEmpty || value.length > 256 || value.trim() != value) {
      return false;
    }
    return value.codeUnits.every((unit) => unit >= 0x20 && unit != 0x7f);
  }

  bool _same(RetirementDescriptor other) =>
      movedPageSchema == other.movedPageSchema &&
      libraryName == other.libraryName &&
      sourceBranch?.value == other.sourceBranch?.value &&
      _sameBytes(indexHtml, other.indexHtml) &&
      _sameBytes(notFoundHtml, other.notFoundHtml) &&
      _sameStrings(deletePaths, other.deletePaths) &&
      marker?.publishId == other.marker?.publishId &&
      marker?.publishedAt == other.marker?.publishedAt &&
      marker?.state == other.marker?.state;
}

/// One atomic pending-move record. It contains no credential or upload token.
final class PendingMove {
  const PendingMove._({
    required this.oldTarget,
    required this.newTarget,
    required this.sourceAnchor,
    required this.retirement,
  });

  /// Exact source selected when the move was confirmed.
  final PublishTarget oldTarget;

  /// Exact destination that already passed complete publication read-back.
  final PublishTarget newTarget;

  /// Source anchor and exact owned paths revalidated before retirement.
  final MoveSourceAnchor sourceAnchor;

  /// Immutable moved-page and marker instructions used by every Retry.
  final RetirementDescriptor retirement;

  /// Current recovery phase; S9 persists only retirement-pending records.
  PendingMovePhase get phase => PendingMovePhase.retirementPending;

  /// Creates a fully validated pending record, or null on inconsistent input.
  static PendingMove? tryCreate({
    required PublishTarget oldTarget,
    required PublishTarget newTarget,
    required MoveSourceAnchor sourceAnchor,
    required List<int> indexHtml,
    required List<int> notFoundHtml,
    required String libraryName,
    int movedPageSchema = RetirementDescriptor.currentMovedPageSchema,
    PublishMarker? retirementMarker,
  }) {
    if (oldTarget.host == newTarget.host) return null;
    final expectedAnchor = MoveSourceAnchor.tryCreate(
      source: oldTarget,
      value: sourceAnchor.value,
      branch: sourceAnchor.branch,
      ownedPaths: sourceAnchor.ownedPaths,
    );
    if (expectedAnchor == null) return null;
    final retirement = RetirementDescriptor._tryCreate(
      oldTarget: oldTarget,
      sourceAnchor: expectedAnchor,
      indexHtml: indexHtml,
      notFoundHtml: notFoundHtml,
      movedPageSchema: movedPageSchema,
      libraryName: libraryName,
      marker: retirementMarker,
    );
    if (retirement == null) return null;
    return PendingMove._(
      oldTarget: oldTarget,
      newTarget: newTarget,
      sourceAnchor: expectedAnchor,
      retirement: retirement,
    );
  }

  /// True when [target] is either exact endpoint of this pending move.
  bool involves(PublishTarget target) =>
      oldTarget.isSameExactTarget(target) ||
      newTarget.isSameExactTarget(target);

  /// The exact pending endpoint for [host], used by target-mutation guards.
  PublishTarget targetFor(PublishHost host) {
    if (oldTarget.host == host) return oldTarget;
    return newTarget;
  }

  /// Full operation identity, used after an uncertain save and before clearing.
  bool sameOperation(PendingMove other) =>
      phase == other.phase &&
      oldTarget.isSameExactTarget(other.oldTarget) &&
      newTarget.isSameExactTarget(other.newTarget) &&
      sourceAnchor.samePublication(other.sourceAnchor) &&
      retirement._same(other.retirement);

  @override
  String toString() =>
      'PendingMove(${oldTarget.targetId} -> ${newTarget.targetId}, $phase)';
}

bool _ownsAnySection(String path) =>
    SiteSection.catalogue.owns(path) ||
    SiteSection.events.owns(path) ||
    SiteSection.retirement.owns(path);

bool _sameStrings(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
