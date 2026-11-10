/// Review finding N11 widget tests: create-backup must reach a typed
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
import 'package:pitaka/features/backup/domain/create_backup_result.dart';
import 'package:pitaka/features/backup/presentation/pages/create_backup_page.dart';

import '../../support/a11y.dart';

/// Use-case fake: returns a fixed result. The collaborator fields are never
/// touched — `noSuchMethod` throws if that ever changes.
class _FakeCreateBackup implements CreateBackupUseCase {
  _FakeCreateBackup(
    Either<Failure, Uint8List> result, {
    bool includesIdentity = true,
    bool includesNetwork = true,
    bool missingPublishState = false,
    List<String> coversLeftOut = const [],
  }) : _result = result.map(
         (bytes) => CreateBackupResult(
           bytes: bytes,
           includesIdentity: includesIdentity,
           includesNetwork: includesNetwork,
           missingPublishState: missingPublishState,
           coversLeftOut: coversLeftOut,
         ),
       );

  final Either<Failure, CreateBackupResult> _result;

  @override
  Future<Either<Failure, CreateBackupResult>> call() async => _result;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Share-sheet fake: a fixed outcome, or throws like a crashing plugin.
class _FakeShare implements FileShareService {
  _FakeShare({this.outcome = ShareOutcome.success, this.error});

  /// Not final: one test changes the outcome between two runs.
  ShareOutcome outcome;
  final Object? error;

  @override
  Future<ShareOutcome> shareBytes({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    String? text,
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

  testWidgets('success shows the hand-off confirmation', (tester) async {
    await tester.pumpWidget(
      page(useCase: _FakeCreateBackup(right(Uint8List.fromList([1, 2, 3])))),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create backup'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Backup handed to the selected app; confirm it was saved or sent.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('plan CV6: the intro says the publishing record is inside', (
    tester,
  ) async {
    await tester.pumpWidget(page());
    expect(
      find.textContaining('its publishing record is included too'),
      findsOneWidget,
    );
    expect(
      find.textContaining('your GitHub or Cloudflare sign-in'),
      findsOneWidget,
    );
    expect(find.textContaining('publishing setup'), findsNothing);
  });

  testWidgets('plan CV6: a record that could not be carried is named', (
    tester,
  ) async {
    await tester.pumpWidget(
      page(
        useCase: _FakeCreateBackup(
          right(Uint8List.fromList([1])),
          missingPublishState: true,
        ),
      ),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create backup'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Note: this backup does not carry your website publishing record — '
        'it could not be read. Everything else is inside.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('three missing parts read naturally', (tester) async {
    await tester.pumpWidget(
      page(
        useCase: _FakeCreateBackup(
          right(Uint8List.fromList([1])),
          includesIdentity: false,
          includesNetwork: false,
          missingPublishState: true,
        ),
      ),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create backup'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining(
        'does not carry your library identity, your saved-libraries list and '
        'your website publishing record',
      ),
      findsOneWidget,
    );
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

  testWidgets('dismissed sharing shows no hand-off or error', (tester) async {
    await tester.pumpWidget(
      page(
        useCase: _FakeCreateBackup(right(Uint8List.fromList([1]))),
        share: _FakeShare(outcome: ShareOutcome.dismissed),
      ),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create backup'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Backup handed to the selected app; confirm it was saved or sent.',
      ),
      findsNothing,
    );
    expect(find.text('Sharing is unavailable on this device.'), findsNothing);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).enabled,
      isTrue,
    );
  });

  // S5 (L5): a catalogue too large for the format gets its OWN sentence —
  // retrying cannot help, so "please try again" would be a lie.
  testWidgets('S5: a too-large catalogue says nothing was exported', (
    tester,
  ) async {
    await tester.pumpWidget(
      page(
        useCase: _FakeCreateBackup(
          left(const BackupTooLargeFailure('itemKindsTooLarge')),
        ),
      ),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create backup'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'This catalogue is too large for this backup format. '
        'Nothing was exported.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Backup handed to the selected app; confirm it was saved or sent.',
      ),
      findsNothing,
    );
  });

  // BR3: a refusal that carries its numbers gets the sentence for its limit.
  // (Every sentence is tested in create_backup_messages_test.dart; this
  // proves the page shows it.)
  testWidgets('BR3: too many cover pictures are named with both numbers', (
    tester,
  ) async {
    await tester.pumpWidget(
      page(
        useCase: _FakeCreateBackup(
          left(const BackupTooLargeFailure('tooManyCovers', 4300, 4086)),
        ),
      ),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create backup'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'This library has 4,300 cover pictures; a backup can hold 4,086. '
        'Nothing was exported.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Backup handed to the selected app; confirm it was saved or sent.',
      ),
      findsNothing,
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).enabled,
      isTrue,
    );
  });

