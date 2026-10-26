import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/catalogue_rules.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/calendar_date.dart';
import 'package:pitaka/features/network/domain/entities/published_catalogue.dart';
import 'package:pitaka/features/network/infrastructure/published_catalogue_codec.dart';

/// Every published-catalogue read rule, one test group each (ADR 0015,
/// docs/ARCHITECTURE.md §5.6, viewer plan S1).
///
/// The reader is the hostile-input boundary: these tests pin the root contract,
/// the row projection matrix (especially `other`/unknown staying SPARSE), the
/// compatibility with payloads the bundled HTML viewer still accepts, and every
/// bound (with injected tiny limits for the expensive ones).
void main() {
  const codec = PublishedCatalogueCodec();

  List<int> bytesOf(Object? json) => utf8.encode(jsonEncode(json));

  List<int> fixtureBytes(String name) =>
      File('test/fixtures/published_catalogue/$name').readAsBytesSync();

  PublishedCatalogue decodeOk(
    Object? json, {
    PublishedCatalogueCodec withCodec = codec,
  }) {
    final result = withCodec.decode(bytesOf(json));
    expect(result.isRight(), isTrue, reason: 'expected a readable catalogue');
    return result.toNullable()!;
  }

  PublishedCatalogueFailureReason refusalOf(
    Object? json, {
    PublishedCatalogueCodec withCodec = codec,
  }) {
    final result = withCodec.decode(bytesOf(json));
    expect(result.isLeft(), isTrue, reason: 'expected a refusal');
    return result.swap().toNullable()!.reason;
  }

  Map<String, Object?> catalogue({
    Object? books = const <Object?>[],
    Object? periodicals,
    int schemaVersion = 1,
    Object? exportedAt,
  }) => {
    'schemaVersion': schemaVersion,
    if (exportedAt != null) 'exportedAt': exportedAt,
    'books': books,
    if (periodicals != null) 'periodicals': periodicals,
  };

  Map<String, Object?> bookRow([Map<String, Object?> extra = const {}]) => {
    'title': 'A Book',
    ...extra,
  };

  group('root contract', () {
    test('a minimal payload decodes to an empty catalogue', () {
      final catalogueResult = decodeOk(catalogue());
      expect(catalogueResult.items, isEmpty);
      expect(catalogueResult.periodicals, isEmpty);
      expect(catalogueResult.exportedAt, isNull);
      expect(catalogueResult.hasNewerSchema, isFalse);
      expect(catalogueResult.hasNoReadableItems, isFalse);
      expect(catalogueResult.warnings.hasPartialRead, isFalse);
    });

    test('an oversized body is refused before decoding', () {
      final result = const PublishedCatalogueCodec(
        maxBodyBytes: 8,
      ).decode(utf8.encode('{"schemaVersion": 1, "books": []}'));
      expect(result.isLeft(), isTrue);
      expect(
        result.swap().toNullable()!.reason,
        PublishedCatalogueFailureReason.tooLarge,
      );
    });

    test('the default body cap is the documented 64 MiB', () {
      expect(PublishedCatalogueCodec.defaultMaxBodyBytes, 64 * 1024 * 1024);
      expect(
        const PublishedCatalogueCodec().maxBodyBytes,
        PublishedCatalogueCodec.defaultMaxBodyBytes,
      );
    });

    test('malformed UTF-8 is invalid, never an exception', () {
      final result = codec.decode(<int>[0x7B, 0xFF, 0xFE, 0x7D]);
      expect(result.isLeft(), isTrue);
      expect(
        result.swap().toNullable()!.reason,
        PublishedCatalogueFailureReason.invalid,
      );
    });

    test('malformed JSON (fixture) is invalid', () {
      final result = codec.decode(fixtureBytes('malformed.json'));
      expect(result.isLeft(), isTrue);
      expect(
        result.swap().toNullable()!.reason,
        PublishedCatalogueFailureReason.invalid,
      );
    });

    test('a non-map root is invalid', () {
      expect(refusalOf(<Object?>[]), PublishedCatalogueFailureReason.invalid);
      expect(refusalOf('a catalogue'), PublishedCatalogueFailureReason.invalid);
      expect(refusalOf(42), PublishedCatalogueFailureReason.invalid);
    });

    for (final badVersion in <Object?>[null, '1', 1.0, 0, -3, true]) {
      test('schemaVersion $badVersion is invalid (never coerced)', () {
        expect(
          refusalOf({'schemaVersion': badVersion, 'books': <Object?>[]}),
          PublishedCatalogueFailureReason.invalid,
        );
      });
    }

    test('a newer schema decodes its known fields and flags the version', () {
      final decoded = decodeOk(
        catalogue(
          schemaVersion: 2,
          books: [
            bookRow({'author': 'Someone', 'futureKey': 'ignored'}),
          ],
        ),
      );
      expect(decoded.hasNewerSchema, isTrue);
      expect(decoded.declaredSchemaVersion, 2);
      expect(decoded.items.single.title, 'A Book');
      expect(decoded.items.single.author, 'Someone');
    });

    test('a missing or non-list books key is corruption, not emptiness', () {
      expect(
        refusalOf({'schemaVersion': 1}),
        PublishedCatalogueFailureReason.invalid,
      );
      expect(
        refusalOf({'schemaVersion': 1, 'books': <String, Object?>{}}),
        PublishedCatalogueFailureReason.invalid,
      );
    });

    test('an empty books list is a successful empty catalogue', () {
      final decoded = decodeOk(catalogue());
      expect(decoded.items, isEmpty);
      expect(decoded.hasNoReadableItems, isFalse);
    });

    test('exportedAt: absent is null, valid zero is kept', () {
      expect(decodeOk(catalogue()).exportedAt, isNull);
      expect(decodeOk(catalogue(exportedAt: 0)).exportedAt, 0);
      expect(
        decodeOk(catalogue(exportedAt: 1760000000000)).exportedAt,
        1760000000000,
      );
    });

    for (final bad in <Object>['1760000000000', -1, 1.5, 8640000000000001]) {
      test('exportedAt $bad is dropped with a warning, items survive', () {
        final decoded = decodeOk(
          catalogue(exportedAt: bad, books: [bookRow()]),
        );
        expect(decoded.exportedAt, isNull);
        expect(decoded.items, hasLength(1));
        expect(decoded.warnings.invalidExportedAt, isTrue);
      });
    }

    test('unknown root keys are ignored and never retained', () {
      final decoded = decodeOk({
        'schemaVersion': 1,
        'books': <Object?>[],
        'futureRootKey': 'SENTINEL-ROOT',
        'canvasAcl': 'private',
      });
      expect(decoded.items, isEmpty);
    });

    test('a nested-bracket bomb is refused by the depth guard', () {
      expect(
        refusalOf({'schemaVersion': 1, 'books': <Object?>[], 'x': _nest(40)}),
        PublishedCatalogueFailureReason.invalid,
      );
    });

    test('the depth limit is configurable and exact at the boundary', () {
      // The root object itself is one level, so 32 nested arrays inside it
      // are 33 deep: refused by the production limit, accepted when the test
      // raises the cap. The limit is the only thing that changed.
      final payload = {
        'schemaVersion': 1,
        'books': <Object?>[],
        'x': _nest(32),
      };
      expect(refusalOf(payload), PublishedCatalogueFailureReason.invalid);
      expect(
        decodeOk(
          payload,
          withCodec: const PublishedCatalogueCodec(maxJsonDepth: 33),
        ).items,
        isEmpty,
      );
      // A legitimate payload nests 4 deep and is accepted at the default.
      final ok = decodeOk(
        catalogue(
          books: [
            {
              'title': 'x',
              'issue': {'periodicalUid': 'p'},
            },
          ],
        ),
      );
      expect(ok.items, hasLength(1));
    });

    test('a non-list periodicals block is ignored, books still read', () {
      final decoded = decodeOk(
        catalogue(books: [bookRow()], periodicals: 'nope'),
      );
      expect(decoded.items, hasLength(1));
      expect(decoded.periodicals, isEmpty);
      expect(decoded.warnings.invalidOptionalFields, 1);
    });
  });

  group('fixtures', () {
    test('the full schema-1 payload decodes every kind', () {
      final decoded = codec.decode(fixtureBytes('full_v1.json')).toNullable()!;
      expect(decoded.items, hasLength(4));
      expect(decoded.periodicals, hasLength(1));
      expect(decoded.exportedAt, 1760000000000);
      expect(decoded.hasNewerSchema, isFalse);
      expect(decoded.warnings.hasPartialRead, isFalse);

      final book = decoded.items[0];
      expect(book.kind, PublishedItemKind.book);
      expect(book.title, 'The Water Margin');
      expect(book.titleTransliteration, 'Shuihu Zhuan');
      expect(book.author, "Shi Nai'an");
      expect(book.isbn, '9780140447194');
      expect(book.publisher, 'Penguin');
      expect(book.publishedYear, 1976);
      expect(book.genre, 'Classics');
      expect(book.language, 'English');
      expect(book.coverUrl, 'covers/water-margin.jpg');
      expect(book.ageGroup, AgeGroup.above15);
      expect(book.availability, PublishedAvailability.available);
      expect(book.issue, isNull);
      expect(book.sourceIndex, 0);

      final issue = decoded.items[1];
      expect(issue.kind, PublishedItemKind.magazineIssue);
      expect(issue.availability, PublishedAvailability.out);
      expect(issue.issue!.periodicalUid, 'chandamama');
      expect(issue.issue!.volume, 249);
      expect(issue.issue!.issueNumber, 10);
      expect(issue.issue!.label, 'Dasara special');
      expect(issue.issue!.isBound, isFalse);
      expect(
        issue.issue!.issueDate,
        CalendarDate.normalizeStoredMillis(1791072000000),
      );
      // Same-site absolute cover: sanitized at decode, resolved later.
      expect(issue.coverUrl, 'https://covers.openlibrary.org/b/id/123-L.jpg');

      final bound = decoded.items[2];
      expect(bound.issue!.isBound, isTrue);
      expect(bound.issue!.boundUntil, greaterThan(bound.issue!.issueDate!));

      final other = decoded.items[3];
      expect(other.kind, PublishedItemKind.other);
      expect(other.language, 'Kannada');
      expect(other.coverUrl, 'covers/dictionary.jpg');
      // Legacy AGE_6_10 maps to above-6 exactly like the HTML viewer.
      expect(other.ageGroup, AgeGroup.above6);

      final series = decoded.periodicals.single;
      expect(series.periodicalUid, 'chandamama');
      expect(series.title, 'Chandamama');
      expect(series.issn, '0009-4838');
      expect(series.publisher, 'Chandamama');
      expect(series.language, 'Telugu');
      expect(series.coverUrl, 'covers/chandamama.jpg');
      expect(series.frequency!.token, 'monthly');
      expect(series.ageGroup, AgeGroup.above6);
    });

    test('a legacy payload without kinds reads every row as a book', () {
      final decoded = codec
          .decode(fixtureBytes('legacy_v1.json'))
          .toNullable()!;
      expect(decoded.items, hasLength(2));
      expect(
        decoded.items.every((i) => i.kind == PublishedItemKind.book),
        isTrue,
      );
      expect(decoded.items[0].ageGroup, AgeGroup.above3);
      expect(decoded.items[1].ageGroup, AgeGroup.advanced);
      expect(decoded.periodicals, isEmpty);
      expect(decoded.warnings.unknownKindItems, 0);
    });

    test('private/hostile payloads cannot smuggle fields into the models', () {
      final decoded = codec
          .decode(fixtureBytes('hostile_privacy.json'))
          .toNullable()!;
      expect(decoded.items, hasLength(3));

      final probe = decoded.items[0];
      expect(probe.author, 'Public Author');
      expect(probe.title, 'Private Field Probe');
      // The Other stays sparse: author/isbn/publisher/year/genre/availability
      // are all refused even though the payload carries them.
      final other = decoded.items[1];
      expect(other.kind, PublishedItemKind.other);
      expect(other.author, isNull);
      expect(other.isbn, isNull);
      expect(other.publisher, isNull);
      expect(other.publishedYear, isNull);
      expect(other.genre, isNull);
      expect(other.availability, isNull);
      expect(other.language, 'Tamil');
      // An unknown kind is plain and badge-less, never a book.
      final future = decoded.items[2];
      expect(future.kind, PublishedItemKind.unknown);
      expect(future.isUnknownKind, isTrue);
      expect(future.author, isNull);
      expect(future.availability, isNull);
      expect(decoded.warnings.unknownKindItems, 1);

      // No retained string anywhere in the catalogue contains a private
      // sentinel — excluded keys are not decoded, so they cannot be searched.
      for (final value in _retainedStrings(decoded)) {
        expect(value, isNot(contains('SENTINEL')));
        expect(value, isNot(contains('private-')));
      }
      // Public periodical fields survive; private ones have no home.
      final series = decoded.periodicals.single;
      expect(series.title, 'Probe Series');
      expect(series.frequency!.token, 'monthly');
    });

    test('rows that all fail produce the "no readable items" state', () {
      final decoded = decodeOk(
        catalogue(
          books: [
            {'title': ''},
            {'nope': 1},
            7,
          ],
        ),
      );
      expect(decoded.items, isEmpty);
      expect(decoded.hasNoReadableItems, isTrue);
      expect(decoded.warnings.droppedItems, 3);
    });
  });

  group('kind projection', () {
    test('only an absent or null kind is a book', () {
      expect(
        decodeOk(catalogue(books: [bookRow()])).items.single.kind,
        PublishedItemKind.book,
      );
      expect(
        decodeOk(
          catalogue(
            books: [
              bookRow({'kind': null}),
            ],
          ),
        ).items.single.kind,
        PublishedItemKind.book,
      );
    });

    test('the exact tokens map to their kinds', () {
      expect(
        decodeOk(
          catalogue(
            books: [
              bookRow({'kind': 'book'}),
            ],
          ),
        ).items.single.kind,
        PublishedItemKind.book,
      );
      expect(
        decodeOk(
          catalogue(
            books: [
              bookRow({'kind': 'magazine-issue'}),
            ],
          ),
        ).items.single.kind,
        PublishedItemKind.magazineIssue,
      );
      expect(
        decodeOk(
          catalogue(
            books: [
              bookRow({'kind': 'other'}),
            ],
          ),
        ).items.single.kind,
        PublishedItemKind.other,
      );
    });

    for (final token in <Object?>[
      'Book',
      'BOOK',
      ' magazine-issue ',
      'issue',
      5,
    ]) {
      test('kind $token is unknown, not coerced to a book', () {
        final decoded = decodeOk(
          catalogue(
            books: [
              bookRow({'kind': token}),
            ],
          ),
        );
        expect(decoded.items.single.kind, PublishedItemKind.unknown);
        expect(decoded.warnings.unknownKindItems, 1);
      });
    }

    test('an unknown kind keeps only common display-safe fields', () {
      final decoded = decodeOk(
        catalogue(
          books: [
            bookRow({
              'kind': 'future-kind',
              'titleTransliteration': 'Translit',
              'author': 'Author',
              'isbn': 'ISBN',
              'publisher': 'Publisher',
              'publishedYear': 2020,
              'genre': 'Genre',
              'language': 'Kannada',
              'coverUrl': 'covers/x.png',
              'ageGroup': 'above-10',
              'availability': 'available',
              'issue': {'periodicalUid': 'p', 'volume': 1},
            }),
          ],
        ),
      );
      final item = decoded.items.single;
      expect(item.kind, PublishedItemKind.unknown);
      expect(item.title, 'A Book');
      expect(item.titleTransliteration, isNull);
      expect(item.author, isNull);
      expect(item.isbn, isNull);
      expect(item.publisher, isNull);
      expect(item.publishedYear, isNull);
      expect(item.genre, isNull);
      expect(item.availability, isNull);
      expect(item.issue, isNull);
      expect(item.language, 'Kannada');
      expect(item.ageGroup, AgeGroup.above10);
      expect(item.coverUrl, 'covers/x.png');
    });

    test('Other cannot gain a magazine issue or availability', () {
      final decoded = decodeOk(
        catalogue(
          books: [
            bookRow({
              'kind': 'other',
              'availability': 'out',
              'issue': {'periodicalUid': 'p'},
            }),
          ],
        ),
      );
      expect(decoded.items.single.availability, isNull);
      expect(decoded.items.single.issue, isNull);
    });
  });

  group('field rules', () {
    test('a missing, blank, wrong-type or over-cap title drops the row', () {
      final overCap = 'x' * (CatalogueRules.maxFieldChars + 1);
      for (final badTitle in <Object?>[null, '', '   ', 42, overCap]) {
        final decoded = decodeOk(
          catalogue(
            books: [
              bookRow({'title': badTitle}),
            ],
          ),
        );
        expect(decoded.items, isEmpty, reason: 'title $badTitle');
        expect(decoded.warnings.droppedItems, 1);
        expect(decoded.hasNoReadableItems, isTrue);
      }
    });

    test('a title exactly at the field cap is kept', () {
      final atCap = 'x' * CatalogueRules.maxFieldChars;
      final decoded = decodeOk(
        catalogue(
          books: [
            bookRow({'title': atCap}),
          ],
        ),
      );
      expect(decoded.items.single.title.length, CatalogueRules.maxFieldChars);
    });

    test(
      'optional strings: blank is silent, wrong type/over-cap is counted',
      () {
        final overCap = 'y' * (CatalogueRules.maxFieldChars + 1);
        final decoded = decodeOk(
          catalogue(
            books: [
              bookRow({'author': ''}),
              bookRow({'author': 7}),
              bookRow({'author': overCap}),
            ],
          ),
        );
        expect(decoded.items[0].author, isNull);
        expect(decoded.items[1].author, isNull);
        expect(decoded.items[2].author, isNull);
        expect(decoded.warnings.invalidOptionalFields, 2);
      },
    );

    test('publishedYear accepts 1..9999 only, never coercing types', () {
      for (final good in <int>[1, 9999]) {
        expect(
          decodeOk(
            catalogue(
              books: [
                bookRow({'publishedYear': good}),
              ],
            ),
          ).items.single.publishedYear,
          good,
        );
      }
      for (final bad in <Object?>[0, -1, 10000, '1976', 1976.5, true]) {
        final decoded = decodeOk(
          catalogue(
            books: [
              bookRow({'publishedYear': bad}),
            ],
          ),
        );
        expect(decoded.items.single.publishedYear, isNull, reason: '$bad');
        expect(decoded.warnings.invalidOptionalFields, 1, reason: '$bad');
      }
    });

    test('availability accepts exactly available/out', () {
      expect(
        decodeOk(
          catalogue(
            books: [
              bookRow({'availability': 'available'}),
            ],
          ),
        ).items.single.availability,
        PublishedAvailability.available,
      );
      expect(
        decodeOk(
          catalogue(
            books: [
              bookRow({'availability': 'out'}),
            ],
          ),
        ).items.single.availability,
        PublishedAvailability.out,
      );
      for (final bad in <Object?>['AVAILABLE', 'lent', 1, true]) {
        final decoded = decodeOk(
          catalogue(
            books: [
              bookRow({'availability': bad}),
            ],
          ),
        );
        expect(decoded.items.single.availability, isNull);
        expect(decoded.warnings.invalidOptionalFields, 1);
      }
    });

    test('age tokens are exact: never trimmed, folded or aliased', () {
      for (final bad in <Object?>['Above-3', ' above-3', 'age-10', 3]) {
        final decoded = decodeOk(
          catalogue(
            books: [
              bookRow({'ageGroup': bad}),
            ],
          ),
        );
        expect(decoded.items.single.ageGroup, isNull, reason: '$bad');
        expect(decoded.warnings.invalidOptionalFields, 1, reason: '$bad');
      }
      // Legacy tokens the bundled viewer still accepts do map.
      expect(
        decodeOk(
          catalogue(
            books: [
              bookRow({'ageGroup': 'AGE_11_16'}),
            ],
          ),
        ).items.single.ageGroup,
        AgeGroup.above10,
      );
    });

    test('an unsafe cover reference is dropped with a warning', () {
      for (final bad in <Object?>[
        'http://covers.openlibrary.org/a.jpg',
        'https://evil.example/a.jpg',
        'covers/../secret.jpg',
        'javascript:alert(1)',
        5,
      ]) {
        final decoded = decodeOk(
          catalogue(
            books: [
              bookRow({'coverUrl': bad}),
            ],
          ),
        );
        expect(decoded.items.single.coverUrl, isNull, reason: '$bad');
      }
      expect(
        decodeOk(
          catalogue(
            books: [
              bookRow({'coverUrl': ' '}),
            ],
          ),
        ).items.single.coverUrl,
        isNull,
      );
      // An allow-listed absolute cover and a relative one both survive.
      expect(
        decodeOk(
          catalogue(
            books: [
              bookRow({'coverUrl': 'https://archive.org/download/x/y.jpg'}),
              bookRow({'coverUrl': 'covers/ok.jpg'}),
            ],
          ),
        ).items.map((i) => i.coverUrl),
        ['https://archive.org/download/x/y.jpg', 'covers/ok.jpg'],
      );
    });
  });

  /// Review finding 9: the 8,000-character retained-field contract applies to
  /// the SANITIZED cover reference too, for both row kinds.
  ///
  /// Cases are identified by label, never by echoing the generated string: a
  /// failure message must not print an 8,000-character hostile value.
  group('cover field cap', () {
    const cap = CatalogueRules.maxFieldChars;

    /// An allow-listed absolute cover reference of exactly [length] characters
    /// after trimming/sanitization.
    String absoluteCoverOfLength(int length) {
      const prefix = 'https://covers.openlibrary.org/b/id/';
      const suffix = '.jpg';
      final leafLength = length - prefix.length - suffix.length;
      return '$prefix${'a' * leafLength}$suffix';
    }

    /// A same-site `covers/<leaf>` reference of exactly [length] characters.
    String sameSiteCoverOfLength(int length) =>
        'covers/${'b' * (length - 'covers/'.length)}';

    Map<String, Object?> seriesRow(String uid, Object? cover) => {
      'periodicalUid': uid,
      'title': 'Series',
      'coverUrl': cover,
    };

    test('an absolute cover exactly at the cap is retained silently', () {
      final atCap = absoluteCoverOfLength(cap);
      final decoded = decodeOk(
        catalogue(
          books: [
            bookRow({'coverUrl': '  $atCap  '}),
          ],
        ),
      );
      expect(decoded.items.single.coverUrl, atCap);
      expect(decoded.warnings.invalidOptionalFields, 0);
      expect(decoded.warnings.hasPartialRead, isFalse);
    });

    test('an absolute cover one over the cap is dropped once', () {
      final overCap = absoluteCoverOfLength(cap + 1);
      final decoded = decodeOk(
        catalogue(
          books: [
            bookRow({'coverUrl': overCap}),
          ],
        ),
      );
      expect(decoded.items.single.coverUrl, isNull);
      expect(decoded.warnings.invalidOptionalFields, 1);
      expect(decoded.warnings.hasPartialRead, isTrue);
    });

    test('a same-site cover is held to the same boundary', () {
      final atCap = sameSiteCoverOfLength(cap);
      final overCap = sameSiteCoverOfLength(cap + 1);

      final kept = decodeOk(
        catalogue(
          books: [
            bookRow({'coverUrl': atCap}),
          ],
        ),
      );
      expect(kept.items.single.coverUrl, atCap);
      expect(kept.warnings.invalidOptionalFields, 0);

      final dropped = decodeOk(
        catalogue(
          books: [
            bookRow({'coverUrl': overCap}),
          ],
        ),
      );
      // Without the cap this would survive the reader and only be refused much
      // later by the resolver, silently and without a warning.
      expect(dropped.items.single.coverUrl, isNull);
      expect(dropped.warnings.invalidOptionalFields, 1);
    });

    test('periodical rows obey the same boundary', () {
      final atCap = absoluteCoverOfLength(cap);
      final overCap = absoluteCoverOfLength(cap + 1);

      final kept = decodeOk(catalogue(periodicals: [seriesRow('kept', atCap)]));
      expect(kept.periodicals.single.coverUrl, atCap);
      expect(kept.warnings.invalidOptionalFields, 0);

      final dropped = decodeOk(
        catalogue(periodicals: [seriesRow('dropped', overCap)]),
      );
      expect(dropped.periodicals.single.coverUrl, isNull);
      expect(dropped.warnings.invalidOptionalFields, 1);
      expect(dropped.warnings.hasPartialRead, isTrue);
    });

    test('a same-site periodical reference is capped too', () {
      final overCap = sameSiteCoverOfLength(cap + 1);
      final decoded = decodeOk(
        catalogue(periodicals: [seriesRow('dropped', '  $overCap  ')]),
      );
      expect(decoded.periodicals.single.coverUrl, isNull);
      expect(decoded.warnings.invalidOptionalFields, 1);
    });

    test('an unsafe value that is also over-cap is counted once', () {
      // Both defects at once must not double-count the one dropped field.
      final hostile = 'http://evil.example/${'c' * (cap + 10)}';
      final decoded = decodeOk(
        catalogue(
          books: [
            bookRow({'coverUrl': hostile}),
          ],
        ),
      );
      expect(decoded.items.single.coverUrl, isNull);
      expect(decoded.warnings.invalidOptionalFields, 1);
    });
  });

  group('issue details', () {
    Map<String, Object?> issueRow(Object? issue) =>
        bookRow({'kind': 'magazine-issue', 'issue': issue});

    test('positive counts only', () {
      final ok = decodeOk(
        catalogue(
          books: [
            issueRow({'periodicalUid': 'p', 'volume': 1, 'issueNumber': 2}),
          ],
        ),
      );
      expect(ok.items.single.issue!.volume, 1);
      expect(ok.items.single.issue!.issueNumber, 2);

      for (final bad in <Object?>[0, -1, 2.5, '2', true]) {
        final decoded = decodeOk(
          catalogue(
            books: [
              issueRow({
                'periodicalUid': 'p',
                'volume': bad,
                'issueNumber': bad,
              }),
            ],
          ),
        );
        expect(decoded.items.single.issue!.volume, isNull, reason: '$bad');
        expect(decoded.items.single.issue!.issueNumber, isNull);
        expect(decoded.warnings.invalidOptionalFields, 2);
      }
    });

    test('an exact UTC-midnight day is preserved', () {
      final day = CalendarDate(2026, 10, 4).epochMillis;
      final decoded = decodeOk(
        catalogue(
          books: [
            issueRow({'periodicalUid': 'p', 'issueDate': day}),
          ],
        ),
      );
      expect(decoded.items.single.issue!.issueDate, day);
    });

    test('invalid or out-of-range days are dropped, never clamped', () {
      for (final bad in <Object?>[-1, 8640000000000001, 'yesterday', 1.5]) {
        final decoded = decodeOk(
          catalogue(
            books: [
              issueRow({'periodicalUid': 'p', 'issueDate': bad}),
            ],
          ),
        );
        expect(decoded.items.single.issue!.issueDate, isNull, reason: '$bad');
        expect(decoded.warnings.invalidOptionalFields, 1);
      }
    });

    test('a bound volume needs a valid, ordered start and end', () {
      final start = CalendarDate(2025, 1, 1).epochMillis;
      final end = CalendarDate(2025, 12, 31).epochMillis;
      final bound = decodeOk(
        catalogue(
          books: [
            issueRow({
              'periodicalUid': 'p',
              'issueDate': start,
              'boundUntil': end,
            }),
          ],
        ),
      ).items.single.issue!;
      expect(bound.isBound, isTrue);
      expect(bound.boundUntil, end);

      final backwards = decodeOk(
        catalogue(
          books: [
            issueRow({
              'periodicalUid': 'p',
              'issueDate': end,
              'boundUntil': start,
            }),
          ],
        ),
      );
      expect(backwards.items.single.issue!.boundUntil, isNull);
      expect(backwards.items.single.issue!.isBound, isFalse);
      expect(backwards.warnings.invalidOptionalFields, 1);

      final noStart = decodeOk(
        catalogue(
          books: [
            issueRow({'periodicalUid': 'p', 'boundUntil': end}),
          ],
        ),
      );
      expect(noStart.items.single.issue!.boundUntil, isNull);
      expect(noStart.warnings.invalidOptionalFields, 1);
    });

    test('a magazine issue without usable linkage stays ungrouped', () {
      final decoded = decodeOk(catalogue(books: [issueRow(null)]));
      expect(decoded.items.single.kind, PublishedItemKind.magazineIssue);
      expect(decoded.items.single.issue, isNull);
      expect(decoded.warnings.droppedItems, 0);
    });

    test('an empty or wrong-typed issue block is not a dropped row', () {
      expect(
        decodeOk(
          catalogue(books: [issueRow(<String, Object?>{})]),
        ).items.single.issue,
        isNull,
      );
      final wrong = decodeOk(catalogue(books: [issueRow('nope')]));
      expect(wrong.items.single.issue, isNull);
      expect(wrong.warnings.invalidOptionalFields, 1);
    });

    test('a partial issue block keeps the readable parts', () {
      final decoded = decodeOk(
        catalogue(
          books: [
            issueRow({'periodicalUid': '  series  ', 'issueNumber': 7}),
          ],
        ),
      );
      final issue = decoded.items.single.issue!;
      expect(issue.periodicalUid, 'series');
      expect(issue.issueNumber, 7);
      expect(issue.volume, isNull);
    });

    test('a blank issue uid is unusable but the issue still displays', () {
      final decoded = decodeOk(
        catalogue(
          books: [
            issueRow({'periodicalUid': '   ', 'issueNumber': 3}),
          ],
        ),
      );
      expect(decoded.items.single.issue!.periodicalUid, isNull);
      expect(decoded.items.single.issue!.issueNumber, 3);
      expect(decoded.warnings.invalidOptionalFields, 1);
    });
  });

  group('periodicals', () {
    Map<String, Object?> series(String uid, [String title = 'Series']) => {
      'periodicalUid': uid,
      'title': title,
    };

    test('duplicate canonical uids: last valid wins, first position kept', () {
      final decoded = decodeOk(
        catalogue(
          periodicals: [
            series('alpha', 'First'),
            series('beta', 'Beta'),
            series(' alpha ', 'Last'),
          ],
        ),
      );
      expect(decoded.periodicals.map((p) => p.periodicalUid), [
        'alpha',
        'beta',
      ]);
      expect(decoded.periodicals.first.title, 'Last');
      expect(decoded.warnings.duplicateSeriesUids, 1);
    });

    test('a duplicate whose later row is invalid keeps the valid entry', () {
      final decoded = decodeOk(
        catalogue(
          periodicals: [
            series('alpha', 'First'),
            {'periodicalUid': 'alpha'},
          ],
        ),
      );
      expect(decoded.periodicals.single.title, 'First');
      expect(decoded.warnings.droppedPeriodicals, 1);
      expect(decoded.warnings.duplicateSeriesUids, 0);
    });

    test('blank uid or missing title drops the series row', () {
      for (final bad in <Object?>[
        {'periodicalUid': '   ', 'title': 'x'},
        {'periodicalUid': 'u'},
        {'title': 'x'},
        ['u', 'x'],
      ]) {
        final decoded = decodeOk(catalogue(periodicals: [bad]));
        expect(decoded.periodicals, isEmpty, reason: '$bad');
        expect(decoded.warnings.droppedPeriodicals, 1, reason: '$bad');
      }
    });

    test('a non-ASCII canonical uid is preserved (trim only)', () {
      final decoded = decodeOk(catalogue(periodicals: [series('  ಚಂದಮಾಮ  ')]));
      expect(decoded.periodicals.single.periodicalUid, 'ಚಂದಮಾಮ');
    });

    test('unknown frequency tokens become absent', () {
      final decoded = decodeOk(
        catalogue(
          periodicals: [
            {'periodicalUid': 'u', 'title': 't', 'frequency': 'hourly'},
          ],
        ),
      );
      expect(decoded.periodicals.single.frequency, isNull);
      expect(decoded.warnings.invalidOptionalFields, 1);
    });
  });

  group('bounds', () {
    test('the row cap truncates visibly (injected small cap)', () {
      final decoded = decodeOk(
        catalogue(books: [bookRow(), bookRow(), bookRow()]),
        withCodec: const PublishedCatalogueCodec(maxRows: 2),
      );
      expect(decoded.items, hasLength(2));
      expect(decoded.warnings.itemsTruncated, isTrue);
      expect(decoded.warnings.hasPartialRead, isTrue);
    });

    test('the periodical row cap truncates visibly', () {
      final decoded = decodeOk(
        catalogue(
          periodicals: [
            {'periodicalUid': 'a', 'title': 'A'},
            {'periodicalUid': 'b', 'title': 'B'},
            {'periodicalUid': 'c', 'title': 'C'},
          ],
        ),
        withCodec: const PublishedCatalogueCodec(maxRows: 2),
      );
      expect(decoded.periodicals, hasLength(2));
      expect(decoded.warnings.periodicalsTruncated, isTrue);
    });

    test('sourceIndex follows the published array, even across drops', () {
      final decoded = decodeOk(
        catalogue(
          books: [
            bookRow({'title': 'one'}),
            {'title': ''},
            bookRow({'title': 'three'}),
          ],
        ),
      );
      expect(decoded.items.map((i) => i.sourceIndex), [0, 2]);
    });

    test('a newer schema version does not change any read rule', () {
      final decoded = decodeOk(
        catalogue(
          schemaVersion: 99,
          books: [
            bookRow({'title': ''}),
            bookRow(),
          ],
        ),
      );
      expect(decoded.items, hasLength(1));
      expect(decoded.warnings.droppedItems, 1);
      expect(decoded.hasNewerSchema, isTrue);
    });

    test('the models are unmodifiable', () {
      final decoded = decodeOk(
        catalogue(
          books: [bookRow()],
          periodicals: [
            {'periodicalUid': 'u', 'title': 't'},
          ],
        ),
      );
      expect(decoded.items, hasLength(1));
      expect(decoded.periodicals, hasLength(1));
      expect(
        () => decoded.items.add(decoded.items.first),
        throwsUnsupportedError,
      );
      expect(
        () => decoded.periodicals.add(decoded.periodicals.first),
        throwsUnsupportedError,
      );
    });
  });
}

/// A real nested value `depth` arrays deep (a JSON-encoded string of brackets
/// would be ignored by the string-aware scan — that is the point of it).
Object? _nest(int depth) => depth == 0 ? 1 : <Object?>[_nest(depth - 1)];

/// Every string a decoded catalogue retains, for the "no private sentinel"
/// assertions. Kept here (test-only) so the production models need no
/// reflection/`toString` for a security test.
Iterable<String> _retainedStrings(PublishedCatalogue catalogue) sync* {
  for (final item in catalogue.items) {
    for (final value in <String?>[
      item.title,
      item.titleTransliteration,
      item.author,
      item.isbn,
      item.publisher,
      item.genre,
      item.language,
      item.coverUrl,
      item.issue?.periodicalUid,
      item.issue?.label,
    ]) {
      if (value != null) yield value;
    }
  }
  for (final series in catalogue.periodicals) {
    for (final value in <String?>[
      series.periodicalUid,
      series.title,
      series.titleTransliteration,
      series.issn,
      series.publisher,
      series.language,
      series.coverUrl,
    ]) {
      if (value != null) yield value;
    }
  }
}
