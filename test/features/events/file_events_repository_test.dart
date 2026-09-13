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
  // Async since N10-a: the real downscale runs in a worker isolate.
  Future<Uint8List?> fakeDownscale(List<int> bytes) async {
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

  test('save is atomic: no temp left behind, previous content survives a '
      'failed write', () async {
    final r = repo();
    final poster = EventPoster.create(
      imageRef: 'posters/a.jpg',
      description: 'keep me',
    )!;
    expect((await r.save(EventsContent.empty.add(poster)!)).isRight(), isTrue);
    expect(
      tmp.listSync().map((e) => e.path.split('/').last),
      isNot(contains('events.json.tmp')),
    );
    // Make the temp path unwritable (a directory sits where the temp file
    // goes) so the next save fails BEFORE any rename — the live file must be
    // untouched (review 2026-09-03: an in-place write used to truncate it).
    Directory('${tmp.path}/events.json.tmp').createSync();
    final failed = await r.save(EventsContent.empty);
    expect(failed.isLeft(), isTrue);
    expect((await r.load()).posters.single.description, 'keep me');
  });

  test('deletePosterImage removes only files inside posters/', () async {
    final r = repo();
    final ref = (await r.savePosterImage(
      Uint8List.fromList([1, 2, 3]),
    )).getOrElse((f) => fail('save failed: $f'));
    final file = File('${tmp.path}/$ref');
    expect(file.existsSync(), isTrue);

    await r.deletePosterImage(ref);
    expect(file.existsSync(), isFalse);

    // Hostile / foreign references are ignored, never IO outside posters/.
    File('${tmp.path}/events.json').writeAsStringSync('{}');
    await r.deletePosterImage('posters/../events.json');
    await r.deletePosterImage('events.json');
    await r.deletePosterImage('');
    expect(File('${tmp.path}/events.json').existsSync(), isTrue);
    // Deleting a missing file is a quiet no-op.
    await r.deletePosterImage(ref);
  });

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
