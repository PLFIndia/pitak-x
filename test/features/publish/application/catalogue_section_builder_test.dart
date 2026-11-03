import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/domain/value_objects/periodical_frequency.dart';
import 'package:pitaka/features/publish/application/publish_cover_decider.dart';
import 'package:pitaka/features/publish/application/site/catalogue_section_builder.dart';
import 'package:pitaka/features/publish/domain/publish_cover_ids.dart';
import 'package:pitaka/features/publish/domain/publish_export.dart';
import 'package:pitaka/features/publish/domain/publish_item_keys.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';
import 'package:pitaka/features/publish/domain/site/publish_mode.dart';
import 'package:pitaka/features/publish/domain/site/publish_section.dart';
import 'package:pitaka/features/publish/domain/site/publish_snapshot.dart';

/// CHARACTERIZATION of the catalogue section (Cloudflare plan S3/R3).
///
/// These tests pin what the GitHub publisher has always produced, so the
/// extraction into a shared builder (and its reuse by the Cloudflare adapter)
/// cannot change the published bytes or file set. If a change here is
/// deliberate, update the expectations AND record the behavior change.
///
/// Deliberate change, publish-optimisation S3 (ADR 0019 Decision 3): every
/// item gains `key`, right after `kind`. Nothing else in `books.json`
/// changed; the exact bytes are pinned below.
///
/// Deliberate change, publish-optimisation S7 (plan J10, A.6 #68): the
/// payload gains a top-level `keySet`, right after `exportedAt`. Nothing else
/// changed.
void main() {
  const salt = 'salt-1234567890';

  final fixedSalt = _FixedSalt(ascii.encode(salt));

  // The public item keys for this salt, pinned as literals:
  // sha256(salt + "item:<id>")[0..16]. A test below proves they are exactly
  // what `PublishItemKeys` computes.
  const keyMap = {
    1: 'f1256752587d05c1',
    2: '1afb3bc2efa863e0',
    9: '2151cb8080cc871a',
  };

  // sha256(salt + "key-set")[0..16], pinned like the keys (plan A.6 #68).
  const keySetId = 'd6aa7f89958f43cb';

  PublishKeySet keysOf(Map<int, String> keysById) =>
      PublishKeySet.tryCreate(id: keySetId, keysById: keysById)!;

  final keys = keysOf(keyMap);

  CatalogueItem book({int id = 1, String? cover}) => CatalogueItem(
    id: id,
    title: 'The Odyssey',
    author: 'Homer',
    notes: 'PII that must never publish',
    location: 'Shelf 3B (private)',
    coverUrl: cover,
  );

  Periodical series({String? cover}) => Periodical(
    id: 7,
    periodicalUid: 'uid-1',
    title: 'Chandamama',
    issn: '0577-6058',
    publisher: 'Chandamama Publications',
    coverUrl: cover,
    frequency: PeriodicalFrequency.monthly,
    notes: 'private series note',
    location: 'private series shelf',
  );

  CatalogueItem issue({int id = 2, String? cover}) => CatalogueItem(
    id: id,
    title: 'Chandamama — Vol 249 No 10 (Oct 2026)',
    coverUrl: cover,
    details: const IssueOf(
      periodicalUid: 'uid-1',
      volume: 249,
      issueNumber: 10,
      issueDate: 1759276800000,
    ),
  );

  CatalogueSectionBuilder builder({
    LocalCoverReader? readLocal,
    RemoteCoverFetcher? fetchRemote,
  }) => CatalogueSectionBuilder(
    covers: PublishCoverDecider(
      coverIds: PublishCoverIds(fixedSalt),
      readLocalCover: readLocal ?? (_) async => null,
      fetchRemoteCover: fetchRemote ?? (_) async => null,
    ),
    buildViewerHtml:
        ({required libraryName, required contact, required sharing}) async =>
            utf8.encode('<html></html>'),
    // The production encoder, so the pinned bytes are the published bytes.
    encodeBooksJson: encodeBooksJsonBytes,
  );

  test(
    'valid input: the exact file set, order and identities are pinned',
    () async {
      final section =
          (await builder(readLocal: (_) async => utf8.encode('IMG')).build(
            books: [
              book(cover: 'covers/local.jpg'),
              // The issue has NO own cover: it falls back to its series' one
              // (the W4 rule), so one uploaded file serves both entries.
              issue(),
            ],
            periodicals: [series(cover: 'covers/s.jpg')],
            activeLoanCounts: const {1: 1},
            libraryJson: utf8.encode('{"schema":1}'),
            gitHubPagesSite: false,
            settings: const PublishPageSettings(libraryName: 'Test Library'),
            previous: PublishManifest.empty,
            now: 1000,
            itemKeys: keys,
          )).toNullable()!;

      // Paths, in the historical write order (books.json, descriptor, viewer,
      // then cover decisions), de-duplicated keeping the first.
      expect(section.paths, [
        'books.json',
        'library.json',
        'index.html',
        'covers/3368361cb6e5a33e.jpg', // sha256(salt + "1")[0..16]
        'covers/8a6f3469e99e562b.jpg', // sha256(salt + "periodical:uid-1")
      ]);
      expect(section.deletePaths, isEmpty);
      expect(section.hasUploads, isTrue);
      // The viewer bytes are byte-identical to the historical template output.
      expect(
        section.files.firstWhere((f) => f.path == 'index.html').gitSha,
        '6c70bcfe4d48d15f8a6531d6b491e65d641a377c',
      );

      // books.json: the world-facing payload keeps its documented shape and
      // still never carries private notes/locations.
      final payload =
          jsonDecode(
                utf8.decode(
                  section.files.firstWhere((f) => f.path == 'books.json').bytes,
                ),
              )
              as Map<String, dynamic>;
      expect(payload.keys, [
        'schemaVersion',
        'exportedAt',
        'keySet',
        'books',
        'periodicals',
      ]);
      expect(payload['exportedAt'], 1000);
      expect(payload['keySet'], keySetId);
      final books = payload['books'] as List;
      expect(books, hasLength(2));
      final first = books.first as Map<String, dynamic>;
      expect(first['title'], 'The Odyssey');
      expect(first.containsKey('notes'), isFalse);
      expect(first.containsKey('location'), isFalse);
      // Availability is coarse and gated on the vault: 1 of 1 lent out.
      expect(first['availability'], 'out');
      // The issue points at its series' single shared cover.
      final issueEntry = books[1] as Map<String, dynamic>;
      expect(issueEntry['coverUrl'], 'covers/8a6f3469e99e562b.jpg');
      final periodicals = payload['periodicals'] as List;
      expect(periodicals, hasLength(1));
      expect(
        (periodicals.single as Map<String, dynamic>)['coverUrl'],
        'covers/8a6f3469e99e562b.jpg',
      );

      // The exact published bytes. S3 added the two `"key"` lines and S7 the
      // `"keySet"` line; nothing else changed (S3 was checked against the
      // pre-S3 builder's output).
      expect(
        utf8.decode(
          section.files.firstWhere((f) => f.path == 'books.json').bytes,
        ),
        _expectedBooksJson,
      );
    },
  );

  test('the pinned keys are exactly what PublishItemKeys computes', () {
    for (final entry in keyMap.entries) {
      expect(
        PublishItemKeys.keyFor(salt: ascii.encode(salt), itemId: entry.key),
        entry.value,
      );
    }
    expect(PublishItemKeys.keySetIdFor(salt: ascii.encode(salt)), keySetId);
  });

  group('item keys (ADR 0019 Decision 3)', () {
    Future<Either<Failure, PublishSection>> buildWith(
      List<CatalogueItem> books,
      PublishKeySet itemKeys, {
      List<Periodical> periodicals = const [],
    }) => builder().build(
      books: books,
      periodicals: periodicals,
      activeLoanCounts: null,
      libraryJson: null,
      gitHubPagesSite: false,
      settings: const PublishPageSettings(libraryName: 'Test Library'),
      previous: PublishManifest.empty,
      now: 1,
      itemKeys: itemKeys,
    );

    List<Map<String, dynamic>> rows(PublishSection section) {
      final payload =
          jsonDecode(
                utf8.decode(
                  section.files.firstWhere((f) => f.path == 'books.json').bytes,
                ),
              )
              as Map<String, dynamic>;
      return (payload['books'] as List).cast<Map<String, dynamic>>();
    }

    test('every kind carries its key, Others included', () async {
      const other = CatalogueItem(
        id: 9,
        title: 'Board game',
        details: OtherItemOf(),
      );
      final section = (await buildWith(
        [book(), issue(), other],
        keys,
        periodicals: [series()],
      )).toNullable()!;
      expect(
        [for (final row in rows(section)) row['key']],
        [keyMap[1], keyMap[2], keyMap[9]],
      );
    });

    test('a removed item needs no key and is not published', () async {
      final section = (await buildWith([
        book(),
        const CatalogueItem(id: 3, title: 'Gone', removed: true),
      ], keysOf(const {1: 'f1256752587d05c1'}))).toNullable()!;
      expect([for (final row in rows(section)) row['key']], [keyMap[1]]);
    });

    test(
      'a live item without a key refuses the build before any cover IO',
      () async {
        var coverReads = 0;
        final result =
            await builder(
              readLocal: (_) async {
                coverReads++;
                return utf8.encode('IMG');
              },
            ).build(
              books: [
                book(cover: 'covers/local.jpg'),
                book(id: 3),
              ],
              periodicals: const [],
              activeLoanCounts: null,
              libraryJson: null,
              gitHubPagesSite: false,
              settings: const PublishPageSettings(libraryName: 'Test Library'),
              previous: PublishManifest.empty,
              now: 1,
              itemKeys: keysOf(const {1: 'f1256752587d05c1'}),
            );
        expect(
          (result.swap().toNullable()! as ValidationFailure).message,
          PublishItemKeys.collisionMessage,
        );
        expect(coverReads, 0, reason: 'keys are checked before covers');
      },
    );

    test('a malformed or shared key cannot even reach the builder', () {
      // Since S7 the builder takes a `PublishKeySet`, which refuses both
      // (plan A.6 #68); the builder itself only checks completeness above.
      expect(
        PublishKeySet.tryCreate(id: keySetId, keysById: const {1: 'NOT-A-KEY'}),
        isNull,
      );
      expect(
        PublishKeySet.tryCreate(
          id: keySetId,
          keysById: const {1: 'f1256752587d05c1', 3: 'f1256752587d05c1'},
        ),
        isNull,
      );
    });

    test('books.json names the key set its keys belong to', () async {
      final section = (await buildWith([book()], keys)).toNullable()!;
      final payload =
          jsonDecode(
                utf8.decode(
                  section.files.firstWhere((f) => f.path == 'books.json').bytes,
                ),
              )
              as Map<String, dynamic>;
      expect(payload['keySet'], keySetId);
    });
  });

  group('inline availability through the ONE rule (A.6 #18)', () {
    Future<String?> inlineTag(CatalogueItem item, Map<int, int>? counts) async {
      final section = (await builder().build(
        books: [item],
        periodicals: const [],
        activeLoanCounts: counts,
        libraryJson: null,
        gitHubPagesSite: false,
        settings: const PublishPageSettings(libraryName: 'Test Library'),
        previous: PublishManifest.empty,
        now: 1,
        itemKeys: keysOf(const {1: 'f1256752587d05c1'}),
      )).toNullable()!;
      final payload =
          jsonDecode(
                utf8.decode(
                  section.files.firstWhere((f) => f.path == 'books.json').bytes,
                ),
              )
              as Map<String, dynamic>;
      final row = (payload['books'] as List).single as Map<String, dynamic>;
      return row['availability'] as String?;
    }

    test('locked vault: no tag at all, never "available"', () async {
      expect(await inlineTag(book(), null), isNull);
    });

    test('some copies free: available; every copy out: out', () async {
      const threeCopies = CatalogueItem(id: 1, title: 'T', copyCount: 3);
      expect(await inlineTag(threeCopies, const {1: 2}), PublishItem.available);
      expect(await inlineTag(threeCopies, const {1: 3}), PublishItem.out);
    });

    test(
      'a malformed copy count is clamped like isBookUnavailable does',
      () async {
        // copyCount 0 never passes CatalogueItem.validate, but the builder
        // must still follow the vault rule: 0 copies counts as 1, so a book
        // with no loans is available (the old inline copy said "out").
        const zeroCopies = CatalogueItem(id: 1, title: 'T', copyCount: 0);
        expect(await inlineTag(zeroCopies, const {}), PublishItem.available);
        expect(await inlineTag(zeroCopies, const {1: 1}), PublishItem.out);
      },
    );
  });

  test('an unchanged published file is reused, not re-uploaded (R3)', () async {
    const manifest = PublishManifest(
      repo: 'me/lib',
      fileShas: {'index.html': '6c70bcfe4d48d15f8a6531d6b491e65d641a377c'},
    );
    final section = (await builder().build(
      books: [book()],
      periodicals: const [],
      activeLoanCounts: null,
      libraryJson: null,
      gitHubPagesSite: false,
      settings: const PublishPageSettings(libraryName: 'Test Library'),
      previous: manifest,
      now: 1000,
      itemKeys: keys,
    )).toNullable()!;

    final viewer = section.files.firstWhere((f) => f.path == 'index.html');
    expect(viewer.upload, isFalse, reason: 'unchanged ⇒ no blob upload');
    // Built files keep their bytes (the host ignores them when upload is
    // false); only a reused COVER is carried without bytes.
    expect(viewer.bytes, isNotEmpty);
  });

  test(
    'opting out of the descriptor deletes ONLY library.json (M14)',
    () async {
      const manifest = PublishManifest(
        repo: 'me/lib',
        fileShas: {
          'library.json': 'abc',
          'books.json': 'def',
          'events.json': 'keep-me',
        },
      );
      final section = (await builder().build(
        books: [book()],
        periodicals: const [],
        activeLoanCounts: null,
        libraryJson: null,
        gitHubPagesSite: false,
        settings: const PublishPageSettings(libraryName: 'Test Library'),
        previous: manifest,
        now: 1,
        itemKeys: keys,
      )).toNullable()!;

      expect(section.deletePaths, ['library.json']);
    },
  );

  test(
    'COMPLETE mode refuses a cover that no source can supply (R2)',
    () async {
      final result = await builder().build(
        books: [book(cover: 'covers/local.jpg')],
        periodicals: const [],
        activeLoanCounts: null,
        libraryJson: null,
        gitHubPagesSite: false,
        settings: const PublishPageSettings(libraryName: 'Test Library'),
        previous: PublishManifest.empty,
        now: 1,
        itemKeys: keys,
        mode: PublishMode.complete,
      );

      expect(result.isLeft(), isTrue);
      expect(
        (result.swap().toNullable()! as ValidationFailure).message,
        CatalogueSectionBuilder.missingCoverMessage,
      );
    },
  );

  test(
    'COMPLETE mode refuses an external-URL fallback after a failed fetch',
    () async {
      final result = await builder().build(
        books: [book(cover: 'https://covers.openlibrary.org/b/id/1-L.jpg')],
        periodicals: const [],
        activeLoanCounts: null,
        libraryJson: null,
        gitHubPagesSite: false,
        settings: const PublishPageSettings(libraryName: 'Test Library'),
        previous: PublishManifest.empty,
        now: 1,
        itemKeys: keys,
        mode: PublishMode.complete,
      );

      expect(result.isLeft(), isTrue);
      expect(
        (result.swap().toNullable()! as ValidationFailure).message,
        CatalogueSectionBuilder.missingCoverMessage,
      );
    },
  );

  test(
    'INCREMENTAL mode drops the same unreadable cover (historical rule)',
    () async {
      final section = (await builder().build(
        books: [book(cover: 'covers/local.jpg')],
        periodicals: const [],
        activeLoanCounts: null,
        libraryJson: null,
        gitHubPagesSite: false,
        settings: const PublishPageSettings(libraryName: 'Test Library'),
        previous: PublishManifest.empty,
        now: 1,
        itemKeys: keys,
      )).toNullable()!;
      expect(
        section.files.map((f) => f.path),
        isNot(contains('covers/3368361cb6e5a33e.jpg')),
      );
    },
  );

  test(
    'a malformed series link refuses the whole section (fail closed)',
    () async {
      const orphan = CatalogueItem(
        id: 9,
        title: 'Orphan issue',
        details: IssueOf(
          periodicalUid: 'missing-series',
          volume: 1,
          issueNumber: 1,
          issueDate: 1759276800000,
        ),
      );
      final result = await builder().build(
        books: [orphan],
        periodicals: const [],
        activeLoanCounts: null,
        libraryJson: null,
        gitHubPagesSite: false,
        settings: const PublishPageSettings(libraryName: 'Test Library'),
        previous: PublishManifest.empty,
        now: 1,
        itemKeys: keys,
      );
      expect(result.swap().toNullable(), isA<ValidationFailure>());
    },
  );
}

