/// What the availability lane remembers between app runs (publish domain,
/// pure Dart; ADR 0019 Decision 9, plan AV7/C.4).
///
/// Why it is saved at all (beginner note): loans change only while the vault
/// is unlocked, but the publish may happen later — after the vault locks,
/// after the phone comes back online, or after GitHub's pacing allows it. So
/// the lane saves the set it computed, and publishes it from here.
///
/// It holds only PUBLIC data: item keys that become public anyway, a content
/// fingerprint, timestamps and one flag. No borrower data, no counts, no
/// token. That is why the store may live in SharedPreferences (plan C.4;
/// AGENTS.md §6.3 governs secrets, and there are none here).
///
/// **A damaged store never produces an empty list.** An empty "not available"
/// list means "everything is on the shelf", and publishing that by mistake
/// is the dangerous direction: a reader walks in for a book that is out. So
/// [AvailabilityLaneState.decode] accepts a stored value only when EVERY
/// field is exactly as this build writes it; anything else reads as
/// [AvailabilityLaneUnreadable], which carries no data. The lane then waits
/// for live loan counts to compute a fresh set (plan C.4).
library;

import 'dart:math' as math;

import 'package:pitaka/features/publish/domain/availability/availability_pacing.dart';
import 'package:pitaka/features/publish/domain/availability/availability_snapshot.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';

/// The last set this phone published, for one exact site.
final class AvailabilityPublished {
  /// Creates the record.
  const AvailabilityPublished({
    required this.targetId,
    required this.siteUrl,
    required this.contentHash,
    required this.asOf,
    required this.publishedAt,
  });

  /// Records that [snapshot] was published to [target] at [publishedAt].
  factory AvailabilityPublished.of({
    required PublishTarget target,
    required AvailabilitySnapshot snapshot,
    required int publishedAt,
  }) => AvailabilityPublished(
    targetId: target.targetId,
    siteUrl: target.siteUrl,
    contentHash: snapshot.contentHash,
    asOf: snapshot.asOf,
    publishedAt: publishedAt,
  );

  /// `PublishTarget.targetId` of the site.
  final String targetId;

  /// `PublishTarget.siteUrl` of the site. Kept with the id because a
  /// Cloudflare address can change while the Worker id stays the same, and a
  /// set published at the old address is not live at the new one.
  final String siteUrl;

  /// `AvailabilitySnapshot.contentHash` of the published key set.
  final String contentHash;

  /// `AvailabilitySnapshot.asOf` of the published set (epoch milliseconds).
  final int asOf;

  /// When the host accepted the publish (epoch milliseconds). On GitHub this
  /// is the spacing anchor ([AvailabilityPacing.gitHubSpacing]).
  final int publishedAt;

  /// True when this record describes exactly [target]: the same identity AND
  /// the same public address (`isSameExactTarget`).
  bool describes(PublishTarget target) =>
      targetId == target.targetId && siteUrl == target.siteUrl;

  /// True when publishing [snapshot] to [target] would change nothing: the
  /// same site already has the same key set. `asOf` is ignored on purpose.
  bool isUnchanged({
    required PublishTarget target,
    required AvailabilitySnapshot snapshot,
  }) => describes(target) && contentHash == snapshot.contentHash;

  @override
  String toString() => 'AvailabilityPublished($targetId, asOf $asOf)';
}

/// Everything the lane store holds.
final class AvailabilityLaneState {
  /// Creates a state. The default is the EMPTY state of a fresh install.
  AvailabilityLaneState({
    this.pending,
    this.published,
    List<int> gitHubCommitTimes = const [],
    this.noticeShown = false,
  }) : gitHubCommitTimes = _newestCommits(gitHubCommitTimes);

  /// The version of the stored JSON this build reads and writes.
  static const int currentVersion = 1;

  /// The set waiting to be published, or null when nothing is waiting.
  final AvailabilitySnapshot? pending;

  /// The last set this phone published, or null when none is recorded.
  final AvailabilityPublished? published;

  /// When this app's newest GitHub commits were accepted (every section),
  /// oldest first, at most [AvailabilityPacing.gitHubBudget] of them.
  final List<int> gitHubCommitTimes;

  /// True once the one-time "availability now updates by itself" notice has
  /// been shown.
  final bool noticeShown;

