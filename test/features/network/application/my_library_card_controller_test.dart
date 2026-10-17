import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/network/application/build_own_descriptor.dart';
import 'package:pitaka/features/network/application/my_library_card_controller.dart';
import 'package:pitaka/features/network/domain/value_objects/library_card_payload.dart';
import 'package:pitaka/features/network/domain/value_objects/library_fingerprint.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tests for [MyLibraryCardController] (§5.8): null until published, the
/// card from identity + site URL, and the D3 promise that the raw library
/// ID never appears in the payload.
void main() {
  const rawId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  ProviderContainer containerWith(String? siteUrl) {
    final container = ProviderContainer(
      overrides: [
        publishedSiteUrlProvider.overrideWith((ref) async => siteUrl),
      ],
    );
    addTearDown(container.dispose);
    // The card controller is autoDispose: without a listener Riverpod may
    // dispose it mid-build (extra awaits on the ID-minting path), so every
    // test keeps one alive until the container dies.
    container.listen(myLibraryCardControllerProvider, (_, _) {});
    return container;
  }

  test('no card before the first publish (null, not an error)', () async {
    SharedPreferences.setMockInitialValues({'library_id': rawId});
    final container = containerWith(null);
    expect(
      await container.read(myLibraryCardControllerProvider.future),
      isNull,
    );
  });

  test('the card carries site URL, fingerprint and the library name', () async {
    SharedPreferences.setMockInitialValues({
      'library_id': rawId,
      'library_name': '  Test Lib  ',
    });
    final container = containerWith('https://me.github.io/lib/');
    final card = await container.read(myLibraryCardControllerProvider.future);
    expect(card, isNotNull);
    expect(card!.siteUrl, 'https://me.github.io/lib/');
    expect(card.fingerprint, LibraryFingerprint.of(rawId));
    expect(card.name, 'Test Lib'); // trimmed by the name rules
  });

  test('a blank name falls back to the default display name', () async {
    SharedPreferences.setMockInitialValues({'library_id': rawId});
    final container = containerWith('https://me.github.io/lib/');
    final card = await container.read(myLibraryCardControllerProvider.future);
    expect(card!.name, BuildOwnDescriptor.fallbackName);
  });

  test('a device with no stored ID gets one minted for the card', () async {
    SharedPreferences.setMockInitialValues({});
    final container = containerWith('https://me.github.io/lib/');
    final card = await container.read(myLibraryCardControllerProvider.future);
    expect(card, isNotNull);
    expect(LibraryFingerprint.isValid(card!.fingerprint), isTrue);
    // The mint went through the settings owner and landed in prefs.
    final prefs = await container.read(sharedPreferencesProvider.future);
    expect(prefs.getString('library_id'), hasLength(32));
  });

  test(
    'SECURITY: the encoded payload never contains the raw library ID',
    () async {
      SharedPreferences.setMockInitialValues({
        'library_id': rawId,
        'library_name': 'Test Lib',
      });
      final container = containerWith('https://me.github.io/lib/');
      final card = await container.read(myLibraryCardControllerProvider.future);
      final payload = LibraryCardPayload.encode(card!);
      expect(payload, isNot(contains(rawId)));
      expect(payload, contains(card.fingerprint));
      // And the payload is exactly what a scanner parses back.
      final parsed = LibraryCardPayload.parse(payload);
      expect(parsed!.fingerprint, card.fingerprint);
      expect(parsed.siteUrl, card.siteUrl);
    },
  );
}
