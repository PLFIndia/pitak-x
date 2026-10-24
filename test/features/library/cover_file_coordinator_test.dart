import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/library/domain/cover_file_coordinator.dart';

import '../../support/async_value_gate.dart';

void main() {
  test(
    'FIFO releases the next operation even when the current one throws',
    () async {
      final coordinator = CoverFileCoordinator();
      final release = AsyncValueGate<void>();
      final events = <String>[];
      final first = coordinator.run<void>(() async {
        events.add('first');
        await release.wait();
        throw StateError('synthetic');
      });
      final failure = expectLater(first, throwsStateError);
      final second = coordinator.run(() async => events.add('second'));
      final third = coordinator.run(() async => events.add('third'));
      await Future<void>.delayed(Duration.zero);
      expect(events, ['first']);
      release.succeed(null);
      await failure;
      await second;
      await third;
      expect(events, ['first', 'second', 'third']);
      await coordinator.run(() async => events.add('after'));
      expect(events.last, 'after');
    },
  );
}
