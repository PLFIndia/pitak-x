import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/share_card_style_controller.dart';
import 'package:pitaka/features/publish/domain/share_card_style.dart';

/// In-memory store; optionally fails or throws on save.
class _MemoryStore implements ShareCardStyleStore {
  _MemoryStore({
    this.initial = ShareCardStyle.classic,
    this.failSave = false,
    this.throwOnSave = false,
  });

  final ShareCardStyle initial;
  final bool failSave;
  final bool throwOnSave;
  final saved = <ShareCardStyle>[];

  @override
  Future<ShareCardStyle> load() async => initial;

  @override
  Future<Either<Failure, Unit>> save(ShareCardStyle style) async {
    if (throwOnSave) throw StateError('plugin exploded');
    if (failSave) return left(const StorageFailure('disk said no'));
    saved.add(style);
    return right(unit);
  }
}

ProviderContainer _container(ShareCardStyleStore store) {
  final container = ProviderContainer(
    overrides: [shareCardStyleStoreProvider.overrideWith((_) async => store)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('build loads the stored style', () async {
    final container = _container(_MemoryStore(initial: ShareCardStyle.dark));
    final style = await container.read(shareCardStyleControllerProvider.future);
    expect(style, ShareCardStyle.dark);
  });

  test('select updates state immediately and persists', () async {
    final store = _MemoryStore();
    final container = _container(store);
    await container.read(shareCardStyleControllerProvider.future);

    final result = await container
        .read(shareCardStyleControllerProvider.notifier)
        .select(ShareCardStyle.framed);

    expect(result.isRight(), isTrue);
    expect(store.saved, [ShareCardStyle.framed]);
    expect(
      container.read(shareCardStyleControllerProvider).valueOrNull,
      ShareCardStyle.framed,
    );
  });

  test(
    'a failed save keeps the optimistic state and returns the left',
    () async {
      final container = _container(_MemoryStore(failSave: true));
      await container.read(shareCardStyleControllerProvider.future);

      final result = await container
          .read(shareCardStyleControllerProvider.notifier)
          .select(ShareCardStyle.gradient);

      expect(result.isLeft(), isTrue);
      // The card still renders in the chosen style — only the memory of the
      // choice is at risk, and the caller is told so via the Either.
      expect(
        container.read(shareCardStyleControllerProvider).valueOrNull,
        ShareCardStyle.gradient,
      );
    },
  );

  test(
    'a throwing store becomes a StorageFailure, never an exception',
    () async {
      final container = _container(_MemoryStore(throwOnSave: true));
      await container.read(shareCardStyleControllerProvider.future);

      final result = await container
          .read(shareCardStyleControllerProvider.notifier)
          .select(ShareCardStyle.dark);

      result.match(
        (f) => expect(f, isA<StorageFailure>()),
        (_) => fail('expected a left'),
      );
    },
  );
}
