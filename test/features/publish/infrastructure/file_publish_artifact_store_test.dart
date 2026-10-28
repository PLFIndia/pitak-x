import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_models.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_asset_hash.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_limits.dart';
import 'package:pitaka/features/publish/domain/git_blob_sha.dart';
import 'package:pitaka/features/publish/domain/site/publish_file.dart';
import 'package:pitaka/features/publish/infrastructure/file_publish_artifact_store.dart';

PublishFile _file(String path, List<int> bytes, {String? sha}) => PublishFile(
  path: path,
  bytes: bytes,
  gitSha: sha ?? GitBlobSha.of(bytes),
  upload: true,
);

Future<List<int>> _readAll(CloudflareBucketAsset asset) async {
  final output = BytesBuilder(copy: false);
  await for (final chunk in asset.openValidated()) {
    expect(
      chunk.length,
      lessThanOrEqualTo(CloudflareLimits.maxArtifactChunkBytes),
    );
    output.add(chunk);
  }
  return output.takeBytes();
}

void main() {
  late Directory dir;
  late FilePublishArtifactStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('pitaka_s8_spool_');
    store = FilePublishArtifactStore(baseDir: dir.path);
  });

  tearDown(() async {
    await store.dispose();
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  test('spools validated metadata and reopens exact bounded streams', () async {
    final bytes = List<int>.generate(150000, (i) => i % 251);
    final result = await store.spool(_file('covers/a.jpg', bytes));

    expect(result.isRight(), isTrue);
    final asset = result.toNullable()!;
    expect(asset.entry.hash, CloudflareAssetHash.of(bytes, 'jpg'));
    expect(asset.entry.size, bytes.length);
    expect(store.spooledRawBytes, bytes.length);
    expect(await _readAll(asset.bucketAsset), bytes);
    // A retry gets a fresh stream, not the already-consumed one.
    expect(await _readAll(asset.bucketAsset), bytes);
  });

  test('identical bytes plus extension share one stored source', () async {
    final bytes = utf8.encode('{"same":true}');
    final first = (await store.spool(_file('books.json', bytes))).toNullable()!;
    final second = (await store.spool(
      _file('library.json', bytes),
    )).toNullable()!;

    expect(first.entry.hash, second.entry.hash);
    expect(identical(first.bucketAsset, second.bucketAsset), isTrue);
    expect(store.spooledRawBytes, bytes.length);
  });

  test(
    'unsafe paths, types, sizes, and content identities fail closed',
    () async {
      final bytes = utf8.encode('x');
      for (final file in [
        _file('../escape.json', bytes),
        _file('unknown.json', bytes),
        _file('books.json', bytes, sha: 'not-the-content-sha'),
      ]) {
        expect((await store.spool(file)).isLeft(), isTrue, reason: file.path);
      }
      expect(store.spooledRawBytes, 0);
    },
  );

  test('dispose removes only the operation spool and is idempotent', () async {
    await store.spool(_file('books.json', utf8.encode('{}')));
    final root = Directory('${dir.path}/publish_artifacts');
    expect(root.existsSync(), isTrue);

    expect((await store.dispose()).isRight(), isTrue);

    expect(root.listSync(), isEmpty);
    expect(store.spooledRawBytes, 0);
    expect((await store.dispose()).isRight(), isTrue);
  });
}
