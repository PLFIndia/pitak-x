import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_content_type.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_site_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/publish_state.dart';
import 'package:pitaka/features/publish/infrastructure/file_cloudflare_manifest_store.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('pitaka_cf_manifest_');
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  FileCloudflareManifestStore store() =>
      FileCloudflareManifestStore(baseDir: dir.path);

  final target = CloudflarePublishTarget.create(
    accountId: '0123456789abcdef0123456789abcdef',
    workerName: 'pitak-library',
    accountSubdomain: 'library',
  )!;
  final manifest = CloudflareSiteManifest(
    target: target,
    state: PublishState.live,
    publishId: 'a' * 32,
    hashScheme: 'sha256-b64-ext-32',
    files: {
      'books.json': CloudflareAssetEntry(
        sha: 'books-sha',
        hash: 'b' * 32,
        size: 3,
        type: CloudflareContentType.json,
      ),
      'index.html': CloudflareAssetEntry(
        sha: 'index-sha',
        hash: 'c' * 32,
        size: 4,
        type: CloudflareContentType.html,
      ),
      'pitak-publish.json': CloudflareAssetEntry(
        sha: 'marker-sha',
        hash: 'd' * 32,
        size: 5,
        type: CloudflareContentType.json,
      ),
    },
    coverUrlByBookId: const {'42': 'https://covers.example/42.jpg'},
  );

  test('saves and loads the complete schema-2 record atomically', () {
    expect(store().save(manifest).isRight(), isTrue);

    final loaded = store().load();

    expect(loaded.describes(target), isTrue);
    expect(loaded.state, PublishState.live);
    expect(loaded.publishId, 'a' * 32);
    expect(loaded.entryFor('books.json')?.hash, 'b' * 32);
    expect(loaded.coverSourceFor('42'), 'https://covers.example/42.jpg');
    expect(
      File(
        p.join(dir.path, 'cloudflare_publish_manifest.json.tmp'),
      ).existsSync(),
      isFalse,
    );
  });

  test('a missing file is the empty record', () {
    expect(store().load().target, isNull);
    expect(store().load().ownedPaths, isEmpty);
  });

  test('a corrupt file is empty, never a partial ownership claim', () {
    File(p.join(dir.path, 'cloudflare_publish_manifest.json'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('{"schema": 2, "files": {');

    final loaded = store().load();

    expect(loaded.target, isNull);
    expect(loaded.ownedPaths, isEmpty);
  });

  test(
    'the attempted deploy lives in its own file and clears idempotently',
    () {
      final attempted = CloudflareSiteManifest(
        target: target,
        state: PublishState.deployed,
        publishId: 'b' * 32,
        hashScheme: 'sha256-b64-ext-32',
        files: manifest.files,
      );

      expect(store().savePending(attempted).isRight(), isTrue);
      expect(
        File(p.join(dir.path, 'cloudflare_publish_pending.json')).existsSync(),
        isTrue,
      );
      expect(store().loadPending().publishId, 'b' * 32);
      expect(
        store().load().target,
        isNull,
        reason: 'the live record is untouched by an attempt',
      );

      expect(store().clearPending().isRight(), isTrue);
      expect(store().loadPending().target, isNull);
      expect(
        store().clearPending().isRight(),
        isTrue,
        reason: 'clearing nothing is not a failure',
      );
    },
  );

  test('a corrupt pending file claims nothing', () {
    File(p.join(dir.path, 'cloudflare_publish_pending.json'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('not json');

    expect(store().loadPending().target, isNull);
  });

  test('a failed save is reported without exposing filesystem detail', () {
    final blocked = p.join(dir.path, 'not-a-dir');
    File(blocked).writeAsStringSync('x');

    final result = FileCloudflareManifestStore(baseDir: blocked).save(manifest);

    expect(result.isLeft(), isTrue);
    expect(result.swap().toNullable().toString(), isNot(contains(blocked)));
  });
}
