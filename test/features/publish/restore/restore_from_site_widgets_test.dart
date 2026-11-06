import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/async/serial_op_queue.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/import_export/application/import_library_use_case.dart';
import 'package:pitaka/features/import_export/domain/import_format_sniffer.dart';
import 'package:pitaka/features/publish/application/restore/restore_from_published_site_controller.dart';
import 'package:pitaka/features/publish/application/restore/restore_from_published_site_result.dart';
import 'package:pitaka/features/publish/application/site/publish_site_status.dart';
import 'package:pitaka/features/publish/application/site/publish_site_status_controller.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/restore/restore_identity_journal.dart';
import 'package:pitaka/features/publish/presentation/widgets/restore_from_site_dialog.dart';
import 'package:pitaka/features/publish/presentation/widgets/restore_from_site_section.dart';
import 'package:pitaka/features/publish/presentation/widgets/restore_from_site_summary.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'restore_use_case_harness.dart';

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

  testWidgets(
    'pending journal after restart shows recovery and hides restore',
    (tester) async {
      final target = GitHubPublishTarget.create('me/lib')!;
      final journal = RestoreIdentityJournal(
        siteUrl: target.siteUrl,
        addedDate: 100,
        fingerprint: 'a' * 64,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            publishSiteStatusProvider.overrideWith(
              (ref) async => PublishSiteStatus(
                activeHost: null,
                target: target,
                verifiedSiteUrl: target.siteUrl,
                setupMessage: null,
              ),
            ),
            pendingRestoreIdentityProvider.overrideWith((ref) async => journal),
          ],
          child: const MaterialApp(
            home: Scaffold(body: RestoreFromSiteSection()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Published identity recovery pending'), findsOneWidget);
      expect(find.textContaining(target.siteUrl), findsOneWidget);
      expect(find.text('Finish identity recovery'), findsOneWidget);
      expect(find.byIcon(Icons.restore), findsNothing);
    },
  );

  testWidgets('Done dismisses a terminal result and restores the idle action', (
    tester,
  ) async {
    final h = RestoreUseCaseHarness();
    SharedPreferences.setMockInitialValues({});
    final target = GitHubPublishTarget.create('me/lib')!;
    final container = ProviderContainer(
      overrides: [
        activePublishTargetResolverProvider.overrideWith(
          (ref) async => h.resolver,
        ),
        restoreFromPublishedSiteUseCaseProvider(
          h.siteUrl,
        ).overrideWith((ref) async => h.useCase),
        recoverPublishedIdentityProvider.overrideWith((ref) async => h.recover),
        catalogueItemRepositoryProvider.overrideWith(
          (ref) async => h.fixture.books,
        ),
        periodicalRepositoryProvider.overrideWith(
          (ref) async => h.fixture.periodicals,
        ),
        publishOperationQueueProvider.overrideWithValue(SerialOpQueue()),
        publishSiteStatusProvider.overrideWith(
          (ref) async => PublishSiteStatus(
            activeHost: null,
            target: target,
            verifiedSiteUrl: target.siteUrl,
            setupMessage: null,
          ),
        ),
        pendingRestoreIdentityProvider.overrideWith((ref) async => null),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await h.dispose();
    });
    await tester.runAsync(
      () => container
          .read(restoreFromPublishedSiteControllerProvider.notifier)
          .restore(downloadCovers: true),
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: RestoreFromSiteSection()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Done'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pump();
    await tester.pump();

    expect(find.byIcon(Icons.restore), findsOneWidget);
    expect(find.text('Restore complete'), findsNothing);
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
      coversFailed: 1,
      coversSkippedByBudget: 1,
      coversNotDownloaded: 0,
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
    expect(find.text('Covers skipped or failed: 1'), findsOneWidget);
    expect(find.textContaining('download budget was reached'), findsOneWidget);
    expect(find.textContaining('Private'), findsOneWidget);
    expect(find.textContaining('Make a backup now'), findsNothing);
    await tester.tap(find.text('Finish identity recovery'));
    expect(recoveries, 1);
  });
}
