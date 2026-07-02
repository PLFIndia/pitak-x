import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:image/image.dart' as img;
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/application/book_cover_controller.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/domain/repositories/book_repository.dart';
import 'package:pitaka/features/library/infrastructure/cover_store.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';

/// Records update() calls; scriptable failure for the fail-closed test.
class _FakeBookRepo implements BookRepository {
  Book? updated;
  Failure? failUpdateWith;

  @override
  Future<Either<Failure, Book>> update(Book book) async {
    final f = failUpdateWith;
    if (f != null) return left(f);
    updated = book;
    return right(book);
  }

  @override
  Future<Either<Failure, List<Book>>> getAll() async => right(const []);
  @override
  Future<Either<Failure, List<Book>>> query({
    required BookSort sort,
    String? language,
  }) async => right(const []);
  @override
  Future<Either<Failure, List<Book>>> search(String query) async =>
      right(const []);
  @override
  Future<Either<Failure, Book?>> findByIsbn(String isbn) async => right(null);
  @override
  Future<Either<Failure, Book?>> getById(int id) async => right(null);
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
  Future<Either<Failure, Book>> insert(Book book) async => right(book);
  @override
  Future<Either<Failure, int>> insertAll(List<Book> books) async =>
      right(books.length);
}

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('cover_ctrl_test');
  });
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Uint8List validImage() =>
      Uint8List.fromList(img.encodePng(img.Image(width: 60, height: 90)));

  ProviderContainer makeContainer(_FakeBookRepo repo) {
    final container = ProviderContainer(
      overrides: [
        bookRepositoryProvider.overrideWith((ref) async => repo),
        coverStoreProvider.overrideWith(
          (ref) async => CoverStore(coversDir: tmp.path),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  const book = Book(id: 7, title: 'Dune');

  test('replaceCover stores the JPEG and persists the reference', () async {
    final repo = _FakeBookRepo();
    final container = makeContainer(repo);

    final result = await container
        .read(bookCoverControllerProvider.notifier)
        .replaceCover(book, validImage());

    final coverRef = result.getOrElse((f) => fail('unexpected failure: $f'));
    expect(coverRef, startsWith('covers/'));
    expect(repo.updated?.coverUrl, coverRef);
    // The file exists on disk.
    final leaf = coverRef.split('/').last;
    expect(File('${tmp.path}/$leaf').existsSync(), isTrue);
  });

  test('undecodable bytes → ValidationFailure, nothing persisted', () async {
    final repo = _FakeBookRepo();
    final container = makeContainer(repo);

    final result = await container
        .read(bookCoverControllerProvider.notifier)
        .replaceCover(book, Uint8List.fromList([1, 2, 3]));

    result.match(
      (f) => expect(f, isA<ValidationFailure>()),
      (_) => fail('expected a failure'),
    );
    expect(repo.updated, isNull);
    expect(tmp.listSync(), isEmpty);
  });

  test('repository failure is surfaced, not swallowed (§5)', () async {
    final repo = _FakeBookRepo()
      ..failUpdateWith = const StorageFailure('disk full');
    final container = makeContainer(repo);

    final result = await container
        .read(bookCoverControllerProvider.notifier)
        .replaceCover(book, validImage());

    result.match(
      (f) => expect(f, isA<StorageFailure>()),
      (_) => fail('expected a failure'),
    );
  });
}
