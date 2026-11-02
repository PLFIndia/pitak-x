/// What this phone remembers about its GitHub uploads between attempts
/// (pure domain; plan J8 (a), ADR 0020 Decision 6 amendment).
///
/// Why a journal (beginner note): a GitHub commit is built in steps — first
/// one "blob" request per new file, then ONE tree, commit and branch move
/// at the end. When GitHub's hourly content limit refuses a request halfway
/// through a large first publish, nothing is committed (the site stays as it
/// was), but every blob GitHub already accepted is kept in the repository.
/// Without a memory, the next attempt sends all of them again and is refused
/// at the same place: a library with more than about 500 new covers could
/// never finish. With this journal the next attempt names those blobs by sha
/// instead (`GitHubCommitPlan.withAlsoHeld`) and only sends the rest, so
/// each attempt gets further and the final commit is still one atomic
/// commit.
///
/// It also remembers the pause GitHub asked for (`GitHubContentLimit`), so
/// no flow — not even the automatic availability lane — sends again too
/// early.
///
/// What it holds is public: repository names and blob shas, which are
/// fingerprints of files that are being published anyway (plan P8). No
/// token, no credential, no library data. A sha is recorded only after
/// GitHub confirmed storing exactly those bytes (`commitFiles`'
/// `onBlobStored`).
///
/// It is safe in both directions. A lost or unreadable journal only means
/// more uploads (the behaviour before J8). A remembered blob GitHub has since
/// thrown away makes GitHub refuse the tree (HTTP 422, verified against the
/// real API, plan A.6 #100): nothing is committed, and the caller forgets the
/// blobs it named (`withoutBlobs`), so the next attempt sends them again.
library;

import 'package:pitaka/features/publish/domain/github_content_limit.dart';
import 'package:pitaka/features/publish/domain/github_pages_url.dart';

/// The blobs a refused or interrupted attempt left on GitHub, per repository,
/// and the pause GitHub asked for. Immutable: every change returns a new
/// value.
final class GitHubUploadJournal {
  const GitHubUploadJournal._({
    required Map<String, Map<String, int>> blobsByRepo,
    required this.pausedUntil,
    required this.refusals,
  }) : _blobsByRepo = blobsByRepo;

  /// Nothing remembered, no pause.
  static const GitHubUploadJournal empty = GitHubUploadJournal._(
    blobsByRepo: {},
    pausedUntil: null,
    refusals: 0,
  );

  /// The stored format's version.
  static const int currentVersion = 1;

  /// How long a remembered blob is trusted. GitHub may clean up blobs that no
  /// commit references; a week is far longer than "publish again in an hour"
  /// and keeps an abandoned journal from growing forever. An older entry is
  /// simply sent again.
  static const Duration maxAge = Duration(days: 7);

  /// The most blobs remembered at once, over all repositories (about 1 MB
  /// stored). The oldest are forgotten first: forgetting only costs uploads.
  static const int maxBlobs = 20000;

  /// The most repositories remembered at once. A phone publishes to one
  /// site; a few more cover a move and a move back.
  static const int maxRepos = 4;

  /// The most consecutive refusals counted; more cannot lengthen the pause
  /// (it is capped at `GitHubContentLimit.maximumPause` long before).
  static const int maxRefusals = 100;

  /// repo key → blob sha → when GitHub confirmed storing it (epoch ms).
  final Map<String, Map<String, int>> _blobsByRepo;

  /// Until when Pitak sends nothing to GitHub (epoch ms); null = no pause.
  final int? pausedUntil;

  /// Refusals in a row without any progress in between.
  final int refusals;

  static final RegExp _sha = RegExp(r'^[0-9a-f]{40}$');

  /// The journal's key for [owner]/[repo]: lower case, because GitHub names
  /// are case-insensitive. Null when the pair is not a valid GitHub
  /// repository name (the same rule as the site address); such a repository
  /// is simply not journaled.
  static String? repoKey(String owner, String repo) {
    final key = '$owner/$repo'.toLowerCase();
    return githubPagesUrlFor(key) == null ? null : key;
  }

  /// How many blobs are remembered, over all repositories.
  int get blobCount =>
      _blobsByRepo.values.fold(0, (sum, blobs) => sum + blobs.length);

