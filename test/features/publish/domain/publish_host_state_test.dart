import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/publish_host_state.dart';

void main() {
  final github = GitHubPublishTarget.create('me/lib')!;

  test('the empty record proves nothing', () {
    expect(PublishHostState.empty.activeHost, isNull);
    expect(PublishHostState.empty.verifiedSiteUrl, isNull);
    expect(PublishHostState.empty.isConsistent, isTrue);
  });

  // R33: the share address exists only after a read-back proved the site.
  test('a verified publish sets the active host and the address', () {
    final state = PublishHostState.empty.afterVerifiedPublish(github);
    expect(state.activeHost, github.host);
    expect(state.verifiedSiteUrl, 'https://me.github.io/lib/');
    expect(state.verifiedTarget!.targetId, 'github:me/lib');
    expect(state.isConsistent, isTrue);
  });

  test('verifies() recognises the same target only', () {
    final state = PublishHostState.empty.afterVerifiedPublish(github);
    expect(state.verifies(github), isTrue);
    expect(state.verifies(GitHubPublishTarget.create('me/other')!), isFalse);
  });

  test('a verified target with no active host is inconsistent', () {
    expect(PublishHostState.empty.isConsistent, isTrue);
    // A record like this can only come from a corrupted/forged file: a target
    // is written together with its host, never alone.
    expect(PublishHostState(verifiedTarget: github).isConsistent, isFalse);
  });
}
