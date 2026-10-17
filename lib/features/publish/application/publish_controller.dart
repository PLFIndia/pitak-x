/// Publish controller (application layer, AGENTS.md §4, #32).
///
/// Assembles the [PublishLibraryUseCase] from live providers and runs a publish
/// on demand, exposing a simple [AsyncValue] of the [PublishResult]. Gathers
/// the inputs the pure use case needs: all books, the vault-gated active-loan
/// counts (null when locked → availability omitted), a JSON encoder, the local/
/// remote cover readers, and the viewer-HTML builder.
library;

import 'dart:convert';

import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/network/application/build_own_descriptor.dart';
import 'package:pitaka/features/network/domain/entities/library_descriptor.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/network/domain/library_descriptor_codec.dart';
import 'package:pitaka/features/publish/application/publish_library_use_case.dart';
import 'package:pitaka/features/publish/domain/github_pages_url.dart';
import 'package:pitaka/features/publish/domain/publish_contact_links.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'publish_controller.g.dart';

/// Runs a publish and exposes its [PublishResult]; idle until [publish] runs.
@riverpod
class PublishController extends _$PublishController {
  @override
  FutureOr<PublishResult?> build() => null;

  /// Runs a publish end-to-end. Returns the result and also stores it in state.
  Future<PublishResult> publish() async {
    // keepAlive for the duration of the run: this provider is autoDispose
    // and the page only read()s it, so a long publish (the post-commit
    // read-back waits up to 60 s) previously let Riverpod dispose+rebuild
    // the element mid-flight — the final `state =` then hit the rebuilt
    // element's already-completed future ("Bad state: Future already
    // completed"). The link pins the element until the run finishes.
    final link = ref.keepAlive();
    state = const AsyncLoading();
    try {
      final result = await _run();
      state = AsyncData(result);
      return result;
    } on Exception catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    } finally {
      link.close();
    }
  }

  Future<PublishResult> _run() async {
    final repo = await ref.read(bookRepositoryProvider.future);
    final books = await repo.getAll();
    // A failed read is not an empty library: stop before preparing any publish.
    // Diagnostics can contain private database details; never show them.
    return books.match<Future<PublishResult>>(
      (_) async => const PublishFailure(
        'Could not read the library. Nothing was published. Please try again.',
      ),
      _publishBooks,
    );
  }

  Future<PublishResult> _publishBooks(List<Book> books) async {
    final api = ref.read(gitHubApiProvider);
    final credentials = ref.read(publishCredentialStoreProvider);
    final manifest = await ref.read(publishManifestStoreProvider.future);
    final coverIds = ref.read(publishCoverIdsProvider);

    final settings = await ref.read(settingsControllerProvider.future);

    final counts = ref.read(activeLoanCountsProvider);

    // Side-effecting ports (bounded HTTP fetch, rootBundle template load)
    // arrive via DI as domain function types — this controller never touches
    // infrastructure directly (§3.1).
    final fetchRemoteCover = ref.read(remoteCoverFetcherProvider);
    final buildViewerHtml = ref.read(viewerHtmlFactoryProvider);
    final fetchPublishedFile = ref.read(publishedFileFetcherProvider);
    // N14: local-cover file IO arrives via DI (infrastructure), keeping this
    // controller free of dart:io (§3.1).
    final readLocalCover = await ref.read(
      publishLocalCoverReaderProvider.future,
    );

    // library.json (libNetwork.md §5.5): the network descriptor rides in the
    // SAME commit as books.json. Identity is read through its single owner
    // (N07 — `SettingsController` implements `LibraryNamespace`); a failed
    // mint/read REFUSES the whole publish, because a descriptor without an
    // honest fingerprint would be unmatchable by every hub (fail closed).
    final identity = await ref
        .read(settingsControllerProvider.notifier)
        .current();
    final own = identity.toNullable();
    if (own == null) {
      return const PublishFailure('Library identity unavailable');
    }
    // The descriptor's siteUrl is the site we are about to publish to. With
    // no target repo chosen there is nothing to build — libraryJson stays
    // null and the use case's own repo check answers with its clearer
    // message before any file decision matters.
    final siteUrl = githubPagesUrlFor(await credentials.targetRepo());
    List<int>? libraryJson;
    if (siteUrl != null) {
      // members = the rows I added by card scan (§5.5): a hub publishes its
      // member list inside its own descriptor. A member row without a
      // fingerprint cannot be listed (there is nothing to match on) — it
      // stays out until a scan/fetch supplies one. memberOf = the hubs whose
      // membership the user CONFIRMED (§5.5/§5.6-4) — pending or declined
      // rows are never published (a membership is public only by explicit
      // choice). The codec sorts both lists by siteUrl.
      final network = await ref.read(networkRepositoryProvider.future);
      final memberRows = await network.loadAll();
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
      // An unbuildable descriptor degrades to "write none" (and remove any
      // stale published one) — the catalogue publish itself is still valid.
      libraryJson = built.match((_) => null, LibraryDescriptorCodec.encode);
    }

    final useCase = PublishLibraryUseCase(
      api: api,
      credentials: credentials,
      manifest: manifest,
      coverIds: coverIds,
      fetchPublishedFile: fetchPublishedFile,
      readLocalCover: readLocalCover,
      fetchRemoteCover: fetchRemoteCover,
      buildViewerHtml: () => buildViewerHtml(
        libraryName: settings.libraryName,
        contact: PublishContact(
          address: settings.publishContactAddress,
          gps: settings.publishContactGps,
          email: settings.publishContactEmail,
          phone: settings.publishContactPhone,
        ),
        // D7: one switch gates the index.html pin and the library.json
        // location alike.
        sharing: settings.publishLocationSharing,
      ),
    );

    return useCase.call(
      books: books,
      activeLoanCounts: counts,
      encodeBooksJson: (e) =>
          utf8.encode(const JsonEncoder.withIndent('  ').convert(e.toJson())),
      libraryJson: libraryJson,
      // No onPhase wiring: the page shows the AsyncValue only, and nothing
      // reads per-phase progress (REVIEW_FINDINGS_2 — the old `_phase` field
      // was write-only dead weight).
    );
  }
}
