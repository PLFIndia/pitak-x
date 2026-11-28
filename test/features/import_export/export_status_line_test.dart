import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/theme/app_theme.dart';
import 'package:pitaka/features/import_export/application/export_controller.dart';
import 'package:pitaka/features/import_export/presentation/widgets/export_status_line.dart';

import '../../support/a11y.dart';
import '../../support/live_regions.dart';

/// Decision D193: the sentence of a finished export, drawn by how the run
/// ended. The page's own tests hold WHICH colour each ending gets; this
/// file holds that each colour can be READ, in the app's real themes.
void main() {
  // One ending of each kind.
  const endings = <String, ExportRunResult>{
    'a success': ExportRunResult(ExportOutcome.saved, fileName: 'a.csv'),
    'a notice': ExportRunResult(ExportOutcome.saveCancelled),
    'a failure': ExportRunResult(ExportOutcome.saveLeftBehind),
  };

  Widget line(ThemeData theme, ExportRunResult result, {GlobalKey? key}) =>
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: ExportStatusLine(
              result: result,
              sentenceKey: key ?? GlobalKey(),
            ),
          ),
        ),
      );

  for (final MapEntry(key: themeName, value: theme) in <String, ThemeData>{
    'light': AppTheme.light,
    'dark': AppTheme.dark,
  }.entries) {
    for (final MapEntry(key: kind, value: result) in endings.entries) {
      testWidgets('$themeName theme: $kind has enough contrast on the page', (
        tester,
      ) async {
        await tester.pumpWidget(line(theme, result));
        await tester.pumpAndSettle();

        await expectMeetsTextContrast(tester);
      });
    }
  }

  testWidgets('the sentence carries the key the page scrolls to (D177), and '
      'is one live region (D190)', (tester) async {
    final handle = tester.ensureSemantics();
    final key = GlobalKey();
    await tester.pumpWidget(
      line(AppTheme.light, endings['a success']!, key: key),
    );

    expect(tester.widget<Text>(find.byKey(key)).data, 'Saved as a.csv.');
    expect(liveRegionLabels(tester), ['Saved as a.csv.']);
    handle.dispose();
  });
}
