import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/platform/file_share.dart';
import 'package:pitaka/features/import_export/application/export_controller.dart';
import 'package:pitaka/features/import_export/application/export_library_use_case.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/domain/repositories/book_repository.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';
import 'package:pitaka/features/wishlist/domain/repositories/wishlist_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeShare implements FileShareService {
  @override
  Future<ShareOutcome> shareText(String text, {Rect? sharePositionOrigin}) =>
      throw UnimplementedError();

  Uint8List? bytes;
  String? fileName;
  ShareOutcome outcome = ShareOutcome.success;

  @override
  Future<ShareOutcome> shareBytes({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    Rect? sharePositionOrigin,
  }) async {
    this.bytes = bytes;
    this.fileName = fileName;
    return outcome;
  }
}

class _Books implements BookRepository {
  _Books(this._books, {this.failWith});
  final List<Book> _books;
  final Failure? failWith;

  @override
  Future<Either<Failure, List<Book>>> getAll() async =>
      failWith != null ? left(failWith!) : right(_books);
  @override
  Future<Either<Failure, List<Book>>> query({
    required BookSort sort,
    String? language,
  }) async => getAll();
  @override
  Future<Either<Failure, List<String>>> distinctLanguages() async =>
      right(const []);
  @override
  Future<Either<Failure, Book?>> getById(int id) async => right(null);
  @override
  Future<Either<Failure, Book>> insert(Book b) async => right(b);
  @override
  Future<Either<Failure, Book>> update(Book b) async => right(b);
  @override
  Future<Either<Failure, Unit>> markRemoved(int id, int at) async =>
      right(unit);
  @override
  Future<Either<Failure, Unit>> restoreRemoved(int id) async => right(unit);
  @override
  Future<Either<Failure, Unit>> delete(int id) async => right(unit);
  @override
  Future<Either<Failure, List<Book>>> search(String q) async => right(const []);
  @override
  Future<Either<Failure, Book?>> findByIsbn(String i) async => right(null);
  @override
  Future<Either<Failure, int>> insertAll(List<Book> b) async => right(b.length);
}

class _Wishlist implements WishlistRepository {
  @override
  Future<Either<Failure, WishlistBook>> insert(WishlistBook b) async =>
      right(b);
  @override
  Future<Either<Failure, WishlistBook>> upsert(WishlistBook b) async =>
      right(b);
  @override
  Future<Either<Failure, WishlistBook>> update(WishlistBook b) async =>
      right(b);
  @override
  Future<Either<Failure, WishlistBook?>> getById(int id) async => right(null);
  @override
  Future<Either<Failure, Unit>> delete(int id) async => right(unit);
  @override
  Future<Either<Failure, WishlistBook?>> findByIsbn(String i) async =>
      right(null);
  @override
  Future<Either<Failure, List<WishlistBook>>> getAll() async => right(const []);
  @override
  Future<Either<Failure, int>> insertAll(List<WishlistBook> b) async =>
      right(b.length);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  ProviderContainer makeContainer({
    required BookRepository books,
    required _FakeShare share,
  }) {
    final container = ProviderContainer(
      overrides: [
        exportLibraryUseCaseProvider.overrideWith(
          (ref) async =>
              ExportLibraryUseCase(bookRepo: books, wishlistRepo: _Wishlist()),
        ),
        fileShareServiceProvider.overrideWithValue(share),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('JSON export shares bytes and mints a library ID', () async {
    final share = _FakeShare();
    final container = makeContainer(
      books: _Books([const Book(id: 1, title: 'Godaan')]),
      share: share,
    );

    final result = await container
        .read(exportControllerProvider.notifier)
        .export(scope: ExportScope.both, format: ExportFormat.json);

    expect(result.outcome, ExportOutcome.shared);
    expect(result.fileName, endsWith('.json'));
    final payload =
        jsonDecode(utf8.decode(share.bytes!)) as Map<String, dynamic>;
    // D40: every JSON export carries a minted 32-hex library ID.
    expect(payload['libraryId'], matches(RegExp(r'^[0-9a-f]{32}$')));
  });

  test(
    'a repository failure maps to ExportOutcome.failed, nothing shared',
    () async {
      final share = _FakeShare();
      final container = makeContainer(
        books: _Books(const [], failWith: const StorageFailure('read failed')),
        share: share,
      );

      final result = await container
          .read(exportControllerProvider.notifier)
          .export(scope: ExportScope.libraryOnly, format: ExportFormat.csv);

      expect(result.outcome, ExportOutcome.failed);
      expect(share.bytes, isNull);
    },
  );

  test('a dismissed share sheet reports dismissed (not an error)', () async {
    final share = _FakeShare()..outcome = ShareOutcome.dismissed;
    final container = makeContainer(books: _Books(const []), share: share);

    final result = await container
        .read(exportControllerProvider.notifier)
        .export(scope: ExportScope.libraryOnly, format: ExportFormat.csv);

    expect(result.outcome, ExportOutcome.dismissed);
  });
}
