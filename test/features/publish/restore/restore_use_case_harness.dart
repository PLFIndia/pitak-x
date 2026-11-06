import 'dart:convert';
import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/import_export/application/import_library_use_case.dart';
import 'package:pitaka/features/import_export/infrastructure/pitaka_json_importer.dart';
import 'package:pitaka/features/network/domain/entities/published_catalogue.dart';
import 'package:pitaka/features/network/domain/published_cover_fetcher.dart';
import 'package:pitaka/features/network/domain/published_cover_resolver.dart';
import 'package:pitaka/features/network/domain/published_file_fetch.dart';
import 'package:pitaka/features/publish/application/publish_library_use_case.dart'
    show PublishManifestGateway;
import 'package:pitaka/features/publish/application/restore/published_cover_restorer.dart';
import 'package:pitaka/features/publish/application/restore/recover_published_identity.dart';
import 'package:pitaka/features/publish/application/restore/restore_from_published_site_use_case.dart';
import 'package:pitaka/features/publish/application/site/active_publish_target.dart';
import 'package:pitaka/features/publish/application/site/publish_host_state_repository.dart';
import 'package:pitaka/features/publish/domain/publish_credential_store.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/restore/restore_identity_journal.dart';
import 'package:pitaka/features/publish/domain/site/published_site_verifier.dart';

import '../../../support/published_file_fakes.dart';
import '../../import_export/bundle_test_fixture.dart';
import '../support/cloudflare_fakes.dart';

final class FakeRestoreJournal implements RestoreIdentityJournalStore {
  RestoreIdentityJournal? value;
  Failure? writeFailure;

  @override
  Future<Either<Failure, RestoreIdentityJournal?>> load() async => right(value);

  @override
  Future<Either<Failure, Unit>> save(RestoreIdentityJournal journal) async {
    final failure = writeFailure;
    if (failure != null) return left(failure);
    value = journal;
    return right(unit);
  }

  @override
  Future<Either<Failure, Unit>> clear() async {
    value = null;
    return right(unit);
  }
}

final class FakeRestoreSiteReader implements PublishedSiteReadVerifier {
  PublishedSiteReadOutcome outcome = const PublishedSiteReadUnreadable();

  @override
  Future<PublishedSiteReadOutcome> readOutcome({
    required String siteUrl,
    required String path,
    required int maxBytes,
    String? cacheBuster,
  }) async => outcome;
}

final class _Credentials implements PublishCredentialStore {
  _Credentials(this.repo);
  final String repo;

  @override
  Future<String?> targetRepo() async => repo;
  @override
  Future<String?> token() async => 'token';
  @override
  Future<void> clearTargetRepo() async {}
  @override
  Future<void> clearToken() async {}
  @override
  Future<void> setTargetRepo(String target) async {}
  @override
  Future<void> setToken(String token) async {}
}

final class _Manifest implements PublishManifestGateway {
  @override
  PublishManifest load() => PublishManifest.empty;
  @override
  Either<Failure, Unit> save(PublishManifest manifest) => right(unit);
}

final class RestoreUseCaseHarness {
  RestoreUseCaseHarness() {
    resolver = ActivePublishTargetResolver(
      hostState: PublishHostStateRepository(
        store: FakePublishHostStateStore(),
        manifest: _Manifest(),
        verifier: FakePublishedSiteVerifier(),
      ),
      gitHubCredentials: _Credentials('me/lib'),
      cloudflareCredentials: InMemoryCloudflareCredentialStore(),
    );
    recover = RecoverPublishedIdentity(
      journal: journal,
      resolveTarget: resolver,
      items: fixture.books,
      periodicals: fixture.periodicals,
      writeFingerprint: writeFingerprint,
    );
    useCase = RestoreFromPublishedSiteUseCase(
      items: fixture.books,
      periodicals: fixture.periodicals,
      importer: ImportLibraryUseCase(
        jsonParser: const PitakaJsonImporter(),
        bookRepo: fixture.books,
        wishlistRepo: fixture.wishlist,
        periodicalRepo: fixture.periodicals,
      ),
      coverFiles: fixture.files,
      coordinator: fixture.coordinator,
      fetchCatalogue: _fetchCatalogue,
      siteReader: reader,
      coverRestorer: PublishedCoverRestorer(
        fetch: _fetchCover,
        clock: () => now,
      ),
      journal: journal,
      recoverIdentity: recover,
      clock: () => now,
    );
    reader.outcome = PublishedSiteReadBody(
      utf8.encode(
        jsonEncode({
          'schemaVersion': 1,
          'fingerprint': fingerprint,
          'name': 'My Library',
          'siteUrl': siteUrl,
          'updatedAt': 1,
        }),
      ),
    );
  }

  final fixture = BundleTestFixture();
  final journal = FakeRestoreJournal();
  final reader = FakeRestoreSiteReader();
  final siteUrl = GitHubPublishTarget.create('me/lib')!.siteUrl;
  final String fingerprint = 'a' * 64;
  final coverResults = <String, PublishedCoverDownload>{};

  late final ActivePublishTargetResolver resolver;
  late final RecoverPublishedIdentity recover;
  late final RestoreFromPublishedSiteUseCase useCase;
  PublishedCatalogue catalogue = PublishedCatalogue(
    declaredSchemaVersion: 1,
    items: const [
      PublishedCatalogueItem(
        sourceIndex: 0,
        title: 'Restored book',
        kind: PublishedItemKind.book,
        author: 'Author',
        isbn: '123',
        coverUrl: 'covers/source.png',
      ),
    ],
    periodicals: const [],
  );
  Failure? catalogueFailure;
  Failure? fingerprintFailure;
  String? writtenFingerprint;
  int fingerprintWrites = 0;
  int catalogueCalls = 0;
  int coverCalls = 0;
  int now = 100;
  Future<void> Function(Future<void>? abortTrigger)? onCover;

  Future<Either<Failure, Unit>> writeFingerprint(String? value) async {
    fingerprintWrites++;
    final failure = fingerprintFailure;
    if (failure != null) return left(failure);
    writtenFingerprint = value;
    return right(unit);
  }

  Future<PublishedFileFetch<PublishedCatalogue>> _fetchCatalogue(
    String url, {
    String? validator,
    Future<void>? abortTrigger,
  }) async {
    catalogueCalls++;
    final failure = catalogueFailure;
    if (failure != null) return failedFetch(failure);
    return fetchedValue(catalogue);
  }

  Future<PublishedCoverDownload> _fetchCover(
    PublishedCoverRequest request, {
    Future<void>? abortTrigger,
  }) async {
    coverCalls++;
    await onCover?.call(abortTrigger);
    final leaf = request.uri.pathSegments.last;
    return coverResults[leaf] ??
        PublishedCoverDownload(
          bytes: Uint8List.fromList([1, 2, 3]),
          sourceByteCount: 3,
        );
  }

  Future<void> dispose() => fixture.dispose();
}
