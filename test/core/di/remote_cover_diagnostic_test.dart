import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/application/cover_file_janitor.dart';
import 'package:pitaka/features/library/domain/cover_owner.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/repositories/catalogue_item_repository.dart';
import 'package:pitaka/features/library/infrastructure/cover_store.dart';
import 'package:pitaka/features/periodicals/domain/repositories/periodical_repository.dart';
import 'package:pitaka/features/publish/domain/cover_fetch_result.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:pitaka/features/settings/domain/settings_repository.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';
import 'package:pitaka/features/wishlist/domain/repositories/wishlist_repository.dart';

/// N08 / N11 D4-b: the composition root wires the refused-cover diagnostic.
/// This exercises the REAL `materializeRemoteCoverUseCaseProvider` with only
/// the network port replaced, and captures `debugPrint` to prove the line
/// carries the typed owner + reason and NOT the URL (AGENTS.md §6.2).
void main() {
  const url = 'https://covers.openlibrary.org/b/id/424242-L.jpg';
  late Directory tmp;
  late List<String> printed;
  late DebugPrintCallback previous;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('remote_cover_diag');
    printed = [];
    previous = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) printed.add(message);
    };
  });
  tearDown(() {
    debugPrint = previous;
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  ProviderContainer make(_OneBookRepo repo, CoverFetchResult outcome) {
    final store = CoverStore(coversDir: tmp.path);
    final container = ProviderContainer(
      overrides: [
        catalogueItemRepositoryProvider.overrideWith((ref) async => repo),
        periodicalRepositoryProvider.overrideWith(
          (ref) async => _NoPeriodicals(),
        ),
        coverStoreProvider.overrideWith((ref) async => store),
        coverFileJanitorProvider.overrideWith(
          (ref) async => CoverFileJanitor(
            books: repo,
            wishlist: _NoWishlist(),
            periodicals: _NoPeriodicals(),
            settings: _NoSettings(),
            store: store,
            coordinator: ref.watch(coverFileCoordinatorProvider),
          ),
        ),
        boundedCoverDownloadProvider.overrideWithValue((_) async => outcome),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('a refusal logs the item owner and reason, never the URL', () async {
    final repo = _OneBookRepo(
      const CatalogueItem(id: 42, title: 'Dune', coverUrl: url),
    );
    final c = make(repo, const CoverRefused(CoverRefusal.redirectRefused));

    final useCase = await c.read(materializeRemoteCoverUseCaseProvider.future);
    final result = await useCase(CoverOwners.item(42), url);

    expect(result.isLeft(), isTrue);
    expect(printed, hasLength(1));
    expect(printed.single, contains('42'));
    expect(printed.single, contains('redirectRefused'));
    expect(printed.single, isNot(contains('openlibrary')));
    expect(printed.single, isNot(contains('424242')));
    expect(printed.single, isNot(contains('https')));
  });

  test('a successful download logs nothing', () async {
    final repo = _OneBookRepo(
      const CatalogueItem(id: 42, title: 'Dune', coverUrl: url),
    );
    final c = make(repo, const CoverFetched([1, 2, 3]));

    final useCase = await c.read(materializeRemoteCoverUseCaseProvider.future);
    final result = await useCase(CoverOwners.item(42), url);

    expect(result.isRight(), isTrue);
    expect(printed, isEmpty);
  });

  test('the publish-side port still yields bytes-or-null', () async {
    final refused = ProviderContainer(
      overrides: [
        boundedCoverDownloadProvider.overrideWithValue(
          (_) async => const CoverRefused(CoverRefusal.tooLarge),
        ),
      ],
    );
    addTearDown(refused.dispose);
    expect(await refused.read(remoteCoverFetcherProvider)(url), isNull);

    final fetched = ProviderContainer(
      overrides: [
        boundedCoverDownloadProvider.overrideWithValue(
          (_) async => const CoverFetched([9, 9]),
        ),
      ],
    );
    addTearDown(fetched.dispose);
    expect(await fetched.read(remoteCoverFetcherProvider)(url), [9, 9]);
  });
}

class _OneBookRepo implements CatalogueItemRepository {
  _OneBookRepo(this.book);
  CatalogueItem book;

  @override
  Future<Either<Failure, CatalogueItem?>> getById(int id) async =>
      right(id == book.id ? book : null);

  @override
  Future<Either<Failure, CatalogueItem>> update(CatalogueItem b) async {
    book = b;
    return right(b);
  }

  @override
  Future<Either<Failure, List<CatalogueItem>>> getAll() async => right([book]);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not used here');
}

class _NoWishlist implements WishlistRepository {
  @override
  Future<Either<Failure, List<WishlistBook>>> getAll() async => right(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not used here');
}

class _NoPeriodicals implements PeriodicalRepository {
  @override
  Future<Either<Failure, List<PeriodicalSummary>>> listAll() async =>
      right(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not used here');
}

class _NoSettings implements SettingsRepository {
  @override
  Future<AppSettings> load() async => AppSettings.defaults;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not used here');
}
