import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/github_oauth_app.dart';

void main() {
  group('safeGithubVerificationUri (hostile-input gate for launchUrl)', () {
    test('accepts the canonical device-flow URL', () {
      final uri = safeGithubVerificationUri('https://github.com/login/device');
      expect(uri, isNotNull);
      expect(uri!.host, 'github.com');
    });

    test('accepts a github.com subdomain over https', () {
      expect(safeGithubVerificationUri('https://gist.github.com/x'), isNotNull);
    });

    test('rejects http (no TLS)', () {
      expect(
        safeGithubVerificationUri('http://github.com/login/device'),
        isNull,
      );
    });

    test('rejects a lookalike host', () {
      expect(
        safeGithubVerificationUri('https://github.com.evil.example/login'),
        isNull,
      );
      expect(safeGithubVerificationUri('https://evilgithub.com/'), isNull);
    });

    test('rejects non-http schemes that could reach other apps', () {
      expect(safeGithubVerificationUri('intent://github.com#Intent'), isNull);
      expect(safeGithubVerificationUri('javascript:alert(1)'), isNull);
      expect(safeGithubVerificationUri('file:///etc/passwd'), isNull);
    });

    test('rejects empty and garbage input', () {
      expect(safeGithubVerificationUri(''), isNull);
      expect(safeGithubVerificationUri('::not a uri::'), isNull);
    });
  });
}
