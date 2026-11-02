import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/application/availability/availability_lane_repository.dart';
import 'package:pitaka/features/publish/domain/availability/availability_lane_state.dart';
import 'package:pitaka/features/publish/domain/availability/availability_snapshot.dart';

import '../support/availability_lane_fakes.dart';
import '../support/key_set_fixtures.dart';

/// The ONE writer of the lane store (ADR 0019 Decision 9, plan S6).
void main() {
  final set = AvailabilitySnapshot.tryCreate(
    keySet: testKeySetId,
    keys: const ['0000000000000001'],
    asOfMillis: 60000,
  )!;

  test(
    'an update applies to the saved state and returns what it wrote',
    () async {
      final store = MemoryAvailabilityLaneStore(
        AvailabilityLaneState(gitHubCommitTimes: const [1]),
      );
      final repository = AvailabilityLaneRepository(store);

      final written = await repository.update((s) => s.withPending(set));

      expect(written.toNullable()!.pending!.keys, set.keys);
      expect(store.saved!.gitHubCommitTimes, [1]);
      expect(store.saved!.pending!.keys, set.keys);
    },
  );

  test('concurrent updates never drop each other (one queue)', () async {
    final store = MemoryAvailabilityLaneStore();
    final repository = AvailabilityLaneRepository(store);

    await Future.wait([
      repository.update((s) => s.withPending(set)),
      repository.recordGitHubCommit(10),
      repository.recordGitHubCommit(20),
      repository.update((s) => s.withNoticeShown()),
    ]);

    final saved = store.saved!;
    expect(saved.pending!.keys, set.keys);
    expect(saved.gitHubCommitTimes, [10, 20]);
    expect(saved.noticeShown, isTrue);
  });

  test('an unreadable store starts from EMPTY: nothing pending, nothing '
      'published — never an empty published list', () async {
    final store = MemoryAvailabilityLaneStore.raw('{"version":1}');
    final repository = AvailabilityLaneRepository(store);
    expect(await repository.read(), isA<AvailabilityLaneUnreadable>());

    await repository.recordGitHubCommit(5);

    final saved = store.saved!;
    expect(saved.pending, isNull);
    expect(saved.published, isNull);
    expect(saved.gitHubCommitTimes, [5]);
  });

  test('a failed write is a typed failure; the old value stays', () async {
    final store = MemoryAvailabilityLaneStore(AvailabilityLaneState())
      ..failWrites = true;
    final repository = AvailabilityLaneRepository(store);

    final written = await repository.update((s) => s.withPending(set));
    await repository.recordGitHubCommit(1); // best effort: no throw

    expect(written.isLeft(), isTrue);
    expect(store.saved!.pending, isNull);
    expect(store.saved!.gitHubCommitTimes, isEmpty);
  });
}
