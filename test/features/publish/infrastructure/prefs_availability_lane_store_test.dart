import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/availability/availability_lane_state.dart';
import 'package:pitaka/features/publish/domain/availability/availability_snapshot.dart';
import 'package:pitaka/features/publish/infrastructure/prefs_availability_lane_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../support/key_set_fixtures.dart';

/// The lane store over SharedPreferences (ADR 0019 Decision 9, plan C.4).
///
/// The property under test: "nothing stored" and "stored but damaged" are
/// different answers, and a damaged value never becomes an empty list.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const key = PrefsAvailabilityLaneStore.key;
  final pending = AvailabilitySnapshot.tryCreate(
    keySet: testKeySetId,
    keys: const ['00000000000000aa', '0000000000000001'],
    asOfMillis: 120000,
  )!;

  Future<PrefsAvailabilityLaneStore> storeWith(Map<String, Object> values) {
    SharedPreferences.setMockInitialValues(values);
    return SharedPreferences.getInstance().then(PrefsAvailabilityLaneStore.new);
  }

  test('nothing stored reads as absent', () async {
    final store = await storeWith({});
    expect(await store.read(), isA<AvailabilityLaneAbsent>());
  });

  test('a written state reads back exactly, under one key', () async {
    final store = await storeWith({});
    final written = await store.write(
      AvailabilityLaneState(
        pending: pending,
        gitHubCommitTimes: const [5, 9],
        noticeShown: true,
      ),
    );
    expect(written.isRight(), isTrue);

    final read = await store.read() as AvailabilityLaneLoaded;
    expect(read.state.pending!.keys, ['0000000000000001', '00000000000000aa']);
    expect(read.state.gitHubCommitTimes, [5, 9]);
    expect(read.state.noticeShown, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), {key});
  });

  group('damage is unreadable, never absent and never empty', () {
    test('malformed JSON', () async {
      final store = await storeWith({key: '{not json'});
      expect(await store.read(), isA<AvailabilityLaneUnreadable>());
    });

    test('a value of another type under the key', () async {
      final store = await storeWith({key: 42});
      expect(await store.read(), isA<AvailabilityLaneUnreadable>());
    });

    test('a newer version', () async {
      final json = AvailabilityLaneState().toJson()..['version'] = 2;
      final store = await storeWith({key: jsonEncode(json)});
      expect(await store.read(), isA<AvailabilityLaneUnreadable>());
    });

    test('a pending set with a bad key is not read as "nothing out"', () async {
      final json = AvailabilityLaneState(pending: pending).toJson();
      (json['pending']! as Map)['out'] = ['NOT-A-KEY'];
      final store = await storeWith({key: jsonEncode(json)});
      expect(await store.read(), isA<AvailabilityLaneUnreadable>());
    });

    test('a value larger than any this build writes', () async {
      final huge = 'x' * (PrefsAvailabilityLaneStore.maxRecordLength + 1);
      final store = await storeWith({key: huge});
      expect(await store.read(), isA<AvailabilityLaneUnreadable>());
    });
  });

  test('holds public data only: keys, a hash, times and a flag', () async {
    final store = await storeWith({});
    await store.write(
      AvailabilityLaneState(
        pending: pending,
        published: AvailabilityPublished(
          targetId: 'github:me/lib',
          siteUrl: 'https://me.github.io/lib/',
          contentHash: pending.contentHash,
          asOf: 120000,
          publishedAt: 130000,
        ),
      ),
    );
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key)!;
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    expect(decoded.keys.toSet(), {
      'version',
      'pending',
      'published',
      'gitHubCommitTimes',
      'noticeShown',
    });
    expect(raw, isNot(contains('token')));
    expect(raw, isNot(contains('borrower')));
  });
}
