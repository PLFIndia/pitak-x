import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/events/domain/entities/event_poster.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/publish/application/publish_cover_decider.dart';
import 'package:pitaka/features/publish/application/site/catalogue_section_builder.dart';
import 'package:pitaka/features/publish/application/site/events_section_builder.dart';
import 'package:pitaka/features/publish/domain/publish_cover_ids.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';
import 'package:pitaka/features/publish/domain/site/publish_artifact_sink.dart';
import 'package:pitaka/features/publish/domain/site/publish_file.dart';
import 'package:pitaka/features/publish/domain/site/publish_mode.dart';

final class _Sink implements PublishArtifactSink {
  final List<PublishFile> files = [];
  Failure? failure;

  @override
  Future<Either<Failure, Unit>> write(PublishFile file) async {
    files.add(file);
    final failure = this.failure;
    return failure == null ? right(unit) : left(failure);
  }
}

final class _Salt implements PublishCoverSaltStore {
  const _Salt();

  @override
  Future<List<int>> salt() async => ascii.encode('salt-1234567890');
}

void main() {
  CatalogueSectionBuilder catalogue(_Sink sink) => CatalogueSectionBuilder(
    covers: PublishCoverDecider(
      coverIds: const PublishCoverIds(_Salt()),
      readLocalCover: (_) async => [1, 2, 3],
      fetchRemoteCover: (_) async => null,
    ),
    buildViewerHtml: () async => utf8.encode('<html></html>'),
    encodeBooksJson: encodeBooksJsonBytes,
    sink: sink,
  );

  EventsSectionBuilder events(_Sink sink) => EventsSectionBuilder(
    readPoster: (_) async => [4, 5, 6],
    buildEventsHtml: (_) async => utf8.encode('<html></html>'),
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
      previous: PublishManifest.empty,
      now: 1,
      mode: PublishMode.complete,
    )).toNullable()!;

    expect(section.files.every((file) => file.bytes.isEmpty), isTrue);
    expect(sink.files.every((file) => file.bytes.isNotEmpty), isTrue);
    expect(
      sink.files.map((file) => file.path),
      contains('covers/3368361cb6e5a33e.jpg'),
    );
  });

  test('events spools each poster and returns only metadata', () async {
    final sink = _Sink();
    final section = (await events(sink).build(
      content: const EventsContent(
        posters: [EventPoster(imageRef: 'posters/a.jpg')],
      ),
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
      previous: PublishManifest.empty,
      now: 1,
      mode: PublishMode.complete,
    );
    final eventsResult = await events(sink).build(
      content: const EventsContent(
        posters: [EventPoster(imageRef: 'posters/a.jpg')],
      ),
      previous: PublishManifest.empty,
      mode: PublishMode.complete,
    );

    expect(catalogueResult.swap().toNullable(), isA<StorageFailure>());
    expect(eventsResult.swap().toNullable(), isA<StorageFailure>());
  });
}
