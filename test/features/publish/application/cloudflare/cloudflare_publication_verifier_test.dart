import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_publication_verifier.dart';
import 'package:pitaka/features/publish/domain/site/publish_file.dart';
import 'package:pitaka/features/publish/domain/site/published_site_verifier.dart';

import '../../support/cloudflare_fakes.dart';
import '../../support/cloudflare_s8_fakes.dart';

void main() {
  final target = cloudflareTestConnection().status.target!;
  final reader = FakeStructuredReader();

  CloudflarePublicationVerifier verifier({int attempts = 1}) =>
      CloudflarePublicationVerifier(
        reader: reader,
        sleep: (_) async {},
        attempts: attempts,
        interval: Duration.zero,
      );

  final additional = <String, PublishFile>{
    'library.json': s8File('library.json', utf8.encode('{"schema":1}')),
    'events.html': s8File('events.html', utf8.encode('<html>1</html>')),
    'events.json': s8File('events.json', utf8.encode('{"posters":[1]}')),
    'posters/a.jpg': s8File('posters/a.jpg', [1, 2, 3]),
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

  test('verifies marker, catalogue, descriptor, events, posters, and removed '
      'poster 404 at one exact origin', () async {
    final result = await verifier().verify(
      target: target,
      manifest: manifest,
      revision: 1,
      markerBytes: files['pitak-publish.json']!.bytes,
      deletedPaths: const ['posters/old.jpg'],
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
  });

  test('a wrong current poster body is not a verified deployment', () async {
    reader.body('posters/a.jpg', [9, 9, 9]);

    final result = await verifier().verify(
      target: target,
      manifest: manifest,
      revision: 1,
    );

    expect(result, CloudflarePublicationVerification.notVerified);
  });

  test(
    'an unreadable descriptor is not accepted as its required 404',
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
      );

      expect(result, CloudflarePublicationVerification.notVerified);
    },
  );

  test(
    'a later propagation round can finish the grouped verification',
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

      final result = await CloudflarePublicationVerifier(
        reader: propagating,
        sleep: (_) async {},
        attempts: 2,
        interval: Duration.zero,
      ).verify(target: target, manifest: manifest, revision: 1);

      expect(result, CloudflarePublicationVerification.verified);
      expect(reads, 2);
    },
  );
}

final class _PropagatingReader implements PublishedSiteReadVerifier {
  _PropagatingReader(this._inner, {required this.onBooks});

  final FakeStructuredReader _inner;
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
