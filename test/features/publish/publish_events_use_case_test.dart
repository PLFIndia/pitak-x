import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/events/domain/entities/event_poster.dart';
import 'package:pitaka/features/publish/application/publish_events_use_case.dart';
import 'package:pitaka/features/publish/application/publish_library_use_case.dart'
    show PublishManifestGateway;
import 'package:pitaka/features/publish/application/site/publish_host_state_repository.dart';
import 'package:pitaka/features/publish/domain/events_posters_html.dart';
import 'package:pitaka/features/publish/domain/git_blob_sha.dart';
import 'package:pitaka/features/publish/domain/github_api.dart';
import 'package:pitaka/features/publish/domain/github_error_messages.dart';
import 'package:pitaka/features/publish/domain/github_models.dart';
import 'package:pitaka/features/publish/domain/publish_credential_store.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/publish_state.dart';
import 'package:pitaka/features/publish/domain/site/published_site_verifier.dart';
import 'package:pitaka/features/publish/infrastructure/events_json_builder.dart';

/// Records the verified-target writes a publish is allowed to make (R33).
class _Recorder implements PublishHostStateRecorder {
  final List<PublishTarget> recorded = [];
  bool fails = false;

  @override
  Future<Either<Failure, Unit>> recordVerified(PublishTarget target) async {
    if (fails) return left(const StorageFailure('journal write'));
    recorded.add(target);
    return right(unit);
  }
}

/// Answers read-back polls from a script; records the paths it was asked for.
class _FakeVerifier implements PublishedSiteVerifier {
  _FakeVerifier(this.answer);
  final Future<List<int>?> Function(String siteUrl, String path) answer;
  final List<String> paths = [];

  @override
  Future<List<int>?> read({
    required String siteUrl,
    required String path,
    required int maxBytes,
    String? cacheBuster,
  }) {
    paths.add(path);
    return answer(siteUrl, path);
  }
}

class _FakeCreds implements PublishCredentialReader {
  _FakeCreds({this.tok = 'TKN'});
  final String? tok;

  @override
  Future<String?> token() async => tok;

  /// Deliberately NOT the target the use case is given: the use case must never
  /// read this for its destination (R1/C3).
  @override
  Future<String?> targetRepo() async => 'me/lib';
}

class _MemManifest implements PublishManifestGateway {
  _MemManifest([this._m = PublishManifest.empty]);
  final PublishManifest _m;
  PublishManifest? saved;
  bool saveFails = false;
  final List<PublishManifest> saves = [];

  /// The record a load would return right now.
  PublishManifest get current => saved ?? _m;

  @override
  PublishManifest load() => current;

  @override
  Either<Failure, Unit> save(PublishManifest m) {
    if (saveFails) return left(const StorageFailure('disk full'));
    saved = m;
    saves.add(m);
    return right(unit);
  }
}

/// S5: implements only the git-data role the use case consumes.
class _CapturingApi implements GitHubGitDataApi {
  _CapturingApi({
    this.pages = const PagesSite(
      sourceBranch: 'main',
      sourcePath: '/',
      isWorkflowBuild: false,
    ),
  });

  /// What `pagesSite()` answers (null = Pages off).
  final PagesSite? pages;

  /// The fake remote tree (R6). `make` seeds it from the gateway's record,
  /// which is the state these tests describe; a test that wants a divergent
  /// remote overwrites `treeFiles` after building the use case.
  Map<String, String> treeFiles = const {};
  String treeHead = 'HEAD';
  bool treeTruncated = false;
  bool throwOnTree = false;

  List<DesiredFile>? committed;
  List<String> deleted = [];
  String? committedBranch;
  String? committedExpectedHead;
  PublishCommitResult result = const PublishCommitSuccess('NEW', ['x']);

  @override
  Future<PagesSite?> pagesSite({
    required String owner,
    required String repo,
    required String token,
  }) async => pages;

