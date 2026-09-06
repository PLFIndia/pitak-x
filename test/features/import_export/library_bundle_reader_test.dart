import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/import_export/infrastructure/library_bundle_reader.dart';

Uint8List _zip(Map<String, List<int>> entries) {
  final archive = Archive();
  entries.forEach(
    (name, data) => archive.addFile(ArchiveFile(name, data.length, data)),
  );
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

void main() {
  const reader = LibraryBundleReader();
  test(
    'reads Unicode metadata and image bytes without filesystem access',
    () async {
      final result = await reader.read(
        _zip({
          'library.json': utf8.encode(
            jsonEncode({
              'schemaVersion': 3,
              'books': [
                {'title': 'गोदान', 'coverUrl': 'covers/uuid-1.jpg'},
              ],
              'wishlist': <Object>[],
            }),
          ),
          'cover_uuid-1.jpg': [9, 9, 9],
        }),
      );
      final bundle = result.toNullable()!;
      expect(bundle.payload.books.single.title, 'गोदान');
      expect(bundle.payload.books.single.coverUrl, 'covers/uuid-1.jpg');
      expect(bundle.covers['uuid-1.jpg'], [9, 9, 9]);
    },
  );

  for (final json in [
    '{broken',
    '[]',
    '{}',
    '{"books":null}',
    '{"books":"bad"}',
    '{"books":[7]}',
    '{"books":[],"wishlist":[null]}',
    '{"schemaVersion":999,"books":[]}',
    '{"books":[{"title":"A","coverUrl":"covers/missing.jpg"}]}',
    '{"wishlist":[{"title":"A","coverUrl":"file:///old/missing.jpg"}]}',
    '{"books":[{"title":"A","coverUrl":"covers/../bad.jpg"}]}',
  ]) {
    test('rejects invalid catalogue: $json', () async {
      final result = await reader.read(
        _zip({'library.json': utf8.encode(json)}),
      );
      expect(result.swap().toNullable(), isA<BackupCorruptFailure>());
    });
  }

  test('rejects unreferenced image entries', () async {
    final result = await reader.read(
      _zip({
        'library.json': utf8.encode('{"books":[]}'),
        'cover_unowned.jpg': [1],
      }),
    );
    expect(result.isLeft(), isTrue);
  });

  test('accepts a valid empty catalogue', () async {
    final result = await reader.read(
      _zip({'library.json': utf8.encode('{"books":[],"wishlist":[]}')}),
    );
    expect(result.toNullable()!.payload.isEmpty, isTrue);
    expect(result.toNullable()!.covers, isEmpty);
  });

  test(
    'rejects malformed UTF-8 rather than silently altering metadata',
    () async {
      expect(
        (await reader.read(
          _zip({
            'library.json': [0xff],
          }),
        )).isLeft(),
        isTrue,
      );
    },
  );

  test('fails closed when library.json is missing', () async {
    expect(
      (await reader.read(
        _zip({
          'cover_x.jpg': [1],
        }),
      )).swap().toNullable(),
      isA<BackupCorruptFailure>(),
    );
  });

  test('maps a hostile/corrupt archive to a safe failure', () async {
    final result = await reader.read(Uint8List.fromList([0, 1, 2]));
    expect(result.swap().toNullable(), isA<BackupCorruptFailure>());
  });
}
