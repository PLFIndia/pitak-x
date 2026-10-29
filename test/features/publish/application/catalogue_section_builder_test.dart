import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/domain/value_objects/periodical_frequency.dart';
import 'package:pitaka/features/publish/application/publish_cover_decider.dart';
import 'package:pitaka/features/publish/application/site/catalogue_section_builder.dart';
import 'package:pitaka/features/publish/domain/publish_cover_ids.dart';
import 'package:pitaka/features/publish/domain/publish_export.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';
import 'package:pitaka/features/publish/domain/site/publish_mode.dart';
import 'package:pitaka/features/publish/domain/site/publish_snapshot.dart';

/// CHARACTERIZATION of the catalogue section (Cloudflare plan S3/R3).
///
/// These tests pin what the GitHub publisher has always produced, so the
/// extraction into a shared builder (and its reuse by the Cloudflare adapter)
/// cannot change the published bytes or file set. If a change here is
/// deliberate, update the expectations AND record the behavior change.
void main() {
  const salt = 'salt-1234567890';

  final fixedSalt = _FixedSalt(ascii.encode(salt));

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

  List<int> encode(PublishExport e) =>
      utf8.encode(const JsonEncoder.withIndent('  ').convert(e.toJson()));

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
    encodeBooksJson: encode,
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
            settings: const PublishPageSettings(libraryName: 'Test Library'),
            previous: PublishManifest.empty,
            now: 1000,
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
        'books',
        'periodicals',
      ]);
      expect(payload['exportedAt'], 1000);
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
    },
  );

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
      settings: const PublishPageSettings(libraryName: 'Test Library'),
      previous: manifest,
      now: 1000,
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
        settings: const PublishPageSettings(libraryName: 'Test Library'),
        previous: manifest,
        now: 1,
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
        settings: const PublishPageSettings(libraryName: 'Test Library'),
        previous: PublishManifest.empty,
        now: 1,
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
        settings: const PublishPageSettings(libraryName: 'Test Library'),
        previous: PublishManifest.empty,
        now: 1,
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
        settings: const PublishPageSettings(libraryName: 'Test Library'),
        previous: PublishManifest.empty,
        now: 1,
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
        settings: const PublishPageSettings(libraryName: 'Test Library'),
        previous: PublishManifest.empty,
        now: 1,
      );
      expect(result.swap().toNullable(), isA<ValidationFailure>());
    },
  );
}

class _FixedSalt implements PublishCoverSaltStore {
  const _FixedSalt(this.bytes);
  final List<int> bytes;
  @override
  Future<List<int>> salt() async => bytes;
}
