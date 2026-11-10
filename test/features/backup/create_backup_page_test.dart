/// Review finding N11 widget tests: create-backup must reach a typed
/// terminal state on EVERY path — a throwing share plugin or use-case
/// provider used to escape as an unhandled async error and leave the busy
/// spinner stuck forever.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/platform/file_share.dart';
import 'package:pitaka/features/backup/application/create_backup_use_case.dart';
import 'package:pitaka/features/backup/domain/backup_progress.dart';
import 'package:pitaka/features/backup/domain/create_backup_result.dart';
import 'package:pitaka/features/backup/presentation/pages/create_backup_page.dart';

import '../../support/a11y.dart';

/// Where the fake use case says the finished backup is. No file is written:
/// the share sheet is a fake too.
const String _fakeBackupPath =
    '/fake/backup_work/run-1/Pitak-backup-20260101-000000.pitabak';

/// What happened, in order, across the two fakes of one test (BR4: the file
/// must be given back AFTER sharing, not before).
typedef _Events = List<String>;

/// Use-case fake: returns a fixed result. The collaborator fields are never
/// touched — `noSuchMethod` throws if that ever changes.
///
/// The first argument is still "the archive" as bytes, so the tests read as
/// before; since BR4 the result carries a path and the size instead.
class _FakeCreateBackup implements CreateBackupUseCase {
  _FakeCreateBackup(
    Either<Failure, Uint8List> result, {
    bool includesIdentity = true,
    bool includesNetwork = true,
    bool missingPublishState = false,
    List<String> coversLeftOut = const [],
    this.gate,
    this.events,
    this.error,
  }) : _result = result.map(
         (bytes) => CreateBackupResult(
           path: _fakeBackupPath,
           sizeBytes: bytes.length,
           includesIdentity: includesIdentity,
           includesNetwork: includesNetwork,
           missingPublishState: missingPublishState,
           coversLeftOut: coversLeftOut,
         ),
       );

  final Either<Failure, CreateBackupResult> _result;

  /// When given, the build waits for it: a test can then act "while the
  /// backup is being built".
  final Completer<void>? gate;

  final _Events? events;

  /// When given, the build throws it instead of returning (after [gate]).
  final Object? error;

  /// The results handed back through [discard], in order.
  final List<CreateBackupResult> discarded = [];

  /// The progress listener of the latest call (BR4 rider 3). A test calls
  /// [report] to play the builder that packs cover pictures.
  BackupProgressListener? _onProgress;

  /// Reports "[done] of [total] covers" to the page, as the running build
  /// would.
  void report(int done, int total) => _onProgress!(
    BackupProgress.tryCreate(coversDone: done, coversTotal: total)!,
  );

  @override
  Future<Either<Failure, CreateBackupResult>> call({
    BackupProgressListener? onProgress,
  }) async {
    _onProgress = onProgress;
    await gate?.future;
    final e = error;
    if (e != null) Error.throwWithStackTrace(e, StackTrace.current);
    return _result;
  }

