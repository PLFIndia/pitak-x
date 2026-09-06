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
import 'package:pitaka/features/publish/application/publish_library_use_case.dart';
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
      ),
    );

    return useCase.call(
      books: books,
      activeLoanCounts: counts,
      encodeBooksJson: (e) =>
          utf8.encode(const JsonEncoder.withIndent('  ').convert(e.toJson())),
      // No onPhase wiring: the page shows the AsyncValue only, and nothing
      // reads per-phase progress (REVIEW_FINDINGS_2 — the old `_phase` field
      // was write-only dead weight).
    );
  }
}
