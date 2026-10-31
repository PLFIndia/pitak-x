import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/events/domain/entities/event_poster.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/publish/application/publish_cover_decider.dart';
import 'package:pitaka/features/publish/application/site/catalogue_section_builder.dart';
import 'package:pitaka/features/publish/application/site/events_section_builder.dart';
import 'package:pitaka/features/publish/application/site/publish_snapshot_builder.dart';
import 'package:pitaka/features/publish/domain/publish_cover_ids.dart';
import 'package:pitaka/features/publish/domain/publish_export.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/publish_mode.dart';
import 'package:pitaka/features/publish/domain/site/publish_section.dart';
import 'package:pitaka/features/publish/domain/site/publish_snapshot.dart';

/// SPECIFICATION of the snapshot builder (Cloudflare plan R2/R4, J.2).
///
/// These tests pin the two-phase contract every host now relies on:
///  - `read` needs no target and never invents empty content for a failed
///    read (the bug that would replace a live site with an empty one);
///  - `build` refuses, rather than omits, when a COMPLETE publish would drop a
///    referenced asset;
///  - the counts the confirmation dialogs show come from the same snapshot
///    that is written.
const _both = {SiteSection.catalogue, SiteSection.events};

void main() {
  CatalogueItem book({int id = 1, String? cover}) => CatalogueItem(
    id: id,
    title: 'The Odyssey',
    author: 'Homer',
    coverUrl: cover,
  );

  List<int> encode(PublishExport e) =>
      utf8.encode(const JsonEncoder.withIndent('  ').convert(e.toJson()));

  PublishSnapshotBuilder builder({
    LocalCoverReader? readLocalCover,
    PosterBytesReader? readPoster,
  }) => PublishSnapshotBuilder(
    catalogue: CatalogueSectionBuilder(
      covers: PublishCoverDecider(
        coverIds: const PublishCoverIds(_FixedSalt(_saltBytes)),
        readLocalCover: readLocalCover ?? (_) async => null,
        fetchRemoteCover: (_) async => null,
      ),
      buildViewerHtml:
          ({required libraryName, required contact, required sharing}) async =>
              utf8.encode('<html></html>'),
      encodeBooksJson: encode,
    ),
    events: EventsSectionBuilder(
      readPoster: readPoster ?? (_) async => null,
      buildEventsHtml: ({required libraryName, required posters}) async =>
          utf8.encode('<html>${posters.length}</html>'),
      buildEventsJson: (posters) => utf8.encode('{"posters":$posters}'),
    ),
  );

  final target = GitHubPublishTarget.create('me/lib')!;

  EventsContent eventsWith(String imageRef) =>
      EventsContent(posters: [EventPoster(imageRef: imageRef)]);

  group('read — strict, target-free', () {
    test(
      'a failed catalogue read aborts before anything else is read',
      () async {
        final reads = _FakeReads()
          ..catalogueResult = left(const StorageFailure('private-db-detail'));
        final result = await builder().read(
          reads: reads,
          target: target,
          sections: _both,
        );

        expect(result.swap().toNullable(), isA<StorageFailure>());
        expect(
          reads.calls,
          ['catalogue'],
          reason: 'a failed read must stop the phase, not continue reading',
        );
      },
    );

    test('a failed periodical read is a failure, not "no magazines"', () async {
      final reads = _FakeReads()
        ..periodicalsResult = left(const StorageFailure('private-db-detail'));
      final result = await builder().read(
        reads: reads,
        target: target,
        sections: _both,
      );

      expect(result.swap().toNullable(), isA<StorageFailure>());
      expect(reads.calls, ['catalogue', 'periodicals']);
    });

    test('an unavailable settings read aborts the publish (M8)', () async {
      final reads = _FakeReads()
        ..settingsResult = left(const StorageFailure('settings unavailable'));
      final result = await builder().read(
        reads: reads,
        target: target,
        sections: _both,
      );

      expect(result.swap().toNullable(), isA<StorageFailure>());
      expect(reads.calls, contains('settings'));
      // Settings are read once, in phase 1, before any build or write.
      expect(reads.calls.where((call) => call == 'settings'), hasLength(1));
    });

    test('a corrupt events file is a failure, not empty content', () async {
      final reads = _FakeReads()
        ..eventsResult = left(const StorageFailure('corrupt-events-json'));
      final result = await builder().read(
        reads: reads,
        target: target,
        sections: _both,
      );

      expect(result.swap().toNullable(), isA<StorageFailure>());
      expect(reads.calls, contains('events'));
    });

    test('a catalogue-only read never touches the events file', () async {
      final reads = _FakeReads();
      final inputs = (await builder().read(
        reads: reads,
        target: target,
        sections: const {SiteSection.catalogue},
      )).toNullable()!;

      expect(inputs.events, isNull);
      expect(reads.calls, isNot(contains('events')));
    });

    test(
      'a null descriptor read means "descriptor off", not "unreadable"',
      () async {
        final reads = _FakeReads()..descriptorResult = right(null);
        final inputs = (await builder().read(
          reads: reads,
          target: target,
          sections: _both,
        )).toNullable()!;

        expect(inputs.catalogue!.libraryJson, isNull);
        expect(inputs.catalogue!.items, isEmpty);
      },
    );

    test('an events-only read touches nothing catalogue-side (L6)', () async {
      final reads = _FakeReads();

      final inputs = (await builder().read(
        reads: reads,
        target: target,
        sections: const {SiteSection.events},
      )).toNullable()!;

      expect(inputs.catalogue, isNull);
      expect(inputs.events, isNotNull);
      // Only the settings every builder needs and the events file itself.
      expect(reads.calls, contains('settings'));
      expect(reads.calls, contains('events'));
      for (final forbidden in [
        'catalogue',
        'periodicals',
        'counts',
        'libraryJson',
      ]) {
        expect(reads.calls, isNot(contains(forbidden)), reason: forbidden);
      }
    });

    test(
      'an invalid periodical link cannot block an events-only read (L6)',
      () async {
        final reads = _FakeReads()
          ..periodicalsResult = left(const ValidationFailure('bad link'));

        final result = await builder().read(
          reads: reads,
          target: target,
          sections: const {SiteSection.events},
        );

        expect(result.isRight(), isTrue);
      },
    );

    test('an events-only build reads no cover (L6)', () async {
      final reads = _FakeReads()..eventsContent = eventsWith('posters/a.jpg');
      var coverReads = 0;
      final subject = builder(
        readLocalCover: (_) async {
          coverReads++;
          return utf8.encode('IMG');
        },
        readPoster: (_) async => utf8.encode('JPG'),
      );
      final inputs = (await subject.read(
        reads: reads,
        target: target,
        sections: const {SiteSection.events},
      )).toNullable()!;

      final snapshot = (await subject.build(
        inputs: inputs,
        previous: PublishManifest.empty,
        now: 1000,
        mode: PublishMode.complete,
      )).toNullable()!;

      expect(coverReads, 0);
      expect(snapshot.catalogue, isNull);
      expect(snapshot.sections.map((section) => section.section), [
        SiteSection.events,
      ]);
    });
  });

  group('build — complete means refuse, never omit', () {
    test('counts come from the snapshot that is written', () async {
      final reads = _FakeReads()
        ..books = [book(), book(id: 2), book(id: 3, cover: 'covers/gone.jpg')]
        ..eventsContent = eventsWith('posters/a.jpg');
      final inputs = (await builder().read(
        reads: reads,
        target: target,
        sections: _both,
      )).toNullable()!;
      final snapshot =
          (await builder(
                readPoster: (_) async => utf8.encode('JPG'),
                readLocalCover: (src) async => utf8.encode('IMG'),
              ).build(
                inputs: inputs,
                previous: PublishManifest.empty,
                now: 1000,
                mode: PublishMode.incremental,
              ))
              .toNullable()!;

      expect(snapshot.catalogueItemCount, 3);
      expect(snapshot.posterCount, 1);
      expect(snapshot.catalogueIsEmpty, isFalse);
      expect(snapshot.eventsIsEmpty, isFalse);
      expect(snapshot.sections, hasLength(2));
      expect(snapshot.mode, PublishMode.incremental);
    });

    test('an empty catalogue and no posters report both warnings', () async {
      final reads = _FakeReads()..eventsContent = EventsContent.empty;
      final inputs = (await builder().read(
        reads: reads,
        target: target,
        sections: _both,
      )).toNullable()!;
      final snapshot = (await builder().build(
        inputs: inputs,
        previous: PublishManifest.empty,
        now: 1000,
        mode: PublishMode.complete,
      )).toNullable()!;

      expect(snapshot.catalogueIsEmpty, isTrue);
      expect(snapshot.posterCount, 0);
      expect(snapshot.eventsIsEmpty, isTrue);
    });

    test(
      'COMPLETE: an unreadable referenced cover fails before any write',
      () async {
        final reads = _FakeReads()..books = [book(cover: 'covers/gone.jpg')];
        final inputs = (await builder().read(
          reads: reads,
          target: target,
          sections: _both,
        )).toNullable()!;

        final result = await builder().build(
          inputs: inputs,
          previous: PublishManifest.empty,
          now: 1000,
          mode: PublishMode.complete,
        );

        final failure = result.swap().toNullable();
        expect(failure, isA<ValidationFailure>());
        expect(
          (failure! as ValidationFailure).message,
          CatalogueSectionBuilder.missingCoverMessage,
        );
      },
    );

    test('COMPLETE: an unreadable poster fails; INCREMENTAL drops it from all '
        'three representations', () async {
      final reads = _FakeReads()
        ..eventsContent = eventsWith('posters/gone.jpg');
      final inputs = (await builder().read(
        reads: reads,
        target: target,
        sections: _both,
      )).toNullable()!;

      final complete = await builder().build(
        inputs: inputs,
        previous: PublishManifest.empty,
        now: 1000,
        mode: PublishMode.complete,
      );
      final failure = complete.swap().toNullable();
      expect(failure, isA<ValidationFailure>());
      expect(
        (failure! as ValidationFailure).message,
        EventsSectionBuilder.missingPosterMessage,
      );

      final incremental = (await builder().build(
        inputs: inputs,
        previous: PublishManifest.empty,
        now: 1000,
        mode: PublishMode.incremental,
      )).toNullable()!;
      expect(incremental.posterCount, 0);
      // The poster is absent from the page, the JSON and the uploads alike.
      expect(incremental.events!.paths, ['events.html', 'events.json']);
    });

    test('availabilityOmitted mirrors a locked vault', () async {
      final locked = _FakeReads()..counts = null;
      final unlocked = _FakeReads()..counts = const {1: 0};

      for (final (reads, expected) in [(locked, true), (unlocked, false)]) {
        final inputs = (await builder().read(
          reads: reads,
          target: target,
          sections: _both,
        )).toNullable()!;
        final snapshot = (await builder().build(
          inputs: inputs,
          previous: PublishManifest.empty,
          now: 1000,
          mode: PublishMode.incremental,
        )).toNullable()!;
        expect(snapshot.availabilityOmitted, expected);
      }
    });

    test('a catalogue-only snapshot carries no events section', () async {
      final reads = _FakeReads()..books = [book()];
      final inputs = (await builder().read(
        reads: reads,
        target: target,
        sections: const {SiteSection.catalogue},
      )).toNullable()!;
      final snapshot = (await builder().build(
        inputs: inputs,
        previous: PublishManifest.empty,
        now: 1000,
        mode: PublishMode.incremental,
      )).toNullable()!;

      expect(snapshot.events, isNull);
      expect(snapshot.posterCount, 0);
      expect(snapshot.eventsIsEmpty, isFalse);
      expect(snapshot.sections.map((s) => s.section.name), ['catalogue']);
    });
  });
}