  /// The same state with [at] added to the GitHub commit times (the oldest
  /// time drops out once there are more than the budget).
  AvailabilityLaneState withGitHubCommit(int at) => AvailabilityLaneState(
    pending: pending,
    published: published,
    gitHubCommitTimes: [...gitHubCommitTimes, at],
    noticeShown: noticeShown,
  );

  /// The same state with [snapshot] waiting to be published (it replaces any
  /// older pending set: only the newest set is ever worth sending).
  AvailabilityLaneState withPending(AvailabilitySnapshot snapshot) =>
      AvailabilityLaneState(
        pending: snapshot,
        published: published,
        gitHubCommitTimes: gitHubCommitTimes,
        noticeShown: noticeShown,
      );

  /// The state after [sent] reached the site described by [record].
  ///
  /// The pending set is cleared only when it IS the set that was sent. A
  /// loan change saved while the publish was running left a newer set
  /// pending, and that one must still go out (beginner note: the publish
  /// runs outside this state, so the state may have moved on meanwhile).
  AvailabilityLaneState afterPublished({
    required AvailabilitySnapshot sent,
    required AvailabilityPublished record,
  }) {
    final waiting = pending;
    final isTheSentSet =
        waiting != null &&
        waiting.sameKeysAs(sent) &&
        waiting.asOf == sent.asOf;
    final stillWaiting = waiting != null && !isTheSentSet;
    return AvailabilityLaneState(
      pending: stillWaiting ? waiting : null,
      published: record,
      gitHubCommitTimes: gitHubCommitTimes,
      noticeShown: noticeShown,
    );
  }

  /// The same state without any saved set: nothing pending, nothing recorded
  /// as published. Used once a switch-off removal is on the site (ADR 0019
  /// Decision 9: turning the lane back on never publishes an old set) and
  /// when a restore makes every saved key meaningless (plan J9).
  AvailabilityLaneState withoutSnapshots() => AvailabilityLaneState(
    gitHubCommitTimes: gitHubCommitTimes,
    noticeShown: noticeShown,
  );

  /// The same state without the published record, keeping any pending set:
  /// the site no longer shows a set from this phone (its file was removed
  /// while the lane stayed on, for example a stale file after gate 7b).
  AvailabilityLaneState withoutPublished() => AvailabilityLaneState(
    pending: pending,
    gitHubCommitTimes: gitHubCommitTimes,
    noticeShown: noticeShown,
  );

  /// The same state with the one-time notice marked as shown.
  AvailabilityLaneState withNoticeShown() => AvailabilityLaneState(
    pending: pending,
    published: published,
    gitHubCommitTimes: gitHubCommitTimes,
    noticeShown: true,
  );

  /// True when nothing is saved: no pending set and no published record.
  bool get holdsNoSnapshots => pending == null && published == null;

  /// Decodes a stored value.
  ///
  /// [raw] is the decoded JSON, or null when nothing was ever stored:
  ///  - null → [AvailabilityLaneAbsent] (a fresh install);
  ///  - exactly what [toJson] writes → [AvailabilityLaneLoaded];
  ///  - anything else (wrong type, wrong version, a missing or malformed
  ///    field, a bad key, too many commit times) →
  ///    [AvailabilityLaneUnreadable].
  ///
  /// There is no partial read: one bad field makes the whole value
  /// unreadable, so a damaged pending set can never turn into an empty one.
  static AvailabilityLaneRead decode(Object? raw) {
    if (raw == null) return const AvailabilityLaneAbsent();
    final state = _decode(raw);
    return state == null
        ? const AvailabilityLaneUnreadable()
        : AvailabilityLaneLoaded(state);
  }

  /// Encodes this state. Every field is always written (pending and
  /// published as JSON null when empty), so [decode] can require all of them.
  Map<String, Object?> toJson() => {
    'version': currentVersion,
    'pending': switch (pending) {
      final pending? => {'asOf': pending.asOf, 'out': pending.keys},
      null => null,
    },
    'published': switch (published) {
      final published? => {
        'targetId': published.targetId,
        'siteUrl': published.siteUrl,
        'contentHash': published.contentHash,
        'asOf': published.asOf,
        'publishedAt': published.publishedAt,
      },
      null => null,
    },
    'gitHubCommitTimes': gitHubCommitTimes,
    'noticeShown': noticeShown,
  };

