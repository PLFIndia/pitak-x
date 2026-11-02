import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/github_content_limit.dart';
import 'package:pitaka/features/publish/domain/github_upload_journal.dart';

/// Plan J8 (a): what the phone remembers between GitHub upload attempts.
void main() {
  const repo = 'me/lib';
  const t0 = 1_800_000_000_000;
  String sha(int n) => n.toRadixString(16).padLeft(40, '0');
  final day = const Duration(days: 1).inMilliseconds;

  GitHubUploadJournal roundTrip(GitHubUploadJournal journal) =>
      GitHubUploadJournal.decode(jsonDecode(jsonEncode(journal.toJson())))!;

  group('repoKey', () {
    test(
      'lower-cases a valid owner/repo (GitHub names are case-insensitive)',
      () {
        expect(GitHubUploadJournal.repoKey('Me', 'My-Lib'), 'me/my-lib');
      },
    );

    test('refuses what is not a GitHub repository name (no journal entry)', () {
      expect(GitHubUploadJournal.repoKey('evil.example', 'r'), isNull);
      expect(GitHubUploadJournal.repoKey('me', 'a/b'), isNull);
      expect(GitHubUploadJournal.repoKey('me', '..'), isNull);
      expect(GitHubUploadJournal.repoKey('', 'r'), isNull);
    });
  });

  group('stored blobs', () {
    test('are held for their repository only', () {
      final journal = GitHubUploadJournal.empty.afterStored(repo, [
        sha(1),
        sha(2),
      ], now: t0);
      expect(journal.heldFor(repo, now: t0), {sha(1), sha(2)});
      expect(journal.heldFor('me/other', now: t0), isEmpty);
      expect(journal.blobCount, 2);
    });

    test('keep the time GitHub first confirmed them', () {
      final journal = GitHubUploadJournal.empty
          .afterStored(repo, [sha(1)], now: t0)
          .afterStored(repo, [sha(1)], now: t0 + 6 * day);
      // Still the first time: a week after t0 it expires, not a week after
      // the repeat.
      expect(journal.heldFor(repo, now: t0 + 7 * day + 1), isEmpty);
    });

    test('ignore anything that is not a lower-case 40-hex sha', () {
      final journal = GitHubUploadJournal.empty.afterStored(repo, [
        'not-a-sha',
        sha(1).toUpperCase().replaceAll('0', 'A'),
        sha(3),
      ], now: t0);
      expect(journal.heldFor(repo, now: t0), {sha(3)});
    });

    test('storing nothing changes nothing', () {
      final journal = GitHubUploadJournal.empty.afterRefusal(
        now: t0,
        serverHint: null,
      );
      expect(
        identical(journal.afterStored(repo, const [], now: t0), journal),
        isTrue,
      );
    });

    test('expire after a week, in either direction of the clock', () {
      final journal = GitHubUploadJournal.empty.afterStored(repo, [
        sha(1),
      ], now: t0);
      expect(journal.heldFor(repo, now: t0 + 7 * day), {sha(1)});
      expect(journal.heldFor(repo, now: t0 + 7 * day + 1), isEmpty);
      // A clock that moved back a long way cannot keep an entry forever.
      expect(journal.heldFor(repo, now: t0 - 8 * day), isEmpty);
    });

    test('expired entries are dropped at the next store', () {
      final journal = GitHubUploadJournal.empty
          .afterStored(repo, [sha(1)], now: t0)
          .afterStored(repo, [sha(2)], now: t0 + 8 * day);
      expect(journal.blobCount, 1);
      expect(journal.heldFor(repo, now: t0 + 8 * day), {sha(2)});
    });

    test('at the cap, the oldest are forgotten first', () {
      var journal = GitHubUploadJournal.empty.afterStored(repo, [
        sha(1),
      ], now: t0);
      journal = journal.afterStored(repo, [
        for (var n = 2; n <= GitHubUploadJournal.maxBlobs + 1; n++) sha(n),
      ], now: t0 + 1);
      expect(journal.blobCount, GitHubUploadJournal.maxBlobs);
      final held = journal.heldFor(repo, now: t0 + 1);
      expect(held.contains(sha(1)), isFalse);
      expect(held.contains(sha(GitHubUploadJournal.maxBlobs + 1)), isTrue);
    });

    test('beyond four repositories, the one used longest ago is forgotten, '
        'never the one just written', () {
      var journal = GitHubUploadJournal.empty;
      for (var n = 1; n <= GitHubUploadJournal.maxRepos; n++) {
        journal = journal.afterStored('me/r$n', [sha(n)], now: t0 + n);
      }
      journal = journal.afterStored('me/new', [sha(99)], now: t0 + 100);
      expect(journal.heldFor('me/r1', now: t0 + 100), isEmpty);
      expect(journal.heldFor('me/r2', now: t0 + 100), {sha(2)});
      expect(journal.heldFor('me/new', now: t0 + 100), {sha(99)});
      // Writing an OLD time to a new repo still keeps the new repo.
      final again = journal.afterStored('me/newer', [sha(100)], now: t0);
      expect(again.heldFor('me/newer', now: t0 + 100), {sha(100)});
    });
  });

  group('after a commit landed', () {
    test('the blobs its tree names are forgotten, the others kept', () {
      final journal = GitHubUploadJournal.empty
          .afterStored(repo, [sha(1), sha(2), sha(3)], now: t0)
          .afterCommitted(repo, [sha(1), sha(2), sha(9)]);
      expect(journal.heldFor(repo, now: t0), {sha(3)});
    });

    test('the pause and the refusal count end', () {
      final journal = GitHubUploadJournal.empty
          .afterRefusal(now: t0, serverHint: null)
          .afterCommitted(repo, const []);
      expect(journal.pausedUntil, isNull);
      expect(journal.refusals, 0);
      expect(journal.pauseLeft(t0), isNull);
    });

    test("a commit to another repository keeps this one's blobs", () {
      final journal = GitHubUploadJournal.empty
          .afterStored(repo, [sha(1)], now: t0)
          .afterCommitted('me/other', [sha(1)]);
      expect(journal.heldFor(repo, now: t0), {sha(1)});
    });

    test('forgetting the last blob of a repository removes the repository', () {
      final journal = GitHubUploadJournal.empty
          .afterStored(repo, [sha(1)], now: t0)
          .afterCommitted(repo, [sha(1)]);
      expect(journal.toJson()['repos'], isEmpty);
      expect(journal.sameAs(GitHubUploadJournal.empty), isTrue);
    });
  });

  group('withoutBlobs (a refused tree)', () {
    test('forgets exactly the given blobs and keeps the pause', () {
      final journal = GitHubUploadJournal.empty
          .afterStored(repo, [sha(1), sha(2)], now: t0)
          .afterRefusal(now: t0, serverHint: null)
          .withoutBlobs(repo, [sha(1)]);
      expect(journal.heldFor(repo, now: t0), {sha(2)});
      expect(journal.pauseLeft(t0), const Duration(minutes: 1));
    });

    test('an unknown repository changes nothing', () {
      final journal = GitHubUploadJournal.empty.afterStored(repo, [
        sha(1),
      ], now: t0);
      expect(journal.withoutBlobs('me/x', [sha(1)]).sameAs(journal), isTrue);
    });
  });

  group('the pause', () {
    test('a refusal starts the pause the content-limit rule decides', () {
      final journal = GitHubUploadJournal.empty.afterRefusal(
        now: t0,
        serverHint: const Duration(minutes: 5),
      );
      expect(journal.refusals, 1);
      expect(journal.pauseLeft(t0), const Duration(minutes: 5));
      expect(journal.pauseLeft(t0 + 4 * 60 * 1000), const Duration(minutes: 1));
      expect(journal.pauseLeft(t0 + 5 * 60 * 1000), isNull);
    });

    test('refusals in a row double it; any stored blob starts again', () {
      var journal = GitHubUploadJournal.empty
          .afterRefusal(now: t0, serverHint: null)
          .afterRefusal(now: t0, serverHint: null)
          .afterRefusal(now: t0, serverHint: null);
      expect(journal.refusals, 3);
      expect(journal.pauseLeft(t0), const Duration(minutes: 4));
      journal = journal
          .afterStored(repo, [sha(1)], now: t0)
          .afterRefusal(now: t0, serverHint: null);
      expect(journal.refusals, 1);
      expect(journal.pauseLeft(t0), const Duration(minutes: 1));
    });

    test('the count stops growing at its cap', () {
      var journal = GitHubUploadJournal.empty;
      for (var i = 0; i < GitHubUploadJournal.maxRefusals + 5; i++) {
        journal = journal.afterRefusal(now: t0, serverHint: null);
      }
      expect(journal.refusals, GitHubUploadJournal.maxRefusals);
      expect(journal.pauseLeft(t0), GitHubContentLimit.maximumPause);
    });

    test('a pause longer than the hourly window is ignored (clock moved '
        'back, or damage): publishing is never switched off for longer', () {
      final journal = GitHubUploadJournal.empty.afterRefusal(
        now: t0,
        serverHint: const Duration(hours: 1),
      );
      expect(journal.pauseLeft(t0), const Duration(hours: 1));
      expect(journal.pauseLeft(t0 - 1), isNull);
    });
  });

  group('stored form', () {
    test('round-trips exactly', () {
      final journal = GitHubUploadJournal.empty
          .afterStored(repo, [sha(1), sha(2)], now: t0)
          .afterStored('me/other', [sha(3)], now: t0 + 5)
          .afterRefusal(now: t0 + 9, serverHint: null);
      final back = roundTrip(journal);
      expect(back.sameAs(journal), isTrue);
      expect(back.heldFor(repo, now: t0), {sha(1), sha(2)});
      expect(back.pausedUntil, journal.pausedUntil);
      expect(back.refusals, 1);
    });

    test('the empty journal round-trips', () {
      expect(
        roundTrip(GitHubUploadJournal.empty).sameAs(GitHubUploadJournal.empty),
        isTrue,
      );
    });

    Map<String, Object?> valid() => {
      'version': 1,
      'pausedUntil': null,
      'refusals': 0,
      'repos': {
        repo: {sha(1): t0},
      },
    };

    test('decodes exactly what toJson writes', () {
      expect(GitHubUploadJournal.decode(valid()), isNotNull);
    });

    final damaged = <String, Map<String, Object?> Function()>{
      'another version': () => {...valid(), 'version': 2},
      'an extra field': () => {...valid(), 'extra': 1},
      'a missing field': () => {...valid()}..remove('refusals'),
      'a negative pause': () => {...valid(), 'pausedUntil': -1},
      'a text pause': () => {...valid(), 'pausedUntil': '1'},
      'a negative count': () => {...valid(), 'refusals': -1},
      'a count over the cap': () => {...valid(), 'refusals': 101},
      'repos not a map': () => {...valid(), 'repos': <Object>[]},
      'an upper-case repo key': () => {
        ...valid(),
        'repos': {
          'Me/lib': {sha(1): t0},
        },
      },
      'an invalid repo key': () => {
        ...valid(),
        'repos': {
          'evil.example/lib': {sha(1): t0},
        },
      },
      'a bad sha': () => {
        ...valid(),
        'repos': {
          repo: {'xyz': t0},
        },
      },
      'an upper-case sha': () => {
        ...valid(),
        'repos': {
          repo: {sha(10).toUpperCase().replaceAll('0', 'A'): t0},
        },
      },
      'a negative time': () => {
        ...valid(),
        'repos': {
          repo: {sha(1): -1},
        },
      },
      'a text time': () => {
        ...valid(),
        'repos': {
          repo: {sha(1): '1'},
        },
      },
      'blobs not a map': () => {
        ...valid(),
        'repos': {repo: <Object>[]},
      },
      'too many repos': () => {
        ...valid(),
        'repos': {
          for (var n = 0; n <= GitHubUploadJournal.maxRepos; n++)
            'me/r$n': {sha(n): t0},
        },
      },
    };
    for (final entry in damaged.entries) {
      test('refuses ${entry.key} (read as "nothing remembered")', () {
        final raw = jsonDecode(jsonEncode(entry.value()));
        expect(GitHubUploadJournal.decode(raw), isNull);
      });
    }

    test('refuses more blobs than the cap', () {
      final raw = {
        ...valid(),
        'repos': {
          repo: {
            for (var n = 0; n <= GitHubUploadJournal.maxBlobs; n++) sha(n): t0,
          },
        },
      };
      expect(GitHubUploadJournal.decode(raw), isNull);
    });

    test('refuses what is not a map at all', () {
      expect(GitHubUploadJournal.decode(null), isNull);
      expect(GitHubUploadJournal.decode('text'), isNull);
      expect(GitHubUploadJournal.decode(const <Object>[]), isNull);
    });
  });

  group('sameAs', () {
    final base = GitHubUploadJournal.empty.afterStored(repo, [sha(1)], now: t0);

    test('compares blobs, times and the pause', () {
      expect(base.sameAs(roundTrip(base)), isTrue);
      expect(base.sameAs(base.afterStored(repo, [sha(2)], now: t0)), isFalse);
      expect(
        base.sameAs(
          GitHubUploadJournal.empty.afterStored(repo, [sha(1)], now: t0 + 1),
        ),
        isFalse,
      );
      expect(
        base.sameAs(base.afterRefusal(now: t0, serverHint: null)),
        isFalse,
      );
      expect(
        base.sameAs(
          GitHubUploadJournal.empty.afterStored('me/x', [sha(1)], now: t0),
        ),
        isFalse,
      );
      expect(
        base.sameAs(
          GitHubUploadJournal.empty
              .afterStored(repo, [sha(1)], now: t0)
              .afterStored('me/x', [sha(2)], now: t0),
        ),
        isFalse,
      );
    });
  });
}