  @override
  Future<GitHubTreeSnapshot> headTree({
    required String owner,
    required String repo,
    required String branch,
    required String token,
  }) async {
    if (throwOnTree) throw const GitHubApiException('boom');
    return GitHubTreeSnapshot(
      repo: '$owner/$repo',
      branch: branch,
      headSha: treeHead,
      files: treeFiles,
      truncated: treeTruncated,
    );
  }

  @override
  Future<PublishCommitResult> commitFiles({
    required String owner,
    required String repo,
    required String branch,
    required String token,
    required List<DesiredFile> files,
    required String commitMessage,
    required String expectedHead,
    List<String> deletePaths = const [],
  }) async {
    committed = files;
    committedBranch = branch;
    committedExpectedHead = expectedHead;
    deleted = deletePaths;
    if (expectedHead != treeHead) return const PublishCommitStale();
    treeFiles = {for (final f in files) f.path: f.gitSha};
    return result;
  }
}

void main() {
  // A manifest that "proves" a catalogue publish to me/lib.
  PublishManifest published() => const PublishManifest(
    repo: 'me/lib',
    branch: 'main',
    headSha: 'HEAD',
    fileShas: {'index.html': 'abc', 'books.json': 'def'},
  );

  EventsContent twoPosters() => EventsContent(
    posters: [
      EventPoster.create(imageRef: 'posters/a.jpg', description: 'Story')!,
      EventPoster.create(imageRef: 'posters/b.jpg')!,
    ],
  );

  Map<String, dynamic> committedEventsJson(_CapturingApi api) {
    final file = api.committed!.singleWhere((f) => f.path == 'events.json');
    return jsonDecode(utf8.decode(file.bytes)) as Map<String, dynamic>;
  }

  PublishEventsUseCase make({
    required GitHubGitDataApi api,
    required PublishManifestGateway manifest,
    PublishCredentialReader? creds,
    PosterBytesReader? readPoster,
    PublishedSiteVerifier? verifier,
    PublishHostStateRecorder? hostState,
    GitHubPublishTarget? target,
  }) {
    // R6: the fake remote starts as what this phone recorded (see the
    // catalogue suite for the same rule).
    if (api is _CapturingApi) {
      final local = manifest.load();
      api
        ..treeFiles = {...local.fileShas}
        ..treeHead = local.headSha ?? api.treeHead;
    }
    return PublishEventsUseCase(
      api: api,
      // R1/C3: the target is passed in, never re-derived inside the use case.
      target: target ?? GitHubPublishTarget.create('me/lib')!,
      credentials: creds ?? _FakeCreds(),
      manifest: manifest,
      readPoster: readPoster ?? (ref) async => ascii.encode('img:$ref'),
      buildEventsHtml: (posters) async =>
          utf8.encode('<html>${posters.length} posters</html>'),
      buildEventsJson: const EventsJsonBuilder().build,
      hostState: hostState ?? _Recorder(),
      verifier: verifier,
      sleep: (_) async {}, // no real waiting in tests
      clock: () => 1000,
    );
  }

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
      branch: 'main',
      fileShas: {'index.html': 'abc'},
    );
    final result = await make(
      api: _CapturingApi(),
      manifest: _MemManifest(otherRepo),
    ).call(twoPosters());
    expect(result, isA<PublishEventsFailure>());
  });

  test(
    'R1: the target comes from the caller, not the credential store',
    () async {
      final api = _CapturingApi();
      final manifest = _MemManifest(
        const PublishManifest(
          repo: 'me/other',
          branch: 'main',
          headSha: 'HEAD',
          fileShas: {'index.html': 'abc'},
        ),
      );
      final result = await make(
        api: api,
        manifest: manifest,
        // Deliberately different: the use case must not read this for the
        // target.
        creds: _FakeCreds(),
        target: GitHubPublishTarget.create('me/other'),
      ).call(twoPosters());

      expect(result, isA<PublishEventsSuccess>());
      expect(
        (result as PublishEventsSuccess).eventsUrl,
        'https://me.github.io/other/events.html',
      );
    },
  );

  test('publishes events.html + events.json + posters atomically', () async {
    final api = _CapturingApi();
    final manifest = _MemManifest(published());
    final result = await make(api: api, manifest: manifest).call(twoPosters());

    expect(result, isA<PublishEventsSuccess>());
    final paths = api.committed!.map((f) => f.path).toList();
    expect(
      paths,
      containsAll([
        'events.html',
        'events.json',
        'posters/a.jpg',
        'posters/b.jpg',
      ]),
    );
    expect(committedEventsJson(api), {
      'schemaVersion': 1,
      'posters': [
        {'imageRef': 'posters/a.jpg', 'description': 'Story'},
        {'imageRef': 'posters/b.jpg'},
      ],
    });
    expect(
      (result as PublishEventsSuccess).eventsUrl,
      'https://me.github.io/lib/events.html',
    );

    // Manifest is merged: the catalogue's index.html/books.json entries survive.
    expect(manifest.saved!.shaFor('index.html'), 'abc');
    expect(manifest.saved!.shaFor('books.json'), 'def');
    expect(manifest.saved!.shaFor('events.html'), isNotNull);
    expect(manifest.saved!.shaFor('events.json'), isNotNull);
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
    // The machine-readable list uses the same readability-filtered list: the
    // missing local image must not leave a broken public reference behind.
    expect(committedEventsJson(api)['posters'], [
      {'imageRef': 'posters/a.jpg', 'description': 'Story'},
    ]);
  });

  test('unchanged poster and events.json files are not re-uploaded', () async {
    final api = _CapturingApi();
    // Pre-seed exact git shas so both files are reused from the manifest.
    final aBytes = ascii.encode('img:posters/a.jpg');
    final jsonBytes = const EventsJsonBuilder().build(const [
      PublishPoster(imagePath: 'posters/a.jpg'),
    ]);
    final manifest = _MemManifest(
      PublishManifest(
        repo: 'me/lib',
        branch: 'main',
        fileShas: {
          'index.html': 'abc',
          'posters/a.jpg': GitBlobSha.of(aBytes),
          'events.json': GitBlobSha.of(jsonBytes),
        },
      ),
    );
    await make(api: api, manifest: manifest).call(
      EventsContent(posters: [EventPoster.create(imageRef: 'posters/a.jpg')!]),
    );
    final aFile = api.committed!.firstWhere((f) => f.path == 'posters/a.jpg');
    final jsonFile = api.committed!.firstWhere((f) => f.path == 'events.json');
    expect(aFile.upload, isFalse);
    expect(jsonFile.upload, isFalse);
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
          branch: 'main',
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
        branch: 'main',
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
    // Both public representations remain, with an explicit empty poster list.
    expect(api.committed!.map((f) => f.path), ['events.html', 'events.json']);
    expect(committedEventsJson(api), {
      'schemaVersion': 1,
      'posters': <Object?>[],
    });
    // Every previously published poster is deleted, but events.json is kept.
    expect(api.deleted, ['posters/a.jpg']);
    expect(manifest.saved!.shaFor('posters/a.jpg'), isNull);
    expect(manifest.saved!.shaFor('events.json'), isNotNull);
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
        branch: 'main',
        fileShas: {'index.html': 'abc'},
      );
      final result = await make(
        api: _CapturingApi(),
        manifest: _MemManifest(manifest),
        target: GitHubPublishTarget.create('me/me.github.io'),
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
        // The record describes the branch Pages serves, so the catalogue it
        // claims is on the branch this publish targets (R6).
        manifest: _MemManifest(
          const PublishManifest(
            repo: 'me/lib',
            branch: 'gh-pages',
            headSha: 'HEAD',
            fileShas: {'index.html': 'abc'},
          ),
        ),
      ).call(twoPosters());
      expect(result, isA<PublishEventsSuccess>());
      expect(api.committedBranch, 'gh-pages');
    });

    // R6, fail closed: after Pages is re-pointed, the OLD branch's record
    // proves nothing about the new one, so the catalogue gate refuses instead
    // of adding a page to a site that may not have a catalogue.
    test(
      'R6: a record from the old branch does not prove the catalogue',
      () async {
        final api = _CapturingApi(
          pages: const PagesSite(
            sourceBranch: 'gh-pages',
            sourcePath: '/',
            isWorkflowBuild: false,
          ),
        );
        final manifest = _MemManifest(published());
        final result = await make(
          api: api,
          manifest: manifest,
        ).call(twoPosters());

        expect(result, isA<PublishEventsFailure>());
        expect(
          (result as PublishEventsFailure).reason,
          contains('Publish your catalogue first'),
        );
        expect(api.committed, isNull);
      },
    );

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

  group('S4 — anchored commits and an honest record (R5/R6/R9)', () {
    test('R6: the commit is anchored to the head that was read', () async {
      final api = _CapturingApi();
      await make(
        api: api,
        manifest: _MemManifest(published()),
      ).call(twoPosters());
      expect(api.committedExpectedHead, 'HEAD');
    });

    test('R6: an unreadable remote tree refuses before any commit', () async {
      final api = _CapturingApi()..throwOnTree = true;
      final manifest = _MemManifest(published());
      final result = await make(
        api: api,
        manifest: manifest,
      ).call(twoPosters());

      expect(result, isA<PublishEventsFailure>());
      expect(
        (result as PublishEventsFailure).reason,
        gitHubSiteStateUnreadableMessage,
      );
      expect(api.committed, isNull);
      expect(manifest.saved, isNull);
    });

    // The gate is "the catalogue is on THIS site", so it must be answered by
    // the remote tree, not by a local claim.
    test(
      'R6: a claimed catalogue marker missing remotely still refuses',
      () async {
        final api = _CapturingApi();
        final manifest = _MemManifest(published());
        final useCase = make(api: api, manifest: manifest);
        // The file the record claims is not on the branch any more.
        api.treeFiles = {'books.json': 'def'};

        final result = await useCase.call(twoPosters());
        expect(result, isA<PublishEventsFailure>());
        expect(
          (result as PublishEventsFailure).reason,
          contains('Publish your catalogue first'),
        );
        expect(manifest.saved, isNull);
      },
    );

    test('R6: a stale head is a typed failure and saves nothing', () async {
      final api = _CapturingApi()..result = const PublishCommitStale();
      final manifest = _MemManifest(published());
      final result = await make(
        api: api,
        manifest: manifest,
      ).call(twoPosters());

      expect(
        (result as PublishEventsFailure).reason,
        gitHubStalePublishMessage,
      );
      expect(manifest.saved, isNull);
    });

    test('R5: read-back upgrades the record to live', () async {
      final api = _CapturingApi();
      final verifier = _FakeVerifier(
        (_, _) async =>
            api.committed!.firstWhere((f) => f.path == 'events.json').bytes,
      );
      final manifest = _MemManifest(published());
      final recorder = _Recorder();
      await make(
        api: api,
        manifest: manifest,
        verifier: verifier,
        hostState: recorder,
      ).call(twoPosters());

      expect(verifier.paths, everyElement('events.json'));
      expect(manifest.saves.map((m) => m.state), [
        PublishState.deployed,
        PublishState.live,
      ]);
      // R33: the events publish also proves the address it may claim.
      expect(recorder.recorded.single.siteUrl, 'https://me.github.io/lib/');
    });

    test('R5: an unproven read-back leaves the record deployed', () async {
      final manifest = _MemManifest(published());
      await make(
        api: _CapturingApi(),
        manifest: manifest,
        verifier: _FakeVerifier((_, _) async => null),
      ).call(twoPosters());

      expect(manifest.current.state, PublishState.deployed);
    });

    test('R9: a failed save is reported, not swallowed', () async {
      final manifest = _MemManifest(published())..saveFails = true;
      final result = await make(
        api: _CapturingApi(),
        manifest: manifest,
      ).call(twoPosters());

      expect(result, isA<PublishEventsSuccess>());
      expect((result as PublishEventsSuccess).localStateSaved, isFalse);
    });
  });
}
