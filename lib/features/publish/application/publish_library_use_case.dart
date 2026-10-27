/// Publish-to-GitHub-Pages orchestrator (application layer, AGENTS.md §4, #32).
///
/// Port of Kotlin `PublishLibraryUseCase`. Pushes the world-facing catalogue
/// (books.json + index.html viewer + library.json + salted covers/) as ONE
/// atomic, incremental commit via [GitHubGitDataApi] (the git-data role of
/// the GitHub port, S5 — this use case never touches auth or repo admin).
///
/// Pipeline:
///  1. Resolve token + target repo + the branch Pages SERVES from (N09: read
///     live from the Pages configuration, never assumed to be the default
///     branch; Pages off or re-pointed → typed failure before any write).
///  2. Load (or rebuild) the incremental manifest.
///  3. Ask the SHARED [PublishSnapshotBuilder] for the section to write
///     (Cloudflare plan R2/R3) — the same builder the Cloudflare adapter will
///     consume, over strict reads, so the two hosts cannot drift and a failed
///     read aborts before any write.
///  4. Merge that section into the publication record (R7): only its own
///     paths are replaced, the events section survives.
///  5. Commit the changed file set + exact owned deletions; persist the merged
///     manifest; read the live site back (bounded).
///
/// Cover images are downscaled by the injected local-cover reader
/// (`ImageDownscaler`, 400×600 q80 — the single image choke point), so a
/// publish uploads small JPEGs and EXIF/GPS never leaves the device.
library;

import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/publish_result.dart';
import 'package:pitaka/features/publish/application/site/catalogue_section_builder.dart';
import 'package:pitaka/features/publish/application/site/publish_snapshot_builder.dart';
import 'package:pitaka/features/publish/domain/github_api.dart';
import 'package:pitaka/features/publish/domain/github_error_messages.dart';
import 'package:pitaka/features/publish/domain/github_models.dart';
import 'package:pitaka/features/publish/domain/publish_credential_store.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/publish_mode.dart';
import 'package:pitaka/features/publish/domain/site/published_site_verifier.dart';
import 'package:pitaka/features/publish/domain/site/section_merge.dart';

export 'publish_result.dart';

/// Coarse publish phases for the UI.
enum PublishPhase {
  /// Building books.json / viewer, deciding what changed.
  preparing,

  /// Creating blobs for changed files.
  uploading,

  /// Tree + commit + ref move.
  committing,

  /// Waiting for the live site to serve the new content (bounded).
  pagesBuilding,
}

/// Orchestrates a single publish run.
final class PublishLibraryUseCase {
  /// Creates the use case over its ports.
  PublishLibraryUseCase({
    required GitHubGitDataApi api,
    required PublishCredentialReader credentials,
    required PublishManifestGateway manifest,
    required PublishSnapshotBuilder snapshotBuilder,
    required PublishReads reads,
    PublishedSiteVerifier? verifier,
    Future<void> Function(Duration)? sleep,
    int Function()? clock,
  }) : _api = api,
       _credentials = credentials,
       _manifest = manifest,
       _snapshotBuilder = snapshotBuilder,
       _reads = reads,
       _verifier = verifier,
       _sleep = sleep ?? Future<void>.delayed,
       _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  final GitHubGitDataApi _api;
  final PublishCredentialReader _credentials;
  final PublishManifestGateway _manifest;

  /// The ONE section builder for every host (R3). Building happens here, after
  /// the manifest is known, so exactly one manifest load feeds the change
  /// detection and the merge — the section is never built twice.
  final PublishSnapshotBuilder _snapshotBuilder;

  /// Strict typed reads the snapshot is built from (R2).
  final PublishReads _reads;

  /// Null ⇒ read-back skipped (tests / no network port wired).
  final PublishedSiteVerifier? _verifier;
  final Future<void> Function(Duration) _sleep;
  final int Function() _clock;

