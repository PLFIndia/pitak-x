import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/import_export/infrastructure/file_bundle_cover_store.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('bundle_files'));
  tearDown(() => dir.deleteSync(recursive: true));
  const id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  final bytes = Uint8List.fromList([1, 2, 3]);
  FileBundleCoverStore store() =>
      FileBundleCoverStore(coversDir: dir.path, newId: () => id);

  test(
    'fresh image preserves its suffix and never overwrites source name',
    () async {
      final original = File('${dir.path}/source.png')..writeAsBytesSync([9]);
      final batch = store().begin();
      final result = await batch.stage('source.png', bytes);
      expect(result.toNullable(), 'covers/$id.png');
      expect(File('${dir.path}/$id.png').readAsBytesSync(), bytes);
      expect(original.readAsBytesSync(), [9]);
      expect((await batch.rollback()).isRight(), isTrue);
      expect((await batch.rollback()).isRight(), isTrue);
      expect(original.readAsBytesSync(), [9]);
      expect(File('${dir.path}/$id.png').existsSync(), isFalse);
    },
  );

  for (final collision in ['file', 'directory', 'link']) {
    test('exclusive creation preserves an existing $collision', () async {
      final path = '${dir.path}/$id.jpg';
      final target = File('${dir.path}/target')..writeAsBytesSync([9]);
      if (collision == 'file') File(path).writeAsBytesSync([8]);
      if (collision == 'directory') Directory(path).createSync();
      if (collision == 'link') Link(path).createSync(target.path);
      final batch = store().begin();
      expect((await batch.stage('source.jpg', bytes)).isLeft(), isTrue);
      await batch.rollback();
      expect(
        FileSystemEntity.typeSync(path, followLinks: false),
        isNot(FileSystemEntityType.notFound),
      );
      expect(target.readAsBytesSync(), [9]);
      if (collision == 'file') expect(File(path).readAsBytesSync(), [8]);
    });
  }
  test(
    'rejects unsafe source, bad generator output and unavailable directory',
    () async {
      expect((await store().begin().stage('../x', bytes)).isLeft(), isTrue);
      final badId = FileBundleCoverStore(
        coversDir: dir.path,
        newId: () => '../bad',
      );
      expect((await badId.begin().stage('x.jpg', bytes)).isLeft(), isTrue);
      final file = File('${dir.path}/not-directory')..writeAsBytesSync([7]);
      final blocked = FileBundleCoverStore(coversDir: file.path);
      expect((await blocked.begin().stage('x.jpg', bytes)).isLeft(), isTrue);
      expect(file.readAsBytesSync(), [7]);
    },
  );
  test('retain removes only owned superseded files before commit', () async {
    final batch = store().begin();
    final first = (await batch.stage('source.png', bytes)).toNullable()!;
    final second = (await batch.stage('source.jpg', bytes)).toNullable()!;
    final existing = File('${dir.path}/keep')..writeAsBytesSync([9]);
    expect((await batch.retainOnly({second, 'covers/keep'})).isRight(), isTrue);
    batch.commit();
    expect(File('${dir.path}/${first.substring(7)}').existsSync(), isFalse);
    expect(File('${dir.path}/${second.substring(7)}').existsSync(), isTrue);
    expect(existing.readAsBytesSync(), [9]);
  });
  test('partial write is owned and removed on rollback', () async {
    final real = File('${dir.path}/$id.jpg');
    final faulty = _FaultFile(real)..failWrite = true;
    final batch = store().begin();
    await IOOverrides.runZoned(() async {
      expect((await batch.stage('source.jpg', bytes)).isLeft(), isTrue);
      expect(real.existsSync(), isTrue);
      expect((await batch.rollback()).isRight(), isTrue);
      expect(real.existsSync(), isFalse);
    }, createFile: (_) => faulty);
  });
  test(
    'failed cleanup reports failure, cleans other files and can retry',
    () async {
      final real = File('${dir.path}/$id.jpg');
      final other = File('${dir.path}/$id.png');
      final faulty = _FaultFile(real)..failDelete = true;
      final batch = store().begin();
      await IOOverrides.runZoned(() async {
        await batch.stage('source.jpg', bytes);
        await batch.stage('source.png', bytes);
        expect((await batch.rollback()).isLeft(), isTrue);
        expect(real.existsSync(), isTrue);
        expect(other.existsSync(), isFalse);
        faulty.failDelete = false;
        expect((await batch.rollback()).isRight(), isTrue);
        expect(real.existsSync(), isFalse);
      }, createFile: (path) => path == real.path ? faulty : other);
    },
  );

  test(
    'missing suffix uses a neutral suffix without changing the bytes',
    () async {
      final batch = store().begin();
      expect(
        (await batch.stage('picture', bytes)).toNullable(),
        'covers/$id.img',
      );
      await batch.rollback();
    },
  );

  test(
    'commit relinquishes ownership; later rollback cannot delete it',
    () async {
      final batch = store().begin();
      await batch.stage('source.jpg', bytes);
      batch.commit();
      await batch.rollback();
      expect(File('${dir.path}/$id.jpg').readAsBytesSync(), bytes);
      expect((await batch.stage('other.jpg', bytes)).isLeft(), isTrue);
      expect((await batch.retainOnly({})).isLeft(), isTrue);
    },
  );
}

class _FaultFile implements File {
  _FaultFile(this.real);
  final File real;
  bool failWrite = false;
  bool failDelete = false;
  @override
  Future<File> create({bool recursive = false, bool exclusive = false}) =>
      real.create(recursive: recursive, exclusive: exclusive);
  @override
  bool existsSync() => real.existsSync();
  @override
  Future<FileSystemEntity> delete({bool recursive = false}) {
    if (failDelete) throw const FileSystemException('synthetic delete failure');
    return real.delete(recursive: recursive);
  }

  @override
  Future<File> writeAsBytes(
    List<int> bytes, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) async {
    if (failWrite) {
      await real.writeAsBytes(bytes.take(1).toList());
      throw const FileSystemException('synthetic write failure');
    }
    return real.writeAsBytes(bytes, mode: mode, flush: flush);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
