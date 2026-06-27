import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/events/domain/entities/event_poster.dart';
import 'package:pitaka/features/events/infrastructure/file_events_repository.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('events_test');
  });
  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  // A downscale stub: echoes the bytes (pretending they decoded) unless they
  // are the sentinel "BAD", simulating an undecodable image (returns null).
  Uint8List? fakeDownscale(List<int> bytes) {
    if (bytes.length == 3 &&
        bytes[0] == 0x42 &&
        bytes[1] == 0x41 &&
        bytes[2] == 0x44) {
      return null; // "BAD"
    }
    return Uint8List.fromList(bytes);
  }

  FileEventsRepository repo() =>
      FileEventsRepository(baseDir: tmp.path, downscale: fakeDownscale);

  test('load returns empty when nothing saved', () async {
    expect((await repo().load()).posters, isEmpty);
  });

  test('save then load round-trips content', () async {
    final r = repo();
    final content = EventsContent(
      posters: [
        EventPoster.create(imageRef: 'posters/a.jpg', description: 'Hi')!,
        EventPoster.create(imageRef: 'posters/b.jpg')!,
      ],
    );
    final saved = await r.save(content);
    expect(saved.isRight(), isTrue);

    // Persisted to disk as events.json.
    expect(File('${tmp.path}/events.json').existsSync(), isTrue);

    // A fresh repo reads it back.
    final reloaded = await repo().load();
    expect(reloaded.posters, hasLength(2));
    expect(reloaded.posters[0].description, 'Hi');
    expect(reloaded.posters[1].imageRef, 'posters/b.jpg');
  });

  test(
    'savePosterImage writes a posters/<uuid>.jpg and returns its ref',
    () async {
      final r = repo();
      final result = await r.savePosterImage(Uint8List.fromList([1, 2, 3, 4]));
      final ref = result.getOrElse((_) => '');
      expect(ref, startsWith('posters/'));
      expect(ref, endsWith('.jpg'));
      // The file exists on disk under baseDir.
      expect(File('${tmp.path}/$ref').existsSync(), isTrue);
    },
  );

  test(
    'savePosterImage returns a ValidationFailure for an undecodable image',
    () async {
      final result = await repo().savePosterImage(
        Uint8List.fromList([0x42, 0x41, 0x44]), // "BAD"
      );
      expect(result.isLeft(), isTrue);
      result.match(
        (f) => expect(f, isA<ValidationFailure>()),
        (_) => fail('expected a failure'),
      );
      // No poster file leaked into the dir.
      final postersDir = Directory('${tmp.path}/posters');
      expect(
        postersDir.existsSync() ? postersDir.listSync() : const <Object>[],
        isEmpty,
      );
    },
  );

  test('a corrupt events.json degrades to empty, never throws', () async {
    File('${tmp.path}/events.json').writeAsStringSync('{ not json');
    expect((await repo().load()).posters, isEmpty);
  });
}
