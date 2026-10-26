import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/domain/entities/published_events.dart';
import 'package:pitaka/features/network/domain/usecases/load_published_events_use_case.dart';

void main() {
  const site = 'https://kadugodi.github.io/pitak/';

  test(
    'resolves the independent events.json sibling before fetching',
    () async {
      final calls = <String>[];
      final useCase = LoadPublishedEventsUseCase(
        fetch: (url, {abortTrigger}) async {
          calls.add(url);
          return const Right(null);
        },
      );
      final result = await useCase(site);
      expect(result.isRight(), isTrue);
      expect(calls, ['https://kadugodi.github.io/pitak/events.json']);
    },
  );

  test('a non-canonical saved URL fails before any request', () async {
    var calls = 0;
    final useCase = LoadPublishedEventsUseCase(
      fetch: (url, {abortTrigger}) async {
        calls++;
        return Right(
          PublishedEvents(declaredSchemaVersion: 1, posters: const []),
        );
      },
    );
    for (final raw in ['http://kadugodi.github.io/pitak/', 'not a url']) {
      final result = await useCase(raw);
      expect(result.isLeft(), isTrue);
      expect(result.swap().toNullable(), isA<ValidationFailure>());
    }
    expect(calls, 0);
  });
}
