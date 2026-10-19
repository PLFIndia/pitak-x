/// Unit tests for [SerialOpQueue]: FIFO serialization of vault mutations
/// with error isolation between ops.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/vault/application/serial_op_queue.dart';

void main() {
  test('two enqueued ops run strictly in order (FIFO)', () async {
    final queue = SerialOpQueue();
    final events = <String>[];
    final gate = Completer<void>();

    // Op 1 parks on the gate; op 2 must wait for it even though op 2's
    // body is trivial.
    final futures = <Future<int> Function()>[
      () async {
        events.add('start-1');
        await gate.future;
        events.add('end-1');
        return 1;
      },
      () async {
        events
          ..add('start-2')
          ..add('end-2');
        return 2;
      },
    ].map(queue.enqueue).toList();

    await Future<void>.delayed(Duration.zero);
    expect(events, ['start-1']); // op 2 has NOT started behind the gate

    gate.complete();
    expect(await futures[0], 1);
    expect(await futures[1], 2);
    expect(events, ['start-1', 'end-1', 'start-2', 'end-2']);
  });

  test('an op that throws does not block subsequent ops; the error goes to '
      'its own caller only', () async {
    final queue = SerialOpQueue();
    final order = <String>[];

    final failing = queue.enqueue<int>(() async {
      order.add('fail');
      throw StateError('boom');
    });
    final succeeding = queue.enqueue(() async {
      order.add('ok');
      return 42;
    });

    await expectLater(failing, throwsStateError);
    expect(await succeeding, 42);
    expect(order, ['fail', 'ok']);
  });

  test(
    'the queue drains back to empty (a later op starts immediately)',
    () async {
      final queue = SerialOpQueue();
      await queue.enqueue(() async {});
      // Tail cleared: this op must not wait on anything.
      final ran = await queue.enqueue(() async => true);
      expect(ran, isTrue);
    },
  );
}
