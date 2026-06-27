import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/events/application/events_controller.dart';
import 'package:pitaka/features/events/domain/entities/event_poster.dart';
import 'package:pitaka/features/events/domain/repositories/events_repository.dart';

/// In-memory events repo. Each saved poster image gets a deterministic ref so
/// tests can assert on it; a bad image is simulated by [failNextImage].
class _FakeEventsRepo implements EventsRepository {
  EventsContent _content = EventsContent.empty;
  int _seq = 0;
  bool failNextImage = false;

  @override
  Future<EventsContent> load() async => _content;

  @override
  Future<Either<Failure, EventsContent>> save(EventsContent content) async {
    _content = content;
    return right(content);
  }

  @override
  Future<Either<Failure, String>> savePosterImage(Uint8List bytes) async {
    if (failNextImage) {
      return left(const ValidationFailure('bad image'));
    }
    return right('posters/img${_seq++}.jpg');
  }
}

ProviderContainer _containerWith(_FakeEventsRepo repo) {
  final c = ProviderContainer(
    overrides: [eventsRepositoryProvider.overrideWith((ref) async => repo)],
  );
  addTearDown(c.dispose);
  return c;
}

final _bytes = Uint8List.fromList([1, 2, 3]);

void main() {
  test('starts empty', () async {
    final c = _containerWith(_FakeEventsRepo());
    final content = await c.read(eventsControllerProvider.future);
    expect(content.posters, isEmpty);
  });

  test('addPoster appends up to two, then refuses the third', () async {
    final c = _containerWith(_FakeEventsRepo());
    final n = c.read(eventsControllerProvider.notifier);
    await c.read(eventsControllerProvider.future);

    expect(await n.addPoster(_bytes, description: 'one'), isTrue);
    expect(await n.addPoster(_bytes), isTrue);
    // Cap reached.
    expect(await n.addPoster(_bytes), isFalse);

    final content = c.read(eventsControllerProvider).value!;
    expect(content.posters, hasLength(2));
    expect(content.posters[0].description, 'one');
    expect(content.isFull, isTrue);
  });

  test('addPoster surfaces failure when the image cannot be saved', () async {
    final repo = _FakeEventsRepo()..failNextImage = true;
    final c = _containerWith(repo);
    final n = c.read(eventsControllerProvider.notifier);
    await c.read(eventsControllerProvider.future);

    expect(await n.addPoster(_bytes), isFalse);
    expect(c.read(eventsControllerProvider).value!.posters, isEmpty);
  });

  test('setDescription updates the caption of an existing poster', () async {
    final c = _containerWith(_FakeEventsRepo());
    final n = c.read(eventsControllerProvider.notifier);
    await c.read(eventsControllerProvider.future);
    await n.addPoster(_bytes);

    expect(await n.setDescription(0, '  New caption  '), isTrue);
    expect(
      c.read(eventsControllerProvider).value!.posters[0].description,
      'New caption',
    );
    // Out-of-range index is rejected.
    expect(await n.setDescription(9, 'x'), isFalse);
  });

  test('setDescription rejects an over-long caption', () async {
    final c = _containerWith(_FakeEventsRepo());
    final n = c.read(eventsControllerProvider.notifier);
    await c.read(eventsControllerProvider.future);
    await n.addPoster(_bytes);

    final tooLong = 'x' * (EventPoster.maxDescriptionLength + 1);
    expect(await n.setDescription(0, tooLong), isFalse);
  });

  test('removePoster removes by index', () async {
    final c = _containerWith(_FakeEventsRepo());
    final n = c.read(eventsControllerProvider.notifier);
    await c.read(eventsControllerProvider.future);
    await n.addPoster(_bytes, description: 'first');
    await n.addPoster(_bytes, description: 'second');

    expect(await n.removePoster(0), isTrue);
    final content = c.read(eventsControllerProvider).value!;
    expect(content.posters, hasLength(1));
    expect(content.posters[0].description, 'second');
  });
}
