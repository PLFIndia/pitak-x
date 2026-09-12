import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

// Existing file_selector dependency's test seam; no runtime dependency added.
// ignore: depend_on_referenced_packages
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/import_export/application/merge_controller.dart';
import 'package:pitaka/features/import_export/application/merge_library_use_case.dart';
import 'package:pitaka/features/import_export/infrastructure/pitaka_json_importer.dart';
import 'package:pitaka/features/import_export/presentation/pages/merge_page.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/domain/merge/library_merge_engine.dart';
import 'package:pitaka/features/library/domain/repositories/book_repository.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';

import '../library/replacement_harness.dart';
import '../library/replacement_test_guard.dart';

class _Picker extends FileSelectorPlatform {
  _Picker([Uint8List? bytes]) : _file = null, _bytes = bytes ?? _defaultJson;

  /// Hands back a specific [XFile] (e.g. the strict-decoding one below).
  _Picker.file(this._file) : _bytes = null;

  final Uint8List? _bytes;
  final XFile? _file;

  static final Uint8List _defaultJson = Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'schemaVersion': 3,
        'libraryId': 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        'libraryName': 'Other',
        'books': [
          {'title': 'Incoming', 'bookUid': 'new'},
        ],
        'wishlist': <Object>[],
      }),
    ),
  );

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async => _file ?? XFile.fromData(_bytes!, name: 'test.json');
}

/// An [XFile] whose `readAsString` STRICTLY decodes UTF-8 (throws on
/// malformed bytes) — like the real path-backed file the picker returns on
/// device. `XFile.fromData` never throws (it maps bytes to code points),
/// which would hide the difference between the old `readAsString` path and
/// the shared bounded read + lenient decode.
class _StrictXFile extends XFile {
  _StrictXFile(this._bytes) : super('fake.json');

  final Uint8List _bytes;

  @override
  Future<int> length() async => _bytes.length;

  @override
  Stream<Uint8List> openRead([int? start, int? end]) async* {
    yield _bytes.sublist(start ?? 0, end);
  }

  @override
  Future<Uint8List> readAsBytes() async => _bytes;

  @override
  Future<String> readAsString({Encoding encoding = utf8}) async =>
      encoding.decode(_bytes);
}

class _Books implements BookRepository {
  @override
  Future<Either<Failure, List<Book>>> getAll() async =>
      right([const Book(id: 7, title: 'Local', bookUid: 'old')]);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
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
      final previous = FileSelectorPlatform.instance;
      addTearDown(() => FileSelectorPlatform.instance = previous);
      FileSelectorPlatform.instance = _Picker();
      final guard = FakeReplacementGuard(
        failure: const ValidationFailure(
          'Existing loan history cannot be matched.',
        ),
      );
      final settings = ReplacementSettings();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsRepositoryProvider.overrideWith((ref) async => settings),
            mergeLibraryUseCaseProvider.overrideWith(
              (ref) async => MergeLibraryUseCase(
                bookRepo: _Books(),
                namespace: ref.read(settingsControllerProvider.notifier),
                jsonParser: const PitakaJsonImporter(),
                replacementGuard: guard,
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
    final previous = FileSelectorPlatform.instance;
    addTearDown(() => FileSelectorPlatform.instance = previous);
    FileSelectorPlatform.instance = _Picker();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWith(
            (ref) async => ReplacementSettings(),
          ),
          mergeLibraryUseCaseProvider.overrideWith((ref) async {
            await gate.future;
            return MergeLibraryUseCase(
              bookRepo: _Books(),
              namespace: ref.read(settingsControllerProvider.notifier),
              jsonParser: const PitakaJsonImporter(),
              replacementGuard: FakeReplacementGuard(),
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
    final previous = FileSelectorPlatform.instance;
    addTearDown(() => FileSelectorPlatform.instance = previous);
    FileSelectorPlatform.instance = _Picker();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
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
    // The old length-then-readAsString path THREW on malformed UTF-8 and showed
    // the read-failure copy; the shared bounded read + lenient decode lets the
    // parser reject it with merge-specific copy instead.
    final previous = FileSelectorPlatform.instance;
    addTearDown(() => FileSelectorPlatform.instance = previous);
    FileSelectorPlatform.instance = _Picker.file(
      _StrictXFile(Uint8List.fromList([0xFF, 0xFE, 0xFD, 0x00, 0x01])),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWith(
            (ref) async => ReplacementSettings(),
          ),
          mergeLibraryUseCaseProvider.overrideWith(
            (ref) async => MergeLibraryUseCase(
              bookRepo: _Books(),
              namespace: ref.read(settingsControllerProvider.notifier),
              jsonParser: const PitakaJsonImporter(),
              replacementGuard: FakeReplacementGuard(),
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

  // N07 (astra-review.md): "do not describe a partial merge as complete
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
    });
  });

  // N07 part 2 (astra-review.md): "conflicts/possible duplicates are counts
  // only, with no way to inspect or apply the implemented resolutions". Each
  // review item is a card showing what differs (or why it looks like a
  // duplicate) with the three resolutions as buttons.
  group('N07 — per-row review cards', () {
    const local = Book(
      id: 1,
      bookUid: 'u1',
      title: 'Godaan',
      author: 'Premchand',
      genre: 'Fiction',
      addedDate: 1,
    );
    const incoming = Book(
      bookUid: 'u1',
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
      const earlierIncoming = Book(
        bookUid: 'uB',
        title: 'Godaan',
        addedDate: 1,
      );
      await pumpReview(
        tester,
        resultWith(
          duplicates: const [
            PossibleDuplicate(
              local: Book(id: 3, title: 'Kabir ke Dohe', addedDate: 1),
              incoming: Book(title: 'Kabir Dohe', addedDate: 1),
              similarity: 0.75,
            ),
            PossibleDuplicate(
              local: earlierIncoming,
              incoming: Book(
                bookUid: 'uB',
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

/// A merge controller pinned to one terminal state, for rendering the
/// summary without driving a whole merge through the picker.
class _DoneController extends MergeController {
  _DoneController(this._result);

  final MergeResult _result;

  @override
  MergeUiState build() => MergeDone(_result);
}
