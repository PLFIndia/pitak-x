/// Shared S9 move test doubles. Synthetic targets, no network or credentials.
library;

import 'dart:convert';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/publish_library_use_case.dart'
    show PublishManifestGateway;
import 'package:pitaka/features/publish/application/site/move_site_operations.dart';
import 'package:pitaka/features/publish/application/site/move_site_result.dart';
import 'package:pitaka/features/publish/application/site/move_site_use_case.dart';
import 'package:pitaka/features/publish/application/site/publish_host_state_repository.dart';
import 'package:pitaka/features/publish/domain/github_branch_name.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/pending_move.dart';
import 'package:pitaka/features/publish/domain/site/publish_host_state.dart';
import 'package:pitaka/features/publish/domain/site/publish_marker.dart';
import 'package:pitaka/features/publish/domain/site/published_site_verifier.dart';

/// Fixed 40-hex GitHub head used by move tests.
const moveGitHubHead = '0123456789abcdef0123456789abcdef01234567';

/// Fixed Cloudflare live publish id used by move tests.
const moveCloudflarePublishId = '00112233445566778899aabbccddeeff';

/// A different, valid retired marker id.
const moveRetiredPublishId = 'ffeeddccbbaa99887766554433221100';

/// The synthetic GitHub endpoint.
final GitHubPublishTarget moveGitHubTarget = GitHubPublishTarget.create(
  'me/library',
)!;

/// The synthetic Cloudflare endpoint.
final CloudflarePublishTarget moveCloudflareTarget =
    CloudflarePublishTarget.create(
      accountId: '0123456789abcdef0123456789abcdef',
      workerName: 'pitak-library',
      accountSubdomain: 'library',
    )!;

/// A valid source anchor for [source], optionally at another head/id.
MoveSourceAnchor moveAnchor(PublishTarget source, {String? value}) {
  final owned = source is GitHubPublishTarget
      ? const ['index.html', 'books.json', 'library.json']
      : const ['index.html', 'books.json'];
  return MoveSourceAnchor.tryCreate(
    source: source,
    value:
        value ??
        (source is GitHubPublishTarget
            ? moveGitHubHead
            : moveCloudflarePublishId),
    branch: source is GitHubPublishTarget
        ? GitHubBranchName.tryParse('main')
        : null,
    ownedPaths: owned,
  )!;
}

/// Builds a valid pending move for [oldTarget] → [newTarget].
PendingMove movePending({
  PublishTarget? oldTarget,
  PublishTarget? newTarget,
  MoveSourceAnchor? anchor,
  List<int>? indexHtml,
  String libraryName = 'My Library',
  int movedPageSchema = 1,
  PublishMarker? marker,
}) {
  final from = oldTarget ?? moveGitHubTarget;
  final to =
      newTarget ??
      (from is GitHubPublishTarget ? moveCloudflareTarget : moveGitHubTarget);
  final page = indexHtml ?? utf8.encode('<html>moved</html>');
  return PendingMove.tryCreate(
    oldTarget: from,
    newTarget: to,
    sourceAnchor: anchor ?? moveAnchor(from),
    indexHtml: page,
    notFoundHtml: page,
    libraryName: libraryName,
    movedPageSchema: movedPageSchema,
    retirementMarker:
        marker ??
        (from is CloudflarePublishTarget
            ? const PublishMarker(
                publishId: moveRetiredPublishId,
                publishedAt: 1700000000000,
                state: PublishMarkerState.retired,
              )
            : null),
  )!;
}

/// A confirmation matching [oldTarget] → [newTarget].
MoveSiteConfirmation moveConfirmation({
  PublishTarget? oldTarget,
  PublishTarget? newTarget,
  MoveSourceAnchor? anchor,
  String digest = 'digest-1',
  int catalogueItemCount = 1,
  int posterCount = 0,
}) {
  final from = oldTarget ?? moveGitHubTarget;
  return MoveSiteConfirmation(
    oldTarget: from,
    newTarget: newTarget ?? moveCloudflareTarget,
    sourceAnchor: anchor ?? moveAnchor(from),
    digest: digest,
    catalogueItemCount: catalogueItemCount,
    posterCount: posterCount,
    availabilityOmitted: false,
  );
}

/// A manifest gateway held entirely in memory.
final class MemoryManifest implements PublishManifestGateway {
  /// Creates a gateway over [value].
  MemoryManifest([this.value = PublishManifest.empty]);

  /// Current record.
  PublishManifest value;

  /// Number of saves.
  int saves = 0;

  @override
  PublishManifest load() => value;

  @override
  Either<Failure, Unit> save(PublishManifest manifest) {
    value = manifest;
    saves++;
    return right(unit);
  }
}

/// A journal store whose Nth save can fail, for crash-boundary tests.
final class ScriptedHostStore implements PublishHostStateStore {
  /// Creates a store, optionally with [stored].
  ScriptedHostStore([this.stored]);

  /// Current journal.
  PublishHostState? stored;

