import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/github_branch_name.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/move_plan.dart';
import 'package:pitaka/features/publish/domain/site/pending_move.dart';
import 'package:pitaka/features/publish/domain/site/publish_host_state.dart';
import 'package:pitaka/features/publish/domain/site/publish_marker.dart';

void main() {
  final github = GitHubPublishTarget.create('me/lib')!;
  final cloudflare = CloudflarePublishTarget.create(
    accountId: '0123456789abcdef0123456789abcdef',
    workerName: 'library',
    accountSubdomain: 'kadugodi',
  )!;
  final head = 'a' * 40;
  final liveId = 'b' * 32;
  final retiredMarker = PublishMarker(
    publishId: 'c' * 32,
    publishedAt: 123,
    state: PublishMarkerState.retired,
  );
  final page = utf8.encode('<html>moved</html>');

  MoveSourceAnchor githubAnchor() => MoveSourceAnchor.tryCreate(
    source: github,
    value: head,
    branch: GitHubBranchName.tryParse('main'),
    ownedPaths: const [
      'index.html',
      'books.json',
      'events.json',
      'covers/a.jpg',
    ],
  )!;

  MoveSourceAnchor cloudflareAnchor() => MoveSourceAnchor.tryCreate(
    source: cloudflare,
    value: liveId,
    ownedPaths: const ['index.html', 'books.json', 'pitak-publish.json'],
  )!;

  PendingMove githubMove() => PendingMove.tryCreate(
    oldTarget: github,
    newTarget: cloudflare,
    sourceAnchor: githubAnchor(),
    indexHtml: page,
    notFoundHtml: page,
    libraryName: 'Test Library',
  )!;

  test('a GitHub pending move persists exact branch and owned deletions', () {
    final pending = githubMove();
    final plan = MovePlan.forGitHub(pending)!;

    expect(pending.phase, PendingMovePhase.retirementPending);
    expect(pending.retirement.sourceBranch?.value, 'main');
    expect(plan.files.map((file) => file.path), ['index.html', '404.html']);
    expect(plan.deletePaths, ['books.json', 'covers/a.jpg', 'events.json']);
    expect(plan.fileShas.keys, {'index.html', '404.html'});
  });

  test('a Cloudflare pending move requires a fresh retired marker', () {
    final pending = PendingMove.tryCreate(
      oldTarget: cloudflare,
      newTarget: github,
      sourceAnchor: cloudflareAnchor(),
      indexHtml: page,
      notFoundHtml: page,
      libraryName: 'Test Library',
      retirementMarker: retiredMarker,
    );

    expect(pending, isNotNull);
    expect(pending!.retirement.marker, same(retiredMarker));
    expect(pending.retirement.deletePaths, isEmpty);
    expect(MovePlan.forGitHub(pending), isNull);
    expect(
      PendingMove.tryCreate(
        oldTarget: cloudflare,
        newTarget: github,
        sourceAnchor: cloudflareAnchor(),
        indexHtml: page,
        notFoundHtml: page,
        libraryName: 'Test Library',
      ),
      isNull,
    );
  });

  test('same-host moves and malformed source evidence are refused', () {
    expect(
      PendingMove.tryCreate(
        oldTarget: github,
        newTarget: GitHubPublishTarget.create('me/other')!,
        sourceAnchor: githubAnchor(),
        indexHtml: page,
        notFoundHtml: page,
        libraryName: 'Test Library',
      ),
      isNull,
    );
    expect(
      MoveSourceAnchor.tryCreate(
        source: github,
        value: 'not-a-head',
        branch: GitHubBranchName.tryParse('main'),
        ownedPaths: const ['index.html', 'books.json'],
      ),
      isNull,
    );
    expect(
      MoveSourceAnchor.tryCreate(
        source: cloudflare,
        value: liveId,
        ownedPaths: const ['index.html', '../books.json'],
      ),
      isNull,
    );
  });

  test('pending keeps the old share target until one final switch', () {
    final live = PublishHostState.empty.afterVerifiedPublish(github);
    final pendingState = live.beginMove(githubMove())!;

    expect(pendingState.isConsistent, isTrue);
    expect(pendingState.verifiedTarget?.targetId, github.targetId);
    expect(
      pendingState.afterVerifiedPublish(cloudflare).pendingMove,
      isNotNull,
    );
    expect(
      pendingState.afterVerifiedPublish(cloudflare).verifiedTarget?.targetId,
      github.targetId,
    );

    final finished = pendingState.finishMove(githubMove())!;
    expect(finished.activeHost, cloudflare.host);
    expect(finished.verifiedTarget?.targetId, cloudflare.targetId);
    expect(finished.pendingMove, isNull);
  });

  test('a pending record with a different verified source is inconsistent', () {
    final other = PublishHostState.empty
        .afterVerifiedPublish(GitHubPublishTarget.create('me/other')!)
        .beginMove(githubMove());
    expect(other, isNull);
  });
}
