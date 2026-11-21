import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:image/image.dart' as img;
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/images/image_downscaler.dart';
import 'package:pitaka/features/library/application/book_cover_controller.dart';
import 'package:pitaka/features/library/application/cover_file_janitor.dart';
import 'package:pitaka/features/library/domain/catalogue_item_page.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/library_query.dart';
import 'package:pitaka/features/library/domain/repositories/catalogue_item_repository.dart';
import 'package:pitaka/features/library/infrastructure/cover_store.dart';
import 'package:pitaka/features/periodicals/domain/repositories/periodical_repository.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:pitaka/features/settings/domain/settings_repository.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';
import 'package:pitaka/features/wishlist/domain/repositories/wishlist_repository.dart';

import '../../support/detailed_test_image.dart';

/// Records update() calls; scriptable failure for the fail-closed test.
class _FakeBookRepo implements CatalogueItemRepository {
  // CatalogueItemRepository additions (review 2026-09-03): fakes default to "no
  // match" and a pass-through transaction unless a test overrides them.
  @override
  Future<Either<Failure, CatalogueItem?>> findByUid(String itemUid) async =>
      right(null);
  @override
  Future<Either<Failure, T>> runInTransaction<T>(
    Future<Either<Failure, T>> Function() action,
  ) => action();
  CatalogueItem? updated;
  Failure? failUpdateWith;

  @override
  Future<Either<Failure, CatalogueItem>> update(CatalogueItem book) async {
    final f = failUpdateWith;
    if (f != null) return left(f);
    updated = book;
    return right(book);
  }

  @override
  Future<Either<Failure, List<CatalogueItem>>> getAll() async =>
      right(updated == null ? const [] : [updated!]);
  @override
  Future<Either<Failure, List<CatalogueItem>>> getAllForInterchange() async =>
      right(updated == null ? const [] : [updated!]);
  @override
  Future<Either<Failure, CatalogueItemPage>> page(
    LibraryQuery query, {
    required int limit,
    int offset = 0,
  }) async {
    final rows = query.isSearch
        ? const <CatalogueItem>[]
        : const <CatalogueItem>[];
    final start = offset.clamp(0, rows.length);
    final end = (start + limit).clamp(start, rows.length);
    return right(
      CatalogueItemPage(
        items: rows.sublist(start, end),
        hasMore: end < rows.length,
      ),
    );
  }

