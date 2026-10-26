import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/events_posters_html.dart';
import 'package:pitaka/features/publish/infrastructure/events_json_builder.dart';

void main() {
  test('emits the versioned public poster refs and optional captions', () {
    final bytes = const EventsJsonBuilder().build(const [
      PublishPoster(imagePath: 'posters/a.jpg', description: 'Story hour'),
      PublishPoster(imagePath: 'posters/b.jpg'),
    ]);

    expect(jsonDecode(utf8.decode(bytes)), {
      'schemaVersion': 1,
      'posters': [
        {'imageRef': 'posters/a.jpg', 'description': 'Story hour'},
        {'imageRef': 'posters/b.jpg'},
      ],
    });
  });

  test('an empty public list is explicit, not a missing posters key', () {
    final bytes = const EventsJsonBuilder().build(const []);

    expect(jsonDecode(utf8.decode(bytes)), {
      'schemaVersion': 1,
      'posters': <Object?>[],
    });
  });
}
