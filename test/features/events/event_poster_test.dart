import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/events/domain/entities/event_poster.dart';

void main() {
  group('EventPoster.create', () {
    test('trims the description and accepts an image ref', () {
      final p = EventPoster.create(
        imageRef: '  posters/a.jpg  ',
        description: '  Story hour  ',
      );
      expect(p, isNotNull);
      expect(p!.imageRef, 'posters/a.jpg');
      expect(p.description, 'Story hour');
    });

    test('rejects a blank image ref', () {
      expect(EventPoster.create(imageRef: '   '), isNull);
    });

    test('rejects a description over the length cap', () {
      final tooLong = 'x' * (EventPoster.maxDescriptionLength + 1);
      expect(
        EventPoster.create(imageRef: 'posters/a.jpg', description: tooLong),
        isNull,
      );
    });

    test('accepts a description exactly at the cap', () {
      final atCap = 'x' * EventPoster.maxDescriptionLength;
      expect(
        EventPoster.create(imageRef: 'posters/a.jpg', description: atCap),
        isNotNull,
      );
    });
  });

  group('EventPoster JSON', () {
    test('omits an empty description, round-trips a set one', () {
      final withDesc = EventPoster.create(
        imageRef: 'posters/a.jpg',
        description: 'Hi',
      )!;
      expect(withDesc.toJson(), {
        'imageRef': 'posters/a.jpg',
        'description': 'Hi',
      });

      final noDesc = EventPoster.create(imageRef: 'posters/b.jpg')!;
      expect(noDesc.toJson(), {'imageRef': 'posters/b.jpg'});

      expect(EventPoster.fromJson(withDesc.toJson())!.description, 'Hi');
      expect(EventPoster.fromJson(noDesc.toJson())!.description, '');
    });

    test('fromJson rejects malformed shapes', () {
      expect(EventPoster.fromJson(null), isNull);
      expect(EventPoster.fromJson('nope'), isNull);
      expect(EventPoster.fromJson({'description': 'no ref'}), isNull);
    });
  });

  group('EventsContent', () {
    final a = EventPoster.create(imageRef: 'posters/a.jpg')!;
    final b = EventPoster.create(imageRef: 'posters/b.jpg')!;
    final c = EventPoster.create(imageRef: 'posters/c.jpg')!;

    test('add appends until the cap, then refuses', () {
      final one = EventsContent.empty.add(a);
      expect(one!.posters, hasLength(1));
      final two = one.add(b);
      expect(two!.posters, hasLength(2));
      expect(two.isFull, isTrue);
      expect(two.add(c), isNull); // over the cap of 2
    });

    test('removeAt removes the right poster; out-of-range is a no-op', () {
      final two = EventsContent(posters: [a, b]);
      expect(two.removeAt(0).posters, [b]);
      expect(two.removeAt(5).posters, [a, b]);
    });

    test('replaceAt swaps a poster; out-of-range returns null', () {
      final two = EventsContent(posters: [a, b]);
      final swapped = two.replaceAt(1, c);
      expect(swapped!.posters, [a, c]);
      expect(two.replaceAt(9, c), isNull);
    });

    test('fromJson drops malformed entries and enforces the cap', () {
      final json = {
        'schemaVersion': 1,
        'posters': [
          {'imageRef': 'posters/a.jpg'},
          {'no': 'ref'}, // dropped
          {'imageRef': 'posters/b.jpg', 'description': 'two'},
          {'imageRef': 'posters/c.jpg'}, // beyond cap of 2 → dropped
        ],
      };
      final content = EventsContent.fromJson(json);
      expect(content.posters, hasLength(2));
      expect(content.posters[0].imageRef, 'posters/a.jpg');
      expect(content.posters[1].description, 'two');
    });

    test('fromJson tolerates non-map / missing posters', () {
      expect(EventsContent.fromJson(null).posters, isEmpty);
      expect(EventsContent.fromJson('x').posters, isEmpty);
      expect(EventsContent.fromJson(const {}).posters, isEmpty);
    });
  });
}
