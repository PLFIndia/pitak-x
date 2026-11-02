import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_site_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_state_backup.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/previous_publication.dart';
import 'package:pitaka/features/publish/domain/site/publish_host.dart';

import '../support/publish_state_fixtures.dart';

/// The backup's publishing record as a value (plan CV6, S11): what makes it
/// adoptable, which site it names, and which local cover sources survive.
void main() {
  group('tryCreate', () {
    test('accepts a record that names a site', () {
      final state = archivedState();
      expect(state.coverSalt, archiveSalt);
      expect(state.describesASite, isTrue);
      expect(() => state.coverSalt.add(1), throwsUnsupportedError);
    });

    test('refuses a salt that is not exactly 16 bytes', () {
      for (final salt in [
        List<int>.filled(15, 1),
        List<int>.filled(17, 1),
        <int>[],
        [...List<int>.filled(15, 1), 256],
        [...List<int>.filled(15, 1), -1],
      ]) {
        expect(
          PublishStateBackup.tryCreate(
            coverSalt: salt,
            gitHubRecord: gitHubRecord(),
          ),
          isNull,
          reason: '$salt',
        );
      }
    });

    test('refuses a verified address of another host (journal rule)', () {
      expect(
        PublishStateBackup.tryCreate(
          coverSalt: archiveSalt,
          gitHubRecord: gitHubRecord(),
          activeHost: PublishHost.cloudflare,
          verifiedTarget: archiveGitHub,
        ),
        isNull,
      );
      expect(
        PublishStateBackup.tryCreate(
          coverSalt: archiveSalt,
          gitHubRecord: gitHubRecord(),
          verifiedTarget: archiveGitHub,
        ),
        isNull,
        reason: 'a verified target needs its active host',
      );
    });

    test('refuses a record that names no site (nothing to adopt)', () {
      expect(PublishStateBackup.tryCreate(coverSalt: archiveSalt), isNull);
      expect(
        PublishStateBackup.tryCreate(
          coverSalt: archiveSalt,
          activeHost: PublishHost.github,
        ),
        isNull,
      );
    });

    test('each part alone names a site', () {
      expect(
        PublishStateBackup.tryCreate(
          coverSalt: archiveSalt,
          gitHubRecord: const PublishManifest(repo: 'a/b'),
        ),
        isNotNull,
      );
      expect(
        PublishStateBackup.tryCreate(
          coverSalt: archiveSalt,
          cloudflareRecord: cloudflareRecord(),
        ),
        isNotNull,
      );
      expect(
        PublishStateBackup.tryCreate(
          coverSalt: archiveSalt,
          activeHost: PublishHost.github,
          verifiedTarget: archiveGitHub,
        ),
        isNotNull,
      );
    });
  });

  group('which site it names', () {
    test('the verified address of the active host wins', () {
      final state = archivedState();
      expect(state.effectiveActiveHost, PublishHost.github);
      expect(state.activeSite!.isSameExactTarget(archiveGitHub), isTrue);
    });

    test('without a verified address: the active host record target', () {
      final cloudflareActive = archivedState(
        activeHost: PublishHost.cloudflare,
        verifiedGitHub: false,
      );
      expect(
        cloudflareActive.activeSite!.isSameExactTarget(archiveCloudflare),
        isTrue,
      );
      final gitHubActive = archivedState(verifiedGitHub: false);
      expect(gitHubActive.activeSite!.isSameExactTarget(archiveGitHub), isTrue);
    });

    test('no journal: a GitHub record means GitHub (legacy default)', () {
      final state = archivedState(activeHost: null, verifiedGitHub: false);
      expect(state.activeHost, isNull);
      expect(state.effectiveActiveHost, PublishHost.github);
      expect(state.activeSite!.isSameExactTarget(archiveGitHub), isTrue);
    });

    test('no journal and only a Cloudflare record: no active site', () {
      final state = PublishStateBackup.tryCreate(
        coverSalt: archiveSalt,
        cloudflareRecord: cloudflareRecord(),
      )!;
      expect(state.effectiveActiveHost, isNull);
      expect(state.activeSite, isNull);
    });
  });

  group('withLocalCoverSourcesFor (ADR 0020 Decision 7)', () {
    test('keeps carried covers/<leaf> sources and every remote one', () {
      final state = archivedState(
        gitHub: gitHubRecord(
          covers: const {
            '1': 'covers/carried.jpg',
            '2': 'covers/not-carried.jpg',
            '3': 'file:///data/user/0/x/covers/carried.jpg',
            '4': 'https://covers.openlibrary.org/b/id/1-L.jpg',
            'periodical:p1': 'covers/carried.jpg',
          },
        ),
        cloudflare: cloudflareRecord(
          covers: const {'1': 'covers/carried.jpg', '2': 'covers/gone.jpg'},
        ),
      ).withLocalCoverSourcesFor({'carried.jpg'});

      expect(state.gitHubRecord.coverUrlByBookId, {
        '1': 'covers/carried.jpg',
        '4': 'https://covers.openlibrary.org/b/id/1-L.jpg',
        'periodical:p1': 'covers/carried.jpg',
      });
      expect(state.cloudflareRecord.coverUrlByBookId, {
        '1': 'covers/carried.jpg',
      });
      // Everything else is untouched.
      expect(state.coverSalt, archiveSalt);
      expect(state.gitHubRecord.fileShas, gitHubRecord().fileShas);
      expect(state.gitHubRecord.coverRendition, isNotNull);
      expect(state.verifiedTarget!.isSameExactTarget(archiveGitHub), isTrue);
    });

    test('no carried covers forgets every local source', () {
      final state = archivedState().withLocalCoverSourcesFor(const {});
      expect(state.gitHubRecord.coverUrlByBookId, {
        '2': 'https://covers.openlibrary.org/b/id/1-L.jpg',
      });
      expect(state.cloudflareRecord.coverUrlByBookId, isEmpty);
    });
  });

  test('the shared rule keeps the J9 reset behaviour by default', () {
    expect(
      coverSourcesKeptAfterNewCovers(const {
        '1': 'covers/a.jpg',
        '2': ' https://x.example/a.jpg',
      }),
      {'2': ' https://x.example/a.jpg'},
    );
    expect(
      const CloudflareSiteManifest(
        coverUrlByBookId: {'1': 'covers/a.jpg'},
      ).withoutLocalCoverSources().coverUrlByBookId,
      isEmpty,
    );
  });

  test('toString never prints the salt', () {
    final text = archivedState().toString();
    expect(text, isNot(contains(archiveSalt.join(', '))));
    expect(text, contains('github:degt3rt/my-library'));
  });
}
