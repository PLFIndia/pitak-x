/// Review item 12: the "Joined library" confirmation after a QR scan must be
/// gated on the PERSISTED identity write. A failed save used to be announced
/// as a join, so the user merged a file into the wrong library namespace.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:pitaka/features/settings/domain/settings_repository.dart';
import 'package:pitaka/features/settings/presentation/widgets/community_library_section.dart';

const _oldId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _scannedId = '0123456789abcdef';

/// Records identity writes; [failIdWrites] answers a typed `StorageFailure`
/// without changing [id] (what the prefs repository does on a false write).
final class _IdentityRepo implements SettingsRepository {
  _IdentityRepo({this.failIdWrites = false});

  final bool failIdWrites;
  String id = _oldId;
  final List<String> idValues = [];

  @override
  Future<AppSettings> load() async =>
      AppSettings.defaults.copyWith(libraryId: id);

  @override
  Future<Either<Failure, Unit>> setLibraryId(String value) async {
    idValues.add(value);
    if (failIdWrites) return left(const StorageFailure('synthetic'));
    id = value;
    return right(unit);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  /// The scan page's camera replaced by one button emitting a pairing QR.
  Widget fakeScanner(void Function(String) onText) => ElevatedButton(
    onPressed: () => onText('pitaka-lib:$_scannedId'),
    child: const Text('emit'),
  );

  Future<ProviderContainer> pumpSection(
    WidgetTester tester,
    _IdentityRepo repo,
  ) async {
    final container = ProviderContainer(
      overrides: [settingsRepositoryProvider.overrideWith((ref) async => repo)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: CommunityLibrarySection(buildScanner: fakeScanner),
          ),
        ),
      ),
    );
    // Load the settings so the controller has a last-good value to keep.
    await container.read(settingsControllerProvider.future);
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> scanAndJoin(WidgetTester tester) async {
    await tester.tap(find.text('Scan a library QR'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('emit'));
    await tester.pumpAndSettle();
    expect(find.text('Join this library?'), findsOneWidget);
    await tester.tap(find.text('Join'));
    await tester.pumpAndSettle();
  }

  testWidgets('a persisted write is announced as joined', (tester) async {
    final repo = _IdentityRepo();
    final container = await pumpSection(tester, repo);

    await scanAndJoin(tester);

    expect(find.text('Joined library — now merge their file.'), findsOneWidget);
    expect(find.textContaining('Could not save'), findsNothing);
    expect(repo.idValues, [_scannedId]);
    expect(repo.id, _scannedId);
    expect(
      container.read(settingsControllerProvider).value?.libraryId,
      _scannedId,
    );
  });

  testWidgets('a StorageFailure is reported as a save failure, not a join', (
    tester,
  ) async {
    final repo = _IdentityRepo(failIdWrites: true);
    final container = await pumpSection(tester, repo);

    await scanAndJoin(tester);

    expect(
      find.text('Could not save the library ID. Please scan again.'),
      findsOneWidget,
    );
    expect(find.textContaining('Joined library'), findsNothing);
    // The write was attempted once; nothing is retried automatically.
    expect(repo.idValues, [_scannedId]);
    expect(repo.id, _oldId, reason: 'the old identity stays in force');
    expect(container.read(settingsControllerProvider).value?.libraryId, _oldId);
    // The section is still there (no navigation away, no merge started).
    expect(find.text('Scan a library QR'), findsOneWidget);
  });

  testWidgets('cancelling the confirmation writes nothing', (tester) async {
    final repo = _IdentityRepo();
    await pumpSection(tester, repo);

    await tester.tap(find.text('Scan a library QR'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('emit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(repo.idValues, isEmpty);
    expect(find.byType(SnackBar), findsNothing);
  });
}
