import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/database/app_database.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/import_export/application/import_controller.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/infrastructure/drift_book_repository.dart';

Uint8List _bundle(String json) {
  final archive = Archive();
  for (final entry in {
    'library.json': utf8.encode(json),
    'cover_existing.jpg': [9, 9, 9],
  }.entries) {
    archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

void main() {
  for (final scenario in [
    'invalid JSON',
    'duplicate ISBN',
    'database rollback',
  ]) {
    test('M04: $scenario leaves existing covers untouched', () async {
      final dir = Directory.systemTemp.createTempSync('m04_safety');
      addTearDown(() => dir.deleteSync(recursive: true));
      final cover = File('${dir.path}/existing.jpg')
        ..writeAsBytesSync([1, 2, 3]);
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final books = DriftBookRepository(db);
      await books.insert(
        const Book(
          title: 'Keep',
          bookUid: 'old',
          isbn: '111',
          coverUrl: 'covers/existing.jpg',
        ),
      );
      await books.insert(const Book(title: 'Other', isbn: '999'));
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWith((ref) async => db),
          coversDirProvider.overrideWith((ref) async => dir.path),
        ],
      );
      addTearDown(container.dispose);
      final json = scenario == 'invalid JSON'
          ? '{broken'
          : jsonEncode({
              'schemaVersion': 3,
              'books': [
                {
                  'title': 'Incoming',
                  'isbn': scenario == 'duplicate ISBN' ? '111' : '222',
                  'coverUrl': 'covers/existing.jpg',
                },
                if (scenario == 'database rollback')
                  {'title': 'Collision', 'bookUid': 'old', 'isbn': '999'},
              ],
              'wishlist': <Object>[],
            });
      await container
          .read(importControllerProvider.notifier)
          .importBytes(_bundle(json));
      // The old implementation writes [9, 9, 9] before any of these outcomes.
      expect(cover.readAsBytesSync(), [1, 2, 3]);
      expect(dir.listSync().whereType<File>(), hasLength(1));
      final rows = (await books.getAll()).toNullable()!;
      expect(rows, hasLength(2));
      expect(rows.singleWhere((b) => b.bookUid == 'old').title, 'Keep');
      final state = container.read(importControllerProvider);
      if (scenario == 'duplicate ISBN') {
        expect(state.requireValue!.booksSkipped, 1);
      } else {
        expect(state.hasError, isTrue);
      }
    });
  }
}
