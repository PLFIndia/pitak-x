import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pitaka/features/network/domain/repositories/published_file_cache.dart';
import 'package:pitaka/features/network/infrastructure/file_published_file_cache.dart';

/// The on-disk saved-copy store (ADR 0018), against a real temporary folder.
/// Pinned here: verified reads, identical-bytes skip, delete-on-remove and
/// orphan sweep, a corrupt index failing closed, path-safe keys, the 200 MiB
/// cap with least-recently-OPENED eviction, and "never fatal" IO.
void main() {
  const siteA = 'https://a.github.io/pitak/';
  const siteB = 'https://b.github.io/pitak/';
  const siteC = 'https://c.github.io/pitak/';
  const catalogue = PublishedFileKind.catalogue;
  const events = PublishedFileKind.events;

  late Directory root;
  late int hashCalls;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('published_copies_test');
    hashCalls = 0;
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  FilePublishedFileCache store({int maxTotalBytes = 1000}) =>
      FilePublishedFileCache(
        resolveRoot: () async => root.path,
        maxTotalBytes: maxTotalBytes,
        hash: (bytes) async {
          hashCalls++;
          return sha256.convert(bytes).toString();
        },
      );

  Uint8List bytes(int length, [int fill = 1]) =>
      Uint8List.fromList(List.filled(length, fill));

  File dataFile(String site, PublishedFileKind kind) => File(
    p.join(root.path, FilePublishedFileCache.keyFor(site), '${kind.name}.bin'),
  );

  Future<Uint8List?> readBack(
    FilePublishedFileCache cache,
    String site,
    PublishedFileKind kind,
  ) async {
    final info = await cache.info(site, kind);
    if (info == null) return null;
    return cache.readBytes(site, kind, contentHash: info.contentHash);
  }

  group('save and read', () {
    test('a saved copy round-trips with its tag, time and SHA-256', () async {
      final cache = store();
      final body = Uint8List.fromList(utf8.encode('{"schemaVersion":1}'));
      final saved = await cache.save(
        siteA,
        catalogue,
        bytes: body,
        checkedAt: 42,
        validator: '"etag-1"',
      );
      expect(saved.isRight(), isTrue);
      final info = (await cache.info(siteA, catalogue))!;
      expect(info.validator, '"etag-1"');
      expect(info.checkedAt, 42);
      expect(info.contentHash, sha256.convert(body).toString());
      expect(await readBack(cache, siteA, catalogue), body);
      expect(await cache.info(siteA, events), isNull, reason: 'own slot');
    });

    test('state survives a new store instance (it is on disk)', () async {
      await store().save(siteA, catalogue, bytes: bytes(5), checkedAt: 1);
      expect(await readBack(store(), siteA, catalogue), bytes(5));
    });

    test(
      'identical bytes are not rewritten; only tag and time change',
      () async {
        final cache = store();
        await cache.save(siteA, catalogue, bytes: bytes(5), checkedAt: 1);
        final file = dataFile(siteA, catalogue);
        final firstWrite = file.lastModifiedSync();
        await Future<void>.delayed(const Duration(milliseconds: 1100));
        await cache.save(
          siteA,
          catalogue,
          bytes: bytes(5),
          checkedAt: 2,
          validator: '"new"',
        );
        expect(file.lastModifiedSync(), firstWrite);
        final info = (await cache.info(siteA, catalogue))!;
        expect(info.checkedAt, 2);
        expect(info.validator, '"new"');
      },
    );

    test('markChecked moves the time only for the SAME copy', () async {
      final cache = store();
      await cache.save(siteA, catalogue, bytes: bytes(5), checkedAt: 1);
      final info = (await cache.info(siteA, catalogue))!;
      await cache.markChecked(
        siteA,
        catalogue,
        contentHash: 'f' * 64,
        checkedAt: 99,
      );
      expect((await cache.info(siteA, catalogue))!.checkedAt, 1);
      await cache.markChecked(
        siteA,
        catalogue,
        contentHash: info.contentHash,
        checkedAt: 99,
      );
      expect((await cache.info(siteA, catalogue))!.checkedAt, 99);
    });

    test('readBytes refuses a copy that was replaced since info()', () async {
      final cache = store();
      await cache.save(siteA, catalogue, bytes: bytes(5), checkedAt: 1);
      final old = (await cache.info(siteA, catalogue))!;
      await cache.save(siteA, catalogue, bytes: bytes(6), checkedAt: 2);
      expect(
        await cache.readBytes(siteA, catalogue, contentHash: old.contentHash),
        isNull,
      );
    });

    test('a file larger than the whole cap is refused, not saved', () async {
      final cache = store(maxTotalBytes: 10);
      final result = await cache.save(
        siteA,
        catalogue,
        bytes: bytes(11),
        checkedAt: 1,
      );
      expect(result.isLeft(), isTrue);
      expect(await cache.info(siteA, catalogue), isNull);
    });
  });

  group('verification (a damaged copy is never handed out)', () {
    test('changed bytes of the same length fail the SHA-256 check and are '
        'deleted', () async {
      final cache = store();
      await cache.save(siteA, catalogue, bytes: bytes(5), checkedAt: 1);
      final info = (await cache.info(siteA, catalogue))!;
      dataFile(siteA, catalogue).writeAsBytesSync(bytes(5, 9));
      expect(
        await cache.readBytes(siteA, catalogue, contentHash: info.contentHash),
        isNull,
      );
      expect(await cache.info(siteA, catalogue), isNull);
      expect(dataFile(siteA, catalogue).existsSync(), isFalse);
    });

    test('a truncated or missing file is reported absent by info()', () async {
      final cache = store();
      await cache.save(siteA, catalogue, bytes: bytes(5), checkedAt: 1);
      dataFile(siteA, catalogue).writeAsBytesSync(bytes(3));
      expect(await cache.info(siteA, catalogue), isNull);

      await cache.save(siteB, catalogue, bytes: bytes(5), checkedAt: 1);
      dataFile(siteB, catalogue).deleteSync();
      expect(await cache.info(siteB, catalogue), isNull);
    });

    test('an unreadable index wipes the folder and starts empty', () async {
      final cache = store();
      await cache.save(siteA, catalogue, bytes: bytes(5), checkedAt: 1);
      File(p.join(root.path, 'index.json')).writeAsStringSync('{broken');
      expect(await cache.info(siteA, catalogue), isNull);
      expect(dataFile(siteA, catalogue).existsSync(), isFalse);
      // …and keeps working afterwards.
      await cache.save(siteA, catalogue, bytes: bytes(2), checkedAt: 2);
      expect(await readBack(cache, siteA, catalogue), bytes(2));
    });

    test('a tampered index cannot point outside the folder', () async {
      final escape = Directory(p.join(root.parent.path, 'escape-target'))
        ..createSync();
      addTearDown(() {
        if (escape.existsSync()) escape.deleteSync(recursive: true);
      });
      File(p.join(root.path, 'index.json')).writeAsStringSync(
        jsonEncode({
          'version': 1,
          'libraries': {
            '../escape-target': {
              'lastOpenedAt': 1,
              'files': {
                'catalogue': {'sha256': 'a' * 64, 'size': 1, 'checkedAt': 1},
              },
            },
          },
        }),
      );
      // The bad key is dropped on decode; retainOnly sweeps only inside root.
      await store().retainOnly({});
      expect(escape.existsSync(), isTrue);
    });

    test('a malformed tag in the index is dropped with its entry', () async {
      File(p.join(root.path, 'index.json')).writeAsStringSync(
        jsonEncode({
          'version': 1,
          'libraries': {
            FilePublishedFileCache.keyFor(siteA): {
              'lastOpenedAt': 1,
              'files': {
                'catalogue': {
                  'sha256': 'a' * 64,
                  'size': 1,
                  'checkedAt': 1,
                  'validator': '"x"\r\nCookie: y',
                },
              },
            },
          },
        }),
      );
      expect(await store().info(siteA, catalogue), isNull);
    });
  });

  group('removal', () {
    test('remove deletes one kind; the last kind takes the folder', () async {
      final cache = store();
      await cache.save(siteA, catalogue, bytes: bytes(5), checkedAt: 1);
      await cache.save(siteA, events, bytes: bytes(2), checkedAt: 1);
      await cache.remove(siteA, events);
      expect(await cache.info(siteA, events), isNull);
      expect(await cache.info(siteA, catalogue), isNotNull);
      await cache.remove(siteA, catalogue);
      expect(
        Directory(
          p.join(root.path, FilePublishedFileCache.keyFor(siteA)),
        ).existsSync(),
        isFalse,
      );
    });

    test(
      'retainOnly drops unsaved libraries, orphan folders and temp files',
      () async {
        final cache = store();
        await cache.save(siteA, catalogue, bytes: bytes(5), checkedAt: 1);
        await cache.save(siteB, catalogue, bytes: bytes(5), checkedAt: 1);
        final orphan = Directory(p.join(root.path, 'b' * 64))..createSync();
        final temp = File('${dataFile(siteA, catalogue).path}.tmp')
          ..writeAsBytesSync(bytes(1));

        await cache.retainOnly({siteA});
        expect(await cache.info(siteA, catalogue), isNotNull);
        expect(await cache.info(siteB, catalogue), isNull);
        expect(dataFile(siteB, catalogue).existsSync(), isFalse);
        expect(orphan.existsSync(), isFalse);
        expect(temp.existsSync(), isFalse);
      },
    );

    test('retainOnly with nothing saved removes everything', () async {
      final cache = store();
      await cache.save(siteA, catalogue, bytes: bytes(5), checkedAt: 1);
      await cache.retainOnly({});
      expect(await cache.info(siteA, catalogue), isNull);
    });
  });

  group('size cap: least recently OPENED libraries go first', () {
    test(
      'saving over the cap evicts the oldest-opened other library',
      () async {
        final cache = store(maxTotalBytes: 100);
        await cache.save(siteA, catalogue, bytes: bytes(40), checkedAt: 10);
        await cache.save(siteB, catalogue, bytes: bytes(40), checkedAt: 20);
        // A was saved first but OPENED most recently: B is now the oldest.
        await cache.markOpened(siteA, openedAt: 30);
        await cache.save(siteC, catalogue, bytes: bytes(40), checkedAt: 40);

        expect(await cache.info(siteA, catalogue), isNotNull);
        expect(await cache.info(siteB, catalogue), isNull);
        expect(await cache.info(siteC, catalogue), isNotNull);
        expect(dataFile(siteB, catalogue).existsSync(), isFalse);
      },
    );

    test('a library counts both of its files and leaves as a whole', () async {
      final cache = store(maxTotalBytes: 100);
      await cache.save(siteA, catalogue, bytes: bytes(30), checkedAt: 1);
      await cache.save(siteA, events, bytes: bytes(30), checkedAt: 1);
      await cache.save(siteB, catalogue, bytes: bytes(50), checkedAt: 2);
      expect(await cache.info(siteA, catalogue), isNull);
      expect(await cache.info(siteA, events), isNull);
      expect(await cache.info(siteB, catalogue), isNotNull);
    });

    test('evicts only as many libraries as needed', () async {
      final cache = store(maxTotalBytes: 100);
      await cache.save(siteA, catalogue, bytes: bytes(30), checkedAt: 1);
      await cache.save(siteB, catalogue, bytes: bytes(30), checkedAt: 2);
      await cache.save(siteC, catalogue, bytes: bytes(50), checkedAt: 3);
      expect(await cache.info(siteA, catalogue), isNull);
      expect(await cache.info(siteB, catalogue), isNotNull);
    });

    test('the library being saved is never evicted for itself', () async {
      final cache = store(maxTotalBytes: 100);
      await cache.save(siteA, catalogue, bytes: bytes(60), checkedAt: 1);
      await cache.save(siteA, catalogue, bytes: bytes(90), checkedAt: 2);
      expect(await readBack(cache, siteA, catalogue), bytes(90));
    });

    test('the production cap is 200 MiB', () {
      expect(PublishedFileCache.maxTotalBytes, 200 * 1024 * 1024);
      expect(
        FilePublishedFileCache(resolveRoot: () async => '').maxTotalBytes,
        200 * 1024 * 1024,
      );
    });
  });

  group('never fatal', () {
    test('an unavailable folder degrades to "nothing saved"', () async {
      final cache = FilePublishedFileCache(
        resolveRoot: () async => throw const FileSystemException('no dir'),
      );
      expect(await cache.info(siteA, catalogue), isNull);
      expect(
        await cache.readBytes(siteA, catalogue, contentHash: 'a' * 64),
        isNull,
      );
      final saved = await cache.save(
        siteA,
        catalogue,
        bytes: bytes(1),
        checkedAt: 1,
      );
      expect(saved.isLeft(), isTrue);
      expect((await cache.markOpened(siteA, openedAt: 1)).isLeft(), isTrue);
    });

    test('a platform Error (not an Exception) while finding the folder is '
        'also "nothing saved"', () async {
      // e.g. path_provider before the binding exists: a FlutterError.
      final cache = FilePublishedFileCache(
        resolveRoot: () async => throw StateError('no binding'),
      );
      expect(await cache.info(siteA, catalogue), isNull);
      expect((await cache.retainOnly({siteA})).isLeft(), isTrue);
    });

    test(
      'markOpened for a library with nothing saved writes nothing',
      () async {
        await store().markOpened(siteA, openedAt: 1);
        expect(File(p.join(root.path, 'index.json')).existsSync(), isFalse);
      },
    );

    test('the site key is a fixed-length hex hash, never the URL', () {
      final key = FilePublishedFileCache.keyFor(siteA);
      expect(key, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(key, isNot(contains('github')));
    });

    test(
      'hashing large bytes off the UI isolate gives the same answer',
      () async {
        final big = bytes(2 * 1024 * 1024, 7);
        expect(
          await FilePublishedFileCache.sha256Hex(big),
          sha256.convert(big).toString(),
        );
        expect(hashCalls, 0, reason: 'the production hasher, not the fake');
      },
    );
  });
}
