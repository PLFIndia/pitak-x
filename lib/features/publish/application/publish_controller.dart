/// Publish controller (application layer, AGENTS.md §4, #32).
///
/// Assembles [PublishLibraryUseCase] from live providers and runs a publish on
/// demand, exposing a simple [AsyncValue] of the [PublishResult].
///
/// This controller is ALSO the app's implementation of [PublishReads]
/// (Cloudflare plan R2). Why here (beginner note): the snapshot builder is
/// host-neutral and pure, so it cannot reach Riverpod itself. The controller
/// owns the providers, so it turns "the library, the magazines, the events
/// file, the network descriptor and the loan counts" into typed reads. The
/// domain stays free of Riverpod, and a failed read becomes a typed failure
/// that aborts the publish before anything is written.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/platform/app_log.dart';
import 'package:pitaka/features/events/domain/entities/event_poster.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/network/application/build_own_descriptor.dart';
import 'package:pitaka/features/network/domain/entities/library_descriptor.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/network/domain/library_descriptor_codec.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_connection_controller.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_publish_outcomes.dart';
import 'package:pitaka/features/publish/application/publish_library_use_case.dart';
import 'package:pitaka/features/publish/application/site/publish_host_state_repository.dart';
import 'package:pitaka/features/publish/application/site/publish_snapshot_builder.dart';
import 'package:pitaka/features/publish/domain/publish_contact_links.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/publish_mode.dart';
import 'package:pitaka/features/publish/domain/site/publish_snapshot.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'publish_controller.g.dart';

/// Runs a publish and exposes its [PublishResult]; idle until [publish] runs.
@riverpod
class PublishController extends _$PublishController implements PublishReads {
  @override
  FutureOr<PublishResult?> build() => null;

  /// Runs a publish end-to-end. Returns the result and also stores it in state.
  ///
  /// [mode] is [PublishMode.complete] for a move or a whole-site replacement:
  /// a missing cover/poster then FAILS instead of being dropped. Ordinary
  /// publishes stay incremental (they may reuse already-published files).
  Future<PublishResult> publish({
    PublishMode mode = PublishMode.incremental,
    PublishReplacementSummary? confirmation,
    bool verificationOnly = false,
  }) async {
    // keepAlive for the duration of the run: this provider is autoDispose
    // and the page only read()s it, so a long publish (the post-commit
    // read-back waits up to 60 s) previously let Riverpod dispose+rebuild
    // the element mid-flight — the final `state =` then hit the rebuilt
    // element's already-completed future ("Bad state: Future already
    // completed"). The link pins the element until the run finishes.
    final link = ref.keepAlive();
    state = const AsyncLoading();
    try {
      // R11: the outermost publish command shares one app-wide queue with
      // events, setup, disconnect, and (later) moves/retirement. Inner use-case
      // steps document that the queue is already held and never enqueue again.
      final result = await ref
          .read(publishOperationQueueProvider)
          .enqueue(
            () => _run(
              mode,
              confirmation: confirmation,
              verificationOnly: verificationOnly,
            ),
          );
      state = AsyncData(result);
      return result;
    } on Object catch (e, st) {
      // `on Object` on purpose: a `Failure` is not an `Exception`, so
      // `on Exception` let it escape and froze the card's spinner for the
      // session (fix-plan M8). The type is logged, never the message.
      appLog('publish failed with: ${e.runtimeType}');
      state = AsyncError(e, st);
      rethrow;
    } finally {
      link.close();
    }
  }

  Future<PublishResult> _run(
    PublishMode mode, {
    PublishReplacementSummary? confirmation,
    bool verificationOnly = false,
  }) async {
    // The journal chooses the host freshly inside this queue. Only that host's
    // credentials supply the exact sealed target; there is no fallback.
    final resolver = await ref.read(activePublishTargetResolverProvider.future);
    final resolved = await resolver.call();
    final targetFailure = resolved.swap().toNullable();
    if (targetFailure != null) {
      return CloudflarePublishOutcomes.failure(targetFailure);
    }
    final target = resolved.toNullable()!;
    if (target is GitHubPublishTarget &&
        (confirmation != null || verificationOnly)) {
      return const PublishFailure(
        'The publishing host changed before this command could continue.',
      );
    }
    return switch (target) {
      final GitHubPublishTarget gitHub => _runGitHub(gitHub, mode),
      final CloudflarePublishTarget cloudflare => _runCloudflare(
        cloudflare,
        mode: mode,
        confirmation: confirmation,
        verificationOnly: verificationOnly,
      ),
    };
  }

