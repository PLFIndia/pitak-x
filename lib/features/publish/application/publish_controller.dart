/// Publish controller (application layer, AGENTS.md §4, #32).
///
/// Assembles the [PublishLibraryUseCase] from live providers and runs a publish
/// on demand, exposing a simple [AsyncValue] of the [PublishResult]. Gathers
/// the inputs the pure use case needs: all books, the vault-gated active-loan
/// counts (null when locked → availability omitted), a JSON encoder, the local/
/// remote cover readers, and the viewer-HTML builder.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/images/image_downscaler.dart';
import 'package:pitaka/features/import_export/domain/cover_paths.dart';
import 'package:pitaka/features/publish/application/publish_library_use_case.dart';
import 'package:pitaka/features/publish/domain/publish_contact_links.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'publish_controller.g.dart';

/// Runs a publish and exposes its [PublishResult]; idle until [publish] runs.
@riverpod
class PublishController extends _$PublishController {
  PublishPhase? _phase;

  @override
  FutureOr<PublishResult?> build() => null;

  /// The latest coarse phase emitted during a run (for progress UI).
  PublishPhase? get phase => _phase;

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
    final api = ref.read(gitHubApiProvider);
    final credentials = ref.read(publishCredentialStoreProvider);
    final manifest = await ref.read(publishManifestStoreProvider.future);
    final coverIds = ref.read(publishCoverIdsProvider);
    final dir = await ref.read(appDocsDirProvider.future);
    final coversDir = p.join(dir.path, CoverPaths.coversDir);

    final settings = await ref.read(settingsControllerProvider.future);

    final books = await ref
        .read(bookRepositoryProvider.future)
        .then((repo) async => (await repo.getAll()).getOrElse((_) => const []));
    final counts = ref.read(activeLoanCountsProvider);

    // Side-effecting ports (bounded HTTP fetch, rootBundle template load)
    // arrive via DI as domain function types — this controller never touches
    // infrastructure directly (§3.1).
    final fetchRemoteCover = ref.read(remoteCoverFetcherProvider);
    final buildViewerHtml = ref.read(viewerHtmlFactoryProvider);
    final fetchPublishedFile = ref.read(publishedFileFetcherProvider);
    final useCase = PublishLibraryUseCase(
      api: api,
      credentials: credentials,
      manifest: manifest,
      coverIds: coverIds,
      fetchPublishedFile: fetchPublishedFile,
      readLocalCover: (src) => _readLocalCover(coversDir, src),
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
      onPhase: (ph) => _phase = ph,
    );
  }

  Future<List<int>?> _readLocalCover(String coversDir, String src) async {
    final leaf = CoverPaths.leafOf(src);
    if (leaf == null) return null;
    final file = File(p.join(coversDir, leaf));
    if (!file.existsSync()) return null;
    try {
      // Downscale before publishing (400x600 q80) so the git push stays small
      // even if the stored cover is larger (closes the Q-P1 follow-up).
      return ImageDownscaler.downscaleJpeg(await file.readAsBytes()) ??
          await file.readAsBytes();
    } on Exception {
      return null;
    }
  }
}
