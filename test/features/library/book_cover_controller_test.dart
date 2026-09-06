import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:image/image.dart' as img;
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/application/book_cover_controller.dart';
import 'package:pitaka/features/library/application/cover_file_janitor.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/domain/repositories/book_repository.dart';
import 'package:pitaka/features/library/infrastructure/cover_store.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:pitaka/features/settings/domain/settings_repository.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';
import 'package:pitaka/features/wishlist/domain/repositories/wishlist_repository.dart';

/// Records update() calls; scriptable failure for the fail-closed test.
class _FakeBookRepo implements BookRepository {
  // BookRepository additions (review 2026-09-03): fakes default to "no match"
  // and a pass-through transaction unless a test overrides them.
  @override
  Future<Either<Failure, Book?>> findByUid(String bookUid) async => right(null);
  @override
  Future<Either<Failure, T>> runInTransaction<T>(
    Future<Either<Failure, T>> Function() action,
  ) => action();
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
  Future<Either<Failure, List<Book>>> getAll() async =>
      right(updated == null ? const [] : [updated!]);
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
  @override
  Future<Either<Failure, int>> replaceAll(List<Book> books) async =>
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
    final store = CoverStore(coversDir: tmp.path);
    final container = ProviderContainer(
      overrides: [
        bookRepositoryProvider.overrideWith((ref) async => repo),
        coverStoreProvider.overrideWith((ref) async => store),
        // Real janitor over the fake repo + an empty settings fake, so the
        // orphan rule is exercised end to end against the temp directory.
        coverFileJanitorProvider.overrideWith(
          (ref) async => CoverFileJanitor(
            books: repo,
            wishlist: _NoWishlist(),
            settings: _NoLogoSettings(),
            store: store,
            coordinator: ref.watch(coverFileCoordinatorProvider),
          ),
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

  // Decision Q12 (review 2026-09-03): replacing a cover must delete the
  // previous file once no row references it — orphans used to pile up
  // forever and bloat every backup.
  test('replaceCover deletes the previous, now-unreferenced cover', () async {
    final repo = _FakeBookRepo();
    final container = makeContainer(repo);
    // An existing cover file the book currently points at.
    File('${tmp.path}/old.jpg').writeAsBytesSync([1, 2, 3]);
    const withOld = Book(id: 7, title: 'Dune', coverUrl: 'covers/old.jpg');

    final result = await container
        .read(bookCoverControllerProvider.notifier)
        .replaceCover(withOld, validImage());
    final coverRef = result.getOrElse((f) => fail('unexpected failure: $f'));

    expect(File('${tmp.path}/old.jpg').existsSync(), isFalse, reason: 'orphan');
    expect(
      File('${tmp.path}/${coverRef.split('/').last}').existsSync(),
      isTrue,
    );
    expect(tmp.listSync(), hasLength(1));
  });

  test('a failed replace removes the NEW file, keeps the old one', () async {
    final repo = _FakeBookRepo()
      ..failUpdateWith = const StorageFailure('disk full');
    final container = makeContainer(repo);
    File('${tmp.path}/old.jpg').writeAsBytesSync([1, 2, 3]);
    const withOld = Book(id: 7, title: 'Dune', coverUrl: 'covers/old.jpg');

    final result = await container
        .read(bookCoverControllerProvider.notifier)
        .replaceCover(withOld, validImage());

    expect(result.isLeft(), isTrue);
    expect(File('${tmp.path}/old.jpg').existsSync(), isTrue);
    expect(tmp.listSync(), hasLength(1), reason: 'no stray new file');
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

/// Settings fake with no logo (so the janitor never protects a logo file).
/// Empty wishlist (M11: the janitor counts wishlist cover refs as live).
class _NoWishlist implements WishlistRepository {
  @override
  Future<Either<Failure, List<WishlistBook>>> getAll() async => right(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not used here');
}

class _NoLogoSettings implements SettingsRepository {
  @override
  Future<AppSettings> load() async => AppSettings.defaults;
  @override
  Future<Either<Failure, Unit>> setThemeMode(AppThemeMode mode) async =>
      right(unit);
  @override
  Future<Either<Failure, Unit>> setLibraryName(String name) async =>
      right(unit);
  @override
  Future<Either<Failure, Unit>> setMaintainerName(String name) async =>
      right(unit);
  @override
  Future<Either<Failure, Unit>> setLibrarySort(BookSort sort) async =>
      right(unit);
  @override
  Future<Either<Failure, String>> getOrCreateLibraryId() async => right('');
  @override
  Future<Either<Failure, String>> regenerateLibraryId() async => right('');
  @override
  Future<Either<Failure, Unit>> setLibraryId(String id) async => right(unit);
  @override
  Future<Either<Failure, Unit>> setLoadRemoteCovers({
    required bool enabled,
  }) async => right(unit);
  @override
  Future<Either<Failure, Unit>> setPublishContact({
    required String address,
    required String gps,
    required String email,
    required String phone,
  }) async => right(unit);
  @override
  Future<Either<Failure, Unit>> setLibraryLogo(String reference) async =>
      right(unit);
  @override
  Future<Either<Failure, Unit>> setAppLockBiometric({
    required bool enabled,
  }) async => right(unit);
}