  @override
  Future<void> discard(CreateBackupResult result) async {
    discarded.add(result);
    events?.add('discard');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Share-sheet fake: a fixed outcome, or throws like a crashing plugin.
class _FakeShare implements FileShareService {
  _FakeShare({
    this.outcome = ShareOutcome.success,
    this.error,
    this.events,
    this.gate,
  });

  /// Not final: one test changes the outcome between two runs.
  ShareOutcome outcome;
  final Object? error;
  final _Events? events;

  /// When given, the share sheet "stays open" until it completes.
  final Completer<void>? gate;

  /// The (path, MIME type) of every file handed to the share sheet.
  final List<({String path, String mimeType})> files = [];

  @override
  Future<ShareOutcome> shareFile({
    required String path,
    required String mimeType,
    Rect? sharePositionOrigin,
  }) async {
    files.add((path: path, mimeType: mimeType));
    events?.add('share');
    await gate?.future;
    final e = error;
    if (e != null) Error.throwWithStackTrace(e, StackTrace.current);
    return outcome;
  }

  // BR4: a backup is shared as a FILE. Holding it in memory to share it is
  // exactly what the rework removed, so this must never be called.
  @override
  Future<ShareOutcome> shareBytes({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    String? text,
    Rect? sharePositionOrigin,
  }) => throw UnimplementedError();

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

  // Decision D12: a backup made by a newer Pitak need not open in an older
  // one. The user is told BEFORE the backup is made, not after.
  testWidgets('D12: says before the backup that an older Pitak may not open '
      'it', (tester) async {
    await tester.pumpWidget(page());
    expect(
      find.text(
        'A backup made with this version may not open in an older version '
        'of Pitak. Update Pitak on the other phone before you restore there.',
      ),
      findsOneWidget,
    );
    // It sits above the button: visible without having made a backup.
    final sentence = tester.getTopLeft(
      find.textContaining('may not open in an older version'),
    );
    final button = tester.getTopLeft(
      find.widgetWithText(FilledButton, 'Create backup'),
    );
    expect(sentence.dy, lessThan(button.dy));
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

  // BR4: the backup is a FILE in a private folder of the app, a plain copy
  // of the whole library. The page shares it by its path and gives it back
  // on every way out, so that it never stays behind.
  group('BR4 — the finished file is shared by path and always given back', () {
    Future<void> createBackup(WidgetTester tester) async {
      await tester.tap(find.widgetWithText(FilledButton, 'Create backup'));
      await tester.pumpAndSettle();
    }

    testWidgets('the path goes to the share sheet as a generic binary, and '
        'the file is given back after sharing', (tester) async {
      final events = <String>[];
      final useCase = _FakeCreateBackup(
        right(Uint8List.fromList([1, 2, 3])),
        events: events,
      );
      final share = _FakeShare(events: events);
      await tester.pumpWidget(page(useCase: useCase, share: share));
      await createBackup(tester);

      expect(share.files, [
        (path: _fakeBackupPath, mimeType: 'application/octet-stream'),
      ]);
      expect(useCase.discarded, hasLength(1));
      expect(useCase.discarded.single.path, _fakeBackupPath);
      expect(events, ['share', 'discard']);
    });

    for (final outcome in [ShareOutcome.dismissed, ShareOutcome.unavailable]) {
      testWidgets('the file is given back once when sharing ends as '
          '${outcome.name}', (tester) async {
        final useCase = _FakeCreateBackup(right(Uint8List.fromList([1])));
        await tester.pumpWidget(
          page(
            useCase: useCase,
            share: _FakeShare(outcome: outcome),
          ),
        );
        await createBackup(tester);

        expect(useCase.discarded, hasLength(1));
      });
    }

    testWidgets('the file is given back once when the share plugin throws', (
      tester,
    ) async {
      final useCase = _FakeCreateBackup(right(Uint8List.fromList([1])));
      await tester.pumpWidget(
        page(
          useCase: useCase,
          share: _FakeShare(error: StateError('plugin exploded')),
        ),
      );
      await createBackup(tester);

      expect(useCase.discarded, hasLength(1));
      expect(
        find.text('Something went wrong creating the backup.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a second backup gives back its own file too', (tester) async {
      final useCase = _FakeCreateBackup(right(Uint8List.fromList([1])));
      await tester.pumpWidget(page(useCase: useCase));
      await createBackup(tester);
      await createBackup(tester);

      expect(useCase.discarded, hasLength(2));
    });

    testWidgets('a failed build shares nothing and has nothing to give back', (
      tester,
    ) async {
      final useCase = _FakeCreateBackup(left(const StorageFailure('x')));
      final share = _FakeShare();
      await tester.pumpWidget(page(useCase: useCase, share: share));
      await createBackup(tester);

      expect(share.files, isEmpty);
      expect(useCase.discarded, isEmpty);
      expect(
        find.text('Could not build the backup. Please try again.'),
        findsOneWidget,
      );
    });

    testWidgets('a page that was left while the backup was being built '
        'gives the file back and shares nothing', (tester) async {
      final gate = Completer<void>();
      final useCase = _FakeCreateBackup(
        right(Uint8List.fromList([1])),
        gate: gate,
      );
      final share = _FakeShare();
      await tester.pumpWidget(page(useCase: useCase, share: share));
      await tester.tap(find.widgetWithText(FilledButton, 'Create backup'));
      await tester.pump();

      // The user leaves: the page is removed while the build still runs.
      await tester.pumpWidget(const SizedBox());
      gate.complete();
      await tester.pumpAndSettle();

      expect(share.files, isEmpty);
      expect(useCase.discarded, hasLength(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a page that was left before a FAILED build returned does '
        'nothing more', (tester) async {
      final gate = Completer<void>();
      final useCase = _FakeCreateBackup(
        left(const StorageFailure('x')),
        gate: gate,
      );
      await tester.pumpWidget(page(useCase: useCase));
      await tester.tap(find.widgetWithText(FilledButton, 'Create backup'));
      await tester.pump();

      await tester.pumpWidget(const SizedBox());
      gate.complete();
      await tester.pumpAndSettle();

      expect(useCase.discarded, isEmpty);
      expect(tester.takeException(), isNull);
    });
  });

  // BR4 rider 3 (the backup part of review finding P4-M7): a large backup
  // spends its time packing cover pictures, and a spinner alone does not
  // say whether anything is still happening. One line under the button
  // counts the covers. The fake use case plays the build: it waits at a
  // gate, and the test reports progress "from inside" it.
  group('BR4 rider 3 — progress while the cover pictures are packed', () {
    final line = find.byKey(const Key('backup-progress'));
    const handedOver =
        'Backup handed to the selected app; confirm it was saved or sent.';

    bool buttonEnabled(WidgetTester tester) =>
        tester.widget<FilledButton>(find.byType(FilledButton)).enabled;

    /// Shows the page with [useCase] and taps the button. The build then
    /// waits at the use case's gate.
    Future<void> startBuild(
      WidgetTester tester,
      _FakeCreateBackup useCase, {
      _FakeShare? share,
    }) async {
      await tester.pumpWidget(page(useCase: useCase, share: share));
      await tester.tap(find.widgetWithText(FilledButton, 'Create backup'));
      await tester.pump();
    }

    testWidgets('before the first report, and for a library without cover '
        'pictures, there is only the spinner', (tester) async {
      final gate = Completer<void>();
      final useCase = _FakeCreateBackup(
        right(Uint8List.fromList([1])),
        gate: gate,
      );
      await startBuild(tester, useCase);

      expect(line, findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Creating…'), findsOneWidget);

      // No report ever comes (no covers): the backup finishes without the
      // line having been shown.
      gate.complete();
      await tester.pumpAndSettle();
      expect(line, findsNothing);
      expect(find.text(handedOver), findsOneWidget);
    });

    testWidgets('a report shows "Cover 1,234 of 9,000" under the button, and '
        'the next report replaces it', (tester) async {
      final gate = Completer<void>();
      final useCase = _FakeCreateBackup(
        right(Uint8List.fromList([1])),
        gate: gate,
      );
      await startBuild(tester, useCase);

      useCase.report(1234, 9000);
      await tester.pump();

      expect(tester.widget<Text>(line).data, 'Cover 1,234 of 9,000');
      final buttonBottom = tester.getBottomLeft(find.byType(FilledButton)).dy;
      expect(tester.getTopLeft(line).dy, greaterThan(buttonBottom));
      // The spinner stays, and the button stays locked: still one backup.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(buttonEnabled(tester), isFalse);

      useCase.report(9000, 9000);
      await tester.pump();

      expect(line, findsOneWidget);
      expect(tester.widget<Text>(line).data, 'Cover 9,000 of 9,000');

      gate.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('the line is removed as soon as the build is over, while '
        'the share sheet is still open', (tester) async {
      final buildGate = Completer<void>();
      final shareGate = Completer<void>();
      final useCase = _FakeCreateBackup(
        right(Uint8List.fromList([1])),
        gate: buildGate,
      );
      final share = _FakeShare(gate: shareGate);
      await startBuild(tester, useCase, share: share);
      useCase.report(3, 3);
      await tester.pump();
      expect(line, findsOneWidget);

      buildGate.complete();
      await tester.pump();

      expect(share.files, hasLength(1), reason: 'the share sheet is open');
      expect(line, findsNothing);
      expect(buttonEnabled(tester), isFalse, reason: 'not finished yet');

      shareGate.complete();
      await tester.pumpAndSettle();
      expect(line, findsNothing);
      expect(find.text(handedOver), findsOneWidget);
      expect(buttonEnabled(tester), isTrue);
    });

    testWidgets('the line is removed when the build fails', (tester) async {
      final gate = Completer<void>();
      final useCase = _FakeCreateBackup(
        left(const StorageFailure('x')),
        gate: gate,
      );
      await startBuild(tester, useCase);
      useCase.report(2, 5);
      await tester.pump();
      expect(line, findsOneWidget);

      gate.complete();
      await tester.pumpAndSettle();

      expect(line, findsNothing);
      expect(
        find.text('Could not build the backup. Please try again.'),
        findsOneWidget,
      );
    });

    testWidgets('the line is removed when the build throws after a report', (
      tester,
    ) async {
      final gate = Completer<void>();
      final useCase = _FakeCreateBackup(
        right(Uint8List.fromList([1])),
        gate: gate,
        error: StateError('disk went away'),
      );
      await startBuild(tester, useCase);
      useCase.report(2, 5);
      await tester.pump();
      expect(line, findsOneWidget);

      gate.complete();
      await tester.pumpAndSettle();

      expect(line, findsNothing);
      expect(
        find.text('Something went wrong creating the backup.'),
        findsOneWidget,
      );
      expect(buttonEnabled(tester), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a report that arrives after the page was left is dropped', (
      tester,
    ) async {
      // The build goes on in its worker when the user leaves the page. A
      // report for a page that is gone must not touch it.
      final gate = Completer<void>();
      final useCase = _FakeCreateBackup(
        right(Uint8List.fromList([1])),
        gate: gate,
      );
      await startBuild(tester, useCase);
      await tester.pumpWidget(const SizedBox());

      useCase.report(1, 2);
      gate.complete();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(useCase.discarded, hasLength(1), reason: 'still given back');
    });

    testWidgets('meets accessibility guidelines while the line is shown', (
      tester,
    ) async {
      final gate = Completer<void>();
      final useCase = _FakeCreateBackup(
        right(Uint8List.fromList([1])),
        gate: gate,
      );
      await startBuild(tester, useCase);
      useCase.report(1234, 9000);
      await tester.pump();

      await expectMeetsA11yGuidelines(tester);

      gate.complete();
      await tester.pumpAndSettle();
    });
  });
}
