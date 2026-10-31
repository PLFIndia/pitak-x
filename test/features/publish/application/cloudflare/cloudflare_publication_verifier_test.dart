import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_publication_verifier.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_limits.dart';
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
