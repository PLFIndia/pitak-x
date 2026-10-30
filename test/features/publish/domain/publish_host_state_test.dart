import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/publish_host.dart';
import 'package:pitaka/features/publish/domain/site/publish_host_state.dart';

import '../support/move_fakes.dart';

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

  group('abandonMove (fix-plan M4)', () {
    PublishHostState pendingState() => PublishHostState(
      activeHost: PublishHost.github,
      verifiedTarget: moveGitHubTarget,
    ).beginMove(movePending(oldTarget: moveGitHubTarget))!;

    test('clears the pending move and keeps both journal facts', () {
      final state = pendingState();

      final abandoned = state.abandonMove(state.pendingMove!)!;

      expect(abandoned.pendingMove, isNull);
      expect(abandoned.activeHost, PublishHost.github);
      expect(abandoned.verifiedTarget!.targetId, moveGitHubTarget.targetId);
      expect(abandoned.isConsistent, isTrue);
    });

    test('a repeat is a no-op success', () {
      final state = pendingState();
      final pending = state.pendingMove!;
      final abandoned = state.abandonMove(pending)!;

      expect(identical(abandoned.abandonMove(pending), abandoned), isTrue);
    });

    test('refuses a different pending operation', () {
      final state = pendingState();
      final other = movePending(
        oldTarget: moveGitHubTarget,
        libraryName: 'Another Library',
      );

      expect(state.abandonMove(other), isNull);
    });

    test('refuses an inconsistent record', () {
      final state = PublishHostState(
        activeHost: PublishHost.github,
        verifiedTarget: moveGitHubTarget,
        pendingMove: movePending(oldTarget: moveGitHubTarget),
      );
      // A pending move whose old target is not the verified one is corrupt.
      expect(state.isConsistent, isTrue);
      final corrupt = PublishHostState(
        activeHost: PublishHost.cloudflare,
        verifiedTarget: moveGitHubTarget,
        pendingMove: movePending(oldTarget: moveGitHubTarget),
      );
      expect(corrupt.abandonMove(corrupt.pendingMove!), isNull);
    });
  });
}
