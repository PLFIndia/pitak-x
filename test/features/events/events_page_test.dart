import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/events/domain/entities/event_poster.dart';
import 'package:pitaka/features/events/domain/repositories/events_repository.dart';
import 'package:pitaka/features/events/presentation/pages/events_page.dart';

class _FakeEventsRepo implements EventsRepository {
  _FakeEventsRepo(this._content);
  EventsContent _content;

  @override
  Future<EventsContent> load() async => _content;
  @override
  Future<Either<Failure, EventsContent>> save(EventsContent content) async {
    _content = content;
    return right(content);
  }

  @override
  Future<Either<Failure, String>> savePosterImage(Uint8List bytes) async =>
      right('posters/x.jpg');
}

Widget _app(EventsRepository repo) => ProviderScope(
  overrides: [eventsRepositoryProvider.overrideWith((ref) async => repo)],
  child: const MaterialApp(home: EventsPage()),
);

void main() {
  testWidgets('empty state shows the intro and an Add poster button', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_FakeEventsRepo(EventsContent.empty)));
    await tester.pumpAndSettle();

    expect(find.text('No posters yet.'), findsOneWidget);
    expect(find.text('Add poster'), findsOneWidget);
    // EventsPage shows an in-body title (no AppBar) now that EventsView is
    // also embeddable as a tab.
    expect(find.text('Events'), findsOneWidget);
  });

  testWidgets('with two posters the add button is disabled at the cap', (
    tester,
  ) async {
    // Tall surface so both full-width posters + the button lay out on-screen.
    tester.view.physicalSize = const Size(600, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final content = EventsContent(
      posters: [
        EventPoster.create(imageRef: 'posters/a.jpg', description: 'Story')!,
        EventPoster.create(imageRef: 'posters/b.jpg')!,
      ],
    );
    await tester.pumpWidget(_app(_FakeEventsRepo(content)));
    await tester.pumpAndSettle();

    // Caption + its placeholder render.
    expect(find.text('Story'), findsOneWidget);
    expect(find.text('No description'), findsOneWidget);
    // The cap message replaces the add label and the button is disabled.
    expect(find.text('Maximum of two posters'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });
}
