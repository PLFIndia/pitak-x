import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/network/domain/events_watch/events_watch_state.dart';
import 'package:pitaka/features/network/domain/events_watch/pending_change.dart';
import 'package:pitaka/features/network/domain/events_watch/site_baseline.dart';
import 'package:pitaka/features/network/domain/events_watch/site_watch_status.dart';
import 'package:pitaka/features/network/domain/events_watch/watch_settings_token.dart';
import 'package:pitaka/features/network/domain/events_watch/watched_library.dart';

/// Every value read back from the state file goes through a `validate`
/// gate. These tests pin that hostile or malformed stored values are
/// rejected rather than trusted (PLAN.md §1 "strict decoding").
void main() {
  const token = WatchSettingsToken(incarnation: 'aaaa', epoch: 1);
  const identity = WatchedLibraryIdentity(
    rowId: 7,
    createdAt: 1,
    siteUrl: 'https://a.github.io/lib/',
  );
  final digest = 'f' * 64;

  group('BaselinePoster.validate', () {
    test('accepts a sanitized same-site reference + hex digest', () {
      expect(
        BaselinePoster.validate(imageRef: 'posters/a.jpg', digest: digest),
        isNotNull,
      );
    });

    test('rejects absolute URLs, traversal, non-strings and bad digests', () {
      for (final ref in [
        'https://x/a.jpg',
        '../a.jpg',
        'posters/../x',
        42,
        null,
      ]) {
        expect(
          BaselinePoster.validate(imageRef: ref, digest: digest),
          isNull,
          reason: '$ref',
        );
      }
      expect(
        BaselinePoster.validate(imageRef: 'posters/a.jpg', digest: 'xyz'),
        isNull,
      );
    });
  });

  group('PendingChange.validate', () {
    PendingChange? v({
      Object? kind = 'added',
      Object? imageRef = 'posters/a.jpg',
      Object? caption,
      Object? dig,
    }) => PendingChange.validate(
      kind: kind,
      identity: identity,
      imageRef: imageRef,
      safeCaption: caption,
      digest: dig ?? digest,
      token: token,
    );

    test('accepts both kinds, null caption and a safe caption', () {
      expect(v()?.kind, PendingChangeKind.added);
      expect(v(kind: 'modified')?.kind, PendingChangeKind.modified);
      expect(v(caption: 'Fine caption')?.safeCaption, 'Fine caption');
    });

    test('rejects unknown kind, bad ref, bad digest, unsafe or untrimmed '
        'stored caption', () {
      expect(v(kind: 'removed'), isNull);
      expect(v(imageRef: '../x'), isNull);
      expect(v(dig: 'nope'), isNull);
      expect(v(caption: 'bidi\u202E'), isNull);
      expect(v(caption: ' padded '), isNull);
      expect(v(caption: 12), isNull);
    });
  });

  group('SiteWatchStatus.validate', () {
    SiteWatchStatus? v({
      Object? id = 5,
      Object? attempt = 1,
      Object? success,
      Object? outcome = 'ok',
    }) => SiteWatchStatus.validate(
      identity: identity,
      notificationId: id,
      lastAttemptAt: attempt,
      lastSuccessfulCheckAt: success,
      lastOutcome: outcome,
      baseline: null,
    );

    test('accepts valid scalars', () {
      expect(v()?.lastOutcome, SiteCheckOutcome.ok);
      expect(v(id: null, attempt: null, outcome: 'never'), isNotNull);
    });

    test('rejects id 0 (reserved for the summary), negatives, >31-bit, '
        'unknown outcomes', () {
      expect(v(id: 0), isNull);
      expect(v(id: -1), isNull);
      expect(v(id: 0x80000000), isNull);
      expect(v(attempt: -1), isNull);
      expect(v(outcome: 'shown'), isNull);
      expect(v(outcome: 1), isNull);
    });
  });

  group('LastRunOutcome.validate', () {
    test('accepts and rejects', () {
      expect(
        LastRunOutcome.validate(
          finishedAt: 1,
          checked: 1,
          withheld: 0,
          failed: 0,
          capacityExceeded: false,
        ),
        isNotNull,
      );
      expect(
        LastRunOutcome.validate(
          finishedAt: 1,
          checked: -1,
          withheld: 0,
          failed: 0,
          capacityExceeded: false,
        ),
        isNull,
      );
      expect(
        LastRunOutcome.validate(
          finishedAt: 1,
          checked: 1,
          withheld: 0,
          failed: 0,
          capacityExceeded: 'no',
        ),
        isNull,
      );
    });
  });

  group('EventsWatchState', () {
    test('lists are unmodifiable', () {
      final s = EventsWatchState.empty();
      expect(
        () => s.sites.add(SiteWatchStatus.fresh(identity)),
        throwsUnsupportedError,
      );
    });

    test('recovered carries the visible notice and the current token', () {
      final s = EventsWatchState.recovered(token: token);
      expect(s.recoveryNotice, RecoveryNotice.stateReset);
      expect(s.observedToken!.sameAs(token), isTrue);
      expect(s.sites, isEmpty);
      expect(s.pending, isEmpty);
    });

    test('copyWith clear flags really clear', () {
      final s = EventsWatchState.recovered(
        token: token,
      ).copyWith(generation: 'gen-000001', revocationToken: token);
      final cleared = s.copyWith(
        clearGeneration: true,
        clearRevocationToken: true,
        clearRecoveryNotice: true,
      );
      expect(cleared.generation, isNull);
      expect(cleared.revocationToken, isNull);
      expect(cleared.recoveryNotice, isNull);
    });
  });
}
