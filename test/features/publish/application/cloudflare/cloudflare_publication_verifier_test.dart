import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_publication_verifier.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_html_routing.dart';
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

  group('round one reads at once (plan SP2)', () {
    test('a deploy that is already served is proven in one round with no '
        'wait at all', () async {
      final events = <String>[];
      final logging = _LoggingReader(reader, events);
      int? rounds;

      final result =
          await CloudflarePublicationVerifier(
            reader: logging,
            sleep: (delay) async => events.add('sleep ${delay.inSeconds}'),
          ).verify(
            target: target,
            manifest: manifest,
            revision: 1,
            markerBytes: files['pitak-publish.json']!.bytes,
            // The default budget: CloudflareReadBackBudget.afterDeploy.
            onRounds: (value) => rounds = value,
          );

      expect(result, CloudflarePublicationVerification.verified);
      expect(rounds, 1);
      expect(events, everyElement(startsWith('read ')));
    });

    test('later rounds still wait the interval first', () async {
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
            ),
          );

      expect(result, CloudflarePublicationVerification.contradicted);
      expect(events.first, startsWith('read '));
      // Three rounds, two waits: only the first one is immediate.
      expect(events.where((e) => e.startsWith('sleep ')), [
        'sleep 5',
        'sleep 5',
      ]);
    });

    test('an earlier record is read at once too', () async {
      final events = <String>[];
      final logging = _LoggingReader(reader, events);

      final result =
          await CloudflarePublicationVerifier(
            reader: logging,
            sleep: (delay) async => events.add('sleep ${delay.inSeconds}'),
          ).verify(
            target: target,
            manifest: manifest,
            revision: 1,
            budget: CloudflareReadBackBudget.earlierDeployment,
          );

      expect(result, CloudflarePublicationVerification.verified);
      expect(events, everyElement(startsWith('read ')));
    });
  });

  group('reads of one round run side by side (plan SP2)', () {
    test(
      'never more than four at once, and they start in path order',
      () async {
        final held = _HeldReader(reader);
        final verification =
            CloudflarePublicationVerifier(
              reader: held,
              sleep: (_) async {},
            ).verify(
              target: target,
              manifest: manifest,
              revision: 1,
              markerBytes: files['pitak-publish.json']!.bytes,
              deletedPaths: const ['posters/old.jpg'],
              budget: oneRound,
            );

        await pumpEventQueue();
        expect(held.started, hasLength(4), reason: 'four reads at once');
        // Release one at a time: each answer lets exactly one more read start.
        while (held.waiting.isNotEmpty) {
          expect(held.inFlight, lessThanOrEqualTo(4));
          held.releaseFirst();
          await pumpEventQueue();
        }

        expect(await verification, CloudflarePublicationVerification.verified);
        expect(held.maxInFlight, 4);
        // Eight paths in the documented set here; reads START in path order
        // (sorted by file name), exactly as they did one by one.
        expect(held.started, [
          'books.json',
          'events', // events.html, read where the Worker serves it
          'events.json',
          '', // index.html, read at the root
          'library.json',
          'pitak-publish.json',
          'posters/a.jpg',
          'posters/old.jpg',
        ]);
      },
    );

    test('a set of two reads both at once (the availability lane)', () async {
      final availability = s8File(
        'availability.json',
        utf8.encode('{"schemaVersion":1,"asOf":0,"out":[]}'),
      );
      reader.body('availability.json', availability.bytes);
      final held = _HeldReader(reader);

      final verification =
          CloudflarePublicationVerifier(
            reader: held,
            sleep: (_) async {},
          ).verify(
            target: target,
            manifest: s8Manifest(
              target: target,
              publishId: cloudflareTestPublishId,
              additional: {...additional, 'availability.json': availability},
            ),
            revision: 1,
            markerBytes: files['pitak-publish.json']!.bytes,
            scope: CloudflareReadBackScope.availabilityOnly,
          );

      await pumpEventQueue();
      expect(held.started, ['availability.json', 'pitak-publish.json']);
      held
        ..releaseFirst()
        ..releaseFirst();
      expect(await verification, CloudflarePublicationVerification.verified);
    });

    test('no read starts once the deadline has passed; reads in flight '
        'finish', () async {
      var now = 0;
      final starts = <int>[];
      // Every read takes 6 s (counted when it answers), so the 10 s deadline
      // passes during round one while four reads are in flight.
      final slow = _SlowReader(
        reader,
        onStart: () => starts.add(now),
        takes: () async {
          await Future<void>.value();
          now += 6000;
        },
      );

      final result =
          await CloudflarePublicationVerifier(
            reader: slow,
            sleep: (delay) async => now += delay.inMilliseconds,
            clock: () => now,
          ).verify(
            target: target,
            manifest: manifest,
            revision: 1,
            markerBytes: files['pitak-publish.json']!.bytes,
            budget: const CloudflareReadBackBudget(
              rounds: 5,
              interval: Duration(seconds: 5),
              deadline: Duration(seconds: 10),
            ),
          );

      expect(result, CloudflarePublicationVerification.unreachable);
      // Four start at once at 0 s. Every later start (if any) happened while
      // time was left, and the round was cut short: the set has eight paths.
      expect(starts.take(4), [0, 0, 0, 0]);
      expect(starts, everyElement(lessThan(10000)));
      expect(starts.length, lessThan(8));
      expect(now, greaterThan(10000), reason: 'reads in flight finished');
    });

    test('a read that throws counts as unreadable and does not stop the '
        'other reads of its round', () async {
      final throwing = _ThrowingReader(reader, failingPath: 'books.json');

      final result =
          await CloudflarePublicationVerifier(
            reader: throwing,
            sleep: (_) async {},
          ).verify(
            target: target,
            manifest: manifest,
            revision: 1,
            markerBytes: files['pitak-publish.json']!.bytes,
            budget: oneRound,
          );

      expect(result, CloudflarePublicationVerification.unreachable);
      expect(throwing.paths, hasLength(7), reason: 'every path was read');
    });

    test('a single-read verifier (the one-by-one order) reads one at a '
        'time', () async {
      final held = _HeldReader(reader);
      final verification =
          CloudflarePublicationVerifier(
            reader: held,
            sleep: (_) async {},
            maxConcurrentReads: 0, // below 1 counts as 1
          ).verify(
            target: target,
            manifest: manifest,
            revision: 1,
            budget: oneRound,
          );

      await pumpEventQueue();
      expect(held.started, hasLength(1));
      while (held.waiting.isNotEmpty) {
        held.releaseFirst();
        await pumpEventQueue();
      }
      expect(await verification, CloudflarePublicationVerification.verified);
      expect(held.maxInFlight, 1);
    });
  });

  group(
    'side-by-side reads decide exactly like one-by-one reads (plan SP2)',
    () {
      // A seeded matrix: every path of the set gets a script of answers over
      // the rounds (always right, always wrong, never readable, a 404, right
      // only from round 2, wrong then unreadable, unreadable then right), and
      // answers arrive in a scrambled order. The outcome, the round count and
      // the reads of every round must match the one-at-a-time verifier.
      const scripts = _Script.values;
      final availability = s8File(
        'availability.json',
        utf8.encode('{"schemaVersion":1,"asOf":0,"out":[]}'),
      );
      final paths = <String>[
        'pitak-publish.json',
        'books.json',
        '',
        'library.json',
        'events',
        'events.json',
        'posters/a.jpg',
        'posters/old.jpg',
        'availability.json',
      ];
      final rightBodies = <String, List<int>>{
        for (final entry in files.entries)
          if (entry.key != 'covers/1.jpg')
            (CloudflareHtmlRouting.servedPath(entry.key) ?? entry.key):
                entry.value.bytes,
        'availability.json': availability.bytes,
      };

      for (final scope in CloudflareReadBackScope.values) {
        test('scope ${scope.name}: 300 seeded cases', () async {
          final random = Random(20261102 + scope.index);
          for (var i = 0; i < 300; i++) {
            final plan = {
              for (final path in paths)
                path: scripts[random.nextInt(scripts.length)],
            };
            final writesAvailability = random.nextBool();
            final rounds = 1 + random.nextInt(4);
            Future<(CloudflarePublicationVerification, int?, String)> run(
              int concurrency,
            ) async {
              final scripted = _ScriptedReader(
                plan: plan,
                rightBodies: rightBodies,
                scrambleSeed: i,
              );
              int? roundsRun;
              final outcome =
                  await CloudflarePublicationVerifier(
                    reader: scripted,
                    sleep: (_) async {},
                    maxConcurrentReads: concurrency,
                  ).verify(
                    target: target,
                    manifest: s8Manifest(
                      target: target,
                      publishId: cloudflareTestPublishId,
                      additional: {
                        ...additional,
                        if (writesAvailability)
                          'availability.json': availability,
                      },
                    ),
                    revision: 7,
                    markerBytes: files['pitak-publish.json']!.bytes,
                    deletedPaths: [
                      'posters/old.jpg',
                      if (!writesAvailability) 'availability.json',
                    ],
                    scope: scope,
                    budget: CloudflareReadBackBudget(
                      rounds: rounds,
                      interval: const Duration(seconds: 5),
                      deadline: const Duration(minutes: 5),
                    ),
                    onRounds: (value) => roundsRun = value,
                  );
              return (outcome, roundsRun, scripted.readsByRound());
            }

            final oneByOne = await run(1);
            final sideBySide = await run(4);
            expect(
              sideBySide,
              oneByOne,
              reason:
                  'case $i: $plan, availability written: '
                  '$writesAvailability, rounds: $rounds',
            );
          }
        });
      }
    },
  );

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