  /// The blobs GitHub holds for [repoKey] from earlier attempts, still within
  /// [maxAge] at [now]. A time in the future (a clock that moved back) counts
  /// by its distance too, so a wrong clock cannot keep an entry forever.
  Set<String> heldFor(String repoKey, {required int now}) => {
    for (final entry in (_blobsByRepo[repoKey] ?? const {}).entries)
      if (_fresh(entry.value, now)) entry.key,
  };

  /// The pause still left at [now], or null when Pitak may send.
  ///
  /// A pause longer than `GitHubContentLimit.maximumPause` cannot have been
  /// written by [afterRefusal] at this clock (the clock moved back, or the
  /// value is damaged), so it is ignored: publishing must never be switched
  /// off for longer than the limit's own window.
  Duration? pauseLeft(int now) {
    final until = pausedUntil;
    if (until == null) return null;
    final left = until - now;
    if (left <= 0 || left > GitHubContentLimit.maximumPause.inMilliseconds) {
      return null;
    }
    return Duration(milliseconds: left);
  }

  /// GitHub confirmed storing [shas] for [repoKey] at [now].
  ///
  /// An entry already remembered keeps its first time. Any stored blob is
  /// progress, so the refusal count starts again. Expired entries are
  /// dropped and the caps applied, oldest first; the repository just written
  /// is the last one forgotten.
  GitHubUploadJournal afterStored(
    String repoKey,
    Iterable<String> shas, {
    required int now,
  }) {
    final added = [
      for (final sha in shas)
        if (_sha.hasMatch(sha)) sha,
    ];
    if (added.isEmpty) return this;
    final next = _copy();
    final repo = next.putIfAbsent(repoKey, () => <String, int>{});
    for (final sha in added) {
      repo.putIfAbsent(sha, () => now);
    }
    return GitHubUploadJournal._(
      blobsByRepo: _pruned(next, now: now, keep: repoKey),
      pausedUntil: pausedUntil,
      refusals: 0,
    );
  }

  /// A commit to [repoKey] landed, naming [namedShas]: those blobs are in the
  /// head tree now, so the tree read finds them and the journal can forget
  /// them. GitHub accepted content again, so the pause and the refusal count
  /// end too.
  GitHubUploadJournal afterCommitted(
    String repoKey,
    Iterable<String> namedShas,
  ) => GitHubUploadJournal._(
    blobsByRepo: _without(repoKey, namedShas),
    pausedUntil: null,
    refusals: 0,
  );

  /// Forgets [shas] for [repoKey]: GitHub refused a tree that named them, so
  /// one of them may be gone. The next attempt sends them again.
  GitHubUploadJournal withoutBlobs(String repoKey, Iterable<String> shas) =>
      GitHubUploadJournal._(
        blobsByRepo: _without(repoKey, shas),
        pausedUntil: pausedUntil,
        refusals: refusals,
      );

  /// GitHub refused a request at [now] because of its rate limit, asking for
  /// [serverHint] (null when it gave none). Starts the pause
  /// `GitHubContentLimit.pauseAfterRefusal` decides.
  GitHubUploadJournal afterRefusal({
    required int now,
    required Duration? serverHint,
  }) {
    final count = refusals >= maxRefusals ? maxRefusals : refusals + 1;
    final pause = GitHubContentLimit.pauseAfterRefusal(
      serverHint: serverHint,
      consecutiveRefusals: count,
    );
    return GitHubUploadJournal._(
      blobsByRepo: _blobsByRepo,
      pausedUntil: now + pause.inMilliseconds,
      refusals: count,
    );
  }

  /// The stored form. [decode] accepts exactly this shape.
  Map<String, Object?> toJson() => {
    'version': currentVersion,
    'pausedUntil': pausedUntil,
    'refusals': refusals,
    'repos': {
      for (final repo in _blobsByRepo.entries)
        repo.key: {for (final blob in repo.value.entries) blob.key: blob.value},
    },
  };

