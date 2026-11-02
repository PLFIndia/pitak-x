import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/github_api.dart';
import 'package:pitaka/features/publish/domain/github_error_messages.dart';

void main() {
  test('every status code maps to a fixed, body-free message', () {
    expect(gitHubHttpErrorMessage(401), contains('sign out and sign in'));
    expect(gitHubHttpErrorMessage(403), contains('rate limit'));
    expect(gitHubHttpErrorMessage(404), contains('could not find'));
    expect(gitHubHttpErrorMessage(422), contains('422'));
    expect(gitHubHttpErrorMessage(500), contains('server problem'));
    expect(gitHubHttpErrorMessage(599), contains('599'));
    expect(gitHubHttpErrorMessage(418), contains('418'));
  });

  test('messages never interpolate anything but the status code '
      '(regression: hostile response bodies must not reach the UI)', () {
    for (final code in [400, 401, 403, 404, 409, 422, 500, 502, 599]) {
      final msg = gitHubHttpErrorMessage(code);
      // Only digits from the code itself may appear; no braces/URLs/JSON.
      expect(msg, isNot(contains('{')));
      expect(msg, isNot(contains('http://')));
      expect(msg, isNot(contains('https://')));
    }
    expect(gitHubNetworkErrorMessage, isNot(contains('{')));
  });

  group('rate limited (plan J8)', () {
    PublishCommitRateLimited limited({
      int held = 450,
      int total = 1004,
      Duration? wait,
      bool refusedNow = true,
    }) => PublishCommitRateLimited(
      filesHeld: held,
      filesToSend: total,
      wait: wait,
      refusedNow: refusedNow,
    );

    test('a refusal says how far the upload got, that the site is unchanged '
        'and to publish again in about an hour', () {
      expect(
        gitHubRateLimitedMessage(limited(wait: const Duration(minutes: 1))),
        'GitHub limits how much one account can upload in an hour, and it '
        'paused this upload. 450 of 1004 files are already on GitHub and will '
        'not be sent again. Nothing on your site has changed yet. Publish '
        'again in about an hour to send the rest.',
      );
    });

    test('everything sent but the last step refused: no "rest" to send', () {
      expect(
        gitHubRateLimitedMessage(limited(held: 1004)),
        endsWith(
          '1004 of 1004 files are already on GitHub and will not be sent '
          'again. Nothing on your site has changed yet. Publish again in '
          'about an hour.',
        ),
      );
    });

    test('a commit with nothing to send names no counts', () {
      expect(
        gitHubRateLimitedMessage(limited(held: 0, total: 0)),
        'GitHub limits how much one account can upload in an hour, and it '
        'paused this upload. Nothing on your site has changed yet. Publish '
        'again in about an hour.',
      );
    });

    test('held back by Pitak: says nothing was sent and the pause left', () {
      expect(
        gitHubRateLimitedMessage(
          limited(
            held: 3,
            total: 5,
            wait: const Duration(minutes: 3, seconds: 10),
            refusedNow: false,
          ),
        ),
        'GitHub asked Pitak to wait before uploading again, so nothing was '
        'sent this time. 3 of 5 files are already on GitHub and will not be '
        'sent again. Nothing on your site has changed yet. Publish again in '
        'about 4 minutes to send the rest.',
      );
    });

    test('the pause is rounded to whole minutes, at most an hour', () {
      String when(Duration? wait) => gitHubRateLimitedMessage(
        limited(held: 0, total: 0, wait: wait, refusedNow: false),
      );
      expect(when(const Duration(seconds: 20)), endsWith('about a minute.'));
      expect(when(const Duration(minutes: 1)), endsWith('about a minute.'));
      expect(when(const Duration(minutes: 49)), endsWith('about 49 minutes.'));
      expect(when(const Duration(minutes: 50)), endsWith('about an hour.'));
      expect(when(null), endsWith('about an hour.'));
    });

    test('a move and a retirement name their own next step', () {
      expect(
        gitHubRateLimitedMessage(
          limited(held: 2, total: 9),
          operation: GitHubLimitedOperation.move,
        ),
        endsWith(
          'Your current site was not changed. Choose Move to other host again '
          'in about an hour to send the rest.',
        ),
      );
      expect(
        gitHubRateLimitedMessage(
          limited(held: 0, total: 1),
          operation: GitHubLimitedOperation.retirement,
        ),
        endsWith(
          'Your old address was not changed yet. Retry the pending move in '
          'about an hour.',
        ),
      );
    });

    test('impossible counts are clamped, never shown as written', () {
      expect(
        gitHubRateLimitedMessage(limited(held: 9, total: 4)),
        contains('4 of 4 files'),
      );
      expect(
        gitHubRateLimitedMessage(limited(held: -3, total: 4)),
        contains('0 of 4 files'),
      );
      expect(
        gitHubRateLimitedMessage(limited(held: 1, total: -1)),
        isNot(contains(' of ')),
      );
    });

    test('the lane sentence carries no time (the row adds "Next try at")', () {
      expect(gitHubPausedMessage, isNot(matches(RegExp(r'\d'))));
    });
  });
}