  /// Read-back budget: [readBackAttempts] polls, [readBackInterval] apart
  /// (Orange budgets 120 s; 60 s covers typical Pages builds and keeps the
  /// worst-case wait tolerable on a phone). ALWAYS terminates.
  static const int readBackAttempts = 12;

  /// Pause between read-back polls.
  static const Duration readBackInterval = Duration(seconds: 5);

  /// Repo-relative path of the network descriptor (docs/ARCHITECTURE.md §5.1).
  static const String libraryJsonPath = CatalogueSectionBuilder.libraryJsonPath;

  /// Runs the publish to [target].
  ///
  /// [target] is the EXACT destination of this operation (R1/C3). It is the
  /// only source of the site URL — for the descriptor, the read-back and the
  /// success message — so a move can publish the new site while the old one is
  /// still the active host.
  ///
  /// Phase 1 reads every input strictly through [_reads]. It runs FIRST, so a
  /// library that cannot be read fails before a token is fetched, before the
  /// GitHub API is called and before the manifest is loaded (R2: no remote
  /// write, and no pointless round trip, for a publish that cannot proceed).
  ///
  /// [mode] is [PublishMode.complete] for a move or a whole-site
  /// replacement: every required cover must then resolve to usable bytes, and
  /// a missing one fails typed BEFORE any write.
  ///
  /// This path publishes the CATALOGUE section only. The events section has
  /// its own independent publish (`PublishEventsUseCase`, Q5=A), so this
  /// snapshot never carries poster files and can never delete one.
  Future<PublishResult> call({
    required GitHubPublishTarget target,
    PublishMode mode = PublishMode.incremental,
    void Function(PublishPhase)? onPhase,
  }) async {
    void phase(PublishPhase p) => onPhase?.call(p);
    phase(PublishPhase.preparing);

    final read = await _snapshotBuilder.read(
      reads: _reads,
      target: target,
      includeEvents: false,
    );
    final inputs = read.toNullable();
    if (inputs == null) {
      // A failed read is never "empty content": nothing is built or written.
      return PublishFailure(_messageFor(read.swap().toNullable()!));
    }

    final token = await _credentials.token();
    if (token == null) return const PublishFailure('Not signed in to GitHub.');
    // The target carries the address (derived, never supplied): no second
    // derivation here, so the descriptor, the commit and the read-back can
    // never disagree about where this publish goes.
    final owner = target.owner;
    final repo = target.repo;
    final ownerRepo = target.ownerRepo;
    final pagesUrl = target.siteUrl;

    final now = _clock();

    // N09 (D2-a): commit to the branch Pages actually serves. Publishing to
    // any other branch would "succeed" without changing the live site.
    final String branch;
    try {
      final site = await _api.pagesSite(owner: owner, repo: repo, token: token);
      if (site == null || !site.isPublishableByApp) {
        return const PublishFailure(gitHubPagesNotServingMessage);
      }
      branch = site.sourceBranch!;
    } on GitHubApiException {
      return const PublishFailure(gitHubNetworkErrorMessage);
    }

    // Load manifest; rebuild from the repo tree if missing / for another repo.
    var manifest = _manifest.load();
    if (manifest.repo != ownerRepo || manifest.fileShas.isEmpty) {
      try {
        final shas = await _api.headTreeShas(
          owner: owner,
          repo: repo,
          branch: branch,
          token: token,
        );
        manifest = PublishManifest(repo: ownerRepo, fileShas: shas);
      } on GitHubApiException {
        manifest = PublishManifest(repo: ownerRepo);
      }
    }

    // Phase 2: build the section through the SHARED builders (R3) against the
    // publication record that will also be merged, so change detection and
    // the merge can never disagree. A typed failure here means NOTHING was
    // written. The catalogue section owns no poster path, so a catalogue
    // publish can never delete one (R7).
    final built = await _snapshotBuilder.build(
      inputs: inputs,
      previous: manifest,
      now: now,
      mode: mode,
    );
    final snapshot = built.toNullable();
    if (snapshot == null) {
      return PublishFailure(_messageFor(built.swap().toNullable()!));
    }
    final section = snapshot.catalogue;

    // R7: merge ONLY this section into the publication record. The events
    // section (and any other app-owned path) survives; the section's own
    // dropped paths become exact deletions (never a prefix sweep).
    final merge = mergeSection(previous: manifest, section: section);

    phase(
      section.hasUploads ? PublishPhase.uploading : PublishPhase.committing,
    );

    final PublishCommitResult result;
    try {
      result = await _api.commitFiles(
        owner: owner,
        repo: repo,
        branch: branch,
        token: token,
        files: [
          for (final f in merge.files)
            DesiredFile(
              path: f.path,
              bytes: f.bytes,
              gitSha: f.gitSha,
              upload: f.upload,
            ),
        ],
        commitMessage: 'Pitaka publish $now',
        deletePaths: merge.deletePaths,
      );
    } on GitHubApiException {
      // Fixed message (§5): exception text can embed URLs/response detail.
      return const PublishFailure(gitHubNetworkErrorMessage);
    }

    switch (result) {
      case PublishCommitSuccess(:final uploadedPaths):
        _manifest.save(
          PublishManifest(
            repo: ownerRepo,
            fileShas: merge.fileShas,
            coverUrlByBookId: section.coverUrlByKey,
          ),
        );
        phase(PublishPhase.pagesBuilding);
        // `pagesUrl` came from the single resolver (github_pages_url.dart),
        // shared with the events publish and the drawer's share action.
        // Bounded read-back: poll the LIVE books.json with a cache-buster
        // until it serves exactly the bytes just published.
        final booksJson = merge.files
            .firstWhere((f) => f.path == CatalogueSectionBuilder.booksJsonPath)
            .bytes;
        final pagesLive = await _verifyLive(pagesUrl, booksJson, now);
        return PublishSuccess(
          pagesUrl: pagesUrl,
          uploadedPaths: uploadedPaths,
          availabilityOmitted: snapshot.availabilityOmitted,
          pagesLive: pagesLive,
        );
      case PublishCommitHttpError(:final code):
        // The response body is deliberately dropped: a hostile network can
        // inject arbitrary text into it (§5 "safe message only").
        return PublishFailure(gitHubHttpErrorMessage(code));
    }
  }

