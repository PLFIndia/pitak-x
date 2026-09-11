/// N11 (astra-review.md) widget tests: create-backup must reach a typed
/// terminal state on EVERY path — a throwing share plugin or use-case
/// provider used to escape as an unhandled async error and leave the busy
/// spinner stuck forever.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/platform/file_share.dart';
import 'package:pitaka/features/backup/application/create_backup_use_case.dart';
import 'package:pitaka/features/backup/presentation/pages/create_backup_page.dart';

/// Use-case fake: returns a fixed result. The collaborator fields are never
/// touched — `noSuchMethod` throws if that ever changes.
class _FakeCreateBackup implements CreateBackupUseCase {
  _FakeCreateBackup(this._result);

  final Either<Failure, Uint8List> _result;

  @override
  Future<Either<Failure, Uint8List>> call() async => _result;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Share-sheet fake: a fixed outcome, or throws like a crashing plugin.
class _FakeShare implements FileShareService {
  _FakeShare({this.outcome = ShareOutcome.success, this.error});

  final ShareOutcome outcome;
  final Object? error;

  @override
  Future<ShareOutcome> shareBytes({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    Rect? sharePositionOrigin,
  }) async {
    final e = error;
    if (e != null) Error.throwWithStackTrace(e, StackTrace.current);
    return outcome;
  }

  @override
  Future<ShareOutcome> shareText(String text, {Rect? sharePositionOrigin}) =>
      throw UnimplementedError();
}

void main() {
  Widget page({CreateBackupUseCase? useCase, _FakeShare? share}) =>
      ProviderScope(
        overrides: [
          if (useCase != null)
            createBackupUseCaseProvider.overrideWith((ref) async => useCase),
          fileShareServiceProvider.overrideWithValue(share ?? _FakeShare()),
        ],
        child: const MaterialApp(home: CreateBackupPage()),
      );

  testWidgets('success shows the saved confirmation', (tester) async {
    await tester.pumpWidget(
      page(useCase: _FakeCreateBackup(right(Uint8List.fromList([1, 2, 3])))),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create backup'));
    await tester.pumpAndSettle();
    expect(find.text('Backup saved.'), findsOneWidget);
  });

  testWidgets('share unavailable shows its message', (tester) async {
    await tester.pumpWidget(
      page(
        useCase: _FakeCreateBackup(right(Uint8List.fromList([1]))),
        share: _FakeShare(outcome: ShareOutcome.unavailable),
      ),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create backup'));
    await tester.pumpAndSettle();
    expect(find.text('Sharing is unavailable on this device.'), findsOneWidget);
  });

  testWidgets('N11: a throwing share plugin shows a safe error and frees the '
      'button', (tester) async {
    await tester.pumpWidget(
      page(
        useCase: _FakeCreateBackup(right(Uint8List.fromList([1]))),
        share: _FakeShare(error: StateError('plugin exploded')),
      ),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create backup'));
    await tester.pumpAndSettle();

    expect(
      find.text('Something went wrong creating the backup.'),
      findsOneWidget,
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).enabled,
      isTrue,
      reason: 'the busy flag must reset on an unexpected failure',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('N11: a throwing use-case provider shows a safe error and frees '
      'the button', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          createBackupUseCaseProvider.overrideWith(
            (ref) async => throw StateError('storage exploded'),
          ),
          fileShareServiceProvider.overrideWithValue(_FakeShare()),
        ],
        child: const MaterialApp(home: CreateBackupPage()),
      ),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create backup'));
    await tester.pumpAndSettle();

    expect(
      find.text('Something went wrong creating the backup.'),
      findsOneWidget,
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).enabled,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });
}
