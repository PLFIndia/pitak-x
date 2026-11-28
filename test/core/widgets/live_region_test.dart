import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/widgets/live_region.dart';

import '../../support/live_regions.dart';

/// Decision D190: the sentence of a finished run is read out by a screen
/// reader when it appears. `LiveRegion` is the one widget both pages use
/// for it.
void main() {
  const note = 'The backup is an ordinary file.';
  const progress = 'Cover 1 of 2';
  const sentence = 'Backup saved as pitak-backup-02Nov2026-134659.pitabak.';
  const second = 'Note: the borrowers vault is not inside this backup.';

  /// A page as both pages are built since D177: a list whose last item
  /// holds a button, a note, a progress line and then [result].
  Widget page(Widget result) => MaterialApp(
    home: Scaffold(
      body: ListView(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(onPressed: () {}, child: const Text('Save')),
              const Text(note),
              const Text(progress),
              result,
            ],
          ),
        ],
      ),
    ),
  );

  testWidgets('inside a list item the region is a node of its own: it is '
      'live, it holds its own words, and its neighbours are not part of '
      'it', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(page(const LiveRegion(child: Text(sentence))));

    // ONE live region on the page, and it says the sentence and nothing
    // else: not the note above it, and not the progress line.
    expect(liveRegionLabels(tester), [sentence]);

    // The neighbours keep a node that is not live, without the sentence.
    final neighbours = tester.getSemantics(find.text(note)).getSemanticsData();
    expect(neighbours.flagsCollection.isLiveRegion, isFalse);
    expect(neighbours.label, contains(note));
    expect(neighbours.label, contains(progress));
    expect(neighbours.label, isNot(contains(sentence)));
    handle.dispose();
  });

  testWidgets('two texts inside one region are read as one, in their '
      'order', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      page(
        const LiveRegion(
          child: Column(children: [Text(sentence), Text(second)]),
        ),
      ),
    );

    expect(liveRegionLabels(tester), ['$sentence\n$second']);
    handle.dispose();
  });

  testWidgets('a page without a region has no live region at all', (
    tester,
  ) async {
    // The check of the helper itself: it can answer "none".
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(page(const Text(sentence)));

    expect(liveRegionLabels(tester), isEmpty);
    handle.dispose();
  });
}
