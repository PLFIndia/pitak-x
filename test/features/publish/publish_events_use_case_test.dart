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
  _FakeCreds({this.tok = 'TKN'});
  final String? tok;
  @override
  Future<String?> token() async => tok;
  @override
  Future<String?> targetRepo() async => 'me/lib';
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
  List<DesiredFile>? committed;
  PublishCommitResult result = const PublishCommitSuccess('NEW', ['x']);

  @override
  Future<String?> defaultBranch({
    required String owner,
    required String repo,
    required String token,
  }) async => 'main';

  @override
  Future<PublishCommitResult> commitFiles({
    required String owner,
    required String repo,
    required String branch,
    required String token,
    required List<DesiredFile> files,
    required String commitMessage,
  }) async {
    committed = files;
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
  Future<List<GitHubRepo>> userRepos(String token) =>
      throw UnimplementedError();
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
}
