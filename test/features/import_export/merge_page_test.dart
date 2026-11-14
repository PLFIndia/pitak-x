import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/platform/document_picker.dart';
import 'package:pitaka/features/import_export/application/merge_controller.dart';
import 'package:pitaka/features/import_export/application/merge_library_use_case.dart';
import 'package:pitaka/features/import_export/infrastructure/pitaka_json_importer.dart';
import 'package:pitaka/features/import_export/presentation/pages/merge_page.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/merge/library_merge_engine.dart';
import 'package:pitaka/features/library/domain/repositories/catalogue_item_repository.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';

import '../../support/a11y.dart';
import '../../support/fake_document_picker.dart';
import '../../support/fake_picked_document_reader.dart';
import '../library/replacement_harness.dart';
import '../library/replacement_test_guard.dart';
import '../periodicals/application/periodical_fakes.dart';

/// A library file of ANOTHER library (its id differs from this device's),
/// with one book: what a pick hands out unless a test says otherwise.
final List<int> _otherLibraryJson = utf8.encode(
  jsonEncode({
    'schemaVersion': 3,
    'libraryId': 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    'libraryName': 'Other',
    'books': [
      {'title': 'Incoming', 'bookUid': 'new'},
    ],
    'wishlist': <Object>[],
  }),
);

class _Books implements CatalogueItemRepository {
  @override
  Future<Either<Failure, List<CatalogueItem>>> getAll() async =>
      right([const CatalogueItem(id: 7, title: 'Local', itemUid: 'old')]);
  @override
  Future<Either<Failure, List<CatalogueItem>>> getAllForInterchange() async =>
      right([const CatalogueItem(id: 7, title: 'Local', itemUid: 'old')]);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  // The system's picker and the private copy it makes, played by a fake
  // that writes real files; and a reader that reads them at once (a widget
  // test cannot wait for real file work). Decision D24.
  late Directory tmp;
  late FakeDocumentPicker picker;
  late FakePickedDocumentReader reader;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('merge_page_test');
    picker = FakeDocumentPicker(Directory('${tmp.path}/picked_documents'));
    reader = FakePickedDocumentReader();
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// Puts the two fakes in the place of the system's picker and the disk.
  List<Override> pickerOverrides() => [
    documentPickerProvider.overrideWith((ref) async => picker),
    pickedDocumentReaderProvider.overrideWith((ref) => reader),
  ];

