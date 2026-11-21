/// Tests of the name a new catalogue row is attributed to.
///
/// The function was moved out of four forms into one file (review finding
/// P4-M1). The move must not change what it answers: the trimmed name, and
/// nothing for a blank name or while the settings are not there.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/library/presentation/maintainer_stamp.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:pitaka/features/settings/domain/settings_repository.dart';

/// A settings store that answers `load()` with what the test hands it.
class _Settings implements SettingsRepository {
  _Settings(this._load);

  final Future<AppSettings> Function() _load;

  @override
  Future<AppSettings> load() => _load();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not used here');
}

void main() {
  /// Pumps a widget that hands its `ref` out, and returns what the function
  /// answers for the settings [load] gives.
  Future<String?> stampFor(
    WidgetTester tester,
    Future<AppSettings> Function() load,
  ) async {
    late WidgetRef captured;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWith(
            (ref) async => _Settings(load),
          ),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            captured = ref;
            // Watching makes the settings load, as the app does at its start.
            ref.watch(settingsControllerProvider);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return maintainerStampOf(captured);
  }

  testWidgets('the name from settings, trimmed', (tester) async {
    final stamp = await stampFor(
      tester,
      () async => AppSettings.defaults.copyWith(maintainerName: '  Meera '),
    );

    expect(stamp, 'Meera');
  });

  testWidgets('no name set: nothing', (tester) async {
    final stamp = await stampFor(tester, () async => AppSettings.defaults);

    expect(AppSettings.defaults.maintainerName, isEmpty);
    expect(stamp, isNull);
  });

  testWidgets('a name of spaces only: nothing', (tester) async {
    final stamp = await stampFor(
      tester,
      () async => AppSettings.defaults.copyWith(maintainerName: '   '),
    );

    expect(stamp, isNull);
  });

  testWidgets('while the settings are still loading: nothing', (tester) async {
    final never = Completer<AppSettings>();
    final stamp = await stampFor(tester, () => never.future);

    expect(stamp, isNull);
  });

  testWidgets('settings that could not be loaded: nothing', (tester) async {
    final stamp = await stampFor(
      tester,
      () async => throw StateError('test: the settings cannot be read'),
    );

    expect(stamp, isNull);
  });
}
