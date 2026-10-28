import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_publish_artifacts.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_limits.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_site_manifest.dart';
import 'package:pitaka/features/publish/domain/site/publish_file.dart';
import 'package:pitaka/features/publish/domain/site/publish_marker.dart';
import 'package:pitaka/features/publish/domain/site/publish_mode.dart';
import 'package:pitaka/features/publish/domain/site/publish_section.dart';
import 'package:pitaka/features/publish/domain/site/publish_snapshot.dart';
import 'package:pitaka/features/publish/domain/site/publish_state.dart';
import 'package:pitaka/features/publish/infrastructure/cloudflare_publish_marker_codec.dart';
import 'package:pitaka/features/publish/infrastructure/file_publish_artifact_store.dart';

import '../../support/cloudflare_fakes.dart';
import '../../support/cloudflare_s8_fakes.dart';

void main() {
  late Directory dir;
  late FilePublishArtifactStore store;
  final target = cloudflareTestConnection().status.target!;
  const marker = PublishMarker(
    publishId: cloudflareTestPublishId,
    publishedAt: cloudflareTestNow,
    state: PublishMarkerState.live,
  );

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('pitaka_s8_assemble_');
    store = FilePublishArtifactStore(baseDir: dir.path);
  });

  tearDown(() async {
    await store.dispose();
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  CloudflarePublishArtifactAssembler assembler() =>
      CloudflarePublishArtifactAssembler(
        store: store,
        codec: const CloudflarePublishMarkerCodec(),
      );

  PublishSnapshot snapshot({
    required List<PublishFile> catalogue,
    List<PublishFile>? events,
  }) => PublishSnapshot(
    mode: PublishMode.complete,
    catalogue: PublishSection(section: SiteSection.catalogue, files: catalogue),
    events: events == null
        ? null
        : PublishSection(section: SiteSection.events, files: events),
    catalogueItemCount: 0,
    posterCount:
        events?.where((f) => f.path.startsWith('posters/')).length ?? 0,
    availabilityOmitted: false,
  );

  test(
    'builds a complete manifest and deduplicates per-hash sources',
    () async {
      final same = utf8.encode('{"same":true}');
      final result = await assembler().assemble(
        target: target,
        previous: CloudflareSiteManifest.empty,
        snapshot: snapshot(
          catalogue: [
            s8File('books.json', same),
            s8File('library.json', same),
            s8File('index.html', utf8.encode('<html></html>')),
          ],
        ),
        marker: marker,
      );

      expect(result.isRight(), isTrue);
      final artifacts = result.toNullable()!;
      expect(artifacts.manifest.state, PublishState.deployed);
      expect(artifacts.manifest.publishId, cloudflareTestPublishId);
      expect(artifacts.uploadManifest, hasLength(4));
      final bookHash = artifacts.manifest.entryFor('books.json')!.hash;
      expect(artifacts.manifest.entryFor('library.json')!.hash, bookHash);
      expect(artifacts.pathsForHash(bookHash), ['books.json', 'library.json']);
      expect(artifacts.assetForHash(bookHash), isNotNull);
    },
  );

  test('a catalogue update preserves events and deletes only stale catalogue '
      'assets', () async {
    final oldId = 'a' * 32;
    final previous = s8Manifest(
      target: target,
      publishId: oldId,
      additional: {
        'events.html': s8File('events.html', utf8.encode('<html>old</html>')),
        'events.json': s8File('events.json', utf8.encode('{"posters":[]}')),
        'posters/a.jpg': s8File('posters/a.jpg', [1, 2, 3]),
        'covers/old.jpg': s8File('covers/old.jpg', [4, 5, 6]),
      },
    );
    final result = await assembler().assemble(
      target: target,
      previous: previous,
      snapshot: snapshot(
        catalogue: [
          s8File('books.json', utf8.encode('{"books":[1]}')),
          s8File('index.html', utf8.encode('<html>new</html>')),
        ],
      ),
      marker: marker,
      onlySection: SiteSection.catalogue,
    );

    final artifacts = result.toNullable()!;
    expect(artifacts.manifest.entryFor('events.json'), isNotNull);
    expect(artifacts.manifest.entryFor('posters/a.jpg'), isNotNull);
    expect(artifacts.manifest.entryFor('covers/old.jpg'), isNull);
    expect(artifacts.deletedPaths, ['covers/old.jpg']);
    expect(artifacts.manifest.publishId, cloudflareTestPublishId);
    final oldPosterHash = previous.entryFor('posters/a.jpg')!.hash;
    expect(artifacts.assetForHash(oldPosterHash), isNull);
  });

  test('an events-only merge does not replace the rebuilt catalogue', () async {
    final previous = s8Manifest(target: target, publishId: 'a' * 32);
    final result = await assembler().assemble(
      target: target,
      previous: previous,
      snapshot: snapshot(
        catalogue: [s8File('books.json', utf8.encode('{"new":true}'))],
        events: [
          s8File('events.html', utf8.encode('<html>new</html>')),
          s8File('events.json', utf8.encode('{"posters":[]}')),
        ],
      ),
      marker: marker,
      onlySection: SiteSection.events,
    );

    final artifacts = result.toNullable()!;
    expect(
      artifacts.manifest.shaFor('books.json'),
      previous.shaFor('books.json'),
    );
    expect(artifacts.manifest.entryFor('events.html'), isNotNull);
  });

  test('an untrusted carried hash requires complete replacement', () async {
    final previousJson = s8Manifest(
      target: target,
      publishId: 'a' * 32,
      additional: {
        'events.html': s8File('events.html', utf8.encode('<html></html>')),
        'events.json': s8File('events.json', utf8.encode('{"posters":[]}')),
      },
    ).toJson();
    previousJson['hashScheme'] = 'older-scheme';
    final previous = CloudflareSiteManifest.fromJson(previousJson);

    final result = await assembler().assemble(
      target: target,
      previous: previous,
      snapshot: snapshot(
        catalogue: s8CoreFiles('b' * 32).values
            .where((file) => file.path != CloudflareLimits.markerPath)
            .toList(),
      ),
      marker: marker,
      onlySection: SiteSection.catalogue,
    );

    expect(result.isLeft(), isTrue);
    final failure = result.swap().toNullable()!;
    expect(failure, isA<CloudflareFailure>());
    expect((failure as CloudflareFailure).requiresCompleteSnapshot, isTrue);
  });
}