/// Holds every read until the test releases it, and records the order reads
/// start in and how many are in flight (plan SP2).
final class _HeldReader implements PublishedSiteReadVerifier {
  _HeldReader(this._inner);

  final PublishedSiteReadVerifier _inner;
  final List<String> started = [];
  final List<Completer<void>> waiting = [];
  int inFlight = 0;
  int maxInFlight = 0;

  /// Lets the oldest held read answer.
  void releaseFirst() => waiting.removeAt(0).complete();

  @override
  Future<PublishedSiteReadOutcome> readOutcome({
    required String siteUrl,
    required String path,
    required int maxBytes,
    String? cacheBuster,
  }) async {
    started.add(path);
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    final gate = Completer<void>();
    waiting.add(gate);
    await gate.future;
    inFlight--;
    return _inner.readOutcome(
      siteUrl: siteUrl,
      path: path,
      maxBytes: maxBytes,
      cacheBuster: cacheBuster,
    );
  }
}

/// A read that takes time on the test's fake clock: [onStart] runs when the
/// read starts, [takes] before it answers.
final class _SlowReader implements PublishedSiteReadVerifier {
  _SlowReader(this._inner, {required this.onStart, required this.takes});

  final PublishedSiteReadVerifier _inner;
  final void Function() onStart;
  final Future<void> Function() takes;

