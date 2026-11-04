import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/events/domain/entities/event_poster.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/publish/application/publish_cover_decider.dart';
import 'package:pitaka/features/publish/application/site/catalogue_section_builder.dart';
import 'package:pitaka/features/publish/application/site/events_section_builder.dart';
import 'package:pitaka/features/publish/domain/publish_cover_names.dart';
import 'package:pitaka/features/publish/domain/publish_item_keys.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';
import 'package:pitaka/features/publish/domain/site/publish_artifact_sink.dart';
import 'package:pitaka/features/publish/domain/site/publish_file.dart';
import 'package:pitaka/features/publish/domain/site/publish_mode.dart';
import 'package:pitaka/features/publish/domain/site/publish_snapshot.dart';

final class _Sink implements PublishArtifactSink {
  final List<PublishFile> files = [];
  Failure? failure;

  /// Called with the path each time a write is accepted; a test records the
  /// order of writes against the order covers are read (finding 6).
  void Function(String path)? onWrite;

  @override
  Future<Either<Failure, Unit>> write(PublishFile file) async {
    files.add(file);
    final failure = this.failure;
    if (failure == null) onWrite?.call(file.path);
    return failure == null ? right(unit) : left(failure);
  }
}

/// A valid public key for item 1 (ADR 0019): the builder refuses an item
/// without one. The cover names come from a fixed salt (plan D.5).
final _naming = (
  keys: PublishKeySet.tryCreate(
    id: 'fedcba9876543210',
    keysById: const {1: '0123456789abcdef'},
  )!,
  coverNames: PublishCoverNames.tryCreate(ascii.encode('salt-1234567890'))!,
);

