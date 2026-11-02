import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_publication_verifier.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_limits.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_site_manifest.dart';
import 'package:pitaka/features/publish/domain/site/publish_file.dart';
import 'package:pitaka/features/publish/domain/site/published_site_verifier.dart';

import '../../support/cloudflare_fakes.dart';
import '../../support/cloudflare_s8_fakes.dart';

void main() {
  final target = cloudflareTestConnection().status.target!;
  final reader = FakeCloudflareWorkerReader();

  const oneRound = CloudflareReadBackBudget(
    rounds: 1,
    interval: Duration.zero,
    deadline: Duration(minutes: 1),
  );

  CloudflarePublicationVerifier verifier({int Function()? clock}) =>
      CloudflarePublicationVerifier(
        reader: reader,
        sleep: (_) async {},
        clock: clock,
      );

  final additional = <String, PublishFile>{
    'library.json': s8File('library.json', utf8.encode('{"schema":1}')),
    'events.html': s8File('events.html', utf8.encode('<html>1</html>')),
    'events.json': s8File('events.json', utf8.encode('{"posters":[1]}')),
    'posters/a.jpg': s8File('posters/a.jpg', [1, 2, 3]),
    'covers/1.jpg': s8File('covers/1.jpg', [4, 5, 6]),
  };
  final files = {...s8CoreFiles(cloudflareTestPublishId), ...additional};
  final manifest = s8Manifest(
    target: target,
    publishId: cloudflareTestPublishId,
    additional: additional,
  );

  setUp(() {
    reader.outcomes.clear();
    reader.calls.clear();
    for (final entry in files.entries) {
      reader.body(entry.key, entry.value.bytes);
    }
    reader.absent('posters/old.jpg');
  });

  test('verifies the documented set at one exact origin, and never reads '
      'covers', () async {
    final result = await verifier().verify(
      target: target,
      manifest: manifest,
      revision: 1,
      markerBytes: files['pitak-publish.json']!.bytes,
      deletedPaths: const ['posters/old.jpg'],
      budget: oneRound,
    );

    expect(result, CloudflarePublicationVerification.verified);
    expect(reader.calls.map((c) => c.$1), everyElement(target.siteUrl));
    expect(
      reader.calls.map((c) => c.$2),
      containsAll(<String>[
        'pitak-publish.json',
        'books.json',
        'library.json',
        'events.json',
        'posters/a.jpg',
        'posters/old.jpg',
      ]),
    );
    expect(
      reader.calls.map((c) => c.$2),
      isNot(anyElement(startsWith('covers/'))),
      reason:
          'the upload protocol already proved every hash; covers are '
          'not read back (M2)',
    );
  });

  // S11 J.7 regression (2026-10-29): the live Worker answered `index.html`
  // and `events.html` with 307s, so a verifier that asked for file names
  // could never pass. It must ask for the canonical addresses instead.
  test('HTML assets are read where the Worker serves them, never at their '
      'redirecting file names', () async {
    final result = await verifier().verify(
      target: target,
      manifest: manifest,
      revision: 1,
      markerBytes: files['pitak-publish.json']!.bytes,
      budget: oneRound,
    );

    expect(result, CloudflarePublicationVerification.verified);
    final paths = reader.calls.map((c) => c.$2).toSet();
    expect(paths, containsAll(<String>['', 'events']));
    expect(paths, isNot(contains('index.html')));
    expect(paths, isNot(contains('events.html')));
  });

  test('a wrong root page body is contradicted', () async {
    reader.body('index.html', utf8.encode('<html>someone else</html>'));

    final result = await verifier().verify(
      target: target,
      manifest: manifest,
      revision: 1,
      budget: oneRound,
    );

    expect(result, CloudflarePublicationVerification.contradicted);
  });

  test('a wrong current poster body is contradicted', () async {
    reader.body('posters/a.jpg', [9, 9, 9]);

    final result = await verifier().verify(
      target: target,
      manifest: manifest,
      revision: 1,
      budget: oneRound,
    );

    expect(result, CloudflarePublicationVerification.contradicted);
  });

  test(
    'an unreadable descriptor is unreachable, never accepted as its 404',
    () async {
      final withoutDescriptor = s8Manifest(
        target: target,
        publishId: cloudflareTestPublishId,
      );
      reader.unreadable('library.json');

      final result = await verifier().verify(
        target: target,
        manifest: withoutDescriptor,
        revision: 1,
        budget: oneRound,
      );

      expect(result, CloudflarePublicationVerification.unreachable);
    },
  );

  test('only timeouts or 404s are unreachable, not contradicted', () async {
    reader
      ..unreadable('books.json')
      ..absent('posters/a.jpg');

    final result = await verifier().verify(
      target: target,
      manifest: manifest,
      revision: 1,
      budget: oneRound,
    );

    expect(result, CloudflarePublicationVerification.unreachable);
  });

  test('a body where a 404 was required is contradicted', () async {
    final withoutDescriptor = s8Manifest(
      target: target,
      publishId: cloudflareTestPublishId,
    );
    reader.body('library.json', utf8.encode('{"schema":1}'));

    final result = await verifier().verify(
      target: target,
      manifest: withoutDescriptor,
      revision: 1,
      budget: oneRound,
    );

    expect(result, CloudflarePublicationVerification.contradicted);
  });

  group('availability.json joins the set (ADR 0019 Decision 11)', () {
    final availability = s8File(
      'availability.json',
      utf8.encode('{"schemaVersion":1,"asOf":0,"out":[]}'),
    );
    final withAvailability = s8Manifest(
      target: target,
      publishId: cloudflareTestPublishId,
      additional: {...additional, 'availability.json': availability},
    );

    test('a recorded file is read back and must match', () async {
      reader.body('availability.json', availability.bytes);
      final verified = await verifier().verify(
        target: target,
        manifest: withAvailability,
        revision: 1,
        markerBytes: files['pitak-publish.json']!.bytes,
        budget: oneRound,
      );
      expect(verified, CloudflarePublicationVerification.verified);
      expect(reader.calls.map((c) => c.$2), contains('availability.json'));

      reader.body('availability.json', utf8.encode('{"out":["stale"]}'));
      final contradicted = await verifier().verify(
        target: target,
        manifest: withAvailability,
        revision: 2,
        markerBytes: files['pitak-publish.json']!.bytes,
        budget: oneRound,
      );
      expect(contradicted, CloudflarePublicationVerification.contradicted);
    });

    test('a removal is proven only by its exact 404', () async {
      reader.absent('availability.json');
      final proven = await verifier().verify(
        target: target,
        manifest: manifest,
        revision: 1,
        markerBytes: files['pitak-publish.json']!.bytes,
        deletedPaths: const ['availability.json'],
        budget: oneRound,
      );
      expect(proven, CloudflarePublicationVerification.verified);
      expect(reader.calls.map((c) => c.$2), contains('availability.json'));

      reader.body('availability.json', availability.bytes);
      final stillServed = await verifier().verify(
        target: target,
        manifest: manifest,
        revision: 2,
        markerBytes: files['pitak-publish.json']!.bytes,
        deletedPaths: const ['availability.json'],
        budget: oneRound,
      );
      expect(stillServed, CloudflarePublicationVerification.contradicted);
    });

    test('a site that never had the file does not read it', () async {
      final result = await verifier().verify(
        target: target,
        manifest: manifest,
        revision: 1,
        markerBytes: files['pitak-publish.json']!.bytes,
        budget: oneRound,
      );
      expect(result, CloudflarePublicationVerification.verified);
      expect(
        reader.calls.map((c) => c.$2),
        isNot(contains('availability.json')),
      );
    });
  });

  group('the availability-only scope (ADR 0019 Decision 11, plan AV13)', () {
    final availability = s8File(
      'availability.json',
      utf8.encode('{"schemaVersion":1,"asOf":0,"out":[]}'),
    );
    final written = s8Manifest(
      target: target,
      publishId: cloudflareTestPublishId,
      additional: {...additional, 'availability.json': availability},
    );
    final markerBytes = files['pitak-publish.json']!.bytes;

    test(
      'a write reads exactly the fresh marker and availability.json',
      () async {
        reader.body('availability.json', availability.bytes);

        final result = await verifier().verify(
          target: target,
          manifest: written,
          revision: 1,
          markerBytes: markerBytes,
          scope: CloudflareReadBackScope.availabilityOnly,
          budget: oneRound,
        );

        expect(result, CloudflarePublicationVerification.verified);
        expect(reader.calls.map((c) => c.$2).toSet(), {
          'pitak-publish.json',
          'availability.json',
        });
        expect(reader.calls.map((c) => c.$1), everyElement(target.siteUrl));
      },
    );

    test('a removal is proven by the marker and the exact 404', () async {
      reader.absent('availability.json');

      final result = await verifier().verify(
        target: target,
        manifest: manifest,
        revision: 1,
        markerBytes: markerBytes,
        deletedPaths: const ['availability.json'],
        scope: CloudflareReadBackScope.availabilityOnly,
        budget: oneRound,
      );

      expect(result, CloudflarePublicationVerification.verified);
      expect(reader.calls.map((c) => c.$2).toSet(), {
        'pitak-publish.json',
        'availability.json',
      });
    });

    test('a still-served file after a removal is contradicted', () async {
      reader.body('availability.json', availability.bytes);

      final result = await verifier().verify(
        target: target,
        manifest: manifest,
        revision: 1,
        markerBytes: markerBytes,
        deletedPaths: const ['availability.json'],
        scope: CloudflareReadBackScope.availabilityOnly,
        budget: oneRound,
      );

      expect(result, CloudflarePublicationVerification.contradicted);
    });

    test('an older marker is never this deploy: it is not verified', () async {
      reader
        ..body('availability.json', availability.bytes)
        ..body('pitak-publish.json', s8Marker('b' * 32));

      final result = await verifier().verify(
        target: target,
        manifest: written,
        revision: 1,
        markerBytes: markerBytes,
        scope: CloudflareReadBackScope.availabilityOnly,
        budget: oneRound,
      );

      expect(result, isNot(CloudflarePublicationVerification.verified));
    });

    test('a deploy that neither wrote nor removed the file proves nothing, '
        'and reads nothing', () async {
      final result = await verifier().verify(
        target: target,
        manifest: manifest,
        revision: 1,
        markerBytes: markerBytes,
        scope: CloudflareReadBackScope.availabilityOnly,
        budget: oneRound,
      );

      expect(result, CloudflarePublicationVerification.unreachable);
      expect(reader.calls, isEmpty);
    });

    test('a record without a marker proves nothing', () async {
      final noMarker = CloudflareSiteManifest(
        target: target,
        publishId: cloudflareTestPublishId,
        files: {'availability.json': s8Entry(availability)},
      );

      final result = await verifier().verify(
        target: target,
        manifest: noMarker,
        revision: 1,
        scope: CloudflareReadBackScope.availabilityOnly,
        budget: oneRound,
      );

      expect(result, CloudflarePublicationVerification.unreachable);
      expect(reader.calls, isEmpty);
    });
  });

  group('immediateFirstRound (plan AV13)', () {
    test(
      'the first round reads before any wait; later rounds still wait',
      () async {
        final events = <String>[];
        // A path that never matches keeps every round going.
        reader.body('books.json', utf8.encode('stale'));
        final logging = _LoggingReader(reader, events);

        final result =
            await CloudflarePublicationVerifier(
              reader: logging,
              sleep: (delay) async => events.add('sleep ${delay.inSeconds}'),
            ).verify(
              target: target,
              manifest: manifest,
              revision: 1,
              budget: const CloudflareReadBackBudget(
                rounds: 3,
                interval: Duration(seconds: 5),
                deadline: Duration(minutes: 1),
                immediateFirstRound: true,
              ),
            );

        expect(result, CloudflarePublicationVerification.contradicted);
        expect(events.first, startsWith('read '));
        // Three rounds, two waits: only the first one is immediate.
        expect(events.where((e) => e.startsWith('sleep ')), [
          'sleep 5',
          'sleep 5',
        ]);
      },
    );

    test('without it, the first round waits first (unchanged)', () async {
      final events = <String>[];
      final logging = _LoggingReader(reader, events);

      await CloudflarePublicationVerifier(
        reader: logging,
        sleep: (delay) async => events.add('sleep ${delay.inSeconds}'),
      ).verify(
        target: target,
        manifest: manifest,
        revision: 1,
        markerBytes: files['pitak-publish.json']!.bytes,
        // The default budget: CloudflareReadBackBudget.afterDeploy.
      );

      expect(events.first, 'sleep 5');
    });
  });

  test(
    'a later propagation round can still finish the grouped verification',
    () async {
      final originalBooks = files['books.json']!.bytes;
      reader.body('books.json', utf8.encode('stale'));
      var reads = 0;
      final propagating = _PropagatingReader(
        reader,
        onBooks: () {
          reads++;
          if (reads == 2) reader.body('books.json', originalBooks);
        },
      );

      final result =
          await CloudflarePublicationVerifier(
            reader: propagating,
            sleep: (_) async {},
          ).verify(
            target: target,
            manifest: manifest,
            revision: 1,
            budget: const CloudflareReadBackBudget(
              rounds: 2,
              interval: Duration.zero,
              deadline: Duration(minutes: 1),
            ),
          );

      expect(result, CloudflarePublicationVerification.verified);
      expect(reads, 2);
    },
  );

  test('the total deadline ends slow reads before the round count', () async {
    var now = 0;
    // One path stays contradicted on every read, so the loop would run for
    // all 100 rounds if the deadline were not enforced.
    reader.unreadable('index.html');
    final counting = _CountingReader(reader);

    final result =
        await CloudflarePublicationVerifier(
          reader: counting,
          sleep: (delay) async => now += delay.inMilliseconds,
          clock: () => now,
        ).verify(
          target: target,
          manifest: manifest,
          revision: 1,
          budget: const CloudflareReadBackBudget(
            rounds: 100,
            interval: Duration(seconds: 5),
            deadline: Duration(seconds: 30),
          ),
        );

    expect(result, CloudflarePublicationVerification.unreachable);
    // 30 s deadline / 5 s per round = 6 rounds (every path is retried once
    // per round), never 100.
    expect(counting.reads, lessThan(100));
    expect(now, greaterThanOrEqualTo(25000));
  });
}