  group('BR3 (D10): cover pictures that were left out', () {
    const sentenceForFive =
        'Note: the cover pictures of 5 items are too large for a backup and '
        'are not inside. The items themselves are inside:';

    testWidgets('five items: the count, the first three titles, and how '
        'many more', (tester) async {
      await tester.pumpWidget(
        page(
          useCase: _FakeCreateBackup(
            right(Uint8List.fromList([1])),
            coversLeftOut: const ['Alpha', 'Beta', 'Gamma', 'Delta', 'Eta'],
          ),
        ),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Create backup'));
      await tester.pumpAndSettle();

      // The backup itself completed.
      expect(
        find.text(
          'Backup handed to the selected app; confirm it was saved or sent.',
        ),
        findsOneWidget,
      );
      expect(find.text(sentenceForFive), findsOneWidget);
      expect(find.text('• Alpha'), findsOneWidget);
      expect(find.text('• Beta'), findsOneWidget);
      expect(find.text('• Gamma'), findsOneWidget);
      expect(find.textContaining('Delta'), findsNothing);
      expect(find.textContaining('Eta'), findsNothing);
      expect(find.text('and 2 more'), findsOneWidget);
      await expectMeetsA11yGuidelines(tester);
    });

    testWidgets('one item: singular wording and no "more" line', (
      tester,
    ) async {
      await tester.pumpWidget(
        page(
          useCase: _FakeCreateBackup(
            right(Uint8List.fromList([1])),
            coversLeftOut: const ['Alpha'],
          ),
        ),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Create backup'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Note: the cover picture of 1 item is too large for a backup and '
          'is not inside. The item itself is inside:',
        ),
        findsOneWidget,
      );
      expect(find.text('• Alpha'), findsOneWidget);
      expect(find.textContaining('more'), findsNothing);
    });

    testWidgets('a very long title stays on one line', (tester) async {
      await tester.pumpWidget(
        page(
          useCase: _FakeCreateBackup(
            right(Uint8List.fromList([1])),
            coversLeftOut: ['A very long title ${'word ' * 400}'],
          ),
        ),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Create backup'));
      await tester.pumpAndSettle();
      final title = tester.widget<Text>(
        find.textContaining('A very long title'),
      );
      expect(title.maxLines, 1);
      expect(title.overflow, TextOverflow.ellipsis);
      expect(tester.takeException(), isNull);
    });

    testWidgets('nothing left out: no note', (tester) async {
      await tester.pumpWidget(
        page(useCase: _FakeCreateBackup(right(Uint8List.fromList([1])))),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Create backup'));
      await tester.pumpAndSettle();
      expect(find.textContaining('cover picture'), findsNothing);
    });

    testWidgets('the note is gone when the next backup starts', (tester) async {
      // The note belongs to ONE finished backup. A second run whose share
      // sheet is dismissed must not keep showing the first run's titles.
      final share = _FakeShare();
      await tester.pumpWidget(
        page(
          useCase: _FakeCreateBackup(
            right(Uint8List.fromList([1])),
            coversLeftOut: const ['Alpha'],
          ),
          share: share,
        ),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Create backup'));
      await tester.pumpAndSettle();
      expect(find.text('• Alpha'), findsOneWidget);

      share.outcome = ShareOutcome.dismissed;
      await tester.tap(find.widgetWithText(FilledButton, 'Create backup'));
      await tester.pumpAndSettle();
      expect(find.text('• Alpha'), findsNothing);
    });
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

  testWidgets('meets accessibility guidelines', (tester) async {
    await tester.pumpWidget(
      page(useCase: _FakeCreateBackup(right(Uint8List.fromList([1, 2, 3])))),
    );
    await tester.pumpAndSettle();
    await expectMeetsA11yGuidelines(tester);
  });
}
