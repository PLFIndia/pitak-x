import 'package:flutter_test/flutter_test.dart';
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
}
