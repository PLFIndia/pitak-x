/// The host journal's rules and its read-back-gated migration (application
/// layer; Cloudflare plan E.5/R33, deviations 24 and 33).
///
/// Why the share address lives HERE and not in the publish manifest (beginner
/// note): the manifest describes what one publish wrote, and it is rewritten by
/// every publish. The address a library hands out — the one printed on a card,
/// shown in a QR code and sent to peers — must survive a failed publish, a
/// target change and a device that is halfway through a move. So it is stored
/// once, separately, and only ever set after a read-back PROVED the site is
/// live.
///
/// The migration rule (E.5): an older install has a manifest but no journal.
/// A manifest is not proof that its site is served, so the first read performs
/// ONE bounded read-back of the address the manifest implies and only then
/// records it as verified. Until that succeeds the journal makes no verified
/// claim and the share address stays empty.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/publish_library_use_case.dart'
    show PublishManifestGateway;
import 'package:pitaka/features/publish/domain/git_blob_sha.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/publish_host.dart';
import 'package:pitaka/features/publish/domain/site/publish_host_state.dart';
import 'package:pitaka/features/publish/domain/site/published_site_verifier.dart';

/// Persistence of the journal record. Implemented over one prefs key in
/// infrastructure; `load()` returns null when this phone has no record.
abstract interface class PublishHostStateStore {
  /// Reads the journal, or null when none was ever written (or it is
  /// unreadable/inconsistent — then there is nothing worth trusting).
  PublishHostState? load();

  /// Writes the whole record (one key, one write). A failure is returned —
  /// never swallowed, because the share/QR address depends on it (R9).
  Future<Either<Failure, Unit>> save(PublishHostState state);
}

/// The narrow ability a PUBLISH has on the journal: record that its own target
/// was proven live.
///
/// Why narrow (beginner note): a publish must not be able to rewrite the
/// active host, clear a move, or point the journal at a site it did not
/// publish to. Keeping that out of reach is cheaper than auditing for it.
///
/// It is an injected SEAM (a fake records calls in tests), not a data
/// abstraction, which is why it has one member.
// ignore: one_member_abstracts
abstract interface class PublishHostStateRecorder {
  /// Records [target] as the verified live target (R5/R33). Returns a typed
  /// failure when the record could not be persisted.
  Future<Either<Failure, Unit>> recordVerified(PublishTarget target);
}

/// A [PublishHostStateRecorder] that resolves the real repository on FIRST
/// USE.
///
/// Why (beginner note): a publish that fails while READING the library must
/// not touch anything else — not the network, not the file system, and now not
/// the preferences store either (R2's fail-fast rule, deviation 41). Resolving
/// the journal up front would open prefs before the first strict read, so the
/// controller passes this wrapper instead and the store is only opened when a
/// publish actually has something verified to record.
final class LazyPublishHostStateRecorder implements PublishHostStateRecorder {
  /// Creates the wrapper over a resolver.
  const LazyPublishHostStateRecorder(this._resolve);

  final Future<PublishHostStateRecorder> Function() _resolve;

  @override
  Future<Either<Failure, Unit>> recordVerified(PublishTarget target) async =>
      (await _resolve()).recordVerified(target);
}

/// Reads, migrates and updates the journal.
final class PublishHostStateRepository implements PublishHostStateRecorder {
  /// Creates the repository over its ports.
  const PublishHostStateRepository({
    required PublishHostStateStore store,
    required PublishManifestGateway manifest,
    required PublishedSiteVerifier verifier,
  }) : _store = store,
       _manifest = manifest,
       _verifier = verifier;

  final PublishHostStateStore _store;
  final PublishManifestGateway _manifest;
  final PublishedSiteVerifier _verifier;

  /// The repo-relative file whose served sha proves the site is live. It is
  /// the same file the publish read-back uses, so "verified" means the same
  /// thing in both places.
  static const String proofPath = 'books.json';

  @override
  Future<Either<Failure, Unit>> recordVerified(PublishTarget target) async {
    final current = _store.load() ?? PublishHostState.empty;
    if (current.verifies(target)) return right(unit);
    return _store.save(current.afterVerifiedPublish(target));
  }

  /// The address to share, or null when nothing is verified yet.
  ///
  /// Reads the journal when it exists. When it does not, performs the ONE
  /// bounded migration read-back described in the library doc and returns the
  /// address only if the site really serves what the manifest recorded.
  Future<String?> verifiedSiteUrl() async {
    final stored = _store.load();
    if (stored != null) return stored.verifiedSiteUrl;

    final manifest = _manifest.load();
    final target = GitHubPublishTarget.create(manifest.repo);
    final expectedSha = manifest.shaFor(proofPath);
    if (target == null || expectedSha == null) return null;

    // ONE fetch, no polling: the site was published minutes or days ago, so
    // either it is serving that file or it is not (E.5's bounded read-back).
    final body = await _verifier.read(
      siteUrl: target.siteUrl,
      path: proofPath,
      maxBytes: publishedCatalogueReadBackMaxBytes,
      cacheBuster: 'migrate',
    );
    final proven = body != null && GitBlobSha.of(body) == expectedSha;

    // Record the attempt either way: the active host is a fact (a GitHub
    // target exists), the verified pointer only when proven. Without the save
    // every later read would retry the fetch, and the share address of a site
    // that is genuinely unreachable would keep costing network.
    final state = PublishHostState(
      activeHost: PublishHost.github,
      verifiedTarget: proven ? target : null,
    );
    await _store.save(state);
    return proven ? target.siteUrl : null;
  }
}
