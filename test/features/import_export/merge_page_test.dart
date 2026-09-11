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
import 'package:pitaka/features/import_export/application/merge_library_use_case.dart';
import 'package:pitaka/features/import_export/infrastructure/pitaka_json_importer.dart';
import 'package:pitaka/features/import_export/presentation/pages/merge_page.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/domain/repositories/book_repository.dart';

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
      final useCase = MergeLibraryUseCase(
        bookRepo: _Books(),
        settings: settings,
        jsonParser: const PitakaJsonImporter(),
        replacementGuard: guard,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mergeLibraryUseCaseProvider.overrideWith((ref) async => useCase),
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
    final useCase = MergeLibraryUseCase(
      bookRepo: _Books(),
      settings: ReplacementSettings(),
      jsonParser: const PitakaJsonImporter(),
      replacementGuard: FakeReplacementGuard(),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mergeLibraryUseCaseProvider.overrideWith((ref) async {
            await gate.future;
            return useCase;
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
    final useCase = MergeLibraryUseCase(
      bookRepo: _Books(),
      settings: ReplacementSettings(),
      jsonParser: const PitakaJsonImporter(),
      replacementGuard: FakeReplacementGuard(),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mergeLibraryUseCaseProvider.overrideWith((ref) async => useCase),
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
}
