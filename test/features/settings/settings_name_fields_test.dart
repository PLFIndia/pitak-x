/// Review item 14, Settings side: the Library/Maintainer name fields await
/// the persisted write through the fixed-failure helper. A failed save shows
/// the fixed sentence and keeps the editor open; it never displays the
/// unsaved name as the saved one. Same page setup as
/// `settings_initial_tab_test.dart`.
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

final class _NameRepo implements SettingsRepository {
  _NameRepo({this.failNameWrites = false});

  final bool failNameWrites;
  String libraryName = 'Old Shelf';
  final List<String> nameWrites = [];

  @override
  Future<AppSettings> load() async =>
      AppSettings.defaults.copyWith(libraryName: libraryName);

  @override
  Future<Either<Failure, Unit>> setLibraryName(String name) async {
    nameWrites.add(name);
    if (failNameWrites) return left(const StorageFailure('synthetic'));
    libraryName = name;
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
    _NameRepo repo,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final tmp = Directory.systemTemp.createTempSync('pitak_settings_names');
    addTearDown(() => tmp.deleteSync(recursive: true));
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
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

  /// Opens the Library name editor (the first Edit on the Appearance tab).
  Future<void> editLibraryName(WidgetTester tester, String text) async {
    await tester.tap(find.text('Edit').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, text);
    // Only the editor's own check: the tab has another check icon elsewhere.
    await tester.tap(
      find.descendant(
        of: find.byType(TextField).first,
        matching: find.byIcon(Icons.check),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a failed name write shows the fixed sentence and keeps the '
      'editor open with the input', (tester) async {
    final repo = _NameRepo(failNameWrites: true);
    final container = await pumpSettings(tester, repo);

    await editLibraryName(tester, 'Unsaved Shelf');

    expect(find.text(settingsSaveFailedMessage), findsOneWidget);
    expect(repo.nameWrites, ['Unsaved Shelf']);
    // Still editing; the unsaved text is in the editor, not a value row.
    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller!.text, 'Unsaved Shelf');
    expect(
      container.read(settingsControllerProvider).value?.libraryName,
      'Old Shelf',
      reason: 'the controller keeps the last persisted value',
    );
  });

  testWidgets('a successful name write collapses to the saved value', (
    tester,
  ) async {
    final repo = _NameRepo();
    final container = await pumpSettings(tester, repo);

    await editLibraryName(tester, 'New Shelf');

    expect(find.text(settingsSaveFailedMessage), findsNothing);
    expect(repo.libraryName, 'New Shelf');
    expect(find.text('New Shelf'), findsOneWidget);
    expect(
      container.read(settingsControllerProvider).value?.libraryName,
      'New Shelf',
    );
  });
}
