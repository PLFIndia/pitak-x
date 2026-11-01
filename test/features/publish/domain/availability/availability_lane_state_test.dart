import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/availability/availability_lane_state.dart';
import 'package:pitaka/features/publish/domain/availability/availability_pacing.dart';
import 'package:pitaka/features/publish/domain/availability/availability_snapshot.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';

/// SPECIFICATION of what the lane store holds (ADR 0019 Decision 9, plan
/// C.4).
///
/// The safety property under test: a damaged store NEVER becomes an empty
/// "not available" list. Absent and unreadable are different answers, and an
/// unreadable store carries no data at all.
void main() {
  const a = '0000000000000001';
  const b = '00000000000000aa';
  final github = GitHubPublishTarget.create('me/lib')!;
  final otherRepo = GitHubPublishTarget.create('me/other')!;
  final cloudflare = CloudflarePublishTarget.create(
    accountId: '0123456789abcdef0123456789abcdef',
    workerName: 'kadugodi-library',
    accountSubdomain: 'kadugodi',
  )!;
  final cloudflareNewAddress = CloudflarePublishTarget.create(
    accountId: '0123456789abcdef0123456789abcdef',
    workerName: 'kadugodi-library',
    accountSubdomain: 'newkadugodi',
  )!;

  AvailabilitySnapshot snapshot(List<String> keys, [int asOf = 60000]) =>
      AvailabilitySnapshot.tryCreate(keys: keys, asOfMillis: asOf)!;

  AvailabilityLaneState full() => AvailabilityLaneState(
    pending: snapshot([b, a], 120000),
    published: AvailabilityPublished.of(
      target: github,
      snapshot: snapshot([a]),
      publishedAt: 90000,
    ),
    gitHubCommitTimes: const [30000, 10000, 20000],
    noticeShown: true,
  );

  AvailabilityLaneState? loaded(AvailabilityLaneRead read) =>
      read is AvailabilityLaneLoaded ? read.state : null;

  group('round trip', () {
    test('every field survives toJson → decode', () {
      final state = loaded(AvailabilityLaneState.decode(full().toJson()))!;

      expect(state.pending!.keys, [a, b]);
      expect(state.pending!.asOf, 120000);
      expect(state.published!.targetId, github.targetId);
      expect(state.published!.siteUrl, github.siteUrl);
      expect(state.published!.contentHash, snapshot([a]).contentHash);
      expect(state.published!.asOf, 60000);
      expect(state.published!.publishedAt, 90000);
      expect(state.gitHubCommitTimes, [10000, 20000, 30000]);
      expect(state.noticeShown, isTrue);
    });

    test('the empty state round-trips with explicit nulls', () {
      final json = AvailabilityLaneState().toJson();
      expect(json, {
        'version': 1,
        'pending': null,
        'published': null,
        'gitHubCommitTimes': <int>[],
        'noticeShown': false,
      });
      final state = loaded(AvailabilityLaneState.decode(json))!;
      expect(state.pending, isNull);
      expect(state.published, isNull);
      expect(state.gitHubCommitTimes, isEmpty);
    });

    test('a known-empty pending set survives as empty (it was computed)', () {
      final json = AvailabilityLaneState(pending: snapshot(const [])).toJson();
      final state = loaded(AvailabilityLaneState.decode(json))!;
      expect(state.pending!.keys, isEmpty);
    });

    test('holds only public data: keys, a hash, times and a flag', () {
      final json = full().toJson();
      expect(json.keys.toSet(), {
        'version',
        'pending',
        'published',
        'gitHubCommitTimes',
        'noticeShown',
      });
      expect(
        json.toString(),
        isNot(anyOf(contains('token'), contains('borrower'))),
      );
    });
  });

  group('absent versus unreadable', () {
    test('nothing stored is absent', () {
      expect(AvailabilityLaneState.decode(null), isA<AvailabilityLaneAbsent>());
    });

    test('a damaged value is unreadable and carries no data', () {
      final damaged = <String, Object? Function()>{
        'not a map': () => 'garbage',
        'a list': () => <Object?>[],
        'wrong version': () => full().toJson()..['version'] = 2,
        'missing version': () => full().toJson()..remove('version'),
        'missing pending': () => full().toJson()..remove('pending'),
        'missing commits': () => full().toJson()..remove('gitHubCommitTimes'),
        'missing notice': () => full().toJson()..remove('noticeShown'),
        'notice not bool': () => full().toJson()..['noticeShown'] = 'yes',
        'commits not list': () => full().toJson()..['gitHubCommitTimes'] = 3,
        'negative commit': () =>
            full().toJson()..['gitHubCommitTimes'] = <int>[-1],
        'commit not int': () =>
            full().toJson()..['gitHubCommitTimes'] = <Object>['1'],
        'too many commits': () => full().toJson()
          ..['gitHubCommitTimes'] = [
            for (var i = 0; i <= AvailabilityPacing.gitHubBudget; i++) i,
          ],
        'published not map': () => full().toJson()..['published'] = 'x',
        'published bad hash': () => full().toJson()
          ..['published'] = {
            'targetId': 'github:me/lib',
            'siteUrl': 'https://me.github.io/lib/',
            'contentHash': 'not-a-hash',
            'asOf': 0,
            'publishedAt': 0,
          },
        'published empty id': () => full().toJson()
          ..['published'] = {
            'targetId': '',
            'siteUrl': 'https://me.github.io/lib/',
            'contentHash': 'a' * 64,
            'asOf': 0,
            'publishedAt': 0,
          },
        'published negative time': () => full().toJson()
          ..['published'] = {
            'targetId': 'github:me/lib',
            'siteUrl': 'https://me.github.io/lib/',
            'contentHash': 'a' * 64,
            'asOf': 0,
            'publishedAt': -5,
          },
      };
      for (final entry in damaged.entries) {
        expect(
          AvailabilityLaneState.decode(entry.value()),
          isA<AvailabilityLaneUnreadable>(),
          reason: entry.key,
        );
      }
    });

    test('a damaged pending set NEVER becomes an empty list', () {
      final damagedPending = <String, Object?>{
        'no out list': {'asOf': 60000},
        'out is null': {'asOf': 60000, 'out': null},
        'out is a string': {'asOf': 60000, 'out': 'abc'},
        'out has a bad key': {
          'asOf': 60000,
          'out': ['NOT-A-KEY'],
        },
        'out has a number': {
          'asOf': 60000,
          'out': [1],
        },
        'no asOf': {'out': <String>[]},
        'negative asOf': {'asOf': -1, 'out': <String>[]},
        'pending is a list': <Object?>[],
      };
      for (final entry in damagedPending.entries) {
        final json = full().toJson()..['pending'] = entry.value;
        final read = AvailabilityLaneState.decode(json);
        expect(read, isA<AvailabilityLaneUnreadable>(), reason: entry.key);
      }
    });
  });

  group('GitHub commit times', () {
    test('keep only the newest budget-many, oldest first', () {
      final state = AvailabilityLaneState(
        gitHubCommitTimes: [for (var i = 12; i >= 1; i--) i * 1000],
      );
      expect(state.gitHubCommitTimes, [for (var i = 3; i <= 12; i++) i * 1000]);
      expect(() => state.gitHubCommitTimes.add(1), throwsUnsupportedError);
    });

    test('withGitHubCommit appends and keeps everything else', () {
      final state = full().withGitHubCommit(40000);
      expect(state.gitHubCommitTimes, [10000, 20000, 30000, 40000]);
      expect(state.pending!.keys, [a, b]);
      expect(state.published!.publishedAt, 90000);
      expect(state.noticeShown, isTrue);
    });

    test('the eleventh commit pushes out the oldest', () {
      var state = AvailabilityLaneState();
      for (var i = 1; i <= 11; i++) {
        state = state.withGitHubCommit(i);
      }
      expect(state.gitHubCommitTimes, [for (var i = 2; i <= 11; i++) i]);
    });
  });

  group('the published record', () {
    final record = AvailabilityPublished.of(
      target: github,
      snapshot: snapshot([a, b]),
      publishedAt: 1,
    );

    test('"unchanged" means same exact site and same keys, any asOf', () {
      expect(
        record.isUnchanged(target: github, snapshot: snapshot([b, a], 999999)),
        isTrue,
      );
      expect(
        record.isUnchanged(target: github, snapshot: snapshot([a])),
        isFalse,
      );
      expect(
        record.isUnchanged(target: otherRepo, snapshot: snapshot([a, b])),
        isFalse,
      );
    });

    test('a new Cloudflare address is a different site', () {
      final onCloudflare = AvailabilityPublished.of(
        target: cloudflare,
        snapshot: snapshot([a]),
        publishedAt: 1,
      );
      expect(onCloudflare.describes(cloudflare), isTrue);
      expect(
        cloudflareNewAddress.targetId,
        cloudflare.targetId,
        reason: 'same Worker identity',
      );
      expect(onCloudflare.describes(cloudflareNewAddress), isFalse);
    });

    test('toString names no keys', () {
      expect(
        record.toString(),
        'AvailabilityPublished(github:me/lib, asOf '
        '60000)',
      );
      expect(full().toString(), isNot(contains(a)));
    });
  });
}
