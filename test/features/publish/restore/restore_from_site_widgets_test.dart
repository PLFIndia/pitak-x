import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/import_export/application/import_library_use_case.dart';
import 'package:pitaka/features/import_export/domain/import_format_sniffer.dart';
import 'package:pitaka/features/publish/application/restore/restore_from_published_site_result.dart';
import 'package:pitaka/features/publish/presentation/widgets/restore_from_site_dialog.dart';
import 'package:pitaka/features/publish/presentation/widgets/restore_from_site_summary.dart';

void main() {
  testWidgets('restore dialog explains losses and returns cover consent', (
    tester,
  ) async {
    bool? covers;
    var completed = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: false),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              covers = await showRestoreFromSiteDialog(
                context,
                siteUrl: 'https://me.github.io/lib/',
              );
              completed = true;
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('https://me.github.io/lib/'), findsOneWidget);
    expect(find.textContaining('Your catalogue must be empty'), findsOneWidget);
    final checkbox = tester.widget<CheckboxListTile>(
      find.byType(CheckboxListTile),
    );
    expect(checkbox.value, isTrue);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();

    expect(completed, isTrue);
    expect(covers, isFalse);
  });

  testWidgets('summary names budget loss and offers identity recovery', (
    tester,
  ) async {
    var recoveries = 0;
    const summary = RestoreFromPublishedSiteSummary(
      import: ImportSummary(
        format: ImportFormat.pitakaBundle,
        booksAdded: 2,
        booksSkipped: 1,
        periodicalsAdded: 1,
      ),
      rowsDropped: 3,
      droppedFields: 4,
      issuesFiledAsBooks: 1,
      coversRestored: 2,
      coversSkipped: 2,
      coversSkippedByBudget: 1,
      thirdPartyCoverLinks: 1,
      downloadCovers: true,
      identityMissing: false,
      identityPending: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: false),
        home: Scaffold(
          body: SingleChildScrollView(
            child: RestoreFromSiteSummary(
              summary: summary,
              onRecoverIdentity: () => recoveries++,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Items added: 2'), findsOneWidget);
    expect(find.textContaining('download budget was reached'), findsOneWidget);
    expect(find.textContaining('Private'), findsOneWidget);
    expect(find.textContaining('Make a backup now'), findsNothing);
    await tester.tap(find.text('Finish identity recovery'));
    expect(recoveries, 1);
  });
}
