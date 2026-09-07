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
  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async => XFile.fromData(
    Uint8List.fromList(
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
    ),
    name: 'test.json',
  );
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
}
