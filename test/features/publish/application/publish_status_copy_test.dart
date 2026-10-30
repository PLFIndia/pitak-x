import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/application/publish_result.dart';
import 'package:pitaka/features/publish/application/publish_status_copy.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_error_messages.dart';
import 'package:pitaka/features/publish/domain/site/publish_host.dart';

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
}
