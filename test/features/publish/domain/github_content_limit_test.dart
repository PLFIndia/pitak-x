import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/github_content_limit.dart';

/// Plan J8: the pacing constant and the pause rule GitHub's REST docs ask
/// for ("honour retry-after; otherwise wait at least a minute, longer each
/// time").
void main() {
  Duration pause(Duration? hint, int refusals) =>
      GitHubContentLimit.pauseAfterRefusal(
        serverHint: hint,
        consecutiveRefusals: refusals,
      );

  test('pacing keeps blob requests at or under 60 a minute (GitHub allows '
      '80)', () {
    expect(GitHubContentLimit.blobSpacing, const Duration(seconds: 1));
    expect(
      const Duration(minutes: 1).inMilliseconds ~/
          GitHubContentLimit.blobSpacing.inMilliseconds,
      lessThanOrEqualTo(80 - 3),
    );
  });

  test('without a hint the pause doubles: 1, 2, 4, 8 … minutes, up to an '
      'hour', () {
    expect(pause(null, 1), const Duration(minutes: 1));
    expect(pause(null, 2), const Duration(minutes: 2));
    expect(pause(null, 3), const Duration(minutes: 4));
    expect(pause(null, 4), const Duration(minutes: 8));
    expect(pause(null, 6), const Duration(minutes: 32));
    expect(pause(null, 7), const Duration(hours: 1));
    expect(pause(null, 100), const Duration(hours: 1));
  });

  test('a longer server hint wins over the backoff', () {
    expect(pause(const Duration(minutes: 10), 1), const Duration(minutes: 10));
  });

  test(
    'a shorter hint never shortens the backoff or the documented minimum',
    () {
      expect(pause(const Duration(seconds: 5), 1), const Duration(minutes: 1));
      expect(pause(const Duration(seconds: 30), 3), const Duration(minutes: 4));
      expect(pause(Duration.zero, 1), const Duration(minutes: 1));
    },
  );

  test('a hostile or huge hint is cut to the hourly window', () {
    expect(pause(const Duration(days: 365), 1), const Duration(hours: 1));
  });

  test('a damaged count (zero or negative) reads as the first refusal', () {
    expect(pause(null, 0), const Duration(minutes: 1));
    expect(pause(null, -5), const Duration(minutes: 1));
  });
}
