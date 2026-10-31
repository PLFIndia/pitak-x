import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pitaka/features/publish/domain/publish_manifest.dart';
import 'package:pitaka/features/publish/domain/site/publish_state.dart';
import 'package:pitaka/features/publish/infrastructure/file_publish_manifest_store.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('pitaka_manifest_');
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  FilePublishManifestStore store() =>
      FilePublishManifestStore(baseDir: dir.path);

  test('saves and loads a schema-2 record atomically', () {
    const manifest = PublishManifest(
      repo: 'me/lib',
      branch: 'main',
      headSha: 'abc',
      ownershipConfirmed: true,
      state: PublishState.live,
      fileShas: {'books.json': 'sha'},
    );
    final saved = store().save(manifest);
    expect(saved.isRight(), isTrue);

    final loaded = store().load();
    expect(loaded.repo, 'me/lib');
    expect(loaded.branch, 'main');
    expect(loaded.headSha, 'abc');
    expect(loaded.state, PublishState.live);
    expect(loaded.ownershipConfirmed, isTrue);

    // The temp file is not state: it must not survive a successful save.
    expect(
      File(p.join(dir.path, 'publish_manifest.json.tmp')).existsSync(),
      isFalse,
    );
  });

  test('a missing file is the empty record', () {
    expect(store().load().repo, isNull);
    expect(store().load().fileShas, isEmpty);
  });

  test('a corrupt file is the empty record, never a partial one', () {
    File(p.join(dir.path, 'publish_manifest.json'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('{"repo": "me/lib", "fileShas": {');

    final loaded = store().load();
    expect(loaded.repo, isNull);
    expect(loaded.fileShas, isEmpty);
  });

  test('a schema-1 file on disk still loads (upgrade path)', () {
    File(p.join(dir.path, 'publish_manifest.json'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'repo': 'me/lib',
          'fileShas': {'books.json': 'old-sha'},
          'coverUrlByBookId': <String, String>{},
        }),
      );

    final loaded = store().load();
    expect(loaded.isLegacy, isTrue);
    expect(loaded.shaFor('books.json'), 'old-sha');
    expect(loaded.state, PublishState.deployed);
  });

  // R9: a silent save failure would tell the user "published" while the phone
  // has no record of what it wrote.
  test('a failed save is REPORTED, not swallowed', () {
    // A regular FILE where the store needs a DIRECTORY: creating the directory
    // cannot succeed, so the write cannot either. (A read-only directory is not
    // portable across the platforms this tests run on.)
    final blocked = p.join(dir.path, 'not-a-dir');
    File(blocked).writeAsStringSync('x');

    final result = FilePublishManifestStore(
      baseDir: blocked,
    ).save(const PublishManifest(repo: 'me/lib', branch: 'main'));
    expect(result.isLeft(), isTrue);
  });
}