/// A fixed cover salt: the decider's deterministic salted paths.
const _saltBytes = <int>[115, 97, 108, 116, 45, 49, 50, 51];

final class _FixedSalt implements PublishCoverSaltStore {
  const _FixedSalt(this.bytes);

  final List<int> bytes;

  @override
  Future<List<int>> salt() async => bytes;
}

/// In-memory strict reads that also record the ORDER they were called in.
final class _FakeReads implements PublishReads {
  List<CatalogueItem> books = const [];
  List<Periodical> titles = const [];
  Map<int, int>? counts = const {};
  EventsContent eventsContent = EventsContent.empty;
  List<int>? descriptor;

  Either<Failure, List<CatalogueItem>>? catalogueResult;
  Either<Failure, List<Periodical>>? periodicalsResult;
  Either<Failure, EventsContent>? eventsResult;
  Either<Failure, List<int>?>? descriptorResult;
  Either<Failure, PublishPageSettings>? settingsResult;

  final calls = <String>[];

  @override
  Future<Either<Failure, List<CatalogueItem>>> catalogueItems() async {
    calls.add('catalogue');
    return catalogueResult ?? right(books);
  }

  @override
  Future<Either<Failure, List<Periodical>>> periodicals() async {
    calls.add('periodicals');
    return periodicalsResult ?? right(titles);
  }

  @override
  Future<Either<Failure, EventsContent>> events() async {
    calls.add('events');
    return eventsResult ?? right(eventsContent);
  }

  @override
  Future<Either<Failure, List<int>?>> libraryJson(String siteUrl) async {
    calls.add('libraryJson');
    return descriptorResult ?? right(descriptor);
  }

  @override
  Future<Either<Failure, PublishPageSettings>> pageSettings() async {
    calls.add('settings');
    return settingsResult ??
        right(const PublishPageSettings(libraryName: 'Test Library'));
  }

  @override
  Future<Either<Failure, Map<int, int>?>> activeLoanCounts() async {
    calls.add('counts');
    return right(counts);
  }
}