  /// Reads a stored journal; null when [raw] is not exactly what [toJson]
  /// writes (another version, a bad key, sha or time, too many entries).
  ///
  /// The caller treats null like "nothing remembered": the safe direction,
  /// because an empty journal only means sending more.
  static GitHubUploadJournal? decode(Object? raw) {
    if (raw is! Map<String, dynamic> || raw.length != 4) return null;
    final version = raw['version'];
    final pausedUntil = raw['pausedUntil'];
    final refusals = raw['refusals'];
    final repos = raw['repos'];
    if (version != currentVersion ||
        (pausedUntil != null && (pausedUntil is! int || pausedUntil < 0)) ||
        refusals is! int ||
        refusals < 0 ||
        refusals > maxRefusals ||
        repos is! Map<String, dynamic> ||
        repos.length > maxRepos) {
      return null;
    }
    final blobsByRepo = <String, Map<String, int>>{};
    var total = 0;
    for (final repo in repos.entries) {
      final blobs = repo.value;
      if (!repoKeyIsValid(repo.key) || blobs is! Map<String, dynamic>) {
        return null;
      }
      final decoded = <String, int>{};
      for (final blob in blobs.entries) {
        final at = blob.value;
        if (!_sha.hasMatch(blob.key) || at is! int || at < 0) return null;
        decoded[blob.key] = at;
      }
      total += decoded.length;
      if (total > maxBlobs) return null;
      blobsByRepo[repo.key] = decoded;
    }
    return GitHubUploadJournal._(
      blobsByRepo: blobsByRepo,
      pausedUntil: pausedUntil as int?,
      refusals: refusals,
    );
  }

  /// Whether [other] holds the same blobs with the same times and the same
  /// pause; the decorator uses it to skip writes that would change nothing.
  ///
  /// A named method rather than `==`: the domain purity allow-list does not
  /// admit `package:meta`'s `@immutable`, which the lints require for an
  /// `==` override (same convention as `LibraryQuery.sameIntentAs`).
  bool sameAs(GitHubUploadJournal other) {
    if (identical(this, other)) return true;
    if (other.pausedUntil != pausedUntil ||
        other.refusals != refusals ||
        other._blobsByRepo.length != _blobsByRepo.length) {
      return false;
    }
    for (final repo in _blobsByRepo.entries) {
      final theirs = other._blobsByRepo[repo.key];
      if (theirs == null || theirs.length != repo.value.length) return false;
      for (final blob in repo.value.entries) {
        if (theirs[blob.key] != blob.value) return false;
      }
    }
    return true;
  }

  /// Whether [key] is a journal key [repoKey] could have produced.
  static bool repoKeyIsValid(String key) =>
      key == key.toLowerCase() && githubPagesUrlFor(key) != null;

  static bool _fresh(int storedAt, int now) =>
      (now - storedAt).abs() <= maxAge.inMilliseconds;

  Map<String, Map<String, int>> _copy() => {
    for (final repo in _blobsByRepo.entries)
      repo.key: Map<String, int>.of(repo.value),
  };

  Map<String, Map<String, int>> _without(
    String repoKey,
    Iterable<String> shas,
  ) {
    final blobs = _blobsByRepo[repoKey];
    if (blobs == null) return _blobsByRepo;
    final drop = shas.toSet();
    final next = _copy();
    final repo = next[repoKey]!..removeWhere((sha, _) => drop.contains(sha));
    if (repo.isEmpty) next.remove(repoKey);
    return next;
  }

  /// Drops expired entries, then whole repositories beyond [maxRepos] (the
  /// one whose newest entry is oldest first, never [keep]), then the oldest
  /// entries beyond [maxBlobs].
  static Map<String, Map<String, int>> _pruned(
    Map<String, Map<String, int>> blobsByRepo, {
    required int now,
    required String keep,
  }) {
    for (final repo in blobsByRepo.values) {
      repo.removeWhere((_, at) => !_fresh(at, now));
    }
    blobsByRepo.removeWhere((key, repo) => repo.isEmpty && key != keep);
    while (blobsByRepo.length > maxRepos) {
      final oldest =
          (blobsByRepo.entries.where((e) => e.key != keep).toList()
                ..sort((a, b) => _newest(a.value).compareTo(_newest(b.value))))
              .first
              .key;
      blobsByRepo.remove(oldest);
    }
    final total = blobsByRepo.values.fold(0, (sum, r) => sum + r.length);
    if (total > maxBlobs) {
      final all = [
        for (final repo in blobsByRepo.entries)
          for (final blob in repo.value.entries)
            (repo: repo.key, sha: blob.key, at: blob.value),
      ]..sort((a, b) => a.at.compareTo(b.at));
      for (final old in all.take(total - maxBlobs)) {
        blobsByRepo[old.repo]!.remove(old.sha);
      }
      blobsByRepo.removeWhere((_, repo) => repo.isEmpty);
    }
    return blobsByRepo;
  }

  static int _newest(Map<String, int> blobs) =>
      blobs.values.fold(0, (newest, at) => at > newest ? at : newest);
}
