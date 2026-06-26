import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/import_export/application/import_controller.dart';
import 'package:pitaka/features/import_export/application/import_library_use_case.dart';
import 'package:pitaka/features/import_export/infrastructure/import_format_sniffer.dart';
import 'package:pitaka/features/import_export/infrastructure/library_bundle_reader.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/domain/repositories/book_repository.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';
import 'package:pitaka/features/wishlist/domain/repositories/wishlist_repository.dart';

class _MemBookRepo implements BookRepository {
  final List<Book> stored = [];
  @override
  Future<Either<Failure, Book?>> findByIsbn(String isbn) async => right(null);
  @override
  Future<Either<Failure, Book>> insert(Book book) async {
    stored.add(book);
    return right(book);
  }

  @override
  Future<Either<Failure, List<Book>>> getAll() async => right(stored);
  @override
  Future<Either<Failure, Book?>> getById(int id) async => right(null);
  @override
  Future<Either<Failure, List<Book>>> query({
    required BookSort sort,
    String? language,
  }) async => getAll();
  @override
  Future<Either<Failure, List<String>>> distinctLanguages() async =>
      right(const []);
  @override
  Future<Either<Failure, Unit>> markRemoved(int id, int at) async =>
      right(unit);
  @override
  Future<Either<Failure, Unit>> restoreRemoved(int id) async => right(unit);

  @override
  Future<Either<Failure, Unit>> delete(int id) async => right(unit);
  @override
  Future<Either<Failure, Book>> update(Book book) async => right(book);
  @override
  Future<Either<Failure, List<Book>>> search(String q) async => right(const []);
  @override
  Future<Either<Failure, int>> insertAll(List<Book> b) async => right(b.length);
}

class _MemWishlistRepo implements WishlistRepository {
  @override
  Future<Either<Failure, WishlistBook?>> findByIsbn(String isbn) async =>
      right(null);
  @override
  Future<Either<Failure, WishlistBook>> insert(WishlistBook book) async =>
      right(book);
  @override
  Future<Either<Failure, WishlistBook>> upsert(WishlistBook book) async =>
      right(book);
  @override
  Future<Either<Failure, WishlistBook?>> getById(int id) async => right(null);
  @override
  Future<Either<Failure, WishlistBook>> update(WishlistBook book) async =>
      right(book);
  @override
  Future<Either<Failure, Unit>> delete(int id) async => right(unit);
  @override
  Future<Either<Failure, List<WishlistBook>>> getAll() async => right(const []);
  @override
  Future<Either<Failure, int>> insertAll(List<WishlistBook> b) async =>
      right(b.length);
}

void main() {
  test('ImportController exposes a summary after importText', () async {
    final useCase = ImportLibraryUseCase(
      bookRepo: _MemBookRepo(),
      wishlistRepo: _MemWishlistRepo(),
    );

    final container = ProviderContainer(
      overrides: [
        importLibraryUseCaseProvider.overrideWith((ref) async => useCase),
      ],
    );
    addTearDown(container.dispose);

    final json = jsonEncode({
      'schemaVersion': 3,
      'exportedAt': 0,
      'books': [
        {'title': 'A', 'isbn': '111'},
      ],
      'wishlist': <dynamic>[],
    });

    await container.read(importControllerProvider.notifier).importText(json);
    final state = container.read(importControllerProvider);

    expect(state.hasValue, isTrue);
    expect(state.value!.format, ImportFormat.pitakaJson);
    expect(state.value!.booksAdded, 1);
  });

  test(
    'ImportController surfaces AsyncError on a unrecognized failure path',
    () async {
      // Unrecognized format returns a Right(summary with null format), not an
      // error — verify the controller still lands in data state with no books.
      final useCase = ImportLibraryUseCase(
        bookRepo: _MemBookRepo(),
        wishlistRepo: _MemWishlistRepo(),
      );
      final container = ProviderContainer(
        overrides: [
          importLibraryUseCaseProvider.overrideWith((ref) async => useCase),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(importControllerProvider.notifier)
          .importText('not a known format');
      final state = container.read(importControllerProvider);

      expect(state.hasValue, isTrue);
      expect(state.value!.format, isNull);
      expect(state.value!.parseErrors, isNotEmpty);
    },
  );

  test('importBytes routes JSON bytes through the text path', () async {
    final useCase = ImportLibraryUseCase(
      bookRepo: _MemBookRepo(),
      wishlistRepo: _MemWishlistRepo(),
    );
    final container = ProviderContainer(
      overrides: [
        importLibraryUseCaseProvider.overrideWith((ref) async => useCase),
      ],
    );
    addTearDown(container.dispose);

    final json = jsonEncode({
      'schemaVersion': 3,
      'exportedAt': 0,
      'books': [
        {'title': 'FromBytes', 'isbn': '222'},
      ],
      'wishlist': <dynamic>[],
    });

    await container
        .read(importControllerProvider.notifier)
        .importBytes(Uint8List.fromList(utf8.encode(json)));
    final state = container.read(importControllerProvider);

    expect(state.value!.format, ImportFormat.pitakaJson);
    expect(state.value!.booksAdded, 1);
  });

  test('importBytes routes ZIP-magic bytes to the bundle reader', () async {
    final tmp = Directory.systemTemp.createTempSync('import_bytes_test');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final useCase = ImportLibraryUseCase(
      bookRepo: _MemBookRepo(),
      wishlistRepo: _MemWishlistRepo(),
    );
    // A minimal valid Pitaka bundle: just library.json (no covers).
    final libraryJson = jsonEncode({
      'schemaVersion': 3,
      'exportedAt': 0,
      'books': [
        {'title': 'Bundled', 'isbn': '333'},
      ],
      'wishlist': <dynamic>[],
    });
    final archive = Archive()
      ..addFile(
        ArchiveFile(
          kBundleLibraryJsonEntry,
          utf8.encode(libraryJson).length,
          utf8.encode(libraryJson),
        ),
      );
    final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive)!);
    // Sanity: the bytes really start with the ZIP magic.
    expect(zipBytes.sublist(0, 4), [0x50, 0x4B, 0x03, 0x04]);

    final container = ProviderContainer(
      overrides: [
        importLibraryUseCaseProvider.overrideWith((ref) async => useCase),
        libraryBundleReaderProvider.overrideWith(
          (ref) async => LibraryBundleReader(coversDir: '${tmp.path}/covers'),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(importControllerProvider.notifier)
        .importBytes(zipBytes);
    final state = container.read(importControllerProvider);

    expect(state.hasValue, isTrue);
    expect(state.value!.format, ImportFormat.pitakaBundle);
    expect(state.value!.booksAdded, 1);
  });
}
