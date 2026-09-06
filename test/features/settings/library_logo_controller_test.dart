import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:image/image.dart' as img;
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/application/cover_file_janitor.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/domain/repositories/book_repository.dart';
import 'package:pitaka/features/library/infrastructure/cover_store.dart';
import 'package:pitaka/features/settings/application/library_logo_controller.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';
import 'package:pitaka/features/wishlist/domain/repositories/wishlist_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('logo_ctrl_test');
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Uint8List validImage() =>
      Uint8List.fromList(img.encodePng(img.Image(width: 64, height: 64)));

  ProviderContainer makeContainer() {
    final store = CoverStore(coversDir: tmp.path);
    final container = ProviderContainer(
      overrides: [
        coverStoreProvider.overrideWith((ref) async => store),
        // Janitor over an EMPTY book repo (no covers reference anything) and
        // the real prefs-backed settings, so the logo rule is exercised.
        coverFileJanitorProvider.overrideWith((ref) async {
          final settings = await ref.watch(settingsRepositoryProvider.future);
          return CoverFileJanitor(
            books: _NoBooks(),
            wishlist: _NoWishlist(),
            settings: settings,
            store: store,
            coordinator: ref.watch(coverFileCoordinatorProvider),
          );
        }),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('setLogo stores the image and persists the reference', () async {
    final container = makeContainer();
    await container.read(settingsControllerProvider.future);

    final result = await container
        .read(libraryLogoControllerProvider.notifier)
        .setLogo(validImage());

    final reference = result.getOrElse((f) => fail('unexpected failure: $f'));
    expect(reference, startsWith('covers/'));
    final settings = container.read(settingsControllerProvider).requireValue;
    expect(settings.libraryLogo, reference);
  });

  test('undecodable bytes → ValidationFailure, settings untouched', () async {
    final container = makeContainer();
    await container.read(settingsControllerProvider.future);

    final result = await container
        .read(libraryLogoControllerProvider.notifier)
        .setLogo(Uint8List.fromList([9, 9]));

    result.match(
      (f) => expect(f, isA<ValidationFailure>()),
      (_) => fail('expected a failure'),
    );
    final settings = container.read(settingsControllerProvider).requireValue;
    expect(settings.libraryLogo, isEmpty);
    expect(tmp.listSync(), isEmpty);
  });

  test('clearLogo empties the stored reference', () async {
    final container = makeContainer();
    await container.read(settingsControllerProvider.future);
    await container
        .read(libraryLogoControllerProvider.notifier)
        .setLogo(validImage());

    final result = await container
        .read(libraryLogoControllerProvider.notifier)
        .clearLogo();

    expect(result.isRight(), isTrue);
    final settings = container.read(settingsControllerProvider).requireValue;
    expect(settings.libraryLogo, isEmpty);
  });
}

/// Book repo with no rows (nothing references any cover file).
/// Empty wishlist (M11: the janitor counts wishlist cover refs as live).
class _NoWishlist implements WishlistRepository {
  @override
  Future<Either<Failure, List<WishlistBook>>> getAll() async => right(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not used here');
}

class _NoBooks implements BookRepository {
  @override
  Future<Either<Failure, List<Book>>> getAll() async => right(const []);
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not used here');
}