  static AvailabilityLaneState? _decode(Object raw) {
    if (raw is! Map) return null;
    const fields = {
      'version',
      'pending',
      'published',
      'gitHubCommitTimes',
      'noticeShown',
    };
    if (!fields.every(raw.containsKey)) return null;
    if (raw['version'] != currentVersion) return null;

    // JSON null means "nothing pending" / "nothing published". Any other
    // value must decode completely, or the whole state is unreadable.
    final Object? rawPending = raw['pending'];
    final pending = rawPending == null ? null : _decodePending(rawPending);
    if (rawPending != null && pending == null) return null;

    final Object? rawPublished = raw['published'];
    final published = rawPublished == null
        ? null
        : _decodePublished(rawPublished);
    if (rawPublished != null && published == null) return null;

    final times = raw['gitHubCommitTimes'];
    if (times is! List ||
        times.length > AvailabilityPacing.gitHubBudget ||
        times.any((time) => time is! int || time < 0)) {
      return null;
    }

    final noticeShown = raw['noticeShown'];
    if (noticeShown is! bool) return null;

    return AvailabilityLaneState(
      pending: pending,
      published: published,
      gitHubCommitTimes: times.cast<int>(),
      noticeShown: noticeShown,
    );
  }

  /// A pending set needs BOTH a valid time and a real list: a missing or
  /// malformed `out` is damage, never "nothing is out".
  static AvailabilitySnapshot? _decodePending(Object raw) {
    if (raw is! Map) return null;
    final asOf = raw['asOf'];
    final out = raw['out'];
    if (asOf is! int || out is! List || out.any((key) => key is! String)) {
      return null;
    }
    return AvailabilitySnapshot.tryCreate(
      keys: out.cast<String>(),
      asOfMillis: asOf,
    );
  }

  static AvailabilityPublished? _decodePublished(Object raw) {
    if (raw is! Map) return null;
    final targetId = raw['targetId'];
    final siteUrl = raw['siteUrl'];
    final contentHash = raw['contentHash'];
    final asOf = raw['asOf'];
    final publishedAt = raw['publishedAt'];
    if (targetId is! String ||
        targetId.isEmpty ||
        siteUrl is! String ||
        siteUrl.isEmpty ||
        contentHash is! String ||
        !_sha256Hex.hasMatch(contentHash) ||
        asOf is! int ||
        asOf < 0 ||
        publishedAt is! int ||
        publishedAt < 0) {
      return null;
    }
    return AvailabilityPublished(
      targetId: targetId,
      siteUrl: siteUrl,
      contentHash: contentHash,
      asOf: asOf,
      publishedAt: publishedAt,
    );
  }

  static final RegExp _sha256Hex = RegExp(r'^[0-9a-f]{64}$');

  /// [times] sorted oldest first, keeping only the newest
  /// [AvailabilityPacing.gitHubBudget]: older commits can no longer affect
  /// the budget, because the pacing only looks at that many.
  static List<int> _newestCommits(List<int> times) {
    final sorted = List<int>.of(times)..sort();
    final drop = math.max(0, sorted.length - AvailabilityPacing.gitHubBudget);
    return List.unmodifiable(sorted.sublist(drop));
  }

  @override
  String toString() =>
      'AvailabilityLaneState(pending: $pending, published: $published, '
      '${gitHubCommitTimes.length} commits)';
}

/// The result of reading the lane store.
///
/// Sealed (beginner note): the compiler makes every caller handle all three
/// cases, so "nothing stored" and "stored but damaged" can never be confused.
sealed class AvailabilityLaneRead {
  const AvailabilityLaneRead();
}

/// Nothing was ever stored (a fresh install, or a cleared store).
final class AvailabilityLaneAbsent extends AvailabilityLaneRead {
  /// Creates the result.
  const AvailabilityLaneAbsent();
}

/// Something is stored but cannot be trusted. Carries NO data on purpose:
/// the lane treats the state as unknown and recomputes from live counts.
final class AvailabilityLaneUnreadable extends AvailabilityLaneRead {
  /// Creates the result.
  const AvailabilityLaneUnreadable();
}

/// The stored state, fully validated.
final class AvailabilityLaneLoaded extends AvailabilityLaneRead {
  /// Wraps [state].
  const AvailabilityLaneLoaded(this.state);

  /// The decoded state.
  final AvailabilityLaneState state;
}
