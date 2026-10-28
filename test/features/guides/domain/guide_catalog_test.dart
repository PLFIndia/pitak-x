/// Invariants of the guide copy (appinfo plan §2). These are the checks a
/// reviewer would otherwise do by eye on every copy edit.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/guides/domain/guide.dart';
import 'package:pitaka/features/guides/domain/guide_catalog.dart';
import 'package:pitaka/features/guides/domain/guide_markup.dart';

void main() {
  test('exactly six guides, unique ids, in the approved order', () {
    expect(guideCatalog.map((g) => g.id).toList(), [
      GuideId.catalogue,
      GuideId.publish,
      GuideId.map,
      GuideId.backup,
      GuideId.vault,
      GuideId.network,
    ]);
    // Every GuideId value is covered — a new id without a guide is a bug.
    expect(guideCatalog.map((g) => g.id).toSet(), GuideId.values.toSet());
  });

  test('guideById resolves every id to the guide with that id', () {
    for (final id in GuideId.values) {
      expect(guideById(id).id, id);
    }
  });

  test('the approved titles, in order', () {
    expect(guideCatalog.map((g) => g.title).toList(), [
      'Books, magazines and other items',
      'Put your catalogue online',
      'Put your library on the map',
      'Backup, restore, export, import',
      'Lending and the borrowers vault',
      'Hubs, members and library cards',
    ]);
  });

  test('S9: the vault guide uses kind-neutral lending copy', () {
    final text = guideById(GuideId.vault).allText.join('\n');

    expect(text, contains('who borrowed which item'));
    expect(text, contains('Your catalogue is never locked'));
    expect(text, contains('Lend an item'));
    expect(text, contains('Open the item'));
    expect(text, contains('next to the item'));
    expect(text, contains('items missing details'));
    expect(text, isNot(contains('which book')));
    expect(text, isNot(contains('Lend a book')));
  });

  test('every GuideSteps section has 2–7 steps', () {
    for (final guide in guideCatalog) {
      for (final section in guide.sections.whereType<GuideSteps>()) {
        expect(
          section.steps.length,
          inInclusiveRange(2, 7),
          reason: '${guide.id} / "${section.title}"',
        );
      }
    }
  });

  test('item count of every block matches the approved copy', () {
    // Why pin exact counts: guide_catalog.dart turns off
    // no_adjacent_strings_in_list (its sentences span several string
    // literals), so a missing comma between two items would silently merge
    // them into one. A merged item changes a count here and fails CI. The
    // numbers are the mockup's (docs/mockups/how-pitak-works.md §3): per
    // guide, [needs, blocks…, goodToKnow].
    const expected = <GuideId, List<int>>{
      // §3.6: picker table (3 rows), 5 steps, two bullet blocks of 3.
      GuideId.catalogue: [0, 3, 5, 3, 3, 3],
      GuideId.publish: [1, 2, 6, 2, 1, 1, 3],
      GuideId.map: [0, 6, 3, 3],
      GuideId.backup: [0, 5, 3, 2, 3, 1, 1, 1, 2],
      GuideId.vault: [0, 3, 3, 3, 3],
      GuideId.network: [0, 1, 2, 5, 0],
    };
    for (final guide in guideCatalog) {
      final counts = <int>[
        guide.needs.length,
        for (final section in guide.sections)
          switch (section) {
            GuideSteps(:final steps) => steps.length,
            GuideBullets(:final bullets) => bullets.length,
            GuideParagraphs(:final paragraphs) => paragraphs.length,
            GuideTable(:final rows) => rows.length,
          },
        guide.goodToKnow.length,
      ];
      expect(counts, expected[guide.id], reason: '${guide.id}');
    }
  });

  test('"Good to know" has at most three bullets', () {
    // Enforced here, not by a constructor assert: a const constructor cannot
    // evaluate `goodToKnow.length`.
    for (final guide in guideCatalog) {
      expect(
        guide.goodToKnow.length,
        lessThanOrEqualTo(Guide.maxGoodToKnow),
        reason: '${guide.id}',
      );
    }
  });

  test('no section, table or chip list is empty', () {
    for (final guide in guideCatalog) {
      expect(guide.sections, isNotEmpty, reason: '${guide.id}');
      for (final section in guide.sections) {
        final count = switch (section) {
          GuideSteps(:final steps) => steps.length,
          GuideBullets(:final bullets) => bullets.length,
          GuideParagraphs(:final paragraphs) => paragraphs.length,
          GuideTable(:final rows) => rows.length,
        };
        expect(count, greaterThan(0), reason: '${guide.id} / $section');
      }
    }
  });

  test('every string parses with no leftover ** or stray backtick', () {
    for (final guide in guideCatalog) {
      for (final text in guide.allText) {
        expect(text.trim(), isNotEmpty, reason: '${guide.id}: empty string');
        final runs = parseGuideMarkup(text);
        // Lossless: the runs put back together equal the source with every
        // marker removed → no marker survived as literal text.
        expect(
          runs.map((r) => r.text).join(),
          stripGuideMarkup(text),
          reason: '${guide.id}: "$text"',
        );
        // An unmatched marker leaves a `**` / `` ` `` inside a run's text.
        for (final run in runs) {
          expect(run.text, isNot(contains('**')), reason: '${guide.id}: $run');
          expect(run.text, isNot(contains('`')), reason: '${guide.id}: $run');
        }
      }
    }
  });

  test('no copy uses Markdown italics (*…*) — the parser has no italic', () {
    final single = RegExp(r'(?<!\*)\*(?!\*)');
    for (final guide in guideCatalog) {
      for (final text in guide.allText) {
        expect(
          single.hasMatch(text),
          isFalse,
          reason: '${guide.id}: single * in "$text"',
        );
      }
    }
  });

  test('"spoke(s)" appears only in the hubs guide, at most once', () {
    final spoke = RegExp(r'\bspokes?\b', caseSensitive: false);
    for (final guide in guideCatalog) {
      final hits = guide.allText.expand(spoke.allMatches).length;
      if (guide.id == GuideId.network) {
        expect(hits, lessThanOrEqualTo(1), reason: 'hubs guide');
      } else {
        expect(hits, 0, reason: '${guide.id} must say member/hub, not spoke');
      }
    }
  });

  test('every guide has a destination and a non-empty button label', () {
    for (final guide in guideCatalog) {
      expect(guide.destinationLabel.trim(), isNotEmpty, reason: '${guide.id}');
      expect(
        guide.destinationLabel,
        startsWith('Open '),
        reason: '${guide.id}: the button reads "Open <screen>"',
      );
    }
    // Each destination is used by exactly one guide; the mapping is 1:1 with
    // the enum so a new destination without a guide (or vice versa) shows up.
    expect(
      guideCatalog.map((g) => g.destination).toSet(),
      GuideDestination.values.toSet(),
    );
  });

  test('the publish guide is the only one with "You need" chips', () {
    for (final guide in guideCatalog) {
      expect(
        guide.needs.isNotEmpty,
        guide.id == GuideId.publish,
        reason: '${guide.id}',
      );
    }
  });

  test('allText covers every field (nothing is silently unchecked)', () {
    // Counting on a tiny synthetic guide so the number is obvious.
    const guide = Guide(
      id: GuideId.publish,
      title: 't',
      cardSubtitle: 's',
      intro: 'i',
      needs: ['n'],
      sections: [
        GuideSteps(title: 'a', steps: ['1', '2']),
        GuideBullets(title: 'b', bullets: ['x']),
        GuideParagraphs(title: 'c', paragraphs: ['p']),
        GuideTable(title: 'd', rows: [(want: 'w', use: 'u')]),
      ],
      goodToKnow: ['g'],
      destination: GuideDestination.vault,
      destinationLabel: 'Open v',
    );
    expect(guide.allText.toList(), [
      't', 's', 'i', 'n', //
      'a', '1', '2', //
      'b', 'x', //
      'c', 'p', //
      'd', 'w', 'u', //
      'g', 'Open v',
    ]);
  });
}
