import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/backup/infrastructure/item_details_archive_codec.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/library/domain/value_objects/item_kind.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/domain/value_objects/periodical_frequency.dart';

/// ADR 0014 W2: the `.pitabak` `item_kinds.json` / `periodicals.json`
/// envelopes. Encode emits exactly the documented shapes; decode bounds,
/// re-validates, and counts every drop (§5.5: "invalid rows dropped and
/// counted").
void main() {
  const issue = IssueOf(
    periodicalUid: 'puid-1',
    volume: 249,
    issueNumber: 10,
    issueDate: 1759276800000,
    label: 'Dasara special',
  );
  const issueRow = CatalogueItem(
    id: 8,
    itemUid: 'uid-8',
    title: 'Chandamama — Vol 249 No 10 (Oct 2026)',
    details: issue,
  );
  const otherRow = CatalogueItem(
    id: 9,
    itemUid: 'uid-9',
    title: 'Carrom board',
    details: OtherItemOf(),
  );
  const bookRow = CatalogueItem(id: 7, itemUid: 'uid-7', title: 'गोदान');
  const periodical = Periodical(
    title: 'Chandamama',
    periodicalUid: 'puid-1',
    issn: '0577-6058',
    publisher: 'Chandamama India',
    language: 'Telugu',
    frequency: PeriodicalFrequency.monthly,
    subscriptionStart: 1760000000000,
    subscriptionEnd: 1790000000000,
    notes: 'gift from ammamma',
    ageGroup: AgeGroup.above6,
    addedDate: 1760000000000,
  );

  group('encodeItemKinds', () {
    test('lists every non-book row with a uid, and nothing else', () {
      final json =
          jsonDecode(
                ItemDetailsArchiveCodec.encodeItemKinds(const [
                  bookRow,
                  issueRow,
                  otherRow,
                  // A uid-less row cannot be keyed — it restores as a book.
                  CatalogueItem(
                    id: 10,
                    title: 'No uid',
                    details: OtherItemOf(),
                  ),
                ]),
              )
              as Map<String, dynamic>;
      expect(json['schemaVersion'], 1);
      final kinds = json['kinds'] as List<dynamic>;
      expect(kinds, hasLength(2));
      expect(
        kinds,
        containsAll([
          {'bookUid': 'uid-8', 'kind': 'magazine-issue'},
          {'bookUid': 'uid-9', 'kind': 'other'},
        ]),
      );
    });

    test('a books-only list still encodes (the writer omits the entry)', () {
      final json =
          jsonDecode(ItemDetailsArchiveCodec.encodeItemKinds(const [bookRow]))
              as Map<String, dynamic>;
      expect(json['kinds'], isEmpty);
    });
  });

  group('decodeItemKinds', () {
    test('round-trips the encoded map', () {
      final decoded = ItemDetailsArchiveCodec.decodeItemKinds(
        ItemDetailsArchiveCodec.encodeItemKinds(const [issueRow, otherRow]),
      );
      expect(decoded, isNotNull);
      expect(decoded!.skipped, 0);
      expect(decoded.byUid, {
        'uid-8': ItemKind.magazineIssue,
        'uid-9': ItemKind.other,
      });
    });

    test('unknown kind tokens are skipped and counted (F6), never guessed', () {
      final decoded = ItemDetailsArchiveCodec.decodeItemKinds(
        jsonEncode({
          'schemaVersion': 1,
          'kinds': [
            {'bookUid': 'uid-8', 'kind': 'magazine-issue'},
            {'bookUid': 'uid-9', 'kind': 'hologram'},
          ],
        }),
      );
      expect(decoded!.byUid, {'uid-8': ItemKind.magazineIssue});
      expect(decoded.skipped, 1);
    });

    test('malformed rows, blank uids and duplicates are skipped + counted', () {
      final decoded = ItemDetailsArchiveCodec.decodeItemKinds(
        jsonEncode({
          'schemaVersion': 1,
          'kinds': [
            'not-an-object',
            {'kind': 'other'}, // no bookUid
            {'bookUid': '  ', 'kind': 'other'},
            {'bookUid': 'uid-8', 'kind': 'other'},
            {'bookUid': 'uid-8', 'kind': 'magazine-issue'}, // dup: first wins
          ],
        }),
      );
      expect(decoded!.byUid, {'uid-8': ItemKind.other});
      expect(decoded.skipped, 4);
    });

    test('an unusable envelope reads as null (fail closed)', () {
      expect(ItemDetailsArchiveCodec.decodeItemKinds('{nope'), isNull);
      expect(ItemDetailsArchiveCodec.decodeItemKinds('[]'), isNull);
      // Too new: a future build's entry must not be half-read.
      expect(
        ItemDetailsArchiveCodec.decodeItemKinds(
          jsonEncode({'schemaVersion': 2, 'kinds': <dynamic>[]}),
        ),
        isNull,
      );
      expect(
        ItemDetailsArchiveCodec.decodeItemKinds(
          jsonEncode({'schemaVersion': 1, 'kinds': <String, dynamic>{}}),
        ),
        isNull,
      );
    });
  });

  group('encodePeriodicals', () {
    test('periodical objects carry the W1 keys; issues ride by bookUid', () {
      final json =
          jsonDecode(
                ItemDetailsArchiveCodec.encodePeriodicals(
                  const [periodical],
                  const [bookRow, issueRow],
                ),
              )
              as Map<String, dynamic>;
      expect(json['schemaVersion'], 1);

      final p =
          (json['periodicals'] as List<dynamic>).single as Map<String, dynamic>;
      // The W1 object (Pitaka-JSON v4) — same keys, same values.
      expect(p['periodicalUid'], 'puid-1');
      expect(p['title'], 'Chandamama');
      expect(p['issn'], '0577-6058');
      expect(p['frequency'], 'monthly');
      expect(p['subscriptionStart'], 1760000000000);
      expect(p['ageGroup'], 'above-6');
      expect(p['removed'], isFalse);
      // Nulls are omitted (compact rule).
      expect(p.containsKey('coverUrl'), isFalse);

      final i =
          (json['issues'] as List<dynamic>).single as Map<String, dynamic>;
      expect(i, {
        'bookUid': 'uid-8',
        'periodicalUid': 'puid-1',
        'volume': 249,
        'issueNumber': 10,
        'issueDate': 1759276800000,
        'label': 'Dasara special',
      });
    });

    test('a removed title is still written (its issues may exist, D8)', () {
      final json =
          jsonDecode(
                ItemDetailsArchiveCodec.encodePeriodicals(const [
                  Periodical(
                    title: 'Gone',
                    periodicalUid: 'puid-9',
                    removed: true,
                    removedAt: 5,
                  ),
                ], const []),
              )
              as Map<String, dynamic>;
      final p =
          (json['periodicals'] as List<dynamic>).single as Map<String, dynamic>;
      expect(p['removed'], isTrue);
      expect(p['removedAt'], 5);
    });
  });

  group('decodePeriodicals', () {
    test('round-trips periodicals and issues, gate-normalised', () {
      final decoded = ItemDetailsArchiveCodec.decodePeriodicals(
        ItemDetailsArchiveCodec.encodePeriodicals(
          const [periodical],
          const [issueRow],
        ),
      );
      expect(decoded, isNotNull);
      expect(decoded!.periodicalsDropped, 0);
      expect(decoded.issuesDropped, 0);
      final p = decoded.periodicals.single;
      expect(p.periodicalUid, 'puid-1');
      expect(p.issn, '0577-6058');
      expect(p.frequency, PeriodicalFrequency.monthly);
      expect(decoded.issuesByBookUid['uid-8']!.sameAs(issue), isTrue);
    });

    test('a whitespace-mismatched series and issue decode to one link', () {
      final decoded = ItemDetailsArchiveCodec.decodePeriodicals(
        jsonEncode({
          'schemaVersion': 1,
          'periodicals': [
            {'periodicalUid': '  p1  ', 'title': 'Frontline'},
          ],
          'issues': [
            {'bookUid': 'uid-8', 'periodicalUid': 'p1', 'issueNumber': 1},
          ],
        }),
      );
      expect(decoded, isNotNull);
      expect(decoded!.periodicalsDropped, 0);
      expect(decoded.issuesDropped, 0);
      expect(decoded.periodicals.single.periodicalUid, 'p1');
      expect(decoded.issuesByBookUid['uid-8']!.periodicalUid, 'p1');
    });

    test('a trim-created periodical UID collision refuses the envelope', () {
      final decoded = ItemDetailsArchiveCodec.decodePeriodicals(
        jsonEncode({
          'schemaVersion': 1,
          'periodicals': [
            {'periodicalUid': ' p1 ', 'title': 'First'},
            {'periodicalUid': 'p1', 'title': 'Second'},
          ],
        }),
      );
      expect(decoded, isNull);
    });

    test('invalid or unkeyable periodical rows are dropped and counted', () {
      final decoded = ItemDetailsArchiveCodec.decodePeriodicals(
        jsonEncode({
          'schemaVersion': 1,
          'periodicals': [
            'not-an-object',
            {'title': 'No uid'}, // uid-less can never be linked
            {
              'periodicalUid': 'puid-bad',
              'title': 'Bad ISSN',
              'issn': 'not-an-issn',
            },
            {'periodicalUid': 'puid-1', 'title': 'Chandamama'},
            {'periodicalUid': 'puid-1', 'title': 'Duplicate'}, // first wins
          ],
        }),
      );
      expect(decoded!.periodicals.single.title, 'Chandamama');
      expect(decoded.periodicalsDropped, 4);
    });

    test('invalid or unkeyable issue entries are dropped and counted', () {
      final decoded = ItemDetailsArchiveCodec.decodePeriodicals(
        jsonEncode({
          'schemaVersion': 1,
          'periodicals': <dynamic>[],
          'issues': [
            42,
            {'periodicalUid': 'puid-1', 'issueNumber': 1}, // no bookUid
            {
              'bookUid': 'uid-8',
              'periodicalUid': 'puid-1',
              // Bound range backwards — IssueOf.validate refuses it.
              'issueDate': 2000,
              'boundUntil': 1000,
            },
            {'bookUid': 'uid-8', 'periodicalUid': 'puid-1', 'issueNumber': 3},
            {
              'bookUid': 'uid-8',
              'periodicalUid': 'puid-1',
              'issueNumber': 4,
            }, // dup: first wins
          ],
        }),
      );
      expect(decoded!.issuesByBookUid['uid-8']!.issueNumber, 3);
      expect(decoded.issuesDropped, 4);
    });

    test('absent lists read as empty; non-lists fail closed to null', () {
      final empty = ItemDetailsArchiveCodec.decodePeriodicals(
        jsonEncode({'schemaVersion': 1}),
      );
      expect(empty, isNotNull);
      expect(empty!.periodicals, isEmpty);
      expect(empty.issuesByBookUid, isEmpty);

      expect(
        ItemDetailsArchiveCodec.decodePeriodicals(
          jsonEncode({'schemaVersion': 1, 'issues': <String, dynamic>{}}),
        ),
        isNull,
      );
      expect(ItemDetailsArchiveCodec.decodePeriodicals('[1]'), isNull);
      expect(
        ItemDetailsArchiveCodec.decodePeriodicals(
          jsonEncode({'schemaVersion': 99}),
        ),
        isNull,
      );
    });

    test('a NaN/Infinity epoch never crashes the parse (hostile input)', () {
      final decoded = ItemDetailsArchiveCodec.decodePeriodicals(
        '{"schemaVersion": 1, "periodicals": [{"periodicalUid": "p", '
        '"title": "T", "subscriptionStart": 1e400}]}',
      );
      // The uncoercible date coerces to null, which the gate accepts
      // (optional field) — the row survives, minus the hostile value.
      expect(decoded, isNotNull);
      expect(decoded!.periodicals.single.subscriptionStart, isNull);
    });
  });
}
