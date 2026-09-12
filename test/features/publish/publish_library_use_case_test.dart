import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/publish/application/publish_library_use_case.dart';
import 'package:pitaka/features/publish/domain/git_blob_sha.dart';
import 'package:pitaka/features/publish/domain/github_api.dart';
import 'package:pitaka/features/publish/domain/github_models.dart';
import 'package:pitaka/features/publish/domain/publish_cover_ids.dart';
import 'package:pitaka/features/publish/domain/publish_credential_store.dart';
import 'package:pitaka/features/publish/domain/publish_export.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';

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

class _FixedSalt implements PublishCoverSaltStore {
  @override
  Future<List<int>> salt() async => ascii.encode('salt-1234567890');
}

/// Records the commit it received; returns a scripted result.
class _CapturingApi implements GitHubApi {
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
    return commitResult ?? const PublishCommitSuccess('NEWCOMMIT', ['x']);
  }

  // Unused.
  @override
  Future<DeviceCodeGrant> requestDeviceCode({
    required String clientId,
    required String scope,
  }) => throw UnimplementedError();
  @override
  Future<PollResult> pollAccessToken({
    required String clientId,
    required String deviceCode,
  }) => throw UnimplementedError();
  @override
  Future<String> currentUserLogin(String token) => throw UnimplementedError();
  @override
  Future<RepoCreateResult> createUserRepo({
    required String name,
    required String token,
  }) => throw UnimplementedError();
  @override
  Future<void> enablePages({
    required String owner,
    required String repo,
    required String branch,
    required String token,
  }) => throw UnimplementedError();
  @override
  Future<RepoListing> userRepos(String token) => throw UnimplementedError();
  @override
  Future<GitHubRepoDetails?> repository({
    required String owner,
    required String repo,
    required String token,
  }) => throw UnimplementedError();
}

