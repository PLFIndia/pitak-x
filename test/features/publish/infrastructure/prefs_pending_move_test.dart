import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/github_branch_name.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/pending_move.dart';
import 'package:pitaka/features/publish/domain/site/publish_host_state.dart';
import 'package:pitaka/features/publish/domain/site/publish_marker.dart';
import 'package:pitaka/features/publish/infrastructure/prefs_publish_host_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final github = GitHubPublishTarget.create('me/lib')!;
  final cloudflare = CloudflarePublishTarget.create(
    accountId: '0123456789abcdef0123456789abcdef',
    workerName: 'library',
    accountSubdomain: 'kadugodi',
  )!;
  final page = utf8.encode('<html>moved</html>');

  PendingMove pending() => PendingMove.tryCreate(
    oldTarget: github,
    newTarget: cloudflare,
    sourceAnchor: MoveSourceAnchor.tryCreate(
      source: github,
      value: 'a' * 40,
      branch: GitHubBranchName.tryParse('main'),
      ownedPaths: const ['index.html', 'books.json', 'covers/a.jpg'],
    )!,
    indexHtml: page,
    notFoundHtml: page,
    libraryName: 'Test Library',
  )!;

  Future<PrefsPublishHostStore> store() async =>
      PrefsPublishHostStore(await SharedPreferences.getInstance());

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the complete pending operation round-trips after a restart', () async {
    final live = PublishHostState.empty.afterVerifiedPublish(github);
    final pendingState = live.beginMove(pending())!;
    expect((await (await store()).save(pendingState)).isRight(), isTrue);

    final loaded = (await store()).load().toNullable()!;
    final restored = loaded.pendingMove!;
    expect(loaded.verifiedTarget?.targetId, github.targetId);
    expect(restored.oldTarget.targetId, github.targetId);
    expect(restored.newTarget.targetId, cloudflare.targetId);
    expect(restored.sourceAnchor.value, 'a' * 40);
    expect(restored.sourceAnchor.branch?.value, 'main');
    expect(restored.retirement.deletePaths, ['books.json', 'covers/a.jpg']);
    expect(restored.retirement.indexHtml, page);
    expect(restored.retirement.notFoundHtml, page);

    final finished = loaded.finishMove(loaded.pendingMove!)!;
    await (await store()).save(finished);
    final afterFinish = (await store()).load().toNullable()!;
    expect(afterFinish.verifiedTarget?.targetId, cloudflare.targetId);
    expect(afterFinish.pendingMove, isNull);
  });

  test('Cloudflare retirement marker data round-trips exactly', () async {
    final marker = PublishMarker(
      publishId: 'c' * 32,
      publishedAt: 1234,
      state: PublishMarkerState.retired,
    );
    final pendingCf = PendingMove.tryCreate(
      oldTarget: cloudflare,
      newTarget: github,
      sourceAnchor: MoveSourceAnchor.tryCreate(
        source: cloudflare,
        value: 'b' * 32,
        ownedPaths: const ['index.html', 'books.json', 'pitak-publish.json'],
      )!,
      indexHtml: page,
      notFoundHtml: page,
      libraryName: 'Test Library',
      retirementMarker: marker,
    )!;
    final state = PublishHostState.empty
        .afterVerifiedPublish(cloudflare)
        .beginMove(pendingCf)!;
    await (await store()).save(state);

    final restored = (await store()).load().toNullable()!.pendingMove!;
    expect(restored.retirement.marker?.publishId, marker.publishId);
    expect(restored.retirement.marker?.publishedAt, marker.publishedAt);
    expect(restored.retirement.marker?.state, PublishMarkerState.retired);
  });

  test(
    'a malformed pending record is never reduced to no pending move',
    () async {
      final live = PublishHostState.empty.afterVerifiedPublish(github);
      await (await store()).save(live.beginMove(pending())!);
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(PrefsPublishHostStore.key)!;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      (decoded['pendingMove'] as Map<String, dynamic>)['indexHtml'] = '%bad%';
      SharedPreferences.setMockInitialValues({
        PrefsPublishHostStore.key: jsonEncode(decoded),
      });

      expect((await store()).load().isLeft(), isTrue);
    },
  );

  test('pending serialization contains no credential material', () async {
    final live = PublishHostState.empty.afterVerifiedPublish(github);
    await (await store()).save(live.beginMove(pending())!);
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(PrefsPublishHostStore.key)!.toLowerCase();

    for (final forbidden in ['token', 'jwt', 'secret', 'bearer']) {
      expect(raw, isNot(contains(forbidden)));
    }
  });
}
