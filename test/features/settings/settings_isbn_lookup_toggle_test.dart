/// Settings → Library: the ISBN-after-scan switch persists through the same
/// fixed-failure path as every other setting. Default off means no new
/// implicit lookup request after a scan.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:pitaka/features/settings/domain/settings_repository.dart';
import 'package:pitaka/features/settings/presentation/pages/settings_page.dart';
import 'package:pitaka/features/settings/presentation/settings_write.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class _LookupSettingsRepo implements SettingsRepository {
  _LookupSettingsRepo({this.failWrites = false});

  final bool failWrites;
  bool enabled = false;

  @override
  Future<AppSettings> load() async =>
      AppSettings.defaults.copyWith(lookupIsbnAfterScan: enabled);

  @override
  Future<Either<Failure, Unit>> setLookupIsbnAfterScan({
    required bool enabled,
  }) async {
    if (failWrites) return left(const StorageFailure('synthetic'));
    this.enabled = enabled;
    return right(unit);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> pumpSettings(
    WidgetTester tester,
    _LookupSettingsRepo repo,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final tmp = Directory.systemTemp.createTempSync('pitak_isbn_setting');
    addTearDown(() => tmp.deleteSync(recursive: true));
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [
        coversDirProvider.overrideWith((ref) async => tmp.path),
        settingsRepositoryProvider.overrideWith((ref) async => repo),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  Finder toggle() =>
      find.widgetWithText(SwitchListTile, 'Look up ISBN after scanning');

  testWidgets('defaults off and enabling persists through the controller', (
    tester,
  ) async {
    final repo = _LookupSettingsRepo();
    final container = await pumpSettings(tester, repo);

    expect(tester.widget<SwitchListTile>(toggle()).value, isFalse);
    await tester.tap(toggle());
    await tester.pumpAndSettle();

    expect(repo.enabled, isTrue);
    expect(tester.widget<SwitchListTile>(toggle()).value, isTrue);
    expect(
      container.read(settingsControllerProvider).value?.lookupIsbnAfterScan,
      isTrue,
    );
  });

  testWidgets('a failed write shows fixed copy and leaves the setting off', (
    tester,
  ) async {
    final repo = _LookupSettingsRepo(failWrites: true);
    final container = await pumpSettings(tester, repo);

    await tester.tap(toggle());
    await tester.pumpAndSettle();

    expect(find.text(settingsSaveFailedMessage), findsOneWidget);
    expect(repo.enabled, isFalse);
    expect(tester.widget<SwitchListTile>(toggle()).value, isFalse);
    expect(
      container.read(settingsControllerProvider).value?.lookupIsbnAfterScan,
      isFalse,
    );
  });
}
