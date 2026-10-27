import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/network/domain/repositories/network_repository.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/domain/value_objects/periodical_frequency.dart';
import 'package:pitaka/features/publish/application/publish_controller.dart';
import 'package:pitaka/features/publish/application/publish_library_use_case.dart';
import 'package:pitaka/features/publish/domain/git_blob_sha.dart';
import 'package:pitaka/features/publish/domain/github_api.dart';
import 'package:pitaka/features/publish/domain/github_models.dart';
import 'package:pitaka/features/publish/domain/publish_cover_ids.dart';
import 'package:pitaka/features/publish/domain/publish_credential_store.dart';
import 'package:pitaka/features/publish/domain/publish_export.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';
import 'package:pitaka/features/publish/domain/site/published_site_verifier.dart';

import '../../support/raw_catalogue_rows.dart';
import '../import_export/bundle_test_fixture.dart';
import '../library/replacement_harness.dart';

class _FakeCreds implements PublishCredentialReader {
  _FakeCreds({this.tok = 'TKN', this.repo = 'me/lib'});
  final String? tok;
  final String? repo;
  @override
  Future<String?> token() async => tok;
  @override
  Future<String?> targetRepo() async => repo;
}

class _MemManifest implements PublishManifestGateway {
  _MemManifest([this._m = PublishManifest.empty]);
  final PublishManifest _m;
  PublishManifest? saved;
  @override
  PublishManifest load() => _m;
  @override
  void save(PublishManifest m) => saved = m;
}

/// Fake read-back: answers by (siteUrl, path) and records every call so the
/// tests can assert the origin binding and the cache-buster.
class _FakeVerifier implements PublishedSiteVerifier {
  _FakeVerifier(this.answer);
  final Future<List<int>?> Function(String siteUrl, String path) answer;
  final List<(String, String, String?)> calls = [];

  @override
  Future<List<int>?> read({
    required String siteUrl,
    required String path,
    required int maxBytes,
    String? cacheBuster,
  }) {
    calls.add((siteUrl, path, cacheBuster));
    return answer(siteUrl, path);
  }
}

class _FixedSalt implements PublishCoverSaltStore {
  @override
  Future<List<int>> salt() async => ascii.encode('salt-1234567890');
}

/// Records the commit it received; returns a scripted result.
/// S5: implements only the git-data role the use case consumes.
class _CapturingApi implements GitHubGitDataApi {
  _CapturingApi({
    this.pages = const PagesSite(
      sourceBranch: 'main',
      sourcePath: '/',
      isWorkflowBuild: false,
    ),
    this.throwOnPagesSite = false,
  });
  final Map<String, String> headShas = const {};

  /// What `pagesSite()` answers (null = Pages off).
  final PagesSite? pages;
  final bool throwOnPagesSite;
  final PublishCommitResult? commitResult = null;
  List<DesiredFile>? committed;

  /// deletePaths the commit was asked to remove (M14 / docs/ARCHITECTURE.md §5.1).
  List<String> deleted = const [];

  /// Branch the commit was made to (N09: must be the Pages source branch).
  String? committedBranch;

  /// Branch the head tree was read from.
  String? headTreeBranch;

  @override
  Future<PagesSite?> pagesSite({
    required String owner,
    required String repo,
    required String token,
  }) async {
    if (throwOnPagesSite) throw const GitHubApiException('boom');
    return pages;
  }

  @override
  Future<Map<String, String>> headTreeShas({
    required String owner,
    required String repo,
    required String branch,
    required String token,
  }) async {
    headTreeBranch = branch;
    return headShas;
  }

  @override
  Future<PublishCommitResult> commitFiles({
    required String owner,
    required String repo,
    required String branch,
    required String token,
    required List<DesiredFile> files,
    required String commitMessage,
    List<String> deletePaths = const [],
  }) async {
    committed = files;
    committedBranch = branch;
    deleted = deletePaths;
    return commitResult ?? const PublishCommitSuccess('NEWCOMMIT', ['x']);
  }
}

/// The aggregate DI port needs the auth/admin methods too. They are not part
/// of these tests, so any unexpected call fails instead of hitting the network.
final class _ControllerApi extends _CapturingApi implements GitHubApi {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected GitHub operation: $invocation');
}

final class _ControllerCredentials extends _FakeCreds
    implements PublishCredentialStore {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected credential write: $invocation');
}

final class _EmptyNetworkRepository implements NetworkRepository {
  @override
  Future<List<NetworkLibrary>> loadAll() async => const [];

  @override
  Future<int> count() async => 0;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected network write: $invocation');
}

