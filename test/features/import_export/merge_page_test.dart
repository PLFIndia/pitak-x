import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/import_export/presentation/pages/merge_page.dart';

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
}
