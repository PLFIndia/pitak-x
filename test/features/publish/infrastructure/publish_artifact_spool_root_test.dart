import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/git_blob_sha.dart';
import 'package:pitaka/features/publish/domain/site/publish_file.dart';
import 'package:pitaka/features/publish/infrastructure/file_publish_artifact_store.dart';
import 'package:pitaka/features/publish/infrastructure/publish_artifact_spool_root.dart';

PublishFile _file(String path, List<int> bytes) => PublishFile(
  path: path,
  bytes: bytes,
  gitSha: GitBlobSha.of(bytes),
  upload: true,
);

void main() {
  late Directory temp;
  late Directory legacy;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pitaka_spool_temp_');
    legacy = await Directory.systemTemp.createTemp('pitaka_spool_legacy_');
  });

  tearDown(() async {
    for (final dir in [temp, legacy]) {
      if (!dir.existsSync()) continue;
      // Restore permissions a test may have tightened.
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is Directory) {
          await Process.run('chmod', ['700', entity.path]);
        }
      }
      await dir.delete(recursive: true);
    }
  });

  Directory rootOf(Directory base) =>
      Directory('${base.path}/${PublishArtifactSpoolRoot.directoryName}');

  PublishArtifactSpoolRoot rootFor({bool withLegacy = true}) =>
      PublishArtifactSpoolRoot(
        tempRoot: temp,
        legacyRoot: withLegacy ? legacy : null,
      );

  test('a stale run folder is swept from both roots', () async {
    final staleTemp = Directory('${rootOf(temp).path}/run-old')
      ..createSync(recursive: true);
    File('${staleTemp.path}/books.json').writeAsStringSync('{}');
    final staleLegacy = Directory('${rootOf(legacy).path}/run-older')
      ..createSync(recursive: true);

    final created = await rootFor().createRunDirectory();

    expect(created.isRight(), isTrue);
    expect(staleTemp.existsSync(), isFalse);
    expect(staleLegacy.existsSync(), isFalse);
    expect(created.toNullable()!.existsSync(), isTrue);
  });

  test('a live run folder is never deleted', () async {
    final root = rootFor();
    final first = (await root.createRunDirectory()).toNullable()!;
    File('${first.path}/books.json').writeAsStringSync('{}');

    final second = (await root.createRunDirectory()).toNullable()!;

    expect(first.existsSync(), isTrue, reason: 'still in use by this process');
    expect(second.existsSync(), isTrue);
    expect(first.path, isNot(second.path));

    // Once released, the next sweep may remove it.
    root.release(first);
    await root.sweep();
    expect(first.existsSync(), isFalse);
  });

  test('a run-named symlink is skipped and its target survives', () async {
    final target = Directory('${temp.path}/precious')..createSync();
    File('${target.path}/keep.txt').writeAsStringSync('keep');
    rootOf(temp).createSync(recursive: true);
    Link('${rootOf(temp).path}/run-link').createSync(target.path);

    final result = await rootFor().sweep();

    expect(result.isRight(), isTrue);
    expect(target.existsSync(), isTrue);
    expect(File('${target.path}/keep.txt').existsSync(), isTrue);
  });

  test('a symlinked root is not swept', () async {
    final elsewhere = Directory('${temp.path}/elsewhere')..createSync();
    final victim = Directory('${elsewhere.path}/run-victim')..createSync();
    Link(rootOf(temp).path).createSync(elsewhere.path);

    final result = await rootFor().sweep();

    expect(result.isRight(), isTrue);
    expect(victim.existsSync(), isTrue, reason: 'a link is never followed');
  });

  test('files and other folder names are left alone', () async {
    rootOf(temp).createSync(recursive: true);
    File('${rootOf(temp).path}/run-not-a-folder').writeAsStringSync('x');
    final other = Directory('${rootOf(temp).path}/keep-me')..createSync();

    await rootFor().sweep();

    expect(File('${rootOf(temp).path}/run-not-a-folder').existsSync(), isTrue);
    expect(other.existsSync(), isTrue);
  });

  test('a deletion error is typed and does not stop a new run', () async {
    final root = rootFor();
    final locked = Directory('${rootOf(temp).path}/run-locked')
      ..createSync(recursive: true);
    File('${locked.path}/books.json').writeAsStringSync('{}');
    await Process.run('chmod', ['500', locked.path]);

    final swept = await root.sweep();
    expect(swept.isLeft(), isTrue, reason: 'the failure is reported');

    // Cleanup is best-effort: a folder that cannot be deleted must never stop
    // a publish.
    final created = await root.createRunDirectory();
    expect(created.isRight(), isTrue);
    expect(created.toNullable()!.existsSync(), isTrue);
  });

  test('the store spools under the temporary root, not Documents', () async {
    final store = FilePublishArtifactStore(spoolRoot: rootFor());
    addTearDown(store.dispose);

    final bytes = utf8.encode('{"public":true}');
    expect((await store.spool(_file('books.json', bytes))).isRight(), isTrue);

    final runs = rootOf(temp)
        .listSync()
        .whereType<Directory>()
        .where(
          (d) => PublishArtifactSpoolRoot.runNamePattern.hasMatch(
            d.path.split('/').last,
          ),
        )
        .toList();
    expect(runs, hasLength(1));
    expect(runs.single.listSync(), isNotEmpty);
    expect(rootOf(legacy).existsSync(), isFalse, reason: 'never written to');
  });
}
