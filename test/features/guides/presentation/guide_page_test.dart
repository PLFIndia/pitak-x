import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/theme/app_theme.dart';
import 'package:pitaka/features/guides/domain/guide.dart';
import 'package:pitaka/features/guides/domain/guide_catalog.dart';
import 'package:pitaka/features/guides/presentation/pages/guide_page.dart';
import 'package:pitaka/features/guides/presentation/widgets/guide_text.dart';

import '../../../support/a11y.dart';

void main() {
  /// Pumps [guide] with a recording opener. Phone width (360 dp) so wrapping
  /// is realistic; 3000 dp tall so the lazy ListView builds every child —
  /// the longest guides (catalogue ≈ 2880 dp, backup ≈ 2800 dp) end inside
  /// that under the test font — and the a11y checks see every node, bottom
  /// button included. A guide that outgrows the surface fails the "every
  /// guide renders" test below: that is the copy-length budget, on purpose.
  Future<List<GuideDestination>> pumpGuide(
    WidgetTester tester,
    Guide guide,
  ) async {
    tester.view.physicalSize = const Size(1080, 9000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final opened = <GuideDestination>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: GuidePage(
          guide: guide,
          openDestination: (_, destination) => opened.add(destination),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    return opened;
  }

  group('publish guide', () {
    testWidgets('renders intro, chips, six numbered steps and the callout', (
      tester,
    ) async {
      await pumpGuide(tester, guideById(GuideId.publish));

      expect(find.text('Put your catalogue online'), findsOneWidget);
      expect(
        find.textContaining('Pitak can turn your book list'),
        findsOneWidget,
      );

      // "You need" chips.
      expect(find.text('You need'), findsOneWidget);
      expect(find.byType(Chip), findsNWidgets(2));
      expect(find.text('Internet'), findsOneWidget);

      // Section headings and the six step bubbles.
      expect(find.text('First time'), findsOneWidget);
      expect(find.text('Every time after that'), findsOneWidget);
      for (var n = 1; n <= 6; n++) {
        expect(find.text('$n'), findsOneWidget, reason: 'step bubble $n');
      }
      expect(find.text('7'), findsNothing);

      expect(find.text('Good to know'), findsOneWidget);
      expect(find.text('Open Publish to web →'), findsOneWidget);
    });

    testWidgets('a **bold** label becomes a bold TextSpan', (tester) async {
      await pumpGuide(tester, guideById(GuideId.publish));

      // Step 5 is the shortest: "Tap **Publish catalogue now**."
      final step = tester.widget<GuideText>(
        find.byWidgetPredicate(
          (w) => w is GuideText && w.source == 'Tap **Publish catalogue now**.',
        ),
      );
      final richText = tester.widget<RichText>(
        find.descendant(
          of: find.byWidget(step),
          matching: find.byType(RichText),
        ),
      );
      final spans = <TextSpan>[];
      richText.text.visitChildren((span) {
        if (span is TextSpan && span.text != null) spans.add(span);
        return true;
      });
      expect(spans.map((s) => s.text), ['Tap ', 'Publish catalogue now', '.']);
      expect(spans[1].style?.fontWeight, FontWeight.w600);
      expect(spans[0].style?.fontWeight, isNull);
    });

    testWidgets("the bottom button calls openDestination with the guide's "
        'destination', (tester) async {
      final opened = await pumpGuide(tester, guideById(GuideId.publish));

      await tester.tap(
        find.widgetWithText(FilledButton, 'Open Publish to web →'),
      );
      await tester.pump();

      expect(opened, [GuideDestination.publishConnection]);
    });
  });

  testWidgets('a guide with no "You need" shows no chip row', (tester) async {
    await pumpGuide(tester, guideById(GuideId.vault));

    expect(find.text('You need'), findsNothing);
    expect(find.byType(Chip), findsNothing);
  });

  testWidgets('a guide with no "Good to know" shows no callout', (
    tester,
  ) async {
    await pumpGuide(tester, guideById(GuideId.network));

    expect(find.text('Good to know'), findsNothing);
    expect(find.text('Open Library network →'), findsOneWidget);
  });

  testWidgets('the backup guide renders the picker table', (tester) async {
    await pumpGuide(tester, guideById(GuideId.backup));

    expect(find.byType(Table), findsOneWidget);
    expect(find.text('I want to…'), findsOneWidget);
    expect(find.text('Use'), findsOneWidget);
    expect(find.textContaining('Bring that copy back'), findsOneWidget);
    expect(find.textContaining('Merge from a file'), findsOneWidget);
  });

  testWidgets('every guide renders without layout errors at phone width', (
    tester,
  ) async {
    for (final guide in guideCatalog) {
      await pumpGuide(tester, guide);
      expect(find.text(guide.title), findsOneWidget, reason: '${guide.id}');
      expect(
        find.text('${guide.destinationLabel} →'),
        findsOneWidget,
        reason: '${guide.id}',
      );
    }
  });

  testWidgets('each destination button maps 1:1 to its guide', (tester) async {
    for (final guide in guideCatalog) {
      final opened = await pumpGuide(tester, guide);
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(opened, [guide.destination], reason: '${guide.id}');
    }
  });

  testWidgets('meets accessibility guidelines (longest guide, backup)', (
    tester,
  ) async {
    await pumpGuide(tester, guideById(GuideId.backup));
    await expectMeetsA11yGuidelines(tester);
  });

  testWidgets('meets accessibility guidelines (publish, with chips)', (
    tester,
  ) async {
    await pumpGuide(tester, guideById(GuideId.publish));
    await expectMeetsA11yGuidelines(tester);
  });

  testWidgets('meets accessibility guidelines (catalogue, table + bullets)', (
    tester,
  ) async {
    await pumpGuide(tester, guideById(GuideId.catalogue));
    await expectMeetsA11yGuidelines(tester);
  });
}
