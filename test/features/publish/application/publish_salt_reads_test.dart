import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/events/domain/entities/event_poster.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/domain/value_objects/periodical_frequency.dart';
import 'package:pitaka/features/publish/application/publish_cover_decider.dart';
import 'package:pitaka/features/publish/application/site/catalogue_section_builder.dart';
import 'package:pitaka/features/publish/application/site/events_section_builder.dart';
import 'package:pitaka/features/publish/application/site/publish_snapshot_builder.dart';
import 'package:pitaka/features/publish/domain/availability/availability_request.dart';
import 'package:pitaka/features/publish/domain/publish_cover_ids.dart';
import 'package:pitaka/features/publish/domain/publish_cover_rendition.dart';
import 'package:pitaka/features/publish/domain/publish_item_keys.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/publish_mode.dart';
import 'package:pitaka/features/publish/domain/site/publish_section.dart';
import 'package:pitaka/features/publish/domain/site/publish_snapshot.dart';

/// Plan D.5 / CV8 (J24): the cover salt is read from secure storage ONCE per
/// publish build, and every item key, the key-set id and every cover file
/// name of that build come from that one read.
///
/// Why this matters (beginner note): a secure-storage read costs about 72 ms
/// on the test phone. Before this fix the item keys were read once per
/// publish but every COVER name read the salt again, so an unchanged
/// republish of 1,000 covers spent 73 of its 90 seconds opening the locked
/// storage although it read no cover file at all.
void main() {
  final salt = ascii.encode('salt-1234567890');
  final target = GitHubPublishTarget.create('me/lib')!;

  String bookPath(int id) =>
      'covers/${PublishCoverIds.shortHashHex(salt, id)}.jpg';
  String seriesPath(String uid) =>
      'covers/${PublishCoverIds.shortHashHexForKey(salt, 'periodical:$uid')}.jpg';

  CatalogueItem book(int id, {String? cover}) =>
      CatalogueItem(id: id, title: 'Book $id', coverUrl: cover);

  Periodical series({String? cover}) => Periodical(
    id: 7,
    periodicalUid: 'uid-1',
    title: 'Chandamama',
    coverUrl: cover,
    frequency: PeriodicalFrequency.monthly,
  );

  /// A record that vouches for every cover in [bookIds] and the series, so an
  /// incremental build REUSES them all and reads no cover file (ADR 0020).
  PublishManifest vouchingRecord(List<int> bookIds, {bool withSeries = true}) =>
      PublishManifest(
        repo: 'me/lib',
        branch: 'main',
        headSha: 'HEAD',
        ownershipConfirmed: true,
        fileShas: {
          for (final id in bookIds) bookPath(id): 'LIVE-$id',
          if (withSeries) seriesPath('uid-1'): 'LIVE-S',
        },
        coverUrlByBookId: {
          for (final id in bookIds) '$id': 'covers/local-$id.jpg',
          if (withSeries) 'periodical:uid-1': 'covers/series.jpg',
        },
        coverRendition: PublishCoverRendition.current,
      );

  PublishSnapshotBuilder builder(
    PublishCoverSaltStore saltStore, {
    LocalCoverReader? readLocalCover,
  }) => PublishSnapshotBuilder(
    itemKeys: PublishItemKeys(saltStore),
    catalogue: CatalogueSectionBuilder(
      covers: PublishCoverDecider(
        readLocalCover: readLocalCover ?? (_) async => utf8.encode('IMG'),
        fetchRemoteCover: (_) async => null,
      ),
      buildViewerHtml:
          ({required libraryName, required contact, required sharing}) async =>
              utf8.encode('<html></html>'),
      encodeBooksJson: encodeBooksJsonBytes,
    ),
    events: EventsSectionBuilder(
      readPoster: (_) async => null,
      buildEventsHtml: ({required libraryName, required posters}) async =>
          utf8.encode('<html></html>'),
      buildEventsJson: (posters) => utf8.encode('{}'),
    ),
  );

  Future<Either<Failure, PublishSnapshot>> readAndBuild(
    PublishSnapshotBuilder subject,
    _FakeReads reads, {
    PublishManifest previous = PublishManifest.empty,
    PublishMode mode = PublishMode.incremental,
  }) async {
    final inputs = (await subject.read(
      reads: reads,
      target: target,
      sections: const {SiteSection.catalogue},
    )).toNullable()!;
    return subject.build(
      inputs: inputs,
      previous: previous,
      now: 1761984345678,
      mode: mode,
    );
  }

  const n = 25;
  final ids = [for (var id = 1; id <= n; id++) id];
  List<CatalogueItem> coveredBooks() => [
    for (final id in ids) book(id, cover: 'covers/local-$id.jpg'),
  ];

  group('one salt read per build (CV8)', () {
    test('an unchanged republish of N covers reads the salt once', () async {
      final store = _CountingSalt(salt);
      var coverReads = 0;
      final subject = builder(
        store,
        readLocalCover: (_) async {
          coverReads++;
          return utf8.encode('IMG');
        },
      );
      final reads = _FakeReads()
        ..books = coveredBooks()
        ..titles = [series(cover: 'covers/series.jpg')];

      final result = await readAndBuild(
        subject,
        reads,
        previous: vouchingRecord(ids),
      );

      expect(result.isRight(), isTrue, reason: '${result.swap().toNullable()}');
      expect(coverReads, 0, reason: 'every cover is reused from the record');
      // Before plan S16 this was 1 + n + 1: the keys read once, then every
      // cover decision (n books + 1 series) read the salt again (J24).
      expect(store.reads, 1);
    });

    test('new covers (every cover read) still read the salt once', () async {
      final store = _CountingSalt(salt);
      final reads = _FakeReads()
        ..books = coveredBooks()
        ..titles = [series(cover: 'covers/series.jpg')];
      final result = await readAndBuild(builder(store), reads);
      expect(result.isRight(), isTrue);
      expect(store.reads, 1);
    });

    test('a COMPLETE snapshot (a move) reads the salt once', () async {
      final store = _CountingSalt(salt);
      final reads = _FakeReads()
        ..books = coveredBooks()
        ..titles = [series(cover: 'covers/series.jpg')];
      final result = await readAndBuild(
        builder(store),
        reads,
        previous: vouchingRecord(ids),
        mode: PublishMode.complete,
      );
      expect(result.isRight(), isTrue);
      expect(store.reads, 1);
    });

    test('a library without covers reads the salt once', () async {
      final store = _CountingSalt(salt);
      final reads = _FakeReads()..books = [for (final id in ids) book(id)];
      final result = await readAndBuild(builder(store), reads);
      expect(result.isRight(), isTrue);
      expect(store.reads, 1);
    });

    test('a lane run (keys only) reads the salt once', () async {
      final store = _CountingSalt(salt);
      final keys = await PublishItemKeys(store).keysFor(ids);
      expect(keys.isRight(), isTrue);
      expect(store.reads, 1);
    });
  });

  group('one read decides everything', () {
    test(
      'keys, key-set id and every cover name come from the FIRST read',
      () async {
        // A store that answers with a different salt on every call. Before
        // plan S16 the keys came from the first read and every cover name
        // from a later one, so this build would have named its covers with
        // salts the keys never saw.
        final store = _ChangingSalt();
        final reads = _FakeReads()
          ..books = coveredBooks()
          ..titles = [series(cover: 'covers/series.jpg')];
        final snapshot = (await readAndBuild(
          builder(store),
          reads,
        )).toNullable()!;

        final first = store.served.first;
        final expectedPaths = {
          for (final id in ids)
            'covers/${PublishCoverIds.shortHashHex(first, id)}.jpg',
          'covers/${PublishCoverIds.shortHashHexForKey(first, 'periodical:uid-1')}.jpg',
        };
        final coverPaths = snapshot.catalogue!.files
            .map((f) => f.path)
            .where((p) => p.startsWith('covers/'))
            .toSet();
        expect(coverPaths, expectedPaths);

        final payload =
            jsonDecode(
                  utf8.decode(
                    snapshot.catalogue!.files
                        .firstWhere((f) => f.path == 'books.json')
                        .bytes,
                  ),
                )
                as Map<String, dynamic>;
        expect(payload['keySet'], PublishItemKeys.keySetIdFor(salt: first));
        // Rows carry no internal id (`publish_export.dart`), so compare the
        // SET of published keys with the set the first salt produces.
        expect(
          {
            for (final row
                in (payload['books'] as List).cast<Map<String, dynamic>>())
              row['key'],
          },
          {
            for (final id in ids)
              PublishItemKeys.keyFor(salt: first, itemId: id),
          },
        );
        expect(store.served, hasLength(1), reason: 'only one read happened');
      },
    );
  });

  group('failure: nothing is read, nothing is written', () {
    test('an empty salt stops the build with the fixed message', () async {
      var coverReads = 0;
      final subject = builder(
        _CountingSalt(const []),
        readLocalCover: (_) async {
          coverReads++;
          return utf8.encode('IMG');
        },
      );
      final result = await readAndBuild(
        subject,
        _FakeReads()..books = coveredBooks(),
      );
      expect(
        (result.swap().toNullable()! as ValidationFailure).message,
        PublishItemKeys.saltUnavailableMessage,
      );
      expect(coverReads, 0);
    });

    test('a throwing store stops the build with the fixed message', () async {
      var coverReads = 0;
      final subject = builder(
        const _ThrowingSalt(),
        readLocalCover: (_) async {
          coverReads++;
          return utf8.encode('IMG');
        },
      );
      final result = await readAndBuild(
        subject,
        _FakeReads()..books = coveredBooks(),
      );
      expect(
        (result.swap().toNullable()! as ValidationFailure).message,
        PublishItemKeys.saltUnavailableMessage,
      );
      expect(coverReads, 0);
    });

    test('namingFor: empty and throwing salts fail the same way', () async {
      final empty = await PublishItemKeys(
        _CountingSalt(const []),
      ).namingFor(ids);
      expect(
        (empty.swap().toNullable()! as ValidationFailure).message,
        PublishItemKeys.saltUnavailableMessage,
      );
      final thrown = await const PublishItemKeys(
        _ThrowingSalt(),
      ).namingFor(ids);
      expect(
        (thrown.swap().toNullable()! as ValidationFailure).message,
        PublishItemKeys.saltUnavailableMessage,
      );
    });
  });
}

