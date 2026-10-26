import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/network/domain/entities/published_events.dart';
import 'package:pitaka/features/network/infrastructure/published_events_codec.dart';
import 'package:pitaka/features/publish/domain/events_posters_html.dart';
import 'package:pitaka/features/publish/infrastructure/events_json_builder.dart';

void main() {
  const codec = PublishedEventsCodec();

  List<int> encode(Object? json) => utf8.encode(jsonEncode(json));

  Map<String, Object> payload({int version = 1, List<Object?>? posters}) => {
    'schemaVersion': version,
    'posters':
        posters ??
        [
          {'imageRef': 'posters/a.jpg', 'description': ' Story hour '},
          {'imageRef': 'posters/b.jpg'},
        ],
  };

  test('decodes ordered posters, captions and forward-version metadata', () {
    final result = codec.decode(encode(payload(version: 2)));
    expect(result.isRight(), isTrue);
    final events = result.toNullable()!;
    expect(events.declaredSchemaVersion, 2);
    expect(events.hasNewerSchema, isTrue);
    expect(events.hasPartialRead, isFalse);
    expect(events.posters, hasLength(2));
    expect(events.posters[0].imageRef, 'posters/a.jpg');
    expect(events.posters[0].description, 'Story hour');
    expect(events.posters[1].description, isEmpty);
    expect(() => events.posters.add(events.posters[0]), throwsUnsupportedError);
  });

  test('an explicit empty poster list is a valid empty snapshot', () {
    final result = codec.decode(encode(payload(posters: [])));
    expect(result.isRight(), isTrue);
    expect(result.toNullable()!.posters, isEmpty);
    expect(result.toNullable()!.hasPartialRead, isFalse);
  });

  test('writer output is directly readable by the native viewer', () {
    final bytes = const EventsJsonBuilder().build(const [
      PublishPoster(imagePath: 'posters/a.jpg', description: 'Story'),
      PublishPoster(imagePath: 'posters/b.jpg'),
    ]);
    final events = codec.decode(bytes).toNullable()!;
    expect(events.declaredSchemaVersion, PublishedEvents.schemaVersion);
    expect(events.posters.map((p) => p.imageRef), [
      'posters/a.jpg',
      'posters/b.jpg',
    ]);
    expect(events.posters.map((p) => p.description), ['Story', '']);
  });

  test('extra and malformed posters are bounded with a visible warning', () {
    final result = codec.decode(
      encode(
        payload(
          posters: [
            {'imageRef': 'posters/a.jpg'},
            {'imageRef': '../secret.jpg'},
            {'imageRef': 'posters/c.jpg'},
          ],
        ),
      ),
    );
    final events = result.toNullable()!;
    expect(events.posters.map((p) => p.imageRef), [
      'posters/a.jpg',
      'posters/c.jpg',
    ]);
    expect(events.hasPartialRead, isTrue);
  });

  test('an over-cap or wrong-typed caption is omitted with a warning', () {
    for (final description in ['x' * 281, 42]) {
      final events = codec
          .decode(
            encode(
              payload(
                posters: [
                  {'imageRef': 'posters/a.jpg', 'description': description},
                ],
              ),
            ),
          )
          .toNullable()!;
      expect(events.posters.single.imageRef, 'posters/a.jpg');
      expect(events.posters.single.description, isEmpty);
      expect(events.hasPartialRead, isTrue);
    }
  });

  test('unsafe poster references never reach the view model', () {
    for (final ref in [
      'https://evil.example/a.jpg',
      'covers/a.jpg',
      'posters/../a.jpg',
      'posters/a/b.jpg',
      r'posters/a\b.jpg',
      'posters/a.jpg?x=1',
      'posters/a.jpg#fragment',
      'posters/a%2fb.jpg',
      'posters/%FF.jpg',
      'posters/%C0%AF.jpg',
      'posters/${'x' * 513}.jpg',
    ]) {
      final events = codec
          .decode(
            encode(
              payload(
                posters: [
                  {'imageRef': ref},
                ],
              ),
            ),
          )
          .toNullable()!;
      expect(events.posters, isEmpty, reason: ref);
      expect(events.hasPartialRead, isTrue, reason: ref);
    }
  });

  test('malformed documents fail rather than looking like no events', () {
    final invalidBodies = <List<int>>[
      utf8.encode('{not json'),
      encode(<Object?>[]),
      encode({'schemaVersion': 1}),
      encode({'schemaVersion': 0, 'posters': <Object?>[]}),
      encode({'schemaVersion': 1, 'posters': <String, Object?>{}}),
    ];
    for (final body in invalidBodies) {
      expect(codec.decode(body).isLeft(), isTrue);
    }
    expect(
      const PublishedEventsCodec(
        maxBodyBytes: 8,
      ).decode(encode(payload())).isLeft(),
      isTrue,
    );
  });
}
