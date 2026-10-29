import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/publish_library_use_case.dart'
    show PublishManifestGateway;
import 'package:pitaka/features/publish/application/site/publish_host_state_repository.dart';
import 'package:pitaka/features/publish/domain/git_blob_sha.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/publish_host.dart';
import 'package:pitaka/features/publish/domain/site/publish_host_state.dart';
import 'package:pitaka/features/publish/domain/site/published_site_verifier.dart';

class _Store implements PublishHostStateStore {
  _Store([this.stored]);
  PublishHostState? stored;
  bool fails = false;
  int saves = 0;

  @override
  Either<Failure, PublishHostState?> load() => right(stored);

  @override
  Future<Either<Failure, Unit>> save(PublishHostState state) async {
    saves++;
    if (fails) return left(const StorageFailure('prefs'));
    stored = state;
    return right(unit);
  }

  @override
  Future<Either<Failure, Unit>> clearUnreadable() async {
    if (load() is Right) {
      return left(const ValidationFailure('readable'));
    }
    stored = null;
    return right(unit);
  }
}

class _Manifest implements PublishManifestGateway {
  _Manifest([this.record = PublishManifest.empty]);
  PublishManifest record;

  @override
  PublishManifest load() => record;

  @override
  Either<Failure, Unit> save(PublishManifest manifest) => right(unit);
}

