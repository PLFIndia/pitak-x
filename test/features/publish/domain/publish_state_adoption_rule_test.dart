import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_site_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_state_adoption.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/publish_host.dart';
import 'package:pitaka/features/publish/domain/site/publish_host_state.dart';

import '../support/move_fakes.dart';
import '../support/publish_state_fixtures.dart';

/// The adoption rule as the product owner decided it at the start of S11:
/// a restored phone takes over the backup's publishing record only when it
/// has NOT published itself, and every connection it has points at the
/// backup's site. Anything else keeps this phone's own state.
void main() {
  PhonePublishSetup phone({
    PublishHostState? journal,
    PublishManifest gitHub = PublishManifest.empty,
    CloudflareSiteManifest cloudflare = CloudflareSiteManifest.empty,
    CloudflareSiteManifest attempt = CloudflareSiteManifest.empty,
    GitHubPublishTarget? gitHubConnection,
    CloudflarePublishTarget? cloudflareConnection,
  }) => PhonePublishSetup(
    journal: journal,
    gitHubRecord: gitHub,
    cloudflareRecord: cloudflare,
    cloudflareAttempt: attempt,
    gitHubConnection: gitHubConnection,
    cloudflareConnection: cloudflareConnection,
  );

  bool mayAdopt(PhonePublishSetup setup, {bool verifiedGitHub = true}) =>
      PublishStateAdoptionRule.mayAdopt(
        phone: setup,
        archived: archivedState(verifiedGitHub: verifiedGitHub),
      );

  group('a phone that has not published adopts', () {
    test('nothing set up at all', () {
      expect(mayAdopt(phone()), isTrue);
    });

    test('an empty journal', () {
      expect(mayAdopt(phone(journal: PublishHostState.empty)), isTrue);
    });

    test('connected to the backup site, never published there', () {
      expect(mayAdopt(phone(gitHubConnection: archiveGitHub)), isTrue);
      expect(
        mayAdopt(
          phone(
            journal: const PublishHostState(activeHost: PublishHost.github),
            gitHubConnection: archiveGitHub,
          ),
        ),
        isTrue,
      );
    });

    test('the same site named only by the backup record', () {
      expect(
        mayAdopt(phone(gitHubConnection: archiveGitHub), verifiedGitHub: false),
        isTrue,
      );
    });
  });

  group('a phone with publishing of its own keeps it', () {
    test('it proved a site (verified address)', () {
      expect(
        mayAdopt(
          phone(
            journal: PublishHostState(
              activeHost: PublishHost.github,
              verifiedTarget: archiveGitHub,
            ),
          ),
        ),
        isFalse,
        reason: 'even the SAME site: its record is newer than the backup',
      );
    });

    test('it holds a GitHub record (repo, head or any path)', () {
      for (final record in [
        const PublishManifest(repo: 'degt3rt/my-library'),
        PublishManifest(headSha: sha40('1')),
        PublishManifest(fileShas: {'books.json': sha40('a')}),
      ]) {
        expect(mayAdopt(phone(gitHub: record)), isFalse, reason: '$record');
      }
    });

    test('it holds a Cloudflare record or an unconfirmed deploy', () {
      expect(mayAdopt(phone(cloudflare: cloudflareRecord())), isFalse);
      expect(mayAdopt(phone(attempt: cloudflareRecord())), isFalse);
    });

    test('a move is pending', () {
      final pending = movePending();
      expect(
        mayAdopt(
          phone(
            journal: PublishHostState(
              activeHost: pending.oldTarget.host,
              verifiedTarget: pending.oldTarget,
              pendingMove: pending,
            ),
          ),
        ),
        isFalse,
      );
    });
  });

  group('a phone connected elsewhere keeps its state', () {
    test('another host chosen on this phone', () {
      expect(
        mayAdopt(
          phone(
            journal: const PublishHostState(activeHost: PublishHost.cloudflare),
          ),
        ),
        isFalse,
      );
    });

    test('another repository', () {
      expect(
        mayAdopt(
          phone(gitHubConnection: GitHubPublishTarget.create('me/other')),
        ),
        isFalse,
      );
    });

    test('a connection on the host the backup does not publish to', () {
      // The backup publishes to GitHub; its Cloudflare record describes an
      // older site. A Cloudflare connection is not "the backup's site".
      expect(mayAdopt(phone(cloudflareConnection: archiveCloudflare)), isFalse);
    });

    test('a connection while the backup names no active site', () {
      final archived = archivedState(activeHost: null, verifiedGitHub: false);
      final cloudflareOnly = PhonePublishSetup(
        journal: null,
        gitHubRecord: PublishManifest.empty,
        cloudflareRecord: CloudflareSiteManifest.empty,
        cloudflareAttempt: CloudflareSiteManifest.empty,
        gitHubConnection: null,
        cloudflareConnection: archiveCloudflare,
      );
      expect(
        PublishStateAdoptionRule.mayAdopt(
          phone: cloudflareOnly,
          archived: archived,
        ),
        isFalse,
      );
    });
  });
}
