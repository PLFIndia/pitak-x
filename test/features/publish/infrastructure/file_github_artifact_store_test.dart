import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pitaka/features/publish/domain/git_blob_sha.dart';
import 'package:pitaka/features/publish/domain/site/publish_file.dart';
import 'package:pitaka/features/publish/infrastructure/file_github_artifact_store.dart';
import 'package:pitaka/features/publish/infrastructure/publish_artifact_spool_root.dart';

/// Review finding 6: the GitHub spool receives the produced site's bytes and
/// hands each one back for the commit, without keeping them all in memory.
void main() {
  late Directory temp;
  late PublishArtifactSpoolRoot root;
  late FileGitHubArtifactStore store;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('gh_artifact_store_');
    root = PublishArtifactSpoolRoot(tempRoot: temp);
    store = FileGitHubArtifactStore(spoolRoot: root);
  });

  tearDown(() async {
    await store.dispose();
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  PublishFile file(String path, List<int> bytes) => PublishFile(
    path: path,
    bytes: bytes,
    gitSha: GitBlobSha.of(bytes),
    upload: true,
  );

  List<Directory> runFolders() {
    final folder = Directory(
      p.join(temp.path, PublishArtifactSpoolRoot.directoryName),
    );
    if (!folder.existsSync()) return const [];
    return folder
        .listSync()
        .whereType<Directory>()
        .where(
          (d) => PublishArtifactSpoolRoot.runNamePattern.hasMatch(
            p.basename(d.path),
          ),
        )
        .toList();
  }

  test(
    'round trip: every file reopens with its exact bytes and size',
    () async {
      final books = await store.write(file('books.json', [1, 2, 3]));
      final cover = await store.write(file('covers/a.jpg', [9, 9]));
      final empty = await store.write(file('.nojekyll', const []));

      expect(books.isRight(), isTrue);
      expect(cover.isRight(), isTrue);
      expect(empty.isRight(), isTrue);
      expect(await store.read('books.json'), [1, 2, 3]);
      expect(await store.read('covers/a.jpg'), [9, 9]);
      expect(await store.read('.nojekyll'), isEmpty);
      expect(await store.read('never-written.json'), isNull);
      // One run folder for the whole operation.
      expect(runFolders(), hasLength(1));
    },
  );

  test('identical content is stored once', () async {
    await store.write(file('covers/a.jpg', [7, 7, 7]));
    await store.write(file('covers/b.jpg', [7, 7, 7]));

    expect(await store.read('covers/a.jpg'), [7, 7, 7]);
    expect(await store.read('covers/b.jpg'), [7, 7, 7]);
    final run = runFolders().single;
    expect(run.listSync().whereType<File>(), hasLength(1));
  });

  test('an unsafe path is refused and nothing is written', () async {
    final traversal = await store.write(file('../outside.json', [1]));
    final absolute = await store.write(file('/etc/passwd', [1]));

    expect(traversal.isLeft(), isTrue);
    expect(absolute.isLeft(), isTrue);
    expect(runFolders(), isEmpty);
    expect(await store.read('../outside.json'), isNull);
  });

  test('a sha that does not match the bytes is refused', () async {
    final lying = PublishFile(
      path: 'books.json',
      bytes: const [1, 2, 3],
      gitSha: GitBlobSha.of(const [4, 5, 6]),
      upload: true,
    );

    expect((await store.write(lying)).isLeft(), isTrue);
    expect(runFolders(), isEmpty);
  });

  test(
    'a damaged spooled file is never handed back as its old content',
    () async {
      await store.write(file('books.json', [1, 2, 3]));
      // e.g. a replaced temp file
      runFolders().single.listSync().whereType<File>().single.writeAsBytesSync([
        8,
        8,
        8,
      ]);

      expect(await store.read('books.json'), isNull);
    },
  );

  test(
    'dispose removes only this operation folder and is idempotent',
    () async {
      await store.write(file('books.json', [1]));
      final run = runFolders().single;

      await store.dispose();
      expect(run.existsSync(), isFalse);
      expect(await store.read('books.json'), isNull);
      // A second dispose is a no-op (and still typed as success).
      await store.dispose();
    },
  );
}