void main() {
  CatalogueSectionBuilder catalogue(_Sink sink) => CatalogueSectionBuilder(
    covers: PublishCoverDecider(
      readLocalCover: (_) async => [1, 2, 3],
      fetchRemoteCover: (_) async => null,
    ),
    buildViewerHtml:
        ({required libraryName, required contact, required sharing}) async =>
            utf8.encode('<html></html>'),
    encodeBooksJson: encodeBooksJsonBytes,
    sink: sink,
  );

  EventsSectionBuilder events(_Sink sink) => EventsSectionBuilder(
    readPoster: (_) async => [4, 5, 6],
    buildEventsHtml: ({required libraryName, required posters}) async =>
        utf8.encode('<html></html>'),
    buildEventsJson: (_) => utf8.encode('{"posters":[]}'),
    sink: sink,
  );

  test('catalogue spools each artifact and returns only metadata', () async {
    final sink = _Sink();
    final section = (await catalogue(sink).build(
      books: const [
        CatalogueItem(id: 1, title: 'Book', coverUrl: 'covers/a.jpg'),
      ],
      periodicals: const [],
      activeLoanCounts: null,
      libraryJson: null,
      gitHubPagesSite: false,
      settings: const PublishPageSettings(libraryName: 'Test Library'),
      previous: PublishManifest.empty,
      now: 1,
      naming: _naming,
      mode: PublishMode.complete,
    )).toNullable()!;

    expect(section.files.every((file) => file.bytes.isEmpty), isTrue);
    expect(sink.files.every((file) => file.bytes.isNotEmpty), isTrue);
    // Every produced file keeps its EXACT length after the bytes are released
    // (review finding 6): read-back caps and timing use storedSize.
    final writtenByPath = {for (final f in sink.files) f.path: f};
    for (final file in section.files) {
      final written = writtenByPath[file.path];
      if (written == null) continue; // a reused entry carries no bytes
      expect(file.storedSize, written.bytes.length);
      expect(file.size, written.bytes.length);
    }
    expect(
      sink.files.map((file) => file.path),
      contains('covers/3368361cb6e5a33e.jpg'),
    );
  });

  test('a cover is written before the NEXT cover is read, and each path is '
      'spooled exactly once', () async {
    final order = <String>[];
    final sink = _Sink()..onWrite = (path) => order.add('write $path');
    final section =
        (await CatalogueSectionBuilder(
              covers: PublishCoverDecider(
                readLocalCover: (coverUrl) async {
                  order.add('read $coverUrl');
                  return [
                    1,
                    2,
                    3,
                  ]; // different sources produce different bytes? both
                },
                fetchRemoteCover: (_) async => null,
              ),
              buildViewerHtml:
                  ({
                    required libraryName,
                    required contact,
                    required sharing,
                  }) async => utf8.encode('<html></html>'),
              encodeBooksJson: encodeBooksJsonBytes,
              sink: sink,
            ).build(
              books: const [
                CatalogueItem(id: 1, title: 'One', coverUrl: 'covers/a.jpg'),
                CatalogueItem(id: 2, title: 'Two', coverUrl: 'covers/b.jpg'),
              ],
              periodicals: const [],
              activeLoanCounts: null,
              libraryJson: null,
              gitHubPagesSite: false,
              settings: const PublishPageSettings(libraryName: 'Test Library'),
              previous: PublishManifest.empty,
              now: 1,
              naming: (
                keys: PublishKeySet.tryCreate(
                  id: 'fedcba9876543210',
                  keysById: const {
                    1: '0123456789abcdef',
                    2: 'fedcba9876543210',
                  },
                )!,
                coverNames: PublishCoverNames.tryCreate(
                  ascii.encode('salt-1234567890'),
                )!,
              ),
              mode: PublishMode.complete,
            ))
            .toNullable()!;

    // The cover decides are interleaved with their writes: the first cover's
    // write finished before the second cover was read.
    final secondRead = order.indexOf('read covers/b.jpg');
    expect(secondRead, isNot(-1));
    expect(
      order.take(secondRead).where((e) => e.startsWith('write covers/')).length,
      1,
      reason: 'the first cover was spooled before the second was read',
    );
    // Each produced path was written once: the assembly stage reuses the
    // stored metadata instead of spooling a second time.
    final writtenPaths = sink.files.map((f) => f.path).toList();
    expect(writtenPaths.toSet().length, writtenPaths.length);
    expect(section.files.every((f) => f.bytes.isEmpty), isTrue);
  });

  test('events spools each poster and returns only metadata', () async {
    final sink = _Sink();
    final section = (await events(sink).build(
      content: const EventsContent(
        posters: [EventPoster(imageRef: 'posters/a.jpg')],
      ),
      settings: const PublishPageSettings(libraryName: 'Test Library'),
      previous: PublishManifest.empty,
      mode: PublishMode.complete,
    )).toNullable()!;

    expect(section.files.every((file) => file.bytes.isEmpty), isTrue);
    expect(sink.files.map((file) => file.path), contains('posters/a.jpg'));
  });

  test('a sink failure is typed and aborts the section build', () async {
    final sink = _Sink()..failure = const StorageFailure('spool failed');
    final catalogueResult = await catalogue(sink).build(
      books: const [CatalogueItem(id: 1, title: 'Book')],
      periodicals: const [],
      activeLoanCounts: null,
      libraryJson: null,
      gitHubPagesSite: false,
      settings: const PublishPageSettings(libraryName: 'Test Library'),
      previous: PublishManifest.empty,
      now: 1,
      naming: _naming,
      mode: PublishMode.complete,
    );
    final eventsResult = await events(sink).build(
      content: const EventsContent(
        posters: [EventPoster(imageRef: 'posters/a.jpg')],
      ),
      settings: const PublishPageSettings(libraryName: 'Test Library'),
      previous: PublishManifest.empty,
      mode: PublishMode.complete,
    );

    expect(catalogueResult.swap().toNullable(), isA<StorageFailure>());
    expect(eventsResult.swap().toNullable(), isA<StorageFailure>());
  });
}