  Future<PublishResult> _runGitHub(
    GitHubPublishTarget target,
    PublishMode mode,
  ) async {
    // Side-effecting ports (bounded HTTP fetch, rootBundle template load)
    // arrive via DI as domain function types — this controller never touches
    // infrastructure directly (§3.1).
    final api = ref.read(gitHubApiProvider);
    final credentials = ref.read(publishCredentialStoreProvider);
    final manifest = await ref.read(publishManifestStoreProvider.future);
    // The ONE section builder (R3): the controller supplies the reads, the
    // use case supplies the target + the previous publication, so the section
    // is built exactly once against the manifest that will also be merged.
    final builder = await ref.read(publishSnapshotBuilderProvider.future);
    // Bounded, origin-bound read-back (R16) — used to prove the live site
    // serves exactly what was published.
    final verifier = ref.read(publishedSiteVerifierProvider);

    final useCase = PublishLibraryUseCase(
      api: api,
      credentials: credentials,
      manifest: manifest,
      snapshotBuilder: builder,
      reads: this,
      // Lazy: the journal is only opened once a read-back proves the site is
      // live (R33), never before the strict reads.
      hostState: LazyPublishHostStateRecorder(
        () => ref.read(publishHostStateRepositoryProvider.future),
      ),
      verifier: verifier,
    );

    final result = await useCase.call(target: target, mode: mode);
    if (result is PublishSuccess) ref.invalidate(publishedSiteUrlProvider);
    return result;
  }

  Future<PublishResult> _runCloudflare(
    CloudflarePublishTarget target, {
    required PublishMode mode,
    PublishReplacementSummary? confirmation,
    bool verificationOnly = false,
  }) async {
    if ((mode == PublishMode.complete && confirmation == null) ||
        (verificationOnly && confirmation != null)) {
      return const PublishFailure(
        'Review the Cloudflare replacement again before continuing.',
      );
    }
    final factory = await ref.read(publishToCloudflareUseCaseProvider.future);
    final result = await factory(this).call(
      target: target,
      section: PublishRequestedSection.catalogue,
      confirmation: confirmation,
      verificationOnly: verificationOnly,
    );
    if (result is PublishSuccess) {
      ref.invalidate(publishedSiteUrlProvider);
      // A rebuild would cancel a setup the user is in the middle of, so the
      // connection controller is refreshed in place (fix-plan M11).
      await ref
          .read(cloudflareConnectionControllerProvider.notifier)
          .refreshStatus();
    }
    return result;
  }

  // --- PublishReads -------------------------------------------------------
  // Each read returns a TYPED failure carrying an already-safe sentence. A
  // read that failed is never turned into empty content (R2): the snapshot
  // builder aborts the publish on any left, before a single byte is written.

  /// The ONE safe message for an unreadable library input: read diagnostics
  /// can carry private database detail and never reach the UI (AGENTS §5).
  Failure _readFailed(Failure _) =>
      const PublishReadFailure(PublishSnapshotBuilder.readFailedMessage);

  @override
  Future<Either<Failure, List<CatalogueItem>>> catalogueItems() async {
    final repo = await ref.read(catalogueItemRepositoryProvider.future);
    final result = await repo.getAllForInterchange();
    return result.mapLeft(_readFailed);
  }

  @override
  Future<Either<Failure, List<Periodical>>> periodicals() async {
    // W3: the series ride along in books.json. A failed read is not "no
    // magazines" — refuse rather than publish issues stripped of their series
    // (the same fail-closed rule as the catalogue read, and the rule S18 gave
    // the export: no partial snapshot).
    final repo = await ref.read(periodicalRepositoryProvider.future);
    final result = await repo.listAll();
    return result
        .mapLeft(_readFailed)
        .map((summaries) => [for (final s in summaries) s.periodical]);
  }

  @override
  Future<Either<Failure, EventsContent>> events() async {
    // STRICT publish read (R2): a corrupt events.json is a failure, never
    // "no events". The tolerant `loadForEditor` path belongs to the editor.
    final repo = await ref.read(eventsRepositoryProvider.future);
    return repo.loadStrict();
  }

