/// The host journal's rules and its read-back-gated migration.
///
/// Reads distinguish a genuinely absent record from an unreadable one. Only an
/// absent record may trigger legacy GitHub defaults/migration; corrupt pending
/// history fails closed and is never overwritten by a fresh publication.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/publish_library_use_case.dart'
    show PublishManifestGateway;
import 'package:pitaka/features/publish/domain/git_blob_sha.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/pending_move.dart';
import 'package:pitaka/features/publish/domain/site/publish_host.dart';
import 'package:pitaka/features/publish/domain/site/publish_host_state.dart';
import 'package:pitaka/features/publish/domain/site/published_site_verifier.dart';

/// Persistence of the journal record over one preferences key.
abstract interface class PublishHostStateStore {
  /// Right(null) means truly absent; Right(state) is valid; Left is corrupt,
  /// unsupported, or unreadable and forbids every default or mutation.
  Either<Failure, PublishHostState?> load();

  /// Writes the whole record (one key, one write).
  Future<Either<Failure, Unit>> save(PublishHostState state);

  /// Deletes the key ONLY when the stored record is unreadable.
  ///
  /// The store re-checks readability itself, so no caller can use this as a
  /// general reset: a readable record is refused. This is the one in-app exit
  /// for an unreadable journal (fix-plan N7/D10).
  Future<Either<Failure, Unit>> clearUnreadable();
}

/// The narrow ability a PUBLISH has on the journal: record verified read-back.
// ignore: one_member_abstracts
abstract interface class PublishHostStateRecorder {
  /// Records [target] as verified, without switching away during a move.
  Future<Either<Failure, Unit>> recordVerified(PublishTarget target);
}

/// Resolves the real repository only when a publish has proof to record.
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

  /// The file whose served sha proves a legacy GitHub site.
  static const String proofPath = 'books.json';

  @override
  Future<Either<Failure, Unit>> recordVerified(PublishTarget target) async {
    final loaded = _store.load();
    if (loaded case Left(value: final failure)) return Left(failure);
    final current = loaded.toNullable() ?? PublishHostState.empty;
    if (current.verifies(target)) return right(unit);
    final next = current.afterVerifiedPublish(target);
    // A cross-host destination publish deliberately changes no journal facts.
    if (identical(next, current)) return right(unit);
    return _store.save(next);
  }

  /// Persists a destination-verified pending move without switching hosts.
  /// Repeating the exact pending operation is a no-write success.
  Future<Either<Failure, Unit>> beginMove(PendingMove pending) async {
    final loaded = _loadWithLegacyDefault();
    if (loaded case Left(value: final failure)) return Left(failure);
    final current = loaded.toNullable() ?? PublishHostState.empty;
    final next = current.beginMove(pending);
    if (next == null) {
      return left(
        const ValidationFailure(
          'The active site changed. Review the move again before continuing.',
        ),
      );
    }
    if (identical(next, current)) return right(unit);
    return _store.save(next);
  }

  /// Selects the verified destination and clears pending history in one write.
  /// Completion and Skip both call this only for their exact expected move.
  Future<Either<Failure, Unit>> finishMove(PendingMove expected) async {
    final loaded = _store.load();
    if (loaded case Left(value: final failure)) return Left(failure);
    final current = loaded.toNullable();
    if (current == null) {
      return left(
        const ValidationFailure(
          'The pending move is no longer available. Review the move again.',
        ),
      );
    }
    final next = current.finishMove(expected);
    if (next == null) {
      return left(
        const ValidationFailure(
          'The pending move is no longer available. Review the move again.',
        ),
      );
    }
    if (identical(next, current)) return right(unit);
    return _store.save(next);
  }

  /// Deletes an UNREADABLE journal on explicit user request (N7/D10).
  ///
  /// Publishing, moves and setup fail closed forever while the record cannot
  /// be read (for example after installing an older version). This clears it
  /// once, so the next publish can record the site again. A readable record
  /// is refused by the store, so this can never be a general reset.
  Future<Either<Failure, Unit>> resetUnreadable() => _store.clearUnreadable();

  /// Reads only the stored journal for fail-fast command routing. No manifest
  /// or network is touched, and unreadable state remains a typed failure.
  Either<Failure, PublishHostState?> storedState() => _store.load();

  /// Display projection. Unreadable state yields no share/setup claim; commands
  /// must use the typed reads above rather than interpreting this as absence.
  PublishHostState? currentState() => _loadWithLegacyDefault().toNullable();

  /// Selects [host] only when no host is active, never during pending recovery.
  Future<Either<Failure, Unit>> ensureActiveHost(PublishHost host) async {
    final loaded = _loadWithLegacyDefault();
    if (loaded case Left(value: final failure)) return Left(failure);
    final current = loaded.toNullable() ?? PublishHostState.empty;
    if (current.activeHost != null) return right(unit);
    return _store.save(PublishHostState(activeHost: host));
  }

  Either<Failure, PublishHostState?> _loadWithLegacyDefault() {
    final loaded = _store.load();
    if (loaded case Left(value: final failure)) return Left(failure);
    final stored = loaded.toNullable();
    if (stored != null) return Right(stored);
    final legacyTarget = GitHubPublishTarget.create(_manifest.load().repo);
    if (legacyTarget == null) return const Right(null);
    return const Right(PublishHostState(activeHost: PublishHost.github));
  }

  /// The address to share, or null when nothing is verified yet.
  Future<String?> verifiedSiteUrl() async {
    final loaded = _store.load();
    if (loaded.isLeft()) return null;
    final stored = loaded.toNullable();
    if (stored != null) return stored.verifiedSiteUrl;

    final manifest = _manifest.load();
    final target = GitHubPublishTarget.create(manifest.repo);
    final expectedSha = manifest.shaFor(proofPath);
    if (target == null || expectedSha == null) return null;

    // One bounded migration fetch, only for a genuinely absent journal.
    final body = await _verifier.read(
      siteUrl: target.siteUrl,
      path: proofPath,
      maxBytes: publishedCatalogueReadBackMaxBytes,
      cacheBuster: 'migrate',
    );
    final proven = body != null && GitBlobSha.of(body) == expectedSha;
    final state = PublishHostState(
      activeHost: PublishHost.github,
      verifiedTarget: proven ? target : null,
    );
    await _store.save(state);
    return proven ? target.siteUrl : null;
  }
}
