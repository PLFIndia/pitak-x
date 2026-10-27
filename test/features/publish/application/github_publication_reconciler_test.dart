import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/github_publication_reconciler.dart';
import 'package:pitaka/features/publish/domain/github_api.dart';
import 'package:pitaka/features/publish/domain/github_error_messages.dart';
import 'package:pitaka/features/publish/domain/github_models.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';

class _Api implements GitHubGitDataApi {
  _Api({this.snapshot, this.throwOnTree = false});

  final GitHubTreeSnapshot? snapshot;
  final bool throwOnTree;
  int treeReads = 0;
  String? readBranch;

  @override
  Future<GitHubTreeSnapshot> headTree({
    required String owner,
    required String repo,
    required String branch,
    required String token,
  }) async {
    treeReads++;
    readBranch = branch;
    if (throwOnTree) throw const GitHubApiException('boom');
    return snapshot!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected GitHub operation: $invocation');
}

GitHubTreeSnapshot snapshot({
  Map<String, String> files = const {'books.json': 'sha-books'},
  String head = 'head-a',
  String branch = 'main',
  bool truncated = false,
}) => GitHubTreeSnapshot(
  repo: 'me/lib',
  branch: branch,
  headSha: head,
  files: files,
  truncated: truncated,
);

void main() {
  final target = GitHubPublishTarget.create('me/lib')!;

  test('returns the reconciled record and the head it read', () async {
    final api = _Api(
      snapshot: snapshot(
        files: {'books.json': 'sha-books', 'covers/1.jpg': 'sha-cover'},
      ),
    );
    final result = await GitHubPublicationReconciler(api).call(
      target: target,
      branch: 'main',
      token: 'TKN',
      local: const PublishManifest(
        repo: 'me/lib',
        branch: 'main',
        fileShas: {'books.json': 'stale', 'covers/1.jpg': 'sha-cover'},
      ),
    );

    final publication = result.toNullable()!;
    expect(publication.headSha, 'head-a');
    expect(publication.manifest.shaFor('books.json'), 'sha-books');
    expect(api.readBranch, 'main');
  });

  test('an unreadable tree is a typed failure with a fixed message', () async {
    final result = await GitHubPublicationReconciler(_Api(throwOnTree: true))
        .call(
          target: target,
          branch: 'main',
          token: 'TKN',
          local: PublishManifest.empty,
        );

    expect(result.isLeft(), isTrue);
    expect(
      (result.swap().toNullable()! as ValidationFailure).message,
      gitHubSiteStateUnreadableMessage,
    );
  });

  test(
    'a truncated tree refuses with the repository-too-large message',
    () async {
      final result =
          await GitHubPublicationReconciler(
            _Api(snapshot: snapshot(truncated: true)),
          ).call(
            target: target,
            branch: 'main',
            token: 'TKN',
            local: PublishManifest.empty,
          );

      expect(result.isLeft(), isTrue);
      expect(
        (result.swap().toNullable()! as ValidationFailure).message,
        gitHubTreeTooLargeMessage,
      );
    },
  );
}
