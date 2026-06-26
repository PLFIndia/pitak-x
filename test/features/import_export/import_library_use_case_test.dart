import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/import_export/application/import_library_use_case.dart';
import 'package:pitaka/features/import_export/infrastructure/import_format_sniffer.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/domain/repositories/book_repository.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';
import 'package:pitaka/features/wishlist/domain/repositories/wishlist_repository.dart';

/// In-memory fakes so the use case is tested without Drift.
class _FakeBookRepo implements BookRepository {
  final List<Book> stored = [];

  @override
  Future<Either<Failure, Book?>> findByIsbn(String isbn) async {
    final match = stored.where((b) => b.isbn == isbn).firstOrNull;
    return right(match);
  }

  @override
  Future<Either<Failure, Book>> insert(Book book) async {
    final withId = book.copyWith(id: stored.length + 1);
    stored.add(withId);
    return right(withId);
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
  Future<Either<Failure, int>> insertAll(List<Book> books) async {
    stored.addAll(books);
    return right(books.length);
  }
}

class _FakeWishlistRepo implements WishlistRepository {
  final List<WishlistBook> stored = [];

  @override
  Future<Either<Failure, WishlistBook?>> findByIsbn(String isbn) async {
    final match = stored.where((b) => b.isbn == isbn).firstOrNull;
    return right(match);
  }

  @override
  Future<Either<Failure, WishlistBook>> insert(WishlistBook book) async {
    final withId = book.copyWith(id: stored.length + 1);
    stored.add(withId);
    return right(withId);
  }

  @override
  Future<Either<Failure, WishlistBook>> upsert(WishlistBook book) async {
    final i = stored.indexWhere((b) => b.id == book.id);
    if (i >= 0) {
      stored[i] = book;
      return right(book);
    }
    return insert(book);
  }

  @override
  Future<Either<Failure, WishlistBook?>> getById(int id) async =>
      right(stored.where((b) => b.id == id).firstOrNull);
  @override
  Future<Either<Failure, WishlistBook>> update(WishlistBook book) async {
    final i = stored.indexWhere((b) => b.id == book.id);
    if (i < 0) return left(const NotFoundFailure());
    stored[i] = book;
    return right(book);
  }

  @override
  Future<Either<Failure, Unit>> delete(int id) async {
    stored.removeWhere((b) => b.id == id);
    return right(unit);
  }

  @override
  Future<Either<Failure, List<WishlistBook>>> getAll() async => right(stored);
  @override
  Future<Either<Failure, int>> insertAll(List<WishlistBook> books) async {
    stored.addAll(books);
    return right(books.length);
  }
}

void main() {
  late _FakeBookRepo bookRepo;
  late _FakeWishlistRepo wishlistRepo;
  late ImportLibraryUseCase useCase;

  setUp(() {
    bookRepo = _FakeBookRepo();
    wishlistRepo = _FakeWishlistRepo();
    useCase = ImportLibraryUseCase(
      bookRepo: bookRepo,
      wishlistRepo: wishlistRepo,
    );
  });

  ImportSummary ok(Either<Failure, ImportSummary> e) =>
      e.getOrElse((f) => fail('unexpected failure: $f'));

  String jsonWith({List<Map<String, dynamic>> books = const []}) => jsonEncode({
    'schemaVersion': 3,
    'exportedAt': 0,
    'books': books,
    'wishlist': <dynamic>[],
  });

  group('ImportLibraryUseCase', () {
    test('unrecognized format is a failure summary', () async {
      final s = ok(await useCase.importText('random text'));
      expect(s.format, isNull);
      expect(s.parseErrors, isNotEmpty);
    });

    test('detects JSON and adds books', () async {
      final s = ok(
        await useCase.importText(
          jsonWith(
            books: [
              {'title': 'A', 'isbn': '111'},
            ],
          ),
        ),
      );
      expect(s.format, ImportFormat.pitakaJson);
      expect(s.booksAdded, 1);
      expect(bookRepo.stored.single.title, 'A');
    });

    test('skips a library book whose ISBN already exists', () async {
      bookRepo.stored.add(const Book(title: 'Existing', isbn: '111', id: 1));
      final s = ok(
        await useCase.importText(
          jsonWith(
            books: [
              {'title': 'Dup', 'isbn': '111'},
              {'title': 'New', 'isbn': '222'},
            ],
          ),
        ),
      );
      expect(s.booksAdded, 1);
      expect(s.booksSkipped, 1);
    });

    test('replaces a wishlist entry on existing ISBN (latest-wins)', () async {
      wishlistRepo.stored.add(
        const WishlistBook(title: 'Old', isbn: '999', id: 5, addedDate: 100),
      );
      const goodreads =
          'Title,ISBN13,Exclusive Shelf\nNewWanted,="999",to-read';
      final s = ok(await useCase.importText(goodreads));
      expect(s.format, ImportFormat.goodreadsCsv);
      expect(s.wishlistReplaced, 1);
      expect(s.wishlistAdded, 0);
      // Same id reused; addedDate preserved; title updated.
      final row = wishlistRepo.stored.single;
      expect(row.id, 5);
      expect(row.addedDate, 100);
      expect(row.title, 'NewWanted');
    });

    test('propagates a repository failure as Left', () async {
      final failing = ImportLibraryUseCase(
        bookRepo: _FailingBookRepo(),
        wishlistRepo: wishlistRepo,
      );
      final result = await failing.importText(
        jsonWith(
          books: [
            {'title': 'A', 'isbn': '111'},
          ],
        ),
      );
      expect(result.isLeft(), isTrue);
    });
  });
}

class _FailingBookRepo implements BookRepository {
  @override
  Future<Either<Failure, Book?>> findByIsbn(String isbn) async =>
      left(const StorageFailure('boom'));
  @override
  Future<Either<Failure, Book>> insert(Book book) async =>
      left(const StorageFailure('boom'));
  @override
  Future<Either<Failure, List<Book>>> getAll() async => right(const []);
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
  Future<Either<Failure, int>> insertAll(List<Book> books) async => right(0);
}
