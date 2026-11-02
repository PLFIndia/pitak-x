import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/backup/domain/archive_inspection.dart';
import 'package:pitaka/features/backup/domain/backup_manifest.dart';
import 'package:pitaka/features/backup/domain/restore_summary.dart';
import 'package:pitaka/features/backup/presentation/widgets/restore_summary_widgets.dart';
import 'package:pitaka/features/publish/domain/publish_state_adoption.dart';
import 'package:pitaka/features/publish/domain/publish_state_backup.dart';

import '../publish/support/publish_state_fixtures.dart';

/// The website publishing record's lines on the Restore screen (plan CV6/
/// CV7, S11): named in the contents list, and one plain sentence for what
/// the restore did with it.
void main() {
  Future<void> pump(WidgetTester tester, Widget child, {bool dark = false}) =>
      tester.pumpWidget(
        MaterialApp(
          theme: dark ? ThemeData.dark() : ThemeData.light(),
          home: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      );

  RestoreSummary summary({
    PublishStateRestoreOutcome? outcome,
    bool invalid = false,
  }) => RestoreSummary(
    booksRestored: 3,
    wishlistRestored: 0,
    borrowersRestored: 0,
    loansRestored: 0,
    publishStateInvalid: invalid,
    publishStateOutcome: outcome,
  );

  group('contents list', () {
    testWidgets('names the site of a readable record', (tester) async {
      await pump(
        tester,
        RestoreManifestSummary(
          inspection: ArchiveInspection(
            manifest: const BackupManifest(
              exportedAt: 0,
              hasPublishState: true,
            ),
            publishState: archivedState(),
          ),
        ),
      );
      expect(
        find.text(
          '• Website publishing record for '
          'https://degt3rt.github.io/my-library/ '
          '(used only if this phone has not published yet)',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a record without an active site is still listed', (
      tester,
    ) async {
      await pump(
        tester,
        RestoreManifestSummary(
          inspection: ArchiveInspection(
            manifest: const BackupManifest(
              exportedAt: 0,
              hasPublishState: true,
            ),
            publishState: PublishStateBackup.tryCreate(
              coverSalt: archiveSalt,
              cloudflareRecord: cloudflareRecord(),
            ),
          ),
        ),
      );
      expect(
        find.textContaining('• Website publishing record'),
        findsOneWidget,
      );
    });

    testWidgets('an unreadable record is called out, not promised', (
      tester,
    ) async {
      await pump(
        tester,
        const RestoreManifestSummary(
          inspection: ArchiveInspection(
            manifest: BackupManifest(exportedAt: 0, hasPublishState: true),
          ),
        ),
      );
      expect(
        find.text(
          '• Website publishing record (unreadable — it will not be used)',
        ),
        findsOneWidget,
      );
    });

    testWidgets('no record, no line', (tester) async {
      await pump(
        tester,
        const RestoreManifestSummary(
          inspection: ArchiveInspection(
            manifest: BackupManifest(exportedAt: 0),
          ),
        ),
      );
      expect(find.textContaining('publishing record'), findsNothing);
    });
  });

  group('outcome sentence', () {
    for (final dark in [false, true]) {
      testWidgets('adopted (${dark ? 'dark' : 'light'})', (tester) async {
        await pump(
          tester,
          RestoreOutcome(
            state: AsyncData(
              summary(outcome: PublishStateRestoreOutcome.adopted),
            ),
          ),
          dark: dark,
        );
        expect(
          find.textContaining(
            'This phone now continues the website from the backup',
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining('will not be uploaded again'),
          findsOneWidget,
        );
      });
    }

    testWidgets('kept: the plan wording', (tester) async {
      await pump(
        tester,
        RestoreOutcome(
          state: AsyncData(
            summary(outcome: PublishStateRestoreOutcome.keptThisPhone),
          ),
        ),
      );
      expect(
        find.text('Publishing settings on this phone were kept.'),
        findsOneWidget,
      );
    });

    testWidgets('not applied', (tester) async {
      await pump(
        tester,
        RestoreOutcome(
          state: AsyncData(
            summary(outcome: PublishStateRestoreOutcome.notApplied),
          ),
        ),
      );
      expect(find.textContaining('could not be applied'), findsOneWidget);
    });

    testWidgets('unreadable', (tester) async {
      await pump(
        tester,
        RestoreOutcome(state: AsyncData(summary(invalid: true))),
      );
      expect(find.textContaining('could not be read'), findsOneWidget);
    });

    testWidgets('no record: no sentence', (tester) async {
      await pump(tester, RestoreOutcome(state: AsyncData(summary())));
      expect(find.textContaining('publishing'), findsNothing);
    });
  });
}
