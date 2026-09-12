import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/events/domain/entities/event_poster.dart';
import 'package:pitaka/features/publish/application/publish_events_use_case.dart';
import 'package:pitaka/features/publish/application/publish_library_use_case.dart'
    show PublishManifestGateway;
import 'package:pitaka/features/publish/domain/git_blob_sha.dart';
import 'package:pitaka/features/publish/domain/github_api.dart';
import 'package:pitaka/features/publish/domain/github_models.dart';
import 'package:pitaka/features/publish/domain/publish_credential_store.dart';
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

class _CapturingApi implements GitHubApi {
  _CapturingApi({
    this.pages = const PagesSite(
      sourceBranch: 'main',
      sourcePath: '/',
      isWorkflowBuild: false,
    ),
  });

  /// What `pagesSite()` answers (null = Pages off).
  final PagesSite? pages;
  List<DesiredFile>? committed;
  List<String> deleted = [];
  String? committedBranch;
  PublishCommitResult result = const PublishCommitSuccess('NEW', ['x']);

  @override
  Future<PagesSite?> pagesSite({
    required String owner,
    required String repo,
    required String token,
  }) async => pages;

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
    return result;
  }

  // Unused by the events path.
  @override
  Future<Map<String, String>> headTreeShas({
    required String owner,
    required String repo,
    required String branch,
    required String token,
  }) => throw UnimplementedError();
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
  // A manifest that "proves" a catalogue publish to me/lib.
  PublishManifest published() => const PublishManifest(
    repo: 'me/lib',
    fileShas: {'index.html': 'abc', 'books.json': 'def'},
  );

  EventsContent twoPosters() => EventsContent(
    posters: [
      EventPoster.create(imageRef: 'posters/a.jpg', description: 'Story')!,
      EventPoster.create(imageRef: 'posters/b.jpg')!,
    ],
  );

  PublishEventsUseCase make({
    required GitHubApi api,
    required PublishManifestGateway manifest,
    PublishCredentialReader? creds,
    PosterBytesReader? readPoster,
  }) => PublishEventsUseCase(
    api: api,
    credentials: creds ?? _FakeCreds(),
    manifest: manifest,
    readPoster: readPoster ?? (ref) async => ascii.encode('img:$ref'),
    buildEventsHtml: (posters) async =>
        utf8.encode('<html>${posters.length} posters</html>'),
    clock: () => 1000,
  );

  test('refuses when not signed in', () async {
    final result = await make(
      api: _CapturingApi(),
      manifest: _MemManifest(published()),
      creds: _FakeCreds(tok: null),
    ).call(twoPosters());
    expect(result, isA<PublishEventsFailure>());
    expect((result as PublishEventsFailure).reason, contains('Not signed in'));
  });

  test('refuses when the catalogue was never published to this repo', () async {
    // Empty manifest → no index.html marker.
    final result = await make(
      api: _CapturingApi(),
      manifest: _MemManifest(),
    ).call(twoPosters());
    expect(result, isA<PublishEventsFailure>());
    expect(
      (result as PublishEventsFailure).reason,
      contains('Publish your catalogue first'),
    );
  });

  test('refuses when the manifest is for a different repo', () async {
    const otherRepo = PublishManifest(
      repo: 'someone/else',
      fileShas: {'index.html': 'abc'},
    );
    final result = await make(
      api: _CapturingApi(),
      manifest: _MemManifest(otherRepo),
    ).call(twoPosters());
    expect(result, isA<PublishEventsFailure>());
  });

  test('publishes events.html + poster files when the gate passes', () async {
    final api = _CapturingApi();
    final manifest = _MemManifest(published());
    final result = await make(api: api, manifest: manifest).call(twoPosters());

    expect(result, isA<PublishEventsSuccess>());
    final paths = api.committed!.map((f) => f.path).toList();
    expect(
      paths,
      containsAll(['events.html', 'posters/a.jpg', 'posters/b.jpg']),
    );
    expect(
      (result as PublishEventsSuccess).eventsUrl,
      'https://me.github.io/lib/events.html',
    );

    // Manifest is merged: the catalogue's index.html/books.json entries survive.
    expect(manifest.saved!.shaFor('index.html'), 'abc');
    expect(manifest.saved!.shaFor('books.json'), 'def');
    expect(manifest.saved!.shaFor('events.html'), isNotNull);
  });

  test('drops a poster whose local image is missing (no broken img)', () async {
    final api = _CapturingApi();
    final result = await make(
      api: api,
      manifest: _MemManifest(published()),
      // a.jpg resolves; b.jpg is missing.
      readPoster: (ref) async =>
          ref.endsWith('a.jpg') ? ascii.encode('img') : null,
    ).call(twoPosters());

    expect(result, isA<PublishEventsSuccess>());
    final paths = api.committed!.map((f) => f.path).toList();
    expect(paths, contains('posters/a.jpg'));
    expect(paths, isNot(contains('posters/b.jpg')));
  });

  test('an unchanged file is not re-uploaded (sha matches manifest)', () async {
    final api = _CapturingApi();
    // Pre-seed the manifest with a.jpg's exact git sha so it is reused.
    final aBytes = ascii.encode('img:posters/a.jpg');
    final manifest = _MemManifest(
      PublishManifest(
        repo: 'me/lib',
        fileShas: {'index.html': 'abc', 'posters/a.jpg': GitBlobSha.of(aBytes)},
      ),
    );
    await make(api: api, manifest: manifest).call(
      EventsContent(posters: [EventPoster.create(imageRef: 'posters/a.jpg')!]),
    );
    final aFile = api.committed!.firstWhere((f) => f.path == 'posters/a.jpg');
    expect(aFile.upload, isFalse); // reused, not uploaded
  });

  // M14 regressions: obsolete posters must be deleted from the branch in
  // the same commit, and an empty publish is the explicit page-clear.
  test(
    'M14: a removed poster is deleted and dropped from the manifest',
    () async {
      final api = _CapturingApi();
      // The manifest still knows about poster b from an earlier publish.
      final manifest = _MemManifest(
        const PublishManifest(
          repo: 'me/lib',
          fileShas: {
            'index.html': 'abc',
            'events.html': 'old',
            'posters/a.jpg': 'sha-a',
            'posters/b.jpg': 'sha-b',
          },
        ),
      );
      // Now only poster a is published.
      final content = EventsContent(
        posters: [EventPoster.create(imageRef: 'posters/a.jpg')!],
      );
      final result = await make(api: api, manifest: manifest).call(content);

      expect(result, isA<PublishEventsSuccess>());
      expect(api.deleted, ['posters/b.jpg']);
      // Catalogue + live poster shas survive; the deleted path is gone.
      expect(manifest.saved!.shaFor('index.html'), 'abc');
      expect(manifest.saved!.shaFor('posters/a.jpg'), isNotNull);
      expect(manifest.saved!.shaFor('posters/b.jpg'), isNull);
    },
  );

  test('M14: publishing with ZERO posters clears the events page', () async {
    final api = _CapturingApi();
    final manifest = _MemManifest(
      const PublishManifest(
        repo: 'me/lib',
        fileShas: {
          'index.html': 'abc',
          'events.html': 'old',
          'posters/a.jpg': 'sha-a',
        },
      ),
    );
    final result = await make(
      api: api,
      manifest: manifest,
    ).call(EventsContent.empty);

    expect(result, isA<PublishEventsSuccess>());
    // events.html is still committed (empty-state page)…
    expect(api.committed!.map((f) => f.path), ['events.html']);
    // …and every previously published poster is deleted.
    expect(api.deleted, ['posters/a.jpg']);
    expect(manifest.saved!.shaFor('posters/a.jpg'), isNull);
    expect(manifest.saved!.shaFor('index.html'), 'abc');
  });

  test('surfaces an HTTP error as a safe failure', () async {
    final api = _CapturingApi()
      ..result = const PublishCommitHttpError(422, 'bad');
    final result = await make(
      api: api,
      manifest: _MemManifest(published()),
    ).call(twoPosters());
    expect(result, isA<PublishEventsFailure>());
    expect((result as PublishEventsFailure).reason, contains('422'));
  });

  group("N09 — events share the catalogue's Pages resolution", () {
    test('a user site (me/me.github.io) links events at the ROOT', () async {
      const manifest = PublishManifest(
        repo: 'me/me.github.io',
        fileShas: {'index.html': 'abc'},
      );
      final result = await make(
        api: _CapturingApi(),
        manifest: _MemManifest(manifest),
        creds: _FakeCreds(repo: 'me/me.github.io'),
      ).call(twoPosters());
      expect(
        (result as PublishEventsSuccess).eventsUrl,
        'https://me.github.io/events.html',
      );
    });

    test('commits to the Pages SOURCE branch, not the default', () async {
      final api = _CapturingApi(
        pages: const PagesSite(
          sourceBranch: 'gh-pages',
          sourcePath: '/',
          isWorkflowBuild: false,
        ),
      );
      final result = await make(
        api: api,
        manifest: _MemManifest(published()),
      ).call(twoPosters());
      expect(result, isA<PublishEventsSuccess>());
      expect(api.committedBranch, 'gh-pages');
    });

    test('Pages turned off → typed failure, no commit', () async {
      final api = _CapturingApi(pages: null);
      final manifest = _MemManifest(published());
      final result = await make(
        api: api,
        manifest: manifest,
      ).call(twoPosters());
      expect(result, isA<PublishEventsFailure>());
      expect((result as PublishEventsFailure).reason, contains('GitHub Pages'));
      expect(api.committed, isNull);
      expect(manifest.saved, isNull);
    });
  });
}