  testWidgets('merge page renders intro + the file-pick action', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: MergePage())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Merge from a file'), findsOneWidget);
    expect(find.text('Choose a library file'), findsOneWidget);
    // The explanatory copy is present so the user knows nothing is deleted.
    expect(
      find.textContaining('Nothing is deleted unless you'),
      findsOneWidget,
    );
  });

  testWidgets(
    'M03: confirmation explains protection and refusal stays visible',
    (tester) async {
      picker.willPick(_otherLibraryJson);
      final guard = FakeReplacementGuard(
        failure: const ValidationFailure(
          'Existing loan history cannot be matched.',
        ),
      );
      final settings = ReplacementSettings();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...pickerOverrides(),
            settingsRepositoryProvider.overrideWith((ref) async => settings),
            mergeLibraryUseCaseProvider.overrideWith(
              (ref) async => MergeLibraryUseCase(
                bookRepo: _Books(),
                periodicalRepo: FakePeriodicals(),
                namespace: ref.read(settingsControllerProvider.notifier),
                jsonParser: const PitakaJsonImporter(),
                replacementGuard: guard,
                planner: planMergeInline,
              ),
            ),
          ],
          child: const MaterialApp(home: MergePage()),
        ),
      );
      await tester.tap(find.text('Choose a library file'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Replace my library'));
      await tester.tap(find.text('Replace my library'));
      await tester.pumpAndSettle();
      expect(find.textContaining('all existing loan history'), findsOneWidget);
      expect(find.textContaining('vault is not affected'), findsNothing);
      expect(guard.calls, 0);
      await tester.tap(find.text('Replace'));
      await tester.pumpAndSettle();
      expect(guard.calls, 1);
      expect(
        find.text('Existing loan history cannot be matched.'),
        findsOneWidget,
      );
      expect(find.text('Merge complete'), findsNothing);
      expect(settings.id, 'local');
    },
  );

  testWidgets('N11: leaving the page mid-merge does not crash', (tester) async {
    // The merge outlives the page (keep-alive controller). Popping Merge
    // mid-run used to throw in the page's unguarded setState — and the error
    // handler then threw AGAIN calling setState on the dead widget.
    final gate = Completer<void>();
    picker.willPick(_otherLibraryJson);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...pickerOverrides(),
          settingsRepositoryProvider.overrideWith(
            (ref) async => ReplacementSettings(),
          ),
          mergeLibraryUseCaseProvider.overrideWith((ref) async {
            await gate.future;
            return MergeLibraryUseCase(
              bookRepo: _Books(),
              periodicalRepo: FakePeriodicals(),
              namespace: ref.read(settingsControllerProvider.notifier),
              jsonParser: const PitakaJsonImporter(),
              replacementGuard: FakeReplacementGuard(),
              planner: planMergeInline,
            );
          }),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const MergePage()),
                ),
                child: const Text('open merge'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open merge'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Choose a library file'));
    await tester.pump(); // the merge is now parked on the gated provider

    // Leave the page mid-merge. Settle FIRST: the pop animation must finish
    // so the widget is fully disposed before the merge completes — otherwise
    // the continuation races the disposal and the test is flaky.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    gate.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('N11: a throwing merge provider surfaces a safe message', (
    tester,
  ) async {
    picker.willPick(_otherLibraryJson);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...pickerOverrides(),
          mergeLibraryUseCaseProvider.overrideWith(
            (ref) async => throw StateError('plugin exploded'),
          ),
        ],
        child: const MaterialApp(home: MergePage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Choose a library file'));
    await tester.pumpAndSettle();

    expect(
      find.text('Merge failed. Please check the file and try again.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('N11: a malformed-UTF8 pick is bounded-read and rejected by the '
      'parser with merge copy', (tester) async {
    // A strict decode would THROW on malformed UTF-8 and show a "could not
    // read" sentence; the bounded read + lenient decode lets the parser
    // reject it with merge-specific copy instead.
    picker.willPick([0xFF, 0xFE, 0xFD, 0x00, 0x01]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...pickerOverrides(),
          settingsRepositoryProvider.overrideWith(
            (ref) async => ReplacementSettings(),
          ),
          mergeLibraryUseCaseProvider.overrideWith(
            (ref) async => MergeLibraryUseCase(
              bookRepo: _Books(),
              periodicalRepo: FakePeriodicals(),
              namespace: ref.read(settingsControllerProvider.notifier),
              jsonParser: const PitakaJsonImporter(),
              replacementGuard: FakeReplacementGuard(),
              planner: planMergeInline,
            ),
          ),
        ],
        child: const MaterialApp(home: MergePage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Choose a library file'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Merge needs a Pitak library file'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  // Decision D24: the file comes through the app's own picker; the page
  // shows a sentence when no file was taken, and nothing else changes.
  group("a chosen file comes through the app's own picker (D24)", () {
    Widget page() => ProviderScope(
      overrides: [
        ...pickerOverrides(),
        settingsRepositoryProvider.overrideWith(
          (ref) async => ReplacementSettings(),
        ),
        mergeLibraryUseCaseProvider.overrideWith(
          (ref) async => MergeLibraryUseCase(
            bookRepo: _Books(),
            periodicalRepo: FakePeriodicals(),
            namespace: ref.read(settingsControllerProvider.notifier),
            jsonParser: const PitakaJsonImporter(),
            replacementGuard: FakeReplacementGuard(),
            planner: planMergeInline,
          ),
        ),
      ],
      child: const MaterialApp(home: MergePage()),
    );

    const tooLargeSentence =
        'This file is too large to merge. A library file can be at most '
        '64.0 MB.';

    testWidgets('a picked library file is merged; the picker was asked with '
        'the text cap, and the copy is removed', (tester) async {
      picker.willPick(_otherLibraryJson);
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Choose a library file'));
      await tester.pumpAndSettle();

      // The file is of another library: the page asks how to combine.
      expect(find.text('Different library'), findsOneWidget);
      expect(picker.caps, [64 * 1024 * 1024]);
      // Merge reads the file without a look at its kind first.
      expect(reader.asked, ['readAll ${64 * 1024 * 1024}']);
      expect(picker.copiesOnDisk(), isEmpty);
    });

    testWidgets('a file above the cap is refused with a sentence that names '
        'the cap, and nothing is read', (tester) async {
      picker.willAnswer(const DocumentPickTooLarge());
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Choose a library file'));
      await tester.pumpAndSettle();

      expect(find.text(tooLargeSentence), findsOneWidget);
      expect(reader.asked, isEmpty);
      expect(find.text('Different library'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    // The four answers that read the same on every page that picks a file.
    const sentences = <(DocumentPickResult, String)>[
      (
        DocumentPickUnreadable(),
        'That file could not be read. If it is kept online, check the '
            'connection and try again.',
      ),
      (
        DocumentPickNotSaved(),
        'The file could not be copied to this phone. Free some storage and '
            'try again.',
      ),
      (
        DocumentPickUnavailable(),
        'Choosing a file is not available on this device.',
      ),
      (
        DocumentPickFailed(),
        'Something went wrong choosing the file. Please try again.',
      ),
    ];
    for (final (answer, sentence) in sentences) {
      testWidgets('${answer.runtimeType} shows its own sentence', (
        tester,
      ) async {
        picker.willAnswer(answer);
        await tester.pumpWidget(page());
        await tester.pumpAndSettle();

        await tester.tap(find.text('Choose a library file'));
        await tester.pumpAndSettle();

        expect(find.text(sentence), findsOneWidget);
        expect(find.text('Different library'), findsNothing);
      });
    }

    testWidgets('a copy that cannot be read shows the "could not be read" '
        'sentence', (tester) async {
      picker.willPick(_otherLibraryJson);
      reader.failing = true;
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Choose a library file'));
      await tester.pumpAndSettle();

      expect(find.textContaining('could not be read'), findsOneWidget);
      expect(picker.copiesOnDisk(), isEmpty, reason: 'the copy is removed');
    });

    testWidgets('closing the picker keeps a pending choice on the page, and '
        'a new tap clears the sentence of the pick before', (tester) async {
      picker
        ..willPick(_otherLibraryJson)
        ..willAnswer(const DocumentPickTooLarge());
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();

      // First pick: the choice between Join and Replace is on the page.
      await tester.tap(find.text('Choose a library file'));
      await tester.pumpAndSettle();
      expect(find.text('Different library'), findsOneWidget);

      // Second pick is too large: the sentence, and the choice is still
      // there.
      await tester.tap(find.text('Choose a library file'));
      await tester.pumpAndSettle();
      expect(find.text(tooLargeSentence), findsOneWidget);
      expect(find.text('Different library'), findsOneWidget);

      // Third pick: nothing is scripted, the fake answers "cancelled".
      await tester.tap(find.text('Choose a library file'));
      await tester.pumpAndSettle();
      expect(picker.caps, hasLength(3));
      expect(find.text(tooLargeSentence), findsNothing);
      expect(find.text('Different library'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    // Seen in the emulator on 2026-11-14: the sentence about a refused
    // file stayed on the page after the Join, above "Merge complete".
    group('the sentence about a refused file goes with the next thing the '
        'user does', () {
      /// A choice between Join and Replace on the page, and above it the
      /// sentence about a second file that was too large.
      Future<void> pumpChoiceAndRefusal(WidgetTester tester) async {
        picker
          ..willPick(_otherLibraryJson)
          ..willAnswer(const DocumentPickTooLarge());
        await tester.pumpWidget(page());
        await tester.pumpAndSettle();
        await tester.tap(find.text('Choose a library file'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Choose a library file'));
        await tester.pumpAndSettle();
        expect(find.text(tooLargeSentence), findsOneWidget);
        expect(find.text('Join (recommended)'), findsOneWidget);
      }

      testWidgets('Join', (tester) async {
        await pumpChoiceAndRefusal(tester);

        await tester.tap(find.text('Join (recommended)'));
        await tester.pumpAndSettle();

        expect(find.text(tooLargeSentence), findsNothing);
      });

      testWidgets('Replace, once it is confirmed; not when the question is '
          'answered with Cancel', (tester) async {
        await pumpChoiceAndRefusal(tester);

        await tester.ensureVisible(find.text('Replace my library'));
        await tester.tap(find.text('Replace my library'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(find.text(tooLargeSentence), findsOneWidget);

        await tester.ensureVisible(find.text('Replace my library'));
        await tester.tap(find.text('Replace my library'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Replace'));
        await tester.pumpAndSettle();
        expect(find.text(tooLargeSentence), findsNothing);
      });

      testWidgets('a review row that is resolved', (tester) async {
        // A tall screen: with the sentence above it, the row's buttons
        // would otherwise lie below the edge of the test's small screen.
        tester.view.physicalSize = const Size(800, 2000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        const local = CatalogueItem(
          id: 1,
          itemUid: 'u1',
          title: 'Godaan',
          genre: 'Fiction',
          addedDate: 1,
        );
        const incoming = CatalogueItem(
          itemUid: 'u1',
          title: 'Godaan',
          genre: 'Classic',
          addedDate: 2,
        );
        // A finished merge with one row to review; its `resolve` is
        // scripted, its `mergeFile` is the real one.
        final controller = _ScriptedController(
          const MergeResult(
            added: 0,
            identical: 0,
            conflicts: [
              MergeConflict(
                local: local,
                incoming: incoming,
                matchedBy: MatchKind.uid,
              ),
            ],
            possibleDuplicates: [],
          ),
        );
        picker.willAnswer(const DocumentPickTooLarge());
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ...pickerOverrides(),
              mergeControllerProvider.overrideWith(() => controller),
            ],
            child: const MaterialApp(home: MergePage()),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Choose a library file'));
        await tester.pumpAndSettle();
        expect(find.text(tooLargeSentence), findsOneWidget);
        expect(find.text('Take theirs'), findsOneWidget);

        await tester.tap(find.text('Take theirs'));
        await tester.pumpAndSettle();

        expect(controller.calls, [(0, MergeResolution.takeTheirs)]);
        expect(find.text(tooLargeSentence), findsNothing);
      });
    });

    testWidgets('while the picker is open the button is off, the spinner '
        'shows, and an earlier choice cannot be acted on', (tester) async {
      final pickerOpen = Completer<void>();
      picker.willPick(_otherLibraryJson);
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose a library file'));
      await tester.pumpAndSettle();
      expect(find.text('Join (recommended)'), findsOneWidget);

      // The picker opens again and stays open.
      picker.holdNextPick = pickerOpen;
      await tester.tap(find.text('Choose a library file'));
      // Not `pumpAndSettle`: the spinner never comes to rest.
      await tester.pump();
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      final choose = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Choose a library file'),
      );
      expect(choose.onPressed, isNull);
      // Join and Replace are not on the page while a pick is under way.
      expect(find.text('Join (recommended)'), findsNothing);
      expect(find.text('Replace my library'), findsNothing);

      // The picker is closed without a choice: everything is back.
      pickerOpen.complete();
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Join (recommended)'), findsOneWidget);
    });

    testWidgets('while a Join or a Replace is being written the button is '
        'off', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...pickerOverrides(),
            mergeControllerProvider.overrideWith(
              () => _PinnedController(
                const MergeNeedsDecision(
                  MergeDiffersDecision(
                    incomingBooks: [],
                    incomingLibraryId: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
                    incomingLibraryName: 'Other',
                    localLibraryName: 'Mine',
                    localIsEmpty: false,
                  ),
                  applying: true,
                ),
              ),
            ),
          ],
          child: const MaterialApp(home: MergePage()),
        ),
      );
      await tester.pump();

      final choose = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Choose a library file'),
      );
      expect(choose.onPressed, isNull);
      expect(picker.caps, isEmpty);
    });
  });

  // Review finding N07: "do not describe a partial merge as complete
  // without explaining omissions". The result view must say what happened —
  // a replacement is a replacement, skipped rows and adjustments are listed,
  // and an identity that could not be adopted is called out.
  group('N07 — the summary is honest about omissions', () {
    /// Pumps the page with the merge controller already in [MergeDone].
    Future<void> pumpDone(WidgetTester tester, MergeResult result) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mergeControllerProvider.overrideWith(() => _DoneController(result)),
          ],
          child: const MaterialApp(home: MergePage()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a replacement is described as one, with the real count', (
      tester,
    ) async {
      await pumpDone(
        tester,
        const MergeResult(
          added: 12,
          identical: 0,
          conflicts: [],
          possibleDuplicates: [],
          replaced: true,
        ),
      );

      expect(find.text('Library replaced'), findsOneWidget);
      expect(find.text('Books now on this device: 12'), findsOneWidget);
      expect(find.text('Merge complete'), findsNothing);
      expect(find.textContaining('Books added'), findsNothing);
    });

    testWidgets('skipped rows and adjustments are listed', (tester) async {
      await pumpDone(
        tester,
        const MergeResult(
          added: 1,
          identical: 0,
          conflicts: [],
          possibleDuplicates: [],
          skippedRows: ['Book 2 skipped: copyCount must be at least 1.'],
          adjustments: ['Book 1: notes shortened to 8000 characters.'],
        ),
      );

      expect(find.text('Merge complete'), findsOneWidget);
      expect(find.text('Not imported'), findsOneWidget);
      expect(find.textContaining('Book 2 skipped: copyCount'), findsOneWidget);
      expect(find.text('Adjustments'), findsOneWidget);
      expect(find.textContaining('notes shortened'), findsOneWidget);
    });

    testWidgets('a failed identity adoption is called out', (tester) async {
      await pumpDone(
        tester,
        const MergeResult(
          added: 3,
          identical: 0,
          conflicts: [],
          possibleDuplicates: [],
          namespace: MergeNamespaceOutcome.adoptionFailed,
        ),
      );

      expect(find.text('Books added: 3'), findsOneWidget);
      expect(
        find.textContaining('could not take on the other library'),
        findsOneWidget,
      );
      expect(find.textContaining('ask you to Join again'), findsOneWidget);
    });

    testWidgets('a clean merge shows no omission sections', (tester) async {
      await pumpDone(
        tester,
        const MergeResult(
          added: 2,
          identical: 5,
          conflicts: [],
          possibleDuplicates: [],
          namespace: MergeNamespaceOutcome.adopted,
        ),
      );

      expect(find.text('Merge complete'), findsOneWidget);
      expect(find.text('Books added: 2'), findsOneWidget);
      expect(find.text('Already matched (no change): 5'), findsOneWidget);
      expect(find.text('Not imported'), findsNothing);
      expect(find.text('Adjustments'), findsNothing);
      expect(find.textContaining('could not take on'), findsNothing);
      expect(find.textContaining('later update'), findsNothing);
      expect(find.textContaining('Magazine titles'), findsNothing);
    });

    // Plan S19: the series counts ride the summary alongside the book counts
    // (ADR 0014 W1) — including the add-only conflicts (kept local, listed).
    testWidgets('periodical counts and kept-local titles are shown', (
      tester,
    ) async {
      await pumpDone(
        tester,
        const MergeResult(
          added: 1,
          identical: 2,
          conflicts: [],
          possibleDuplicates: [],
          periodicalsAdded: 1,
          periodicalsIdentical: 1,
          periodicalConflicts: [
            PeriodicalMergeConflict(
              local: Periodical(
                id: 3,
                periodicalUid: 'p1',
                title: 'Chandamama',
              ),
              incoming: Periodical(
                periodicalUid: 'p9',
                title: 'Chandamama Weekly',
              ),
              matchedBy: PeriodicalMatchKind.issn,
            ),
          ],
        ),
      );

      expect(find.text('Books added: 1'), findsOneWidget);
      expect(find.text('Magazine titles added: 1'), findsOneWidget);
      expect(find.text('Magazine titles already matched: 1'), findsOneWidget);
      expect(
        find.textContaining(
          'Magazine titles kept as they are on this device: 1',
        ),
        findsOneWidget,
      );
      expect(find.text('• Chandamama Weekly'), findsOneWidget);
      // Series conflicts are informational: no review section for them.
      expect(find.text('Needs your review'), findsNothing);
    });

    testWidgets('a replacement reports the series count as "now on this '
        'device"', (tester) async {
      await pumpDone(
        tester,
        const MergeResult(
          added: 12,
          identical: 0,
          conflicts: [],
          possibleDuplicates: [],
          replaced: true,
          periodicalsAdded: 2,
        ),
      );

      expect(find.text('Library replaced'), findsOneWidget);
      expect(
        find.text('Magazine titles now on this device: 2'),
        findsOneWidget,
      );
      expect(find.textContaining('Magazine titles added'), findsNothing);
    });
  });

  // Review finding N07 part 2: "conflicts/possible duplicates are counts
  // only, with no way to inspect or apply the implemented resolutions". Each
  // review item is a card showing what differs (or why it looks like a
  // duplicate) with the three resolutions as buttons.
  group('N07 — per-row review cards', () {
    const local = CatalogueItem(
      id: 1,
      itemUid: 'u1',
      title: 'Godaan',
      author: 'Premchand',
      genre: 'Fiction',
      addedDate: 1,
    );
    const incoming = CatalogueItem(
      itemUid: 'u1',
      title: 'Godaan',
      author: 'Premchand',
      genre: 'Classic',
      notes: 'Their note',
      addedDate: 2,
    );

    MergeResult resultWith({
      List<MergeConflict> conflicts = const [],
      List<PossibleDuplicate> duplicates = const [],
    }) => MergeResult(
      added: 0,
      identical: 0,
      conflicts: conflicts,
      possibleDuplicates: duplicates,
    );

    Future<_ScriptedController> pumpReview(
      WidgetTester tester,
      MergeResult result, {
      Failure? failWith,
    }) async {
      final controller = _ScriptedController(result, failWith: failWith);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [mergeControllerProvider.overrideWith(() => controller)],
          child: const MaterialApp(home: MergePage()),
        ),
      );
      await tester.pumpAndSettle();
      return controller;
    }

    testWidgets('a conflict card shows the differing fields, yours → theirs, '
        'and all three actions', (tester) async {
      await pumpReview(
        tester,
        resultWith(
          conflicts: const [
            MergeConflict(
              local: local,
              incoming: incoming,
              matchedBy: MatchKind.uid,
            ),
          ],
        ),
      );

      expect(find.text('Needs your review'), findsOneWidget);
      expect(find.text('Godaan'), findsOneWidget);
      expect(find.textContaining('Genre'), findsOneWidget);
      expect(find.textContaining('Fiction'), findsOneWidget);
      expect(find.textContaining('Classic'), findsOneWidget);
      expect(find.textContaining('Notes'), findsOneWidget);
      expect(find.textContaining('Their note'), findsOneWidget);
      // Unchanged fields are not listed.
      expect(find.textContaining('Premchand'), findsNothing);
      expect(find.text('Keep mine'), findsOneWidget);
      expect(find.text('Take theirs'), findsOneWidget);
      expect(find.text('Keep both'), findsOneWidget);
      // The old count-only line is gone.
      expect(find.textContaining('Your versions were kept'), findsNothing);
    });

    testWidgets('tapping Take theirs calls resolve with the row index and '
        'the card shows the resolved line', (tester) async {
      final controller = await pumpReview(
        tester,
        resultWith(
          conflicts: const [
            MergeConflict(
              local: local,
              incoming: incoming,
              matchedBy: MatchKind.uid,
            ),
          ],
        ),
      );

      await tester.tap(find.text('Take theirs'));
      await tester.pumpAndSettle();

      expect(controller.calls, [(0, MergeResolution.takeTheirs)]);
      expect(find.text('Take theirs'), findsNothing);
      expect(find.textContaining('Took theirs'), findsOneWidget);
    });

    testWidgets('a fuzzy possible duplicate shows both titles and the '
        'similarity; a key collision shows a plain explanation and NO Take '
        'theirs', (tester) async {
      const earlierIncoming = CatalogueItem(
        itemUid: 'uB',
        title: 'Godaan',
        addedDate: 1,
      );
      await pumpReview(
        tester,
        resultWith(
          duplicates: const [
            PossibleDuplicate(
              local: CatalogueItem(id: 3, title: 'Kabir ke Dohe', addedDate: 1),
              incoming: CatalogueItem(title: 'Kabir Dohe', addedDate: 1),
              similarity: 0.75,
            ),
            PossibleDuplicate(
              local: earlierIncoming,
              incoming: CatalogueItem(
                itemUid: 'uB',
                title: 'Godaan (duplicate row)',
                addedDate: 1,
              ),
              similarity: 1,
              reason: DuplicateReason.identityKey,
            ),
          ],
        ),
      );

      // Fuzzy card.
      expect(find.textContaining('Kabir ke Dohe'), findsOneWidget);
      expect(find.textContaining('Kabir Dohe'), findsOneWidget);
      expect(find.textContaining('75%'), findsOneWidget);
      // Collision card: explains the same-file situation, offers skip/add.
      expect(find.textContaining('Godaan (duplicate row)'), findsOneWidget);
      expect(find.textContaining('same file'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
      expect(find.text('Add as a separate book'), findsOneWidget);
      // Exactly one Take theirs on screen: the fuzzy card's.
      expect(find.text('Take theirs'), findsOneWidget);
    });

    testWidgets('a failed resolution shows safe copy and keeps the actions '
        'for a retry', (tester) async {
      final controller = await pumpReview(
        tester,
        resultWith(
          conflicts: const [
            MergeConflict(
              local: local,
              incoming: incoming,
              matchedBy: MatchKind.uid,
            ),
          ],
        ),
        failWith: const StorageFailure('disk full: /data/x'),
      );

      await tester.tap(find.text('Take theirs'));
      await tester.pumpAndSettle();

      expect(controller.calls, hasLength(1));
      expect(find.textContaining('disk full'), findsNothing);
      expect(find.textContaining('Could not apply'), findsOneWidget);
      expect(find.text('Take theirs'), findsOneWidget, reason: 'retry');
    });

    testWidgets('while one row is applying, its buttons and the file picker '
        'are disabled', (tester) async {
      final controller = await pumpReview(
        tester,
        resultWith(
          conflicts: const [
            MergeConflict(
              local: local,
              incoming: incoming,
              matchedBy: MatchKind.uid,
            ),
          ],
        ),
      );
      controller.hold = true;

      await tester.tap(find.text('Take theirs'));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Take theirs'), findsNothing);
      final pick = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Choose a library file'),
      );
      expect(pick.onPressed, isNull);

      controller.release();
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('a summary with nothing to review shows no review section', (
      tester,
    ) async {
      await pumpReview(tester, resultWith());
      expect(find.text('Needs your review'), findsNothing);
    });
  });

  testWidgets('meets accessibility guidelines', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: MergePage())),
    );
    await tester.pumpAndSettle();
    await expectMeetsA11yGuidelines(tester);
  });
}

/// A merge controller pinned to [MergeDone] whose `resolve` is scripted: it
/// records every call, optionally parks ([hold]) and optionally fails with
/// the failure given at construction. Lets the page tests drive the review
/// cards without a repository.
class _ScriptedController extends MergeController {
  _ScriptedController(this._result, {Failure? failWith}) : _failWith = failWith;

  final MergeResult _result;
  final Failure? _failWith;

  /// Every `(index, resolution)` the page asked for.
  final calls = <(int, MergeResolution)>[];

  /// When true, `resolve` stays in [ReviewApplying] until [release].
  bool hold = false;
  Completer<void>? _gate;

  void release() => _gate?.complete();

  @override
  MergeUiState build() => MergeDone(_result);

  @override
  Future<void> resolve(int index, MergeResolution resolution) async {
    calls.add((index, resolution));
    final done = state as MergeDone;
    state = done.withItemStatus(index, const ReviewApplying());
    if (hold) {
      _gate = Completer<void>();
      await _gate!.future;
    }
    final failure = _failWith;
    state = (state as MergeDone).withItemStatus(
      index,
      failure == null ? ReviewResolved(resolution) : ReviewFailed(failure),
    );
  }
}

/// A merge controller pinned to any one state, for rendering the page in a
/// state that is hard to stop a real merge in.
class _PinnedController extends MergeController {
  _PinnedController(this._state);

  final MergeUiState _state;

  @override
  MergeUiState build() => _state;
}

/// A merge controller pinned to one terminal state, for rendering the
/// summary without driving a whole merge through the picker.
class _DoneController extends MergeController {
  _DoneController(this._result);

  final MergeResult _result;

  @override
  MergeUiState build() => MergeDone(_result);
}