  @override
  Future<Either<Failure, CatalogueItem?>> findByIsbn(String isbn) async =>
      right(null);
  @override
  Future<Either<Failure, CatalogueItem?>> getById(int id) async => right(null);
  @override
  Future<Either<Failure, List<String>>> distinctLanguages() async =>
      right(const []);
  @override
  Future<Either<Failure, List<String>>> distinctSourceDetails(
    ItemSourceType type,
  ) async => right(const []);
  @override
  Future<Either<Failure, Unit>> markRemoved(int id, int at) async =>
      right(unit);
  @override
  Future<Either<Failure, Unit>> restoreRemoved(int id) async => right(unit);
  @override
  Future<Either<Failure, Unit>> delete(int id) async => right(unit);
  @override
  Future<Either<Failure, CatalogueItem>> insert(CatalogueItem book) async =>
      right(book);
  @override
  Future<Either<Failure, int>> insertAll(List<CatalogueItem> books) async =>
      right(books.length);
  @override
  Future<Either<Failure, int>> replaceAll(List<CatalogueItem> books) async =>
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
        catalogueItemRepositoryProvider.overrideWith((ref) async => repo),
        coverStoreProvider.overrideWith((ref) async => store),
        // Real janitor over the fake repo + an empty settings fake, so the
        // orphan rule is exercised end to end against the temp directory.
        coverFileJanitorProvider.overrideWith(
          (ref) async => CoverFileJanitor(
            books: repo,
            wishlist: _NoWishlist(),
            periodicals: _NoPeriodicals(),
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

  const book = CatalogueItem(id: 7, title: 'Dune');

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

  // Decision of 2026-11-10: a photographed cover is stored at most 240×360
  // at JPEG quality 70 (`PhotoCoverRecipe`). The expectations use the plain
  // numbers on purpose, so a change of the recipe has to be made here too.
  group('stored size and quality', () {
    Future<Uint8List> storedBytes(Uint8List capture) async {
      final container = makeContainer(_FakeBookRepo());
      final result = await container
          .read(bookCoverControllerProvider.notifier)
          .replaceCover(book, capture);
      final coverRef = result.getOrElse((f) => fail('unexpected failure: $f'));
      return File('${tmp.path}/${coverRef.split('/').last}').readAsBytesSync();
    }

    test('a large capture is stored at 240x360, quality 70', () async {
      final capture = img.encodeJpg(
        detailedTestImage(width: 720, height: 1080),
      );

      final stored = await storedBytes(capture);

      final picture = img.decodeImage(stored)!;
      expect(picture.width, 240);
      expect(picture.height, 360);
      // Same picture, same settings, same bytes: this pins the quality too.
      final atQuality70 = ImageDownscaler.downscaleJpeg(
        capture,
        maxW: 240,
        maxH: 360,
        quality: 70,
      )!;
      final atDefaultQuality = ImageDownscaler.downscaleJpeg(
        capture,
        maxW: 240,
        maxH: 360,
      )!;
      expect(stored, orderedEquals(atQuality70));
      expect(
        stored,
        isNot(orderedEquals(atDefaultQuality)),
        reason: 'the test picture must tell quality 70 from the default 80',
      );
    });

    test('a wide capture is bounded by its width', () async {
      final capture = img.encodeJpg(
        detailedTestImage(width: 1080, height: 720),
      );

      final picture = img.decodeImage(await storedBytes(capture))!;

      expect(picture.width, 240);
      expect(picture.height, 160);
    });

    test('a small capture is not enlarged', () async {
      final picture = img.decodeImage(await storedBytes(validImage()))!;

      expect(picture.width, 60);
      expect(picture.height, 90);
    });

    test('EXIF, including the GPS position, is not stored', () async {
      final source = detailedTestImage(width: 720, height: 1080);
      source.exif.imageIfd[0x010F] = img.IfdValueAscii('TestMake'); // Make
      source.exif.gpsIfd[0x0002] = img.IfdValueRational(48, 1); // Latitude
      final capture = img.encodeJpg(source);
      // The test picture really carries EXIF before it is stored.
      expect(img.decodeImage(capture)!.exif.isEmpty, isFalse);

      final picture = img.decodeImage(await storedBytes(capture))!;

      expect(picture.exif.isEmpty, isTrue);
    });
  });

  // Decision Q12 (review 2026-09-03): replacing a cover must delete the
  // previous file once no row references it — orphans used to pile up
  // forever and bloat every backup.
  test('replaceCover deletes the previous, now-unreferenced cover', () async {
    final repo = _FakeBookRepo();
    final container = makeContainer(repo);
    // An existing cover file the book currently points at.
    File('${tmp.path}/old.jpg').writeAsBytesSync([1, 2, 3]);
    const withOld = CatalogueItem(
      id: 7,
      title: 'Dune',
      coverUrl: 'covers/old.jpg',
    );

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
    const withOld = CatalogueItem(
      id: 7,
      title: 'Dune',
      coverUrl: 'covers/old.jpg',
    );

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

/// No periodicals (W4: the janitor counts series cover refs as live).
class _NoPeriodicals implements PeriodicalRepository {
  @override
  Future<Either<Failure, List<PeriodicalSummary>>> listAll() async =>
      right(const []);

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
  Future<Either<Failure, Unit>> setLibrarySort(LibrarySort sort) async =>
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
  Future<Either<Failure, Unit>> setPublishLocationSharing(
    LocationSharing sharing,
  ) async => right(unit);
  @override
  Future<Either<Failure, Unit>> setNetworkMapTilesConsent({
    required bool enabled,
  }) async => right(unit);
  @override
  Future<Either<Failure, Unit>> setLibraryLogo(String reference) async =>
      right(unit);
  @override
  Future<Either<Failure, Unit>> setAppLockBiometric({
    required bool enabled,
  }) async => right(unit);

  @override
  Future<Either<Failure, Unit>> setAutoPublishAvailability({
    required bool enabled,
  }) async => right(unit);

  @override
  Future<Either<Failure, Unit>> setLookupIsbnAfterScan({
    required bool enabled,
  }) async => right(unit);
}