  /// Maps a typed failure to the fixed, user-facing publish message.
  static String _messageFor(Failure failure) => switch (failure) {
    // A read failure carries its own already-safe sentence (M14: "could not
    // read your saved libraries" must not become a generic message).
    PublishReadFailure(:final message) => message,
    ValidationFailure(:final message) => message,
    _ => 'Something went wrong. Nothing was published.',
  };

  /// Polls the live site (bounded) until books.json serves [expected].
  /// Returns true when verified, null when the budget ran out or no fetch
  /// port is wired. Never throws, never loops unbounded.
  Future<bool?> _verifyLive(
    String pagesUrl,
    List<int> expected,
    int revision,
  ) async {
    final verifier = _verifier;
    if (verifier == null) return null;
    for (var attempt = 0; attempt < readBackAttempts; attempt++) {
      await _sleep(readBackInterval);
      // Origin-bound, redirect-free, capped at exactly the expected size (a
      // longer body cannot be the file we wrote). A fresh cache-buster per
      // attempt so a CDN cannot answer with a stale copy.
      final body = await verifier.read(
        siteUrl: pagesUrl,
        path: 'books.json',
        maxBytes: expected.isEmpty ? 1 : expected.length,
        cacheBuster: '$revision-$attempt',
      );
      if (body != null && _sameBytes(body, expected)) return true;
    }
    return null;
  }

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Load/save view of the manifest the orchestrator needs.
abstract interface class PublishManifestGateway {
  /// Loads the manifest (or empty).
  PublishManifest load();

  /// Persists [manifest].
  void save(PublishManifest manifest);
}
