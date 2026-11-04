/// Operation-scoped spooling of GitHub publish artifacts (application layer;
/// review finding 6).
///
/// Why (beginner note): a complete GitHub publish builds every cover before
/// it commits. Keeping each cover's bytes in `PublishFile.bytes` meant a
/// 1,000-cover site held the whole produced site in heap at once. Cloudflare
/// already hands each file to an `PublishArtifactSink` immediately; GitHub
/// needs the same seam, plus the ability to READ one file back, because the
/// commit sends one blob request per changed file.
///
/// The file-backed implementation lives in infrastructure
/// (`FileGitHubArtifactStore`), so this application-layer use case never
/// touches `dart:io` (AGENTS §3.1). One store belongs to ONE operation: it
/// writes into its own run folder and removes only that folder.
library;

import 'package:pitaka/features/publish/domain/site/publish_artifact_sink.dart';

/// Creates a fresh operation-scoped store (never shared between operations).
typedef GitHubArtifactStoreFactory = GitHubArtifactStore Function();

/// Receives each built file immediately and can reopen it for the commit.
abstract interface class GitHubArtifactStore implements PublishArtifactSink {
  /// Reopens one spooled artifact's bytes, verified against the sha recorded
  /// when it was written. Null when this operation spooled nothing for
  /// [path] — an in-memory file (a merged `availability.json`, an empty
  /// `.nojekyll`) stays valid without a store entry.
  Future<List<int>?> read(String path);

  /// Removes this operation's run folder. Idempotent and never throws: a
  /// cleanup failure must not change the result of a commit that landed.
  Future<void> dispose();
}