  /// Number of save attempts.
  int saves = 0;

  /// 1-based save number that returns a failure; -1 disables.
  int failSaveAt = -1;

  /// When true, reads return a typed directory failure.
  bool failLoad = false;

  @override
  Either<Failure, PublishHostState?> load() => failLoad
      ? left(const StorageFailure('synthetic host read failure'))
      : right(stored);

  @override
  Future<Either<Failure, Unit>> save(PublishHostState state) async {
    saves++;
    if (saves == failSaveAt) {
      return left(const StorageFailure('synthetic host save failure'));
    }
    stored = state;
    return right(unit);
  }

  @override
  Future<Either<Failure, Unit>> clearUnreadable() async {
    if (load() is Right) {
      return left(const ValidationFailure('synthetic readable record'));
    }
    failLoad = false;
    stored = null;
    return right(unit);
  }
}

final class _NoManifest implements PublishManifestGateway {
  const _NoManifest();

  @override
  PublishManifest load() => PublishManifest.empty;

  @override
  Either<Failure, Unit> save(PublishManifest manifest) => right(unit);
}

final class _NoVerifier implements PublishedSiteVerifier {
  const _NoVerifier();

  @override
  Future<List<int>?> read({
    required String siteUrl,
    required String path,
    required int maxBytes,
    String? cacheBuster,
  }) async => null;
}

/// A real host-state repository over [store] with inert legacy inputs.
PublishHostStateRepository moveHostRepository(ScriptedHostStore store) =>
    PublishHostStateRepository(
      store: store,
      manifest: const _NoManifest(),
      verifier: const _NoVerifier(),
    );

/// A resolver whose result tests can change.
final class FakeMoveTargets implements MoveTargetResolver {
  /// Creates a resolver for one direction.
  FakeMoveTargets({required this.oldTarget, required this.newTarget});

  /// Current source.
  PublishTarget oldTarget;

  /// Current destination.
  PublishTarget newTarget;

  /// When set, every call returns this failure.
  Failure? failure;

  /// Number of resolutions.
  int calls = 0;

  @override
  Future<Either<Failure, MoveTargets>> call() async {
    calls++;
    final blocked = failure;
    if (blocked != null) return left(blocked);
    return right(MoveTargets(oldTarget: oldTarget, newTarget: newTarget));
  }
}

/// A scriptable source host with call counters.
final class FakeMoveSource implements MoveSourceOperations {
  /// Creates a source with an optional default [anchor].
  FakeMoveSource({this.anchor});

  /// Default anchor returned when [anchorResults] is empty.
  MoveSourceAnchor? anchor;

  /// When set, the default read returns this failure.
  Failure? anchorFailure;

  /// One-shot results consumed before [anchor]/[anchorFailure].
  final List<Either<Failure, MoveSourceAnchor>> anchorResults = [];

  /// When set, retirement returns this failure.
  Failure? retireFailure;

  /// Successful retirement outcome.
  SiteRetirementOutcome retirementOutcome = const SiteRetirementOutcome();

  /// What the Skip check reports.
  SourceSkipCheck skipCheckResult = const SourceAbsent();

  /// Whether the old site already shows the recorded moved page.
  bool retirementObservedValue = false;

  /// Counters for exact-boundary assertions.
  int readAnchorCalls = 0;
  int retireCalls = 0;
  int skipCalls = 0;
  int retirementObservedCalls = 0;

  @override
  Future<Either<Failure, MoveSourceAnchor>> readAnchor(
    PublishTarget oldTarget,
  ) async {
    readAnchorCalls++;
    if (anchorResults.isNotEmpty) return anchorResults.removeAt(0);
    final failure = anchorFailure;
    if (failure != null) return left(failure);
    return right(anchor!);
  }

  @override
  Future<Either<Failure, SiteRetirementOutcome>> retire(
    PendingMove pending,
  ) async {
    retireCalls++;
    final failure = retireFailure;
    if (failure != null) return left(failure);
    return right(retirementOutcome);
  }

  @override
  Future<SourceSkipCheck> skipCheck(PendingMove pending) async {
    skipCalls++;
    return skipCheckResult;
  }

  @override
  Future<bool> retirementObserved(PendingMove pending) async {
    retirementObservedCalls++;
    return retirementObservedValue;
  }
}

/// A scriptable destination host with call counters.
final class FakeMoveDestination implements MoveDestinationPublisher {
  /// Write-free preparation failure.
  Failure? prepareFailure;

  /// Exact preparation outcome; defaults to [moveConfirmation].
  MoveSiteConfirmation? prepareConfirmation;

  /// Fixed publish outcome.
  MoveDestinationResult? publishResult;

  /// Optional publish behavior with access to the recheck callback.
  MoveDestinationResult Function(
    MoveSiteConfirmation confirmation,
    Future<bool> Function() beforeWrite,
  )?
  onPublish;

