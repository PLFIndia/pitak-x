import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/infrastructure/cover_store.dart';
import 'package:pitaka/features/settings/application/library_logo_controller.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';
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
    final container = ProviderContainer(
      overrides: [
        coverStoreProvider.overrideWith(
          (ref) async => CoverStore(coversDir: tmp.path),
        ),
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