/// The exact `books.json` of the first test (production encoder, two-space
/// indent). Pre-S3 it was the same text without the two `"key"` lines, and
/// pre-S7 without the `"keySet"` line.
/// (Dart drops the newline right after the opening quotes.)
const _expectedBooksJson = '''
{
  "schemaVersion": 1,
  "exportedAt": 1000,
  "keySet": "d6aa7f89958f43cb",
  "books": [
    {
      "title": "The Odyssey",
      "kind": "book",
      "key": "f1256752587d05c1",
      "author": "Homer",
      "coverUrl": "covers/3368361cb6e5a33e.jpg",
      "availability": "out"
    },
    {
      "title": "Chandamama — Vol 249 No 10 (Oct 2026)",
      "kind": "magazine-issue",
      "key": "1afb3bc2efa863e0",
      "issue": {
        "periodicalUid": "uid-1",
        "volume": 249,
        "issueNumber": 10,
        "issueDate": 1759276800000
      },
      "coverUrl": "covers/8a6f3469e99e562b.jpg",
      "availability": "available"
    }
  ],
  "periodicals": [
    {
      "periodicalUid": "uid-1",
      "title": "Chandamama",
      "issn": "0577-6058",
      "publisher": "Chandamama Publications",
      "coverUrl": "covers/8a6f3469e99e562b.jpg",
      "frequency": "monthly"
    }
  ]
}''';

class _FixedSalt implements PublishCoverSaltStore {
  const _FixedSalt(this.bytes);
  final List<int> bytes;
  @override
  Future<List<int>> salt() async => bytes;
}
