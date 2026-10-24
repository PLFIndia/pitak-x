import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/application/cover_file_janitor.dart';
import 'package:pitaka/features/library/domain/cover_file_coordinator.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/repositories/catalogue_item_repository.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/library/infrastructure/cover_store.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/domain/repositories/periodical_repository.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:pitaka/features/settings/domain/settings_repository.dart';
import 'package:pitaka/features/wishlist/domain/repositories/wishlist_repository.dart';

/// Minimal collaborators: just enough for each use case to reach its first
/// repository call, which proves the module handed it the right store.
class _Periodicals implements PeriodicalRepository {
  final List<String> calls = [];

  @override
  Future<Either<Failure, Periodical>> insert(Periodical periodical) async {
    calls.add('insert');
    return right(periodical.copyWith(id: 1, periodicalUid: 'uid-1'));
  }

  @override
  Future<Either<Failure, Periodical?>> findByUid(String periodicalUid) async {
    calls.add('findByUid');
    return right(null);
  }

  @override
  Future<Either<Failure, Periodical?>> getById(int id) async {
    calls.add('getById');
    return right(null);
  }

  @override
  Future<Either<Failure, List<PeriodicalSummary>>> listAll() async =>
      right(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not used here');
}

class _Items implements CatalogueItemRepository {
  final List<String> calls = [];

  @override
  Future<Either<Failure, CatalogueItem?>> getById(int id) async {
    calls.add('getById');
    return right(null);
  }

  @override
  Future<Either<Failure, T>> runInTransaction<T>(
    Future<Either<Failure, T>> Function() action,
  ) {
    calls.add('runInTransaction');
    return action();
  }

  @override
  Future<Either<Failure, List<CatalogueItem>>> getAll() async =>
      right(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not used here');
}

class _Wishlist implements WishlistRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not used here');
}

class _Settings implements SettingsRepository {
  @override
  Future<AppSettings> load() async => AppSettings.defaults;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not used here');
}

/// The periodicals DI module (plan S12): every use-case provider resolves
/// from the overridden repositories and the janitor, and reaches the store
/// it was wired to. Guards the module against a mis-wired `ref.watch`.
void main() {
  late _Periodicals periodicals;
  late _Items items;
  late Directory tmp;
  late ProviderContainer container;

  setUp(() {
    periodicals = _Periodicals();
    items = _Items();
    tmp = Directory.systemTemp.createTempSync('periodical_providers');
    container = ProviderContainer(
      overrides: [
        periodicalRepositoryProvider.overrideWith((ref) async => periodicals),
        catalogueItemRepositoryProvider.overrideWith((ref) async => items),
        coverFileJanitorProvider.overrideWith(
          (ref) async => CoverFileJanitor(
            books: items,
            wishlist: _Wishlist(),
            periodicals: periodicals,
            settings: _Settings(),
            store: CoverStore(coversDir: tmp.path),
            coordinator: CoverFileCoordinator(),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(() => tmp.deleteSync(recursive: true));
  });

  test('addPeriodicalUseCase inserts through the periodicals store', () async {
    final useCase = await container.read(addPeriodicalUseCaseProvider.future);
    final saved = await useCase(const Periodical(title: 'Chandamama'));
    expect(saved.isRight(), isTrue);
    expect(periodicals.calls, ['insert']);
  });

  test('updatePeriodicalUseCase runs in the item store transaction', () async {
    final useCase = await container.read(
      updatePeriodicalUseCaseProvider.future,
    );
    // No row behind the fake: the use case reaches the transaction, then
    // the periodicals store answers through `noSuchMethod`.
    await expectLater(
      useCase(const Periodical(id: 1, title: 'Chandamama')),
      throwsUnimplementedError,
    );
    expect(items.calls, ['runInTransaction']);
  });

  test('deletePeriodicalUseCase reads the periodicals store', () async {
    final useCase = await container.read(
      deletePeriodicalUseCaseProvider.future,
    );
    final result = await useCase(1);
    expect(result.isRight(), isTrue, reason: 'missing row → no-op');
    expect(periodicals.calls, ['getById']);
  });

  test(
    'addIssueUseCase looks the series up in the periodicals store',
    () async {
      final useCase = await container.read(addIssueUseCaseProvider.future);
      final result = await useCase(
        const CatalogueItem(
          title: '',
          details: IssueOf(periodicalUid: 'uid-x', issueNumber: 1),
        ),
      );
      expect(result.isLeft(), isTrue, reason: 'unknown series');
      expect(periodicals.calls, ['findByUid']);
    },
  );

  test('updateIssueUseCase reads the stored row from the item store', () async {
    final useCase = await container.read(updateIssueUseCaseProvider.future);
    final result = await useCase(
      const CatalogueItem(
        id: 7,
        title: '',
        details: IssueOf(periodicalUid: 'uid-x', issueNumber: 1),
      ),
    );
    expect(result.isLeft(), isTrue, reason: 'vanished row');
    expect(items.calls, ['runInTransaction', 'getById']);
  });
}
