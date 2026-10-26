import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/events/domain/entities/event_poster.dart';
import 'package:pitaka/features/publish/application/site/events_section_builder.dart';
import 'package:pitaka/features/publish/domain/events_posters_html.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';
import 'package:pitaka/features/publish/domain/site/publish_mode.dart';

/// R2/R3/R7: the events section is built once, from ONE filtered poster list,
/// and a complete publish fails closed instead of dropping a poster.
void main() {
  EventsContent content({int posters = 2}) => EventsContent(
    posters: [
      for (var i = 0; i < posters; i++)
        EventPoster(imageRef: 'posters/$i.jpg', description: 'Event $i'),
    ],
  );

  EventsSectionBuilder builder({
    Set<String> readable = const {'posters/0.jpg', 'posters/1.jpg'},
  }) => EventsSectionBuilder(
    readPoster: (ref) async =>
        readable.contains(ref) ? utf8.encode('img:$ref') : null,
    buildEventsHtml: (posters) async =>
        utf8.encode(EventsPostersHtml.render(posters, escape: (s) => s)),
    buildEventsJson: (posters) => utf8.encode(
      jsonEncode([
        for (final p in posters)
          {'image': p.imagePath, 'description': p.description},
      ]),
    ),
  );

  test('html, json and uploads come from the SAME poster list', () async {
    final section = (await builder().build(
      content: content(),
      previous: PublishManifest.empty,
    )).toNullable()!;

    expect(section.paths, [
      'events.html',
      'events.json',
      'posters/0.jpg',
      'posters/1.jpg',
    ]);
    final json =
        jsonDecode(
              utf8.decode(
                section.files.firstWhere((f) => f.path == 'events.json').bytes,
              ),
            )
            as List;
    expect(json, hasLength(2));
    final html = utf8.decode(
      section.files.firstWhere((f) => f.path == 'events.html').bytes,
    );
    expect(html, contains('posters/0.jpg'));
    expect(html, contains('posters/1.jpg'));
  });

  test(
    'INCREMENTAL: an unreadable poster is dropped from every form',
    () async {
      final section = (await builder(readable: const {'posters/0.jpg'}).build(
        content: content(),
        previous: PublishManifest.empty,
      )).toNullable()!;

      expect(section.paths, ['events.html', 'events.json', 'posters/0.jpg']);
      final json =
          jsonDecode(
                utf8.decode(
                  section.files
                      .firstWhere((f) => f.path == 'events.json')
                      .bytes,
                ),
              )
              as List;
      expect(json, hasLength(1));
    },
  );

  test(
    'COMPLETE: the same unreadable poster refuses the section (R2)',
    () async {
      final result = await builder(readable: const {'posters/0.jpg'}).build(
        content: content(),
        previous: PublishManifest.empty,
        mode: PublishMode.complete,
      );

      expect(result.swap().toNullable(), isA<ValidationFailure>());
      expect(
        (result.swap().toNullable()! as ValidationFailure).message,
        EventsSectionBuilder.missingPosterMessage,
      );
    },
  );

  test('posters the previous publication owned but this run dropped are '
      'deleted (M14), and only poster paths are candidates', () async {
    const previous = PublishManifest(
      repo: 'me/lib',
      fileShas: {
        'posters/0.jpg': 'a',
        'posters/old.jpg': 'b',
        'books.json': 'keep',
      },
    );

    final section = (await builder().build(
      content: content(posters: 1),
      previous: previous,
    )).toNullable()!;

    expect(section.deletePaths, ['posters/old.jpg']);
  });
}