  @override
  Future<Either<Failure, List<int>?>> libraryJson(String siteUrl) async {
    // library.json (docs/ARCHITECTURE.md §5.1): the network descriptor. Its
    // identity is read through its single owner (N07 — `SettingsController`
    // implements `LibraryNamespace`); a failed mint/read REFUSES the whole
    // publish, because a descriptor without an honest fingerprint would be
    // unmatchable by every hub (fail closed).
    final identity = await ref
        .read(settingsControllerProvider.notifier)
        .current();
    final own = identity.toNullable();
    if (own == null) {
      return left(const PublishReadFailure('Library identity unavailable'));
    }

    // Typed read (M8): a settings failure is a `Left`, never a thrown
    // non-Exception. The last good value is used after any write failure.
    final loadedSettings = await ref
        .read(settingsControllerProvider.notifier)
        .loaded();
    final settings = loadedSettings.toNullable();
    if (settings == null) {
      return left(
        const PublishReadFailure(
          PublishSnapshotBuilder.settingsUnavailableMessage,
        ),
      );
    }
    // [siteUrl] comes from the operation's sealed target (C3): it is never
    // re-derived from "the current repo", so a move cannot publish a
    // descriptor pointing at the old host.

    // members = the rows I added by card scan (§5.5): a hub publishes its
    // member list inside its own descriptor. A member row without a
    // fingerprint cannot be listed (there is nothing to match on) — it
    // stays out until a scan/fetch supplies one. memberOf = the hubs whose
    // membership the user CONFIRMED (§5.5/§5.6-4) — pending or declined
    // rows are never published (a membership is public only by explicit
    // choice). The codec sorts both lists by siteUrl.
    //
    // The repository hand-out awaits the one-time legacy-bookmarks
    // migration; if THAT failed, the network table cannot be trusted and
    // a descriptor built over it would publish an empty member list —
    // detaching every member while the UI says "Published!". Refuse with
    // the real reason instead of the generic exception message (M14).
    final List<NetworkLibrary> memberRows;
    try {
      final network = await ref.read(networkRepositoryProvider.future);
      memberRows = await network.loadAll();
    } on LegacyBookmarksMigrationException {
      return left(
        const PublishReadFailure(
          'Could not read your saved libraries. Nothing was published. '
          'Please try again.',
        ),
      );
    }

    final built = BuildOwnDescriptor.build(
      libraryId: own.id,
      libraryName: settings.libraryName,
      siteUrl: siteUrl,
      sharing: settings.publishLocationSharing,
      gps: settings.publishContactGps,
      updatedAt: ref.read(clockProvider)(),
      members: [
        for (final row in memberRows)
          if (row.isMember && row.fingerprint != null)
            MemberEntry(
              fingerprint: row.fingerprint!,
              siteUrl: row.siteUrl,
              name: row.name.isEmpty ? null : row.name,
            ),
      ],
      memberOf: [
        for (final row in memberRows)
          if (row.membership == MembershipState.confirmed) row.siteUrl,
      ],
    );
    // An unbuildable descriptor REFUSES the publish (§5.5, fail closed).
    // The only ways build() fails are an identity that is not a valid
    // library ID (e.g. a malformed stored value — getOrCreateLibraryId
    // returns whatever is on disk) or an unusable site URL. Folding that
    // to "write none" would silently DELETE the published library.json
    // (the use case treats null as opt-out) while the UI says
    // "Published!" — detaching this library from every hub (review M1).
    final descriptor = built.toNullable();
    if (descriptor == null) {
      return left(const PublishReadFailure('Library identity unavailable'));
    }

    // Stable bytes for a stable descriptor: a fresh updatedAt on every
    // publish made library.json differ every time, so the unchanged-sha
    // skip never applied to it (review Lows). When the LIVE descriptor has
    // identical content, reuse its timestamp — the encoded bytes then match
    // the manifest sha and the upload is skipped. A stale/absent/undecodable
    // live copy degrades to "upload anyway" — the safe direction (the
    // manifest's shas come from GitHub's tree, not this CDN read).
    // Read through the SAME bounded, origin-bound verifier as the publish
    // read-back (R16): the descriptor is public, capped at its own wire
    // limit, and never fetched through a redirect.
    final verifier = ref.read(publishedSiteVerifierProvider);
    final liveBytes = await verifier.read(
      siteUrl: descriptor.siteUrl,
      path: PublishLibraryUseCase.libraryJsonPath,
      maxBytes: 64 * 1024,
      cacheBuster: '${ref.read(clockProvider)()}',
    );
    final live = liveBytes == null
        ? null
        : LibraryDescriptorCodec.decode(liveBytes).toNullable();
    final effective = live != null && live.samePublishedContentAs(descriptor)
        ? descriptor.withUpdatedAt(live.updatedAt)
        : descriptor;
    // Fail closed (review L1): a descriptor over the wire caps would be
    // REFUSED IN FULL by every peer that reads it — the whole library
    // would silently disappear from the network behind a "Published!".
    // Refuse the publish instead; nothing is uploaded, nothing deleted.
    final encoded = LibraryDescriptorCodec.encodeChecked(
      effective,
    ).toNullable();
    if (encoded == null) {
      return left(
        const PublishReadFailure(
          'Your published member list is too large. Remove some members in '
          'the Library network list, then publish again.',
        ),
      );
    }
    return right(encoded);
  }

  @override
  Future<Either<Failure, PublishPageSettings>> pageSettings() async {
    final loadedSettings = await ref
        .read(settingsControllerProvider.notifier)
        .loaded();
    return loadedSettings.map(
      (settings) => PublishPageSettings(
        libraryName: settings.libraryName,
        contact: PublishContact(
          address: settings.publishContactAddress,
          gps: settings.publishContactGps,
          email: settings.publishContactEmail,
          phone: settings.publishContactPhone,
        ),
        sharing: settings.publishLocationSharing,
      ),
    );
  }

  @override
  Future<Either<Failure, Map<int, int>?>> activeLoanCounts() async {
    // Null means the vault is locked: availability is then OMITTED from the
    // payload (never published as "everything available"). Reading this
    // provider cannot fail.
    return right(ref.read(activeLoanCountsProvider));
  }
}