final class _CountingReader implements PublishedSiteReadVerifier {
  _CountingReader(this._inner);

  final PublishedSiteReadVerifier _inner;
  int reads = 0;

  @override
  Future<PublishedSiteReadOutcome> readOutcome({
    required String siteUrl,
    required String path,
    required int maxBytes,
    String? cacheBuster,
  }) {
    reads++;
    return _inner.readOutcome(
      siteUrl: siteUrl,
      path: path,
      maxBytes: maxBytes,
      cacheBuster: cacheBuster,
    );
  }
}

/// Records each read (by path) into [events], interleaved with the sleeps.
final class _LoggingReader implements PublishedSiteReadVerifier {
  _LoggingReader(this._inner, this.events);

  final PublishedSiteReadVerifier _inner;
  final List<String> events;

  @override
  Future<PublishedSiteReadOutcome> readOutcome({
    required String siteUrl,
    required String path,
    required int maxBytes,
    String? cacheBuster,
  }) {
    events.add('read $path');
    return _inner.readOutcome(
      siteUrl: siteUrl,
      path: path,
      maxBytes: maxBytes,
      cacheBuster: cacheBuster,
    );
  }
}

final class _PropagatingReader implements PublishedSiteReadVerifier {
  _PropagatingReader(this._inner, {required this.onBooks});

  final PublishedSiteReadVerifier _inner;
  final void Function() onBooks;

  @override
  Future<PublishedSiteReadOutcome> readOutcome({
    required String siteUrl,
    required String path,
    required int maxBytes,
    String? cacheBuster,
  }) {
    if (path == 'books.json') onBooks();
    return _inner.readOutcome(
      siteUrl: siteUrl,
      path: path,
      maxBytes: maxBytes,
      cacheBuster: cacheBuster,
    );
  }
}