class _Verifier implements PublishedSiteVerifier {
  _Verifier(this.answer);
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

void main() {
  final github = GitHubPublishTarget.create('me/lib')!;

  PublishHostStateRepository repository({
    required PublishHostStateStore store,
    PublishManifest manifest = PublishManifest.empty,
    PublishedSiteVerifier? verifier,
  }) => PublishHostStateRepository(
    store: store,
    manifest: _Manifest(manifest),
    verifier: verifier ?? _Verifier((_, _) async => null),
  );

  group('recordVerified', () {
    test('writes the active host and the verified address', () async {
      final store = _Store();
      final result = await repository(store: store).recordVerified(github);

      expect(result.isRight(), isTrue);
      expect(store.stored!.activeHost, github.host);
      expect(store.stored!.verifiedSiteUrl, 'https://me.github.io/lib/');
    });

    test('an already-verified target is not rewritten', () async {
      final store = _Store(PublishHostState.empty.afterVerifiedPublish(github));
      final result = await repository(store: store).recordVerified(github);

      expect(result.isRight(), isTrue);
      expect(store.saves, 0);
    });

    test('a failed write is returned, not swallowed', () async {
      final store = _Store()..fails = true;
      final result = await repository(store: store).recordVerified(github);
      expect(result.isLeft(), isTrue);
    });
  });

  group('verifiedSiteUrl (E.5 migration)', () {
    test('a stored journal answers without touching the network', () async {
      final verifier = _Verifier((_, _) async => fail('must not fetch'));
      final url = await repository(
        store: _Store(PublishHostState.empty.afterVerifiedPublish(github)),
        verifier: verifier,
      ).verifiedSiteUrl();

      expect(url, 'https://me.github.io/lib/');
      expect(verifier.calls, isEmpty);
    });

    test('a journal that proves nothing returns no address', () async {
      final url = await repository(
        store: _Store(PublishHostState.empty),
      ).verifiedSiteUrl();
      expect(url, isNull);
    });

    // R33: a legacy manifest is NOT proof. One bounded read-back decides.
    test(
      'a legacy manifest whose file is served migrates the address',
      () async {
        final bytes = utf8.encode('{"books":[]}');
        final store = _Store();
        final verifier = _Verifier((siteUrl, path) async {
          expect(siteUrl, 'https://me.github.io/lib/');
          expect(path, PublishHostStateRepository.proofPath);
          return bytes;
        });
        final url = await repository(
          store: store,
          manifest: PublishManifest(
            repo: 'me/lib',
            fileShas: {
              PublishHostStateRepository.proofPath: GitBlobSha.of(bytes),
            },
          ),
          verifier: verifier,
        ).verifiedSiteUrl();

        expect(url, 'https://me.github.io/lib/');
        expect(store.stored!.activeHost, github.host);
        expect(store.stored!.verifiedSiteUrl, 'https://me.github.io/lib/');
        expect(verifier.calls, hasLength(1));
      },
    );

    test('a legacy manifest whose file differs yields no address', () async {
      final store = _Store();
      final url = await repository(
        store: store,
        manifest: const PublishManifest(
          repo: 'me/lib',
          fileShas: {'books.json': 'a-different-sha'},
        ),
        verifier: _Verifier((_, _) async => utf8.encode('{"books":[]}')),
      ).verifiedSiteUrl();

      expect(url, isNull);
      // The host is recorded (a GitHub target exists); the proof is not.
      expect(store.stored!.activeHost, github.host);
      expect(store.stored!.verifiedTarget, isNull);
    });

    test('an unreachable site yields no address', () async {
      final url = await repository(
        store: _Store(),
        manifest: const PublishManifest(
          repo: 'me/lib',
          fileShas: {'books.json': 'sha'},
        ),
        verifier: _Verifier((_, _) async => null),
      ).verifiedSiteUrl();

      expect(url, isNull);
    });

    test('no manifest at all means no migration attempt', () async {
      final verifier = _Verifier((_, _) async => fail('must not fetch'));
      final url = await repository(
        store: _Store(),
        verifier: verifier,
      ).verifiedSiteUrl();

      expect(url, isNull);
      expect(verifier.calls, isEmpty);
    });
  });

  group('ensureActiveHost (S7 setup)', () {
    test(
      'sets only the host when unset, never a verified-live pointer',
      () async {
        final store = _Store();
        final result = await repository(
          store: store,
        ).ensureActiveHost(PublishHost.cloudflare);

        expect(result.isRight(), isTrue);
        expect(store.stored?.activeHost, PublishHost.cloudflare);
        expect(store.stored?.verifiedTarget, isNull);
      },
    );

    test('preserves an existing GitHub active and verified target', () async {
      final journal = PublishHostState.empty.afterVerifiedPublish(github);
      final store = _Store(journal);
      final result = await repository(
        store: store,
      ).ensureActiveHost(PublishHost.cloudflare);

      expect(result.isRight(), isTrue);
      expect(store.stored, same(journal));
      expect(store.saves, 0);
    });

    test('returns a failed journal write', () async {
      final store = _Store()..fails = true;
      final result = await repository(
        store: store,
      ).ensureActiveHost(PublishHost.cloudflare);
      expect(result.isLeft(), isTrue);
    });

    test(
      'legacy GitHub default blocks a switch without bypassing migration',
      () async {
        final bytes = utf8.encode('{"books":[]}');
        final store = _Store();
        final verifier = _Verifier((_, _) async => bytes);
        final repo = repository(
          store: store,
          manifest: PublishManifest(
            repo: 'me/lib',
            fileShas: {
              PublishHostStateRepository.proofPath: GitBlobSha.of(bytes),
            },
          ),
          verifier: verifier,
        );

        final result = await repo.ensureActiveHost(PublishHost.cloudflare);
        expect(result.isRight(), isTrue);
        expect(store.saves, 0);
        expect(store.stored, isNull);
        expect(repo.currentState()?.activeHost, PublishHost.github);
        expect(repo.currentState()?.verifiedTarget, isNull);

        // The unpersisted default leaves the raw journal absent, so the normal
        // read-back-gated migration still runs and can later prove the address.
        final url = await repo.verifiedSiteUrl();
        expect(url, 'https://me.github.io/lib/');
        expect(verifier.calls, hasLength(1));
        expect(store.stored?.activeHost, PublishHost.github);
        expect(store.stored?.verifiedTarget?.targetId, github.targetId);
      },
    );

    test('currentState performs no migration read-back', () async {
      final verifier = _Verifier((_, _) async => fail('must not fetch'));
      final store = _Store(PublishHostState.empty);
      final current = repository(
        store: store,
        verifier: verifier,
      ).currentState();
      expect(current, same(store.stored));
      expect(verifier.calls, isEmpty);
    });
  });
}