void main() {
  Book book({int id = 1, String? cover}) => Book(
    id: id,
    title: 'The Odyssey',
    author: 'Homer',
    notes: 'PII from Ravi',
    location: 'Shelf 3B',
    coverUrl: cover,
  );

  List<int> encode(PublishExport e) =>
      utf8.encode(const JsonEncoder().convert(e.toJson()));

  PublishLibraryUseCase makeUseCase(
    GitHubApi api,
    PublishManifestGateway manifest, {
    PublishedFileFetcher? fetchPublishedFile,
    PublishCredentialReader? credentials,
  }) => PublishLibraryUseCase(
    api: api,
    credentials: credentials ?? _FakeCreds(),
    manifest: manifest,
    coverIds: PublishCoverIds(_FixedSalt()),
    readLocalCover: (_) async => null,
    fetchRemoteCover: (_) async => null,
    buildViewerHtml: () async => utf8.encode('<html></html>'),
    fetchPublishedFile: fetchPublishedFile,
    sleep: (_) async {}, // no real waiting in tests
    clock: () => 1000,
  );

  group('read-back verification (à la Localcart Orange)', () {
    test(
      'pagesLive true once the live site serves the published bytes',
      () async {
        final api = _CapturingApi();
        final polled = <String>[];
        final result =
            await makeUseCase(
              api,
              _MemManifest(),
              fetchPublishedFile: (url) async {
                polled.add(url);
                // Poll 1: stale content; poll 2: the committed bytes.
                if (polled.length == 1) return utf8.encode('old');
                return api.committed!
                    .firstWhere((f) => f.path == 'books.json')
                    .bytes;
              },
            ).call(
              books: [book()],
              activeLoanCounts: const {},
              encodeBooksJson: encode,
            );
        expect((result as PublishSuccess).pagesLive, isTrue);
        expect(polled, hasLength(2));
        // Cache-busted, against the real site URL.
        expect(
          polled.first,
          startsWith('https://me.github.io/lib/books.json?rb='),
        );
        expect(polled.first, isNot(equals(polled.last))); // unique busters
      },
    );

    test('bounded: never-matching content stops after readBackAttempts '
        'with pagesLive null (regression: infinite "Publishing…")', () async {
      var polls = 0;
      final result =
          await makeUseCase(
            _CapturingApi(),
            _MemManifest(),
            fetchPublishedFile: (_) async {
              polls++;
              return utf8.encode('never matches');
            },
          ).call(
            books: [book()],
            activeLoanCounts: const {},
            encodeBooksJson: encode,
          );
      expect((result as PublishSuccess).pagesLive, isNull);
      expect(polls, PublishLibraryUseCase.readBackAttempts);
    });

    test('fetch failures (null) are tolerated and stay bounded', () async {
      final result =
          await makeUseCase(
            _CapturingApi(),
            _MemManifest(),
            fetchPublishedFile: (_) async => null,
          ).call(
            books: [book()],
            activeLoanCounts: const {},
            encodeBooksJson: encode,
          );
      expect((result as PublishSuccess).pagesLive, isNull);
    });
  });

  test('publishes books.json + index.html and returns the pages URL', () async {
    final api = _CapturingApi();
    final manifest = _MemManifest();
    final result = await makeUseCase(api, manifest).call(
      books: [book()],
      activeLoanCounts: const {},
      encodeBooksJson: encode,
    );
    expect(result, isA<PublishSuccess>());
    final s = result as PublishSuccess;
    expect(s.pagesUrl, 'https://me.github.io/lib/');
    // No fetchPublishedFile wired ⇒ read-back skipped ⇒ unknown liveness.
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
    final result = await makeUseCase(
      api,
      manifest,
    ).call(books: const [], activeLoanCounts: null, encodeBooksJson: encode);

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
      activeLoanCounts: const {},
      encodeBooksJson: encode,
    );
    final booksFile = api.committed!.firstWhere((f) => f.path == 'books.json');
    final json = utf8.decode(booksFile.bytes);
    expect(json, contains('The Odyssey'));
    expect(json, isNot(contains('Ravi')));
    expect(json, isNot(contains('Shelf')));
  });

  test('removed books are excluded entirely', () async {
    final api = _CapturingApi();
    const removed = Book(id: 9, title: 'Gone', removed: true);
    await makeUseCase(api, _MemManifest()).call(
      books: [book(), removed],
      activeLoanCounts: const {},
      encodeBooksJson: encode,
    );
    final json = utf8.decode(
      api.committed!.firstWhere((f) => f.path == 'books.json').bytes,
    );
    expect(json, isNot(contains('Gone')));
  });

  test('unchanged files are not re-uploaded (incremental)', () async {
    // Run once to discover the shas, then run again with that manifest seeded:
    // identical inputs ⇒ identical shas ⇒ nothing flagged for upload.
    final api1 = _CapturingApi();
    final m1 = _MemManifest();
    await makeUseCase(api1, m1).call(
      books: [book()],
      activeLoanCounts: const {},
      encodeBooksJson: encode,
    );
    final seeded = _MemManifest(m1.saved!);

    final api2 = _CapturingApi();
    await makeUseCase(api2, seeded).call(
      books: [book()],
      activeLoanCounts: const {},
      encodeBooksJson: encode,
    );
    // Same inputs ⇒ same shas ⇒ nothing flagged for upload.
    expect(api2.committed!.every((f) => !f.upload), isTrue);
  });

  test('availability omitted when vault locked (counts null)', () async {
    final api = _CapturingApi();
    final result = await makeUseCase(
      api,
      _MemManifest(),
    ).call(books: [book()], activeLoanCounts: null, encodeBooksJson: encode);
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
      activeLoanCounts: const {},
      encodeBooksJson: encode,
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
        activeLoanCounts: const {},
        encodeBooksJson: encode,
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
          activeLoanCounts: const {},
          encodeBooksJson: encode,
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
        activeLoanCounts: const {},
        encodeBooksJson: encode,
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
          activeLoanCounts: const {},
          encodeBooksJson: encode,
        );
        expect(result, isA<PublishFailure>());
        expect(api.committed, isNull);
      }
    });

    test('a transport failure reading Pages is the network message', () async {
      final api = _CapturingApi(throwOnPagesSite: true);
      final result = await makeUseCase(api, _MemManifest()).call(
        books: [book()],
        activeLoanCounts: const {},
        encodeBooksJson: encode,
      );
      expect(result, isA<PublishFailure>());
      expect((result as PublishFailure).reason, contains('connection'));
      expect(api.committed, isNull);
    });

    test('a user site (me/me.github.io) reports the ROOT address', () async {
      final api = _CapturingApi();
      final polled = <String>[];
      final result =
          await makeUseCase(
            api,
            _MemManifest(),
            credentials: _FakeCreds(repo: 'me/me.github.io'),
            fetchPublishedFile: (url) async {
              polled.add(url);
              return null;
            },
          ).call(
            books: [book()],
            activeLoanCounts: const {},
            encodeBooksJson: encode,
          );
      expect((result as PublishSuccess).pagesUrl, 'https://me.github.io/');
      // The read-back polls the same resolved address.
      expect(polled.first, startsWith('https://me.github.io/books.json?rb='));
    });
  });
}
