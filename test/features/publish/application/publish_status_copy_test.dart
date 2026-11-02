import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/application/publish_result.dart';
import 'package:pitaka/features/publish/application/publish_status_copy.dart';
import 'package:pitaka/features/publish/application/site/deferred_publish_verification.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_error_messages.dart';
import 'package:pitaka/features/publish/domain/github_error_messages.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/publish_host.dart';
import 'package:pitaka/features/publish/domain/site/publish_proof_path.dart';

void main() {
  const url = 'https://example.pitak.workers.dev/';

  PublishSuccess success({
    bool pagesLive = true,
    bool localStateSaved = true,
    bool newDeployment = true,
  }) => PublishSuccess(
    pagesUrl: url,
    uploadedPaths: const [],
    pagesLive: pagesLive,
    localStateSaved: localStateSaved,
    newDeployment: newDeployment,
  );

  group('cataloguePublishStatusMessage (L7)', () {
    test('a deploy-free verification never says Published!', () {
      final message = cataloguePublishStatusMessage(
        success(newDeployment: false),
        host: PublishHost.cloudflare,
      );

      expect(
        message,
        'Verified: your live site matches this phone’s last publish.',
      );
      expect(message, isNot(contains('Published!')));
    });

    test('a real deployment still says Published!', () {
      expect(
        cataloguePublishStatusMessage(success(), host: PublishHost.cloudflare),
        'Published! Your site is verified live.',
      );
    });

    test('an unsaved record is reported even when nothing was deployed', () {
      final message = cataloguePublishStatusMessage(
        success(newDeployment: false, localStateSaved: false),
        host: PublishHost.cloudflare,
      );

      expect(message, contains('could not save'));
      expect(message, isNot(contains('Verified:')));
    });

    test('cleanup truth is appended, never hidden', () {
      final message = cataloguePublishStatusMessage(
        const PublishSuccess(
          pagesUrl: url,
          uploadedPaths: [],
          pagesLive: true,
          temporaryCleanupFailed: true,
        ),
        host: PublishHost.cloudflare,
      );

      expect(message, contains(CloudflareErrorMessages.temporaryCleanup));
    });
  });

  group('eventsPublishStatusMessage (L7)', () {
    test('a deploy-free verification names the events address', () {
      expect(
        eventsPublishStatusMessage(
          success(newDeployment: false),
          host: PublishHost.cloudflare,
        ),
        'Verified: your events page is live at $url',
      );
    });

    test('a real events deployment keeps its Published! copy', () {
      expect(
        eventsPublishStatusMessage(success(), host: PublishHost.cloudflare),
        'Published! Your events page is at $url',
      );
    });
  });

  group('plan SP1 — a GitHub publish returns at commit time', () {
    final target = GitHubPublishTarget.create('me/lib')!;
    final request = DeferredVerificationRequest.forRecord(
      target: target,
      record: const PublishManifest(
        repo: 'me/lib',
        branch: 'main',
        headSha: 'NEWCOMMIT',
        fileShas: {'books.json': 'b1', 'events.json': 'e1'},
        proofPath: PublishProofPath.booksJson,
        committedAt: 1000,
      ),
      revision: 1000,
    )!;
    final committed = PublishSuccess(
      pagesUrl: target.siteUrl,
      uploadedPaths: const ['books.json'],
      verification: request,
    );

    String catalogue(DeferredVerificationOutcome? outcome) =>
        cataloguePublishStatusMessage(
          committed,
          host: PublishHost.github,
          goingLive: outcome,
        );

    test("the card's line follows the deferred check (product owner, "
        '2026-11-02)', () {
      expect(
        catalogue(null),
        'Published — going live (usually within a minute).',
      );
      expect(
        catalogue(DeferredVerificationOutcome.live),
        'Published! Your site is live.',
      );
      expect(
        catalogue(DeferredVerificationOutcome.notSaved),
        gitHubPublishRecordUnsavedMessage,
      );
      for (final outcome in [
        DeferredVerificationOutcome.notProven,
        DeferredVerificationOutcome.superseded,
        DeferredVerificationOutcome.cancelled,
      ]) {
        expect(
          catalogue(outcome),
          'Published! The commit is pushed — the site can take a minute to '
          'update.',
          reason: outcome.name,
        );
      }
    });

    test('never "live" without proof: no check, no live line', () {
      final noCheck = PublishSuccess(
        pagesUrl: target.siteUrl,
        uploadedPaths: const [],
      );
      expect(
        cataloguePublishStatusMessage(
          noCheck,
          host: PublishHost.github,
          goingLive: DeferredVerificationOutcome.live,
        ),
        gitHubNotSeenLiveMessage,
      );
    });

    test('an unsaved record wins over any check outcome', () {
      final unsaved = PublishSuccess(
        pagesUrl: target.siteUrl,
        uploadedPaths: const [],
        localStateSaved: false,
      );
      expect(
        cataloguePublishStatusMessage(unsaved, host: PublishHost.github),
        gitHubPublishRecordUnsavedMessage,
      );
    });

    test('Cloudflare ignores the GitHub check entirely', () {
      expect(
        cataloguePublishStatusMessage(
          success(pagesLive: false),
          host: PublishHost.cloudflare,
          goingLive: DeferredVerificationOutcome.live,
        ),
        'Deployed, but the site is not reachable yet. Retry verification.',
      );
    });

    test('the events screen shows ONE message with the address (product '
        'owner, 2026-11-02)', () {
      final events = PublishSuccess(
        pagesUrl: '${target.siteUrl}events.html',
        uploadedPaths: const ['events.json'],
        verification: request,
      );
      expect(
        eventsPublishStatusMessage(events, host: PublishHost.github),
        'Published — your events page is going live (usually within a '
        'minute): https://me.github.io/lib/events.html',
      );
      expect(
        eventsPublishStatusMessage(
          PublishSuccess(pagesUrl: events.pagesUrl, uploadedPaths: const []),
          host: PublishHost.github,
        ),
        'Published! The events commit is pushed — the page can take a minute '
        'to update.',
      );
    });
  });
}