  @override
  Future<PublishedSiteReadOutcome> readOutcome({
    required String siteUrl,
    required String path,
    required int maxBytes,
    String? cacheBuster,
  }) async {
    onStart();
    await takes();
    return _inner.readOutcome(
      siteUrl: siteUrl,
      path: path,
      maxBytes: maxBytes,
      cacheBuster: cacheBuster,
    );
  }
}

/// What one path answers, round by round, in the SP2 comparison matrix.
enum _Script {
  right,
  wrong,
  unreadable,
  absent,
  rightFromRoundTwo,
  wrongThenUnreadable,
  unreadableThenRight,
}

/// Answers each path by its [_Script] for the round named in the cache
/// buster (`<revision>-<round>`), after a scrambled number of event-loop
/// turns, so side-by-side reads answer in a different order than they
/// started.
final class _ScriptedReader implements PublishedSiteReadVerifier {
  _ScriptedReader({
    required this.plan,
    required this.rightBodies,
    required this.scrambleSeed,
  });

  final Map<String, _Script> plan;
  final Map<String, List<int>> rightBodies;
  final int scrambleSeed;
  final Map<int, List<String>> _reads = {};

  /// Every round's reads, as one comparable line (paths sorted per round).
  String readsByRound() {
    final rounds = _reads.keys.toList()..sort();
    return [
      for (final round in rounds)
        '$round:${(_reads[round]!..sort()).join(',')}',
    ].join(' | ');
  }

  @override
  Future<PublishedSiteReadOutcome> readOutcome({
    required String siteUrl,
    required String path,
    required int maxBytes,
    String? cacheBuster,
  }) async {
    final round = int.parse(cacheBuster!.split('-').last);
    _reads.putIfAbsent(round, () => []).add(path);
    final hops = (path.length * 7 + round * 3 + scrambleSeed) % 5;
    for (var i = 0; i < hops; i++) {
      await Future<void>.value();
    }
    final right = rightBodies[path];
    final rightAnswer = right == null
        ? const PublishedSiteReadAbsent()
        : PublishedSiteReadBody(right) as PublishedSiteReadOutcome;
    final wrongAnswer = PublishedSiteReadBody(utf8.encode('wrong $path'));
    const unreadable = PublishedSiteReadUnreadable();
    return switch (plan[path]!) {
      _Script.right => rightAnswer,
      _Script.wrong => wrongAnswer,
      _Script.unreadable => unreadable,
      _Script.absent => const PublishedSiteReadAbsent(),
      _Script.rightFromRoundTwo => round == 1 ? wrongAnswer : rightAnswer,
      _Script.wrongThenUnreadable => round == 1 ? wrongAnswer : unreadable,
      _Script.unreadableThenRight => round == 1 ? unreadable : rightAnswer,
    };
  }
}

/// Throws (like a transport bug) for [failingPath]; answers every other path
/// from the inner reader. Records every path asked for.
final class _ThrowingReader implements PublishedSiteReadVerifier {
  _ThrowingReader(this._inner, {required this.failingPath});

  final PublishedSiteReadVerifier _inner;
  final String failingPath;
  final List<String> paths = [];

  @override
  Future<PublishedSiteReadOutcome> readOutcome({
    required String siteUrl,
    required String path,
    required int maxBytes,
    String? cacheBuster,
  }) async {
    paths.add(path);
    await Future<void>.value();
    if (path == failingPath) {
      throw const FormatException('synthetic transport failure');
    }
    return _inner.readOutcome(
      siteUrl: siteUrl,
      path: path,
      maxBytes: maxBytes,
      cacheBuster: cacheBuster,
    );
  }
}