  /// Counters and the last reviewed confirmation.
  int prepareCalls = 0;
  int publishCalls = 0;
  MoveSiteConfirmation? lastConfirmation;

  @override
  Future<Either<Failure, MoveSiteConfirmation>> prepare({
    required PublishTarget oldTarget,
    required PublishTarget newTarget,
    required MoveSourceAnchor sourceAnchor,
  }) async {
    prepareCalls++;
    final failure = prepareFailure;
    if (failure != null) return left(failure);
    return right(
      prepareConfirmation ??
          moveConfirmation(
            oldTarget: oldTarget,
            newTarget: newTarget,
            anchor: sourceAnchor,
          ),
    );
  }

  @override
  Future<MoveDestinationResult> publish({
    required MoveSiteConfirmation confirmation,
    required Future<bool> Function() beforeWrite,
  }) async {
    publishCalls++;
    lastConfirmation = confirmation;
    final callback = onPublish;
    if (callback != null) return callback(confirmation, beforeWrite);
    return publishResult ?? const MoveDestinationPublished();
  }
}

/// The full outer state machine over fakes for one direction.
final class MoveHarness {
  /// Creates a harness with a consistent live journal for [oldTarget].
  MoveHarness({
    PublishTarget? oldTarget,
    PublishTarget? newTarget,
    this.withJournal = true,
    MoveLibraryNameReader? readLibraryName,
  }) : oldTarget = oldTarget ?? moveGitHubTarget,
       newTarget = newTarget ?? moveCloudflareTarget,
       // M9/M8 need a scriptable settings read; the default keeps every
       // existing test on the same name.
       readLibraryName =
           readLibraryName ??
           (() async => right<Failure, String>('My Library')) {
    targets = FakeMoveTargets(
      oldTarget: this.oldTarget,
      newTarget: this.newTarget,
    );
    store = ScriptedHostStore(
      withJournal
          ? PublishHostState(
              activeHost: this.oldTarget.host,
              verifiedTarget: this.oldTarget,
            )
          : null,
    );
    hostState = moveHostRepository(store);
    gitHubSource = FakeMoveSource(
      anchor: this.oldTarget is GitHubPublishTarget
          ? moveAnchor(this.oldTarget)
          : moveAnchor(moveGitHubTarget),
    );
    cloudflareSource = FakeMoveSource(
      anchor: this.oldTarget is CloudflarePublishTarget
          ? moveAnchor(this.oldTarget)
          : moveAnchor(moveCloudflareTarget),
    );
    gitHubDestination = FakeMoveDestination();
    cloudflareDestination = FakeMoveDestination();
    useCase = MoveSiteUseCase(
      targets: targets,
      hostState: hostState,
      gitHubSource: gitHubSource,
      cloudflareSource: cloudflareSource,
      gitHubDestination: gitHubDestination,
      cloudflareDestination: cloudflareDestination,
      buildMovedHtml: ({required libraryName, required newTarget}) async =>
          utf8.encode('<html>$libraryName moved</html>'),
      validateMovedHtml: (pending) async => validateMoved,
      readLibraryName: this.readLibraryName,
      clock: () => 1700000000000,
      publishId: () => moveRetiredPublishId,
    );
  }

  /// Whether the harness starts with a consistent live journal.
  final bool withJournal;

  /// Reads the moved-page library name; scriptable since Phase 0.7.
  final MoveLibraryNameReader readLibraryName;

  /// Direction's source.
  final PublishTarget oldTarget;

  /// Direction's destination.
  final PublishTarget newTarget;

  /// Target resolver.
  late final FakeMoveTargets targets;

  /// Journal store.
  late final ScriptedHostStore store;

  /// Real journal rules over [store].
  late final PublishHostStateRepository hostState;

  /// GitHub source operations.
  late final FakeMoveSource gitHubSource;

  /// Cloudflare source operations.
  late final FakeMoveSource cloudflareSource;

  /// GitHub destination publisher.
  late final FakeMoveDestination gitHubDestination;

  /// Cloudflare destination publisher.
  late final FakeMoveDestination cloudflareDestination;

  /// The state machine under test.
  late final MoveSiteUseCase useCase;

  /// Whether persisted moved HTML still validates.
  bool validateMoved = true;

  /// The source fake for this direction.
  FakeMoveSource get source =>
      oldTarget is GitHubPublishTarget ? gitHubSource : cloudflareSource;

  /// The destination fake for this direction.
  FakeMoveDestination get destination => newTarget is GitHubPublishTarget
      ? gitHubDestination
      : cloudflareDestination;

  /// Seeds a destination-verified pending move in the journal.
  PendingMove seedPending({MoveSourceAnchor? anchor}) {
    final pending = movePending(
      oldTarget: oldTarget,
      newTarget: newTarget,
      anchor: anchor ?? source.anchor,
    );
    store.stored = PublishHostState(
      activeHost: oldTarget.host,
      verifiedTarget: oldTarget,
    ).beginMove(pending);
    return pending;
  }
}
