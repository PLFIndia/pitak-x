import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/application/publish_result.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_remote_anchor.dart';
import 'package:pitaka/features/publish/presentation/widgets/replace_site_dialog.dart';

import 'support/cloudflare_fakes.dart';

void main() {
  final target = cloudflareTestConnection().status.target!;

  PublishReplacementSummary targetChanged({required bool workerExists}) =>
      PublishReplacementSummary(
        target: target,
        requestedSection: PublishRequestedSection.catalogue,
        digest: 'a' * 64,
        catalogueItemCount: 3,
        posterCount: 0,
        availabilityOmitted: false,
        remoteAnchor: CloudflareRemoteAnchor(
          workerExists: workerExists,
          markerKind: CloudflareMarkerKind.absent,
        ),
        reason: PublishReplacementReason.targetChanged,
        previousSiteUrl: 'https://old.example-sub.workers.dev/',
      );

  Future<void> open(WidgetTester tester, PublishReplacementSummary s) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => unawaited(showReplaceSiteDialog(context, s)),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  // Regression (handoff §12, 2026-10-31): the counts were bracketed twice,
  // so the phone showed "catalogue ((3 items) and 0 event posters)".
  for (final exists in [true, false]) {
    testWidgets('the target-changed review brackets the counts once '
        '(workerExists: $exists)', (tester) async {
      await open(tester, targetChanged(workerExists: exists));

      expect(
        find.textContaining(
          'with this phone’s catalogue (3 items) and 0 event posters.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('(('), findsNothing);
    });
  }
}
