import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/vault/application/lending_rules_controller.dart';
import 'package:pitaka/features/vault/domain/borrower_limit_policy.dart';
import 'package:pitaka/features/vault/domain/borrower_limit_policy_store.dart';

class _Store implements BorrowerLimitPolicyStore {
  BorrowerLimitPolicy? stored;
  Failure? readFailure;
  bool failWrites = false;
  final writes = <BorrowerLimitPolicy>[];

  @override
  Either<Failure, BorrowerLimitPolicy?> load() {
    final failure = readFailure;
    return failure == null ? Right(stored) : Left(failure);
  }

  @override
  Future<Either<Failure, Unit>> save(BorrowerLimitPolicy policy) async {
    if (failWrites) return left(const StorageFailure('write refused'));
    stored = policy;
    readFailure = null;
    writes.add(policy);
    return right(unit);
  }
}

BorrowerLimitPolicy _policy(int limit, BorrowerLimitAction action) =>
    BorrowerLimitPolicy.validate(
      maxActiveLoans: limit,
      action: action,
    ).toNullable()!;

ProviderContainer _container(_Store store) {
  final container = ProviderContainer(
    overrides: [
      borrowerLimitPolicyStoreProvider.overrideWith((ref) async => store),
    ],
  );
  // Keep the auto-dispose controller alive for notifier method tests.
  final subscription = container.listen(
    lendingRulesControllerProvider,
    (_, _) {},
  );
  addTearDown(() {
    subscription.close();
    container.dispose();
  });
  return container;
}

Future<LendingRulesController> _load(ProviderContainer container) async {
  final controller = container.read(lendingRulesControllerProvider.notifier);
  await container.read(lendingRulesControllerProvider.future);
  return controller;
}

void main() {
  test('absent storage starts with the limit off', () async {
    final container = _container(_Store());
    await _load(container);
    final policy = container.read(lendingRulesControllerProvider).value!;
    expect(policy.isOn, isFalse);
    expect(policy.action, BorrowerLimitAction.warn);
  });

  test('an unreadable document surfaces AsyncError', () async {
    final container = _container(
      _Store()..readFailure = const StorageFailure('corrupt'),
    );
    await expectLater(
      container.read(lendingRulesControllerProvider.future),
      throwsA(isA<StorageFailure>()),
    );
    expect(container.read(lendingRulesControllerProvider).hasError, isTrue);
  });

  test('successful save round-trips into state', () async {
    final store = _Store();
    final container = _container(store);
    final controller = await _load(container);
    final policy = _policy(3, BorrowerLimitAction.refuse);

    final result = await controller.save(policy);

    expect(result.isRight(), isTrue);
    expect(container.read(lendingRulesControllerProvider).value, same(policy));
    expect(store.writes, [same(policy)]);
    expect(store.stored, same(policy));
  });

  test(
    'failed save returns a failure without publishing the candidate',
    () async {
      final store = _Store()..failWrites = true;
      final container = _container(store);
      final controller = await _load(container);

      final result = await controller.save(
        _policy(2, BorrowerLimitAction.warn),
      );

      expect(result.isLeft(), isTrue);
      expect(
        container.read(lendingRulesControllerProvider).value!.isOn,
        isFalse,
      );
      expect(store.writes, isEmpty);
    },
  );

  test('save from AsyncError replaces the unreadable document', () async {
    final store = _Store()..readFailure = const StorageFailure('corrupt');
    final container = _container(store);
    final controller = container.read(lendingRulesControllerProvider.notifier);
    await expectLater(
      container.read(lendingRulesControllerProvider.future),
      throwsA(isA<StorageFailure>()),
    );

    final result = await controller.save(
      _policy(4, BorrowerLimitAction.refuse),
    );

    expect(result.isRight(), isTrue);
    final state = container.read(lendingRulesControllerProvider);
    expect(state.hasError, isFalse);
    expect(state.value!.maxActiveLoans, 4);
    expect(state.value!.action, BorrowerLimitAction.refuse);
    expect(store.readFailure, isNull);
    expect(store.writes, hasLength(1));
  });
}