/// Counts every `salt()` call: the whole point of this file.
final class _CountingSalt implements PublishCoverSaltStore {
  _CountingSalt(this.bytes);

  final List<int> bytes;
  int reads = 0;

  @override
  Future<List<int>> salt() async {
    reads++;
    return bytes;
  }
}

/// Answers with a DIFFERENT 16-byte salt on every call and remembers each
/// one, so a test can tell which read a name or a key came from.
final class _ChangingSalt implements PublishCoverSaltStore {
  final List<List<int>> served = [];

  @override
  Future<List<int>> salt() async {
    final next = List<int>.generate(16, (i) => (served.length * 31 + i) & 0xff);
    served.add(next);
    return next;
  }
}

/// Fails like unreadable secure storage (a platform error is an Exception).
final class _ThrowingSalt implements PublishCoverSaltStore {
  const _ThrowingSalt();

  @override
  Future<List<int>> salt() async =>
      throw const FormatException('secure storage unreadable');
}

/// In-memory strict reads for a catalogue-only build.
final class _FakeReads implements PublishReads {
  List<CatalogueItem> books = const [];
  List<Periodical> titles = const [];

  @override
  Future<Either<Failure, List<CatalogueItem>>> catalogueItems() async =>
      right(books);

  @override
  Future<Either<Failure, List<Periodical>>> periodicals() async =>
      right(titles);

  @override
  Future<Either<Failure, EventsContent>> events() async =>
      right(EventsContent.empty);

  @override
  Future<Either<Failure, List<int>?>> libraryJson(String siteUrl) async =>
      right(null);

  @override
  Future<Either<Failure, PublishPageSettings>> pageSettings() async =>
      right(const PublishPageSettings(libraryName: 'Test Library'));

  @override
  Future<Either<Failure, Map<int, int>?>> activeLoanCounts() async =>
      right(const {});

  @override
  Future<Either<Failure, AvailabilityRequest>> availability() async =>
      right(const AvailabilityRemoval());
}
