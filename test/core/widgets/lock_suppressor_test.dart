import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/widgets/lock_suppressor.dart';

void main() {
  test('not suppressed by default (fail closed)', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(lockSuppressorProvider), isFalse);
  });

  test('suppressed while a guarded action is in flight', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(lockSuppressorProvider.notifier);

    final started = Completer<void>();
    final release = Completer<void>();
    final fut = n.guard(() async {
      started.complete();
      await release.future;
    });
    await started.future;
    expect(n.isSuppressed, isTrue); // on during the action

    release.complete();
    await fut;
    // Still suppressed immediately after (grace window keeps it on).
    expect(n.isSuppressed, isTrue);
  });

  test('clears after the grace window', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(lockSuppressorProvider.notifier);

    await n.guard(() async {});
    expect(n.isSuppressed, isTrue); // within grace

    // Grace is 2s; wait past it and confirm it fails closed.
    await Future<void>.delayed(const Duration(milliseconds: 2200));
    expect(n.isSuppressed, isFalse);
  });

  test('overlapping guards keep suppression until the last finishes', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(lockSuppressorProvider.notifier);

    final r1 = Completer<void>();
    final r2 = Completer<void>();
    final f1 = n.guard(() => r1.future);
    final f2 = n.guard(() => r2.future);
    expect(n.isSuppressed, isTrue);

    r1.complete();
    await f1;
    expect(n.isSuppressed, isTrue); // second still running

    r2.complete();
    await f2;
    expect(n.isSuppressed, isTrue); // grace window after the last
  });
}