void main() {
  CatalogueItem book({int id = 1, String? cover}) => CatalogueItem(
    id: id,
    title: 'The Odyssey',
    author: 'Homer',
    notes: 'PII from Ravi',
    location: 'Shelf 3B',
    coverUrl: cover,
  );

  /// S20 fixtures (W3): a series with private fields that must NOT leave the
  /// device, and an issue of it (its projected title is what publishes).
  Periodical series({
    String uid = 'uid-1',
    String? cover,
    bool removed = false,
  }) => Periodical(
    id: 7,
    periodicalUid: uid,
    title: 'Chandamama',
    issn: '0577-6058',
    publisher: 'Chandamama Publications',
    language: 'Telugu',
    coverUrl: cover,
    frequency: PeriodicalFrequency.monthly,
    subscriptionStart: 1760000000000,
    subscriptionEnd: 1790000000000,
    notes: 'private series note',
    location: 'private series shelf',
    sourceDetail: 'private series source',
    removed: removed,
  );

  CatalogueItem issue({
    int id = 2,
    String? cover,
    String uid = 'uid-1',
    bool removed = false,
  }) => CatalogueItem(
    id: id,
    title: 'Chandamama — Vol 249 No 10 (Oct 2026)',
    publisher: 'Chandamama Publications',
    coverUrl: cover,
    removed: removed,
    details: IssueOf(
      periodicalUid: uid,
      volume: 249,
      issueNumber: 10,
      issueDate: 1759276800000,
    ),
  );

  List<int> encode(PublishExport e) =>
      utf8.encode(const JsonEncoder().convert(e.toJson()));

  /// Decodes the books.json the api was asked to commit.
  Map<String, dynamic> committedPayload(_CapturingApi api) =>
      jsonDecode(
            utf8.decode(
              api.committed!.firstWhere((f) => f.path == 'books.json').bytes,
            ),
          )
          as Map<String, dynamic>;

  PublishLibraryUseCase makeUseCase(
    GitHubGitDataApi api,
    PublishManifestGateway manifest, {
    PublishedSiteVerifier? verifier,
    PublishCredentialReader? credentials,
    LocalCoverReader? readLocalCover,
    RemoteCoverFetcher? fetchRemoteCover,
    ViewerHtmlBuilderFn? buildViewerHtml,
  }) => PublishLibraryUseCase(
    api: api,
    credentials: credentials ?? _FakeCreds(),
    manifest: manifest,
    coverIds: PublishCoverIds(_FixedSalt()),
    readLocalCover: readLocalCover ?? (_) async => null,
    fetchRemoteCover: fetchRemoteCover ?? (_) async => null,
    buildViewerHtml:
        buildViewerHtml ?? () async => utf8.encode('<html></html>'),
    verifier: verifier,
    sleep: (_) async {}, // no real waiting in tests
    clock: () => 1000,
  );

  group('read-back verification (à la Localcart Orange)', () {
    test(
      'pagesLive true once the live site serves the published bytes',
      () async {
        final api = _CapturingApi();
        late _FakeVerifier verifier;
        verifier = _FakeVerifier((_, _) async {
          // Poll 1: stale content; poll 2: the bytes just committed.
          if (verifier.calls.length == 1) return utf8.encode('old');
          return api.committed!.firstWhere((f) => f.path == 'books.json').bytes;
        });
        final result =
            await makeUseCase(api, _MemManifest(), verifier: verifier).call(
              books: [book()],
              periodicals: const [],
              activeLoanCounts: const {},
              encodeBooksJson: encode,
              libraryJson: null,
            );
        expect((result as PublishSuccess).pagesLive, isTrue);
        expect(verifier.calls, hasLength(2));
        // Origin-bound: the exact site root and the fixed file, never a URL.
        expect(verifier.calls.first.$1, 'https://me.github.io/lib/');
        expect(verifier.calls.first.$2, 'books.json');
        // Cache-busted, with a fresh buster per attempt.
        expect(verifier.calls.first.$3, isNotNull);
        expect(verifier.calls.first.$3, isNot(verifier.calls.last.$3));
      },
    );

    test('bounded: never-matching content stops after readBackAttempts '
        'with pagesLive null (regression: infinite "Publishing…")', () async {
      var polls = 0;
      final result =
          await makeUseCase(
            _CapturingApi(),
            _MemManifest(),
            verifier: _FakeVerifier((_, _) async {
              polls++;
              return utf8.encode('never matches');
            }),
          ).call(
            books: [book()],
            periodicals: const [],
            activeLoanCounts: const {},
            encodeBooksJson: encode,
            libraryJson: null,
          );
      expect((result as PublishSuccess).pagesLive, isNull);
      expect(polls, PublishLibraryUseCase.readBackAttempts);
    });

    test('fetch failures (null) are tolerated and stay bounded', () async {
      final result =
          await makeUseCase(
            _CapturingApi(),
            _MemManifest(),
            verifier: _FakeVerifier((_, _) async => null),
          ).call(
            books: [book()],
            periodicals: const [],
            activeLoanCounts: const {},
            encodeBooksJson: encode,
            libraryJson: null,
          );
      expect((result as PublishSuccess).pagesLive, isNull);
    });
  });

  test('publishes books.json + index.html and returns the pages URL', () async {
    final api = _CapturingApi();
    final manifest = _MemManifest();
    final result = await makeUseCase(api, manifest).call(
      books: [book()],
      periodicals: const [],
      activeLoanCounts: const {},
      encodeBooksJson: encode,
      libraryJson: null,
    );
    expect(result, isA<PublishSuccess>());
    final s = result as PublishSuccess;
    expect(s.pagesUrl, 'https://me.github.io/lib/');
    // No verifier wired ⇒ read-back skipped ⇒ unknown liveness.
    expect(s.pagesLive, isNull);
    // books.json + index.html both in the commit.
    final paths = api.committed!.map((f) => f.path).toSet();
    expect(paths, containsAll(<String>['books.json', 'index.html']));
    // Manifest persisted for the repo.
    expect(manifest.saved?.repo, 'me/lib');
  });

  test('an explicitly empty catalogue is a valid publication input', () async {
    final api = _CapturingApi();
    final manifest = _MemManifest();
    final result = await makeUseCase(api, manifest).call(
      books: const [],
      periodicals: const [],
      activeLoanCounts: null,
      encodeBooksJson: encode,
      libraryJson: null,
    );

    expect(result, isA<PublishSuccess>());
    final files = api.committed!;
    final payload =
        jsonDecode(
              utf8.decode(
                files.firstWhere((f) => f.path == 'books.json').bytes,
              ),
            )
            as Map<String, dynamic>;
    expect(payload['books'], isEmpty);
    expect(files.map((file) => file.path), ['books.json', 'index.html']);
    expect(manifest.saved?.repo, 'me/lib');
  });

  test('books.json carries redacted data only (no PII)', () async {
    final api = _CapturingApi();
    await makeUseCase(api, _MemManifest()).call(
      books: [book()],
      periodicals: const [],
      activeLoanCounts: const {},
      encodeBooksJson: encode,
      libraryJson: null,
    );
    final booksFile = api.committed!.firstWhere((f) => f.path == 'books.json');
    final json = utf8.decode(booksFile.bytes);
    expect(json, contains('The Odyssey'));
    expect(json, isNot(contains('Ravi')));
    expect(json, isNot(contains('Shelf')));
  });

  test('removed books and issues are excluded entirely', () async {
    final api = _CapturingApi();
    const removed = CatalogueItem(id: 9, title: 'Gone', removed: true);
    final removedIssue = issue(
      id: 10,
      removed: true,
    ).copyWith(title: 'Removed issue');
    await makeUseCase(api, _MemManifest()).call(
      books: [book(), removed, removedIssue],
      periodicals: const [],
      activeLoanCounts: const {},
      encodeBooksJson: encode,
      libraryJson: null,
    );
    final json = utf8.decode(
      api.committed!.firstWhere((f) => f.path == 'books.json').bytes,
    );
    expect(json, isNot(contains('Gone')));
    expect(json, isNot(contains('Removed issue')));
  });

  test('unchanged files are not re-uploaded (incremental)', () async {
    // Run once to discover the shas, then run again with that manifest seeded:
    // identical inputs ⇒ identical shas ⇒ nothing flagged for upload.
    final api1 = _CapturingApi();
    final m1 = _MemManifest();
    await makeUseCase(api1, m1).call(
      books: [book()],
      periodicals: const [],
      activeLoanCounts: const {},
      encodeBooksJson: encode,
      libraryJson: null,
    );
    final seeded = _MemManifest(m1.saved!);

    final api2 = _CapturingApi();
    await makeUseCase(api2, seeded).call(
      books: [book()],
      periodicals: const [],
      activeLoanCounts: const {},
      encodeBooksJson: encode,
      libraryJson: null,
    );
    // Same inputs ⇒ same shas ⇒ nothing flagged for upload.
    expect(api2.committed!.every((f) => !f.upload), isTrue);
  });

  test('availability omitted when vault locked (counts null)', () async {
    final api = _CapturingApi();
    final result = await makeUseCase(api, _MemManifest()).call(
      books: [book()],
      periodicals: const [],
      activeLoanCounts: null,
      encodeBooksJson: encode,
      libraryJson: null,
    );
    expect((result as PublishSuccess).availabilityOmitted, isTrue);
    final json = utf8.decode(
      api.committed!.firstWhere((f) => f.path == 'books.json').bytes,
    );
    expect(json, isNot(contains('availability')));
  });

  test('not signed in fails fast', () async {
    final uc = PublishLibraryUseCase(
      api: _CapturingApi(),
      credentials: _FakeCreds(tok: null),
      manifest: _MemManifest(),
      coverIds: PublishCoverIds(_FixedSalt()),
      readLocalCover: (_) async => null,
      fetchRemoteCover: (_) async => null,
      buildViewerHtml: () async => const [],
    );
    final r = await uc.call(
      books: [book()],
      periodicals: const [],
      activeLoanCounts: const {},
      encodeBooksJson: encode,
      libraryJson: null,
    );
    expect(r, isA<PublishFailure>());
  });

  test(
    'local cover is read, sha-d, and uploaded under a salted path',
    () async {
      final api = _CapturingApi();
      final uc = PublishLibraryUseCase(
        api: api,
        credentials: _FakeCreds(),
        manifest: _MemManifest(),
        coverIds: PublishCoverIds(_FixedSalt()),
        readLocalCover: (src) async => utf8.encode('IMG'),
        fetchRemoteCover: (_) async => null,
        buildViewerHtml: () async => utf8.encode('<html></html>'),
        clock: () => 1000,
      );
      await uc.call(
        books: [book(cover: 'covers/abc.jpg')],
        periodicals: const [],
        activeLoanCounts: const {},
        encodeBooksJson: encode,
        libraryJson: null,
      );
      final coverFile = api.committed!.firstWhere(
        (f) => f.path.startsWith('covers/'),
      );
      expect(coverFile.upload, isTrue);
      expect(coverFile.gitSha, GitBlobSha.of(utf8.encode('IMG')));
      // books.json points at the salted cover path, not the original.
      final json = utf8.decode(
        api.committed!.firstWhere((f) => f.path == 'books.json').bytes,
      );
      expect(json, contains(coverFile.path));
    },
  );

  group('N09 — the publish goes where Pages actually serves from', () {
    test(
      'commits to the Pages SOURCE branch, not the default branch',
      () async {
        final api = _CapturingApi(
          pages: const PagesSite(
            sourceBranch: 'gh-pages',
            sourcePath: '/',
            isWorkflowBuild: false,
          ),
        );
        final result = await makeUseCase(api, _MemManifest()).call(
          books: [book()],
          periodicals: const [],
          activeLoanCounts: const {},
          encodeBooksJson: encode,
          libraryJson: null,
        );
        expect(result, isA<PublishSuccess>());
        expect(api.committedBranch, 'gh-pages');
        expect(api.headTreeBranch, 'gh-pages');
      },
    );

    test('Pages turned off since setup → typed failure, no commit', () async {
      final api = _CapturingApi(pages: null);
      final manifest = _MemManifest();
      final result = await makeUseCase(api, manifest).call(
        books: [book()],
        periodicals: const [],
        activeLoanCounts: const {},
        encodeBooksJson: encode,
        libraryJson: null,
      );
      expect(result, isA<PublishFailure>());
      expect((result as PublishFailure).reason, contains('GitHub Pages'));
      expect(api.committed, isNull);
      expect(manifest.saved, isNull);
    });

    test('Pages re-pointed at /docs or a workflow → typed failure', () async {
      for (final site in const [
        PagesSite(
          sourceBranch: 'main',
          sourcePath: '/docs',
          isWorkflowBuild: false,
        ),
        PagesSite(sourceBranch: null, sourcePath: null, isWorkflowBuild: true),
      ]) {
        final api = _CapturingApi(pages: site);
        final result = await makeUseCase(api, _MemManifest()).call(
          books: [book()],
          periodicals: const [],
          activeLoanCounts: const {},
          encodeBooksJson: encode,
          libraryJson: null,
        );
        expect(result, isA<PublishFailure>());
        expect(api.committed, isNull);
      }
    });

    test('a transport failure reading Pages is the network message', () async {
      final api = _CapturingApi(throwOnPagesSite: true);
      final result = await makeUseCase(api, _MemManifest()).call(
        books: [book()],
        periodicals: const [],
        activeLoanCounts: const {},
        encodeBooksJson: encode,
        libraryJson: null,
      );
      expect(result, isA<PublishFailure>());
      expect((result as PublishFailure).reason, contains('connection'));
      expect(api.committed, isNull);
    });

    test('a user site (me/me.github.io) reports the ROOT address', () async {
      final api = _CapturingApi();
      final verifier = _FakeVerifier((_, _) async => null);
      final result =
          await makeUseCase(
            api,
            _MemManifest(),
            credentials: _FakeCreds(repo: 'me/me.github.io'),
            verifier: verifier,
          ).call(
            books: [book()],
            periodicals: const [],
            activeLoanCounts: const {},
            encodeBooksJson: encode,
            libraryJson: null,
          );
      expect((result as PublishSuccess).pagesUrl, 'https://me.github.io/');
      // The read-back is bound to the same resolved address.
      expect(verifier.calls.first.$1, 'https://me.github.io/');
    });
  });

  group('library.json (docs/ARCHITECTURE.md §5.1)', () {
    final descriptor = utf8.encode('{"schemaVersion":1}');

    test('a provided descriptor rides in the same atomic commit', () async {
      final api = _CapturingApi();
      final result = await makeUseCase(api, _MemManifest()).call(
        books: [book()],
        periodicals: const [],
        activeLoanCounts: const {},
        encodeBooksJson: encode,
        libraryJson: descriptor,
      );
      expect(result, isA<PublishSuccess>());
      expect(api.committed!.map((f) => f.path), [
        'books.json',
        'library.json',
        'index.html',
      ]);
      expect(api.deleted, isEmpty);
    });

    test('unchanged descriptor bytes are not re-uploaded (sha skip)', () async {
      final api1 = _CapturingApi();
      final m1 = _MemManifest();
      await makeUseCase(api1, m1).call(
        books: [book()],
        periodicals: const [],
        activeLoanCounts: const {},
        encodeBooksJson: encode,
        libraryJson: descriptor,
      );
      expect(
        api1.committed!.firstWhere((f) => f.path == 'library.json').upload,
        isTrue,
        reason: 'first publish uploads it',
      );

      // Second run with the persisted manifest: identical bytes ⇒ same git
      // blob sha ⇒ the incremental publish skips the upload.
      final api2 = _CapturingApi();
      await makeUseCase(api2, _MemManifest(m1.saved!)).call(
        books: [book()],
        periodicals: const [],
        activeLoanCounts: const {},
        encodeBooksJson: encode,
        libraryJson: descriptor,
      );
      expect(
        api2.committed!.firstWhere((f) => f.path == 'library.json').upload,
        isFalse,
      );
    });

    test(
      'null descriptor REMOVES a previously published library.json',
      () async {
        final api = _CapturingApi();
        final manifest = _MemManifest(
          const PublishManifest(
            repo: 'me/lib',
            fileShas: {'library.json': 'OLD_SHA'},
          ),
        );
        await makeUseCase(api, manifest).call(
          books: [book()],
          periodicals: const [],
          activeLoanCounts: const {},
          encodeBooksJson: encode,
          libraryJson: null,
        );
        // The opt-out deletes the stale file in the SAME commit (M14), so a
        // previously published location never outlives the switch.
        expect(api.deleted, ['library.json']);
        expect(
          api.committed!.map((f) => f.path),
          isNot(contains('library.json')),
        );
      },
    );

    test('null descriptor with nothing published deletes nothing', () async {
      final api = _CapturingApi();
      await makeUseCase(api, _MemManifest()).call(
        books: [book()],
        periodicals: const [],
        activeLoanCounts: const {},
        encodeBooksJson: encode,
        libraryJson: null,
      );
      expect(api.deleted, isEmpty);
    });
  });

  group('W3 — kinds and periodicals in books.json', () {
    test('every entry carries its kind; an issue nests its issue{}', () async {
      final api = _CapturingApi();
      await makeUseCase(api, _MemManifest()).call(
        books: [
          book(),
          issue(),
          const CatalogueItem(
            id: 3,
            title: 'Carrom board',
            details: OtherItemOf(),
          ),
          const CatalogueItem(
            id: 4,
            title: 'Chandamama — Jan–Feb 2026',
            details: IssueOf(
              periodicalUid: 'uid-1',
              issueDate: 1767225600000,
              boundUntil: 1769904000000,
              label: 'Winter bound volume',
            ),
          ),
        ],
        periodicals: [series()],
        activeLoanCounts: const {},
        encodeBooksJson: encode,
        libraryJson: null,
      );
      final payload = committedPayload(api);
      final books = (payload['books'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(books[0]['kind'], 'book');
      expect(books[0].containsKey('issue'), isFalse);
      expect(books[1]['kind'], 'magazine-issue');
      expect(books[1]['issue'], {
        'periodicalUid': 'uid-1',
        'volume': 249,
        'issueNumber': 10,
        'issueDate': 1759276800000,
      });
      expect(books[2]['kind'], 'other');
      expect(books[3]['kind'], 'magazine-issue');
      expect(books[3]['issue'], {
        'periodicalUid': 'uid-1',
        'issueDate': 1767225600000,
        'boundUntil': 1769904000000,
        'label': 'Winter bound volume',
      });
    });

    test(
      'periodicals[] carries public fields only (private ones stripped)',
      () async {
        final api = _CapturingApi();
        await makeUseCase(api, _MemManifest()).call(
          books: [issue()],
          periodicals: [series()],
          activeLoanCounts: const {},
          encodeBooksJson: encode,
          libraryJson: null,
        );
        final payload = committedPayload(api);
        final periodicals = (payload['periodicals'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        expect(periodicals, hasLength(1));
        expect(periodicals.single, {
          'periodicalUid': 'uid-1',
          'title': 'Chandamama',
          'issn': '0577-6058',
          'publisher': 'Chandamama Publications',
          'language': 'Telugu',
          'frequency': 'monthly',
        });
        // The serialised payload contains none of the private values (the
        // redaction test pins the key set; here the whole file is scanned).
        final json = utf8.decode(
          api.committed!.firstWhere((f) => f.path == 'books.json').bytes,
        );
        expect(json, isNot(contains('private series')));
        expect(json, isNot(contains('subscription')));
      },
    );

    test('no magazines ⇒ the additive periodicals key is omitted', () async {
      final api = _CapturingApi();
      await makeUseCase(api, _MemManifest()).call(
        books: [book()],
        periodicals: const [],
        activeLoanCounts: const {},
        encodeBooksJson: encode,
        libraryJson: null,
      );
      expect(committedPayload(api).containsKey('periodicals'), isFalse);
    });

    test(
      'a removed series publishes no entry; its issue keeps the cover fallback',
      () async {
        final api = _CapturingApi();
        final result =
            await makeUseCase(
              api,
              _MemManifest(),
              readLocalCover: (_) async => utf8.encode('SERIES-IMG'),
            ).call(
              books: [issue()],
              periodicals: [series(removed: true, cover: 'covers/series.jpg')],
              activeLoanCounts: const {},
              encodeBooksJson: encode,
              libraryJson: null,
            );

        expect(result, isA<PublishSuccess>());
        final payload = committedPayload(api);
        expect(payload.containsKey('periodicals'), isFalse);
        final books = (payload['books'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        expect(books.single['kind'], 'magazine-issue');
        expect(books.single['title'], contains('Chandamama'));
        final covers = api.committed!
            .where((file) => file.path.startsWith('covers/'))
            .toList();
        expect(covers, hasLength(1));
        final salt = ascii.encode('salt-1234567890');
        expect(
          covers.single.path,
          'covers/${PublishCoverIds.shortHashHexForKey(salt, 'periodical:uid-1')}.jpg',
        );
        expect(books.single['coverUrl'], covers.single.path);
      },
    );

    test('an issue without its own cover publishes the series cover '
        '(IssueCover.resolve), uploaded once', () async {
      final api = _CapturingApi();
      await makeUseCase(
        api,
        _MemManifest(),
        readLocalCover: (src) async => utf8.encode('SERIES-IMG'),
      ).call(
        books: [issue()],
        periodicals: [series(cover: 'covers/series.jpg')],
        activeLoanCounts: const {},
        encodeBooksJson: encode,
        libraryJson: null,
      );
      // Exactly ONE cover file in the commit: the series' salted path.
      final covers = api.committed!
          .where((f) => f.path.startsWith('covers/'))
          .toList();
      expect(covers, hasLength(1));
      final salt = ascii.encode('salt-1234567890');
      expect(
        covers.single.path,
        'covers/${PublishCoverIds.shortHashHexForKey(salt, 'periodical:uid-1')}.jpg',
      );
      // Both the series entry and the issue point at it.
      final payload = committedPayload(api);
      expect(
        (payload['periodicals'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .single['coverUrl'],
        covers.single.path,
      );
      expect(
        (payload['books'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .single['coverUrl'],
        covers.single.path,
      );
    });

    test(
      'a remote series cover is fetched once and shared with its issue',
      () async {
        const source = 'https://covers.openlibrary.org/x.jpg';
        final api = _CapturingApi();
        final requested = <String>[];
        final result =
            await makeUseCase(
              api,
              _MemManifest(),
              fetchRemoteCover: (url) async {
                requested.add(url);
                return utf8.encode('REMOTE-SERIES-IMG');
              },
            ).call(
              books: [issue()],
              periodicals: [series(cover: source)],
              activeLoanCounts: const {},
              encodeBooksJson: encode,
              libraryJson: null,
            );

        expect(result, isA<PublishSuccess>());
        expect(requested, [source]);
        final covers = api.committed!
            .where((file) => file.path.startsWith('covers/'))
            .toList();
        expect(covers, hasLength(1));
        expect(covers.single.bytes, utf8.encode('REMOTE-SERIES-IMG'));
        expect(covers.single.upload, isTrue);
        final salt = ascii.encode('salt-1234567890');
        expect(
          covers.single.path,
          'covers/${PublishCoverIds.shortHashHexForKey(salt, 'periodical:uid-1')}.jpg',
        );
        final payload = committedPayload(api);
        expect(
          (payload['periodicals'] as List<dynamic>)
              .cast<Map<String, dynamic>>()
              .single['coverUrl'],
          covers.single.path,
        );
        expect(
          (payload['books'] as List<dynamic>)
              .cast<Map<String, dynamic>>()
              .single['coverUrl'],
          covers.single.path,
        );
      },
    );

    test('an issue with its own cover publishes its own salted path', () async {
      final api = _CapturingApi();
      await makeUseCase(
        api,
        _MemManifest(),
        readLocalCover: (src) async => utf8.encode('IMG:$src'),
      ).call(
        books: [issue(cover: 'covers/issue.jpg')],
        periodicals: [series(cover: 'covers/series.jpg')],
        activeLoanCounts: const {},
        encodeBooksJson: encode,
        libraryJson: null,
      );
      final salt = ascii.encode('salt-1234567890');
      final payload = committedPayload(api);
      expect(
        (payload['books'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .single['coverUrl'],
        'covers/${PublishCoverIds.shortHashHex(salt, 2)}.jpg',
      );
      expect(
        (payload['periodicals'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .single['coverUrl'],
        'covers/${PublishCoverIds.shortHashHexForKey(salt, 'periodical:uid-1')}.jpg',
      );
      // Both covers uploaded — two distinct salted paths.
      expect(
        api.committed!.where((f) => f.path.startsWith('covers/')),
        hasLength(2),
      );
    });

    test('periodical covers get the remote source-identity skip too', () async {
      final api = _CapturingApi();
      final salt = ascii.encode('salt-1234567890');
      final path =
          'covers/${PublishCoverIds.shortHashHexForKey(salt, 'periodical:uid-1')}.jpg';
      final manifest = _MemManifest(
        PublishManifest(
          repo: 'me/lib',
          fileShas: {path: 'EXISTING_SHA'},
          coverUrlByBookId: {
            'periodical:uid-1': 'https://covers.openlibrary.org/x.jpg',
          },
        ),
      );
      var fetches = 0;
      await makeUseCase(
        api,
        manifest,
        fetchRemoteCover: (_) async {
          fetches++;
          return utf8.encode('REMOTE-IMG');
        },
      ).call(
        books: [issue()],
        periodicals: [series(cover: 'https://covers.openlibrary.org/x.jpg')],
        activeLoanCounts: const {},
        encodeBooksJson: encode,
        libraryJson: null,
      );
      // URL unchanged + file already in the repo ⇒ no fetch, no upload.
      expect(fetches, 0);
      final coverFile = api.committed!.firstWhere(
        (f) => f.path.startsWith('covers/'),
      );
      expect(coverFile.upload, isFalse);
      expect(coverFile.gitSha, 'EXISTING_SHA');
      // The manifest remembers the series' source URL for the next run.
      expect(
        manifest.saved?.coverUrlByBookId['periodical:uid-1'],
        'https://covers.openlibrary.org/x.jpg',
      );
    });
  });

  group('S8 — Unicode covers and canonical series links', () {
    test(
      'a non-ASCII covered series commits with grouping and cover fallback',
      () async {
        const uid = 'పత్రిక-१';
        final api = _CapturingApi();
        final result =
            await makeUseCase(
              api,
              _MemManifest(),
              readLocalCover: (_) async => utf8.encode('SERIES-IMG'),
            ).call(
              books: [issue(uid: uid)],
              periodicals: [series(uid: uid, cover: 'covers/series.jpg')],
              activeLoanCounts: const {},
              encodeBooksJson: encode,
              libraryJson: null,
            );

        expect(result, isA<PublishSuccess>());
        final covers = api.committed!
            .where((file) => file.path.startsWith('covers/'))
            .toList();
        expect(covers, hasLength(1));
        expect(covers.single.path, 'covers/d6558de0d7c76239.jpg');
        final payload = committedPayload(api);
        final publishedIssue = (payload['books'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .single;
        expect(publishedIssue['issue'], {
          'periodicalUid': uid,
          'volume': 249,
          'issueNumber': 10,
          'issueDate': 1759276800000,
        });
        expect(publishedIssue['coverUrl'], covers.single.path);
        final publishedSeries = (payload['periodicals'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .single;
        expect(publishedSeries['periodicalUid'], uid);
        expect(publishedSeries['coverUrl'], covers.single.path);
      },
    );

    Future<void> expectLinkRefusal({
      required List<CatalogueItem> books,
      required List<Periodical> periodicals,
      required String privateDiagnostic,
    }) async {
      final api = _CapturingApi();
      final manifest = _MemManifest();
      var coverReads = 0;
      var viewerBuilds = 0;
      var encodeCalls = 0;
      final result =
          await makeUseCase(
            api,
            manifest,
            readLocalCover: (_) async {
              coverReads++;
              return utf8.encode('IMG');
            },
            buildViewerHtml: () async {
              viewerBuilds++;
              return utf8.encode('<html></html>');
            },
          ).call(
            books: books,
            periodicals: periodicals,
            activeLoanCounts: const {},
            encodeBooksJson: (export) {
              encodeCalls++;
              return encode(export);
            },
            libraryJson: null,
          );

      expect(result, isA<PublishFailure>());
      final reason = (result as PublishFailure).reason;
      expect(
        reason,
        'Some magazine series or issue links are invalid. '
        'Nothing was published.',
      );
      expect(reason, isNot(contains(privateDiagnostic)));
      expect(coverReads, 0, reason: 'refuse before cover processing');
      expect(viewerBuilds, 0, reason: 'refuse before building an artifact');
      expect(encodeCalls, 0, reason: 'refuse before building books.json');
      expect(api.committed, isNull);
      expect(manifest.saved, isNull);
    }

    test('an issue pointing to a missing series is refused', () async {
      await expectLinkRefusal(
        books: [issue(uid: 'missing-private-uid')],
        periodicals: const [],
        privateDiagnostic: 'missing-private-uid',
      );
    });

    test('a noncanonical issue UID is refused', () async {
      await expectLinkRefusal(
        books: [issue(uid: ' series-private-uid ')],
        periodicals: [
          series(uid: 'series-private-uid', cover: 'covers/series.jpg'),
        ],
        privateDiagnostic: 'series-private-uid',
      );
    });

    test('a noncanonical periodical UID is refused before cover IO', () async {
      await expectLinkRefusal(
        books: const [],
        periodicals: [
          series(uid: ' series-private-uid ', cover: 'covers/series.jpg'),
        ],
        privateDiagnostic: 'series-private-uid',
      );
    });

    test('a persisted series without its UID is refused', () async {
      await expectLinkRefusal(
        books: const [],
        periodicals: const [
          Periodical(
            id: 7,
            title: 'private-series-diagnostic',
            coverUrl: 'covers/series.jpg',
          ),
        ],
        privateDiagnostic: 'private-series-diagnostic',
      );
    });

    test('duplicate series UIDs are refused instead of choosing one', () async {
      await expectLinkRefusal(
        books: [issue(uid: 'duplicate-private-uid')],
        periodicals: [
          series(uid: 'duplicate-private-uid', cover: 'covers/one.jpg'),
          series(uid: 'duplicate-private-uid', cover: 'covers/two.jpg'),
        ],
        privateDiagnostic: 'duplicate-private-uid',
      );
    });
  });

  group('S11 — real-Drift interchange corruption at the publish boundary', () {
    for (final rawKind in ['hologram', 'magazine-issue']) {
      final description = rawKind == 'hologram'
          ? 'an unknown kind'
          : 'a detail-less issue';
      test('$description refuses before artifact IO or commit', () async {
        final fixture = BundleTestFixture();
        addTearDown(fixture.dispose);
        final rawId = await seedRawCatalogueRow(
          fixture.database,
          title: 'Raw $rawKind evidence',
          kind: rawKind,
          coverUrl: 'covers/raw.jpg',
        );
        final integrityRead = await fixture.books.getAllForInterchange();
        final integrityFailure = integrityRead.getLeft().toNullable();
        expect(
          integrityFailure,
          rawKind == 'hologram'
              ? isA<UnsupportedItemKindFailure>()
              : isA<StorageFailure>(),
          reason:
              'the raw fixture must exercise the intended strict-read guard',
        );

        final api = _ControllerApi();
        final manifest = _MemManifest();
        final settings = ReplacementSettings()
          ..id = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
        var localCoverReads = 0;
        var remoteCoverFetches = 0;
        var viewerBuilds = 0;
        var publishedFileFetches = 0;
        final container = ProviderContainer(
          overrides: [
            catalogueItemRepositoryProvider.overrideWith(
              (ref) async => fixture.books,
            ),
            periodicalRepositoryProvider.overrideWith(
              (ref) async => fixture.periodicals,
            ),
            gitHubApiProvider.overrideWithValue(api),
            publishCredentialStoreProvider.overrideWithValue(
              _ControllerCredentials(),
            ),
            publishManifestStoreProvider.overrideWith((ref) async => manifest),
            publishCoverIdsProvider.overrideWithValue(
              PublishCoverIds(_FixedSalt()),
            ),
            settingsRepositoryProvider.overrideWith((ref) async => settings),
            networkRepositoryProvider.overrideWith(
              (ref) async => _EmptyNetworkRepository(),
            ),
            activeLoanCountsProvider.overrideWith((ref) => null),
            publishLocalCoverReaderProvider.overrideWith(
              (ref) async => (source) async {
                localCoverReads++;
                return utf8.encode('LOCAL-IMG');
              },
            ),
            remoteCoverFetcherProvider.overrideWithValue((_) async {
              remoteCoverFetches++;
              return null;
            }),
            publishedSiteVerifierProvider.overrideWithValue(
              _FakeVerifier((_, path) async {
                publishedFileFetches++;
                return null;
              }),
            ),
            viewerHtmlFactoryProvider.overrideWithValue(({
              required libraryName,
              required contact,
              required sharing,
            }) async {
              viewerBuilds++;
              return utf8.encode('<html></html>');
            }),
            clockProvider.overrideWithValue(() => 1000),
          ],
        );
        addTearDown(container.dispose);

        final result = await container
            .read(publishControllerProvider.notifier)
            .publish();

        expect(result, isA<PublishFailure>());
        expect(
          (result as PublishFailure).reason,
          'Could not read the library. Nothing was published. '
          'Please try again.',
        );
        expect(localCoverReads, 0);
        expect(remoteCoverFetches, 0);
        expect(viewerBuilds, 0);
        expect(publishedFileFetches, 0);
        expect(api.committed, isNull);
        expect(manifest.saved, isNull);
        expect(container.exists(appDocsDirProvider), isFalse);

        final stored = await (fixture.database.select(
          fixture.database.books,
        )..where((row) => row.id.equals(rawId))).getSingle();
        expect(stored.kind, rawKind);
        expect(stored.title, 'Raw $rawKind evidence');
        expect(stored.coverUrl, 'covers/raw.jpg');
        expect(
          await fixture.database.select(fixture.database.books).get(),
          hasLength(1),
        );
        expect(
          await fixture.database.select(fixture.database.magazineIssues).get(),
          isEmpty,
        );
      });
    }
  });
}
