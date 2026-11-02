/// Which file bytes one GitHub commit really sends (pure domain; ADR 0020
/// Decision 6, plan CV5).
///
/// Why a plan (beginner note): a GitHub commit is built from "blobs". A blob
/// is one stored copy of a file's bytes, named by its git blob sha, a content
/// fingerprint (`GitBlobSha`). Once a blob is in a repository, ANY path in a
/// new tree can point at it by that sha, and the bytes never have to be sent
/// again. Sending bytes ("create a blob") is one request per file, and GitHub
/// limits how many content-creating requests an account may make (about 80 a
/// minute and 500 an hour, plan J8). Every blob Pitak does not send makes a
/// large publish faster and keeps it further from that limit.
///
/// The rule lives here, ONCE, for every commit Pitak makes: catalogue,
/// events, availability, a move and a retirement. The port
/// (`GitHubGitDataApi.commitFiles`) only accepts a plan, so no commit can skip
/// it.
///  1. A file its section builder marked unchanged ([PublishFile.upload] is
///     false) is never sent. It may even carry no bytes.
///  2. A file whose sha the branch's head tree already holds, at ANY path, is
///     not sent. The new tree just names that sha.
///  3. Two files with the same bytes in one commit are sent once.
///
/// Everything else is sent. Deletions are not part of the plan: they stay the
/// exact owned paths the caller computed, so blob reuse can never widen what
/// a commit deletes.
///
/// It is safe in both directions. An empty or incomplete known set only means
/// more uploads (the behaviour before ADR 0020). And if a named sha were
/// missing from the repository, GitHub refuses the tree, so the commit fails
/// and the live site stays as it was.
library;

import 'package:pitaka/features/publish/domain/github_models.dart';
import 'package:pitaka/features/publish/domain/site/publish_file.dart';

/// The tree entries of one commit, each marked "send the bytes" or "name a
/// blob GitHub already holds".
final class GitHubCommitPlan {
  /// Plans [files] against [knownBlobShas]: every blob sha GitHub already
  /// holds in the target repository, at any path. Today that is the set of
  /// shas in the branch's complete head tree, read just before the commit.
  ///
  /// [files] keeps its order: it becomes the tree, and when two files share
  /// bytes the FIRST one carries the upload.
  factory GitHubCommitPlan({
    required Iterable<PublishFile> files,
    required Set<String> knownBlobShas,
  }) {
    // Shas this commit already sends: a second file with the same bytes then
    // names the blob the first one created (rule 3).
    final sentInThisCommit = <String>{};
    final entries = <DesiredFile>[];
    for (final file in files) {
      var send = file.upload; // rule 1
      if (send && knownBlobShas.contains(file.gitSha)) send = false; // rule 2
      if (send && !sentInThisCommit.add(file.gitSha)) send = false; // rule 3
      entries.add(
        DesiredFile(
          path: file.path,
          bytes: file.bytes,
          gitSha: file.gitSha,
          upload: send,
        ),
      );
    }
    return GitHubCommitPlan._(List.unmodifiable(entries));
  }

  const GitHubCommitPlan._(this.files);

  /// Every tree entry of the commit, in order. An entry with
  /// [DesiredFile.upload] true has its bytes sent as a new blob; the others
  /// name an existing blob by its sha.
  final List<DesiredFile> files;

  /// The entries whose bytes this commit sends.
  Iterable<DesiredFile> get uploads => files.where((f) => f.upload);

  /// Whether this commit sends any bytes at all.
  bool get hasUploads => files.any((f) => f.upload);

  /// The paths whose bytes this commit sends (reported as
  /// `PublishCommitSuccess.uploadedPaths`).
  List<String> get uploadedPaths => [for (final f in uploads) f.path];

  /// How many bytes this commit sends (the S0 timings report it).
  int get uploadBytes => uploads.fold(0, (sum, f) => sum + f.bytes.length);
}
