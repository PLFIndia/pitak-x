import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/publish_host.dart';

/// SPECIFICATION of the sealed publish target (Cloudflare plan R1/C3, J.1).
///
/// The point of these tests: an address can only exist if its parts were
/// valid. There is no constructor that takes a host + URL, so "publish to
/// https://evil.example/" has no representation at all.
void main() {
  group('GitHubPublishTarget is derived, never supplied', () {
    test('a project site resolves to owner.github.io/repo/', () {
      final target = GitHubPublishTarget.create('me/lib')!;

      expect(target.ownerRepo, 'me/lib');
      expect(target.owner, 'me');
      expect(target.repo, 'lib');
      expect(target.siteUrl, 'https://me.github.io/lib/');
      expect(target.targetId, 'github:me/lib');
    });

    test('a user site resolves to the account ROOT (no repo path)', () {
      final target = GitHubPublishTarget.create('me/me.github.io')!;

      expect(target.siteUrl, 'https://me.github.io/');
    });

    test('the host is lower-cased but the repo path keeps its case', () {
      // GitHub serves every login lower-cased; a Pages path is case-sensitive.
      expect(
        GitHubPublishTarget.create('Me/MyShelf')!.siteUrl,
        'https://me.github.io/MyShelf/',
      );
    });

    for (final hostile in <String?>[
      null,
      '',
      '/',
      'me',
      'me/',
      '/lib',
      'me/lib/extra',
      'me/../lib',
      'me/./lib',
      'evil.example/repo',
      'me/repo?x=1',
      'me/repo#frag',
      'me/re po',
      'me/https://evil.example',
      // An owner may not start with '-' (GitHub login rule). A repo MAY (its
      // charset allows a leading '-'), so that is deliberately not refused.
      '-me/lib',
      'https://evil.example/',
    ]) {
      test('a non-target "$hostile" is refused', () {
        expect(GitHubPublishTarget.create(hostile), isNull);
      });
    }

    test('two targets are the same when their targetId matches', () {
      final a = GitHubPublishTarget.create('me/lib')!;
      final b = GitHubPublishTarget.create('me/lib')!;
      final other = GitHubPublishTarget.create('me/other')!;

      expect(a.isSameTarget(b), isTrue);
      expect(a.isSameTarget(other), isFalse);
    });

    test('a target never renders a secret or an arbitrary URL', () {
      final target = GitHubPublishTarget.create('me/lib')!;

      // toString is safe to log: it names the target, nothing else.
      expect(target.toString(), 'GitHubPublishTarget(me/lib)');
      expect(target.siteUrl, startsWith('https://me.github.io/'));
    });
  });

  group('CloudflarePublishTarget is derived, never supplied', () {
    final target = CloudflarePublishTarget.create(
      accountId: '0123456789abcdef0123456789abcdef',
      workerName: 'Kadugodi-Library',
      accountSubdomain: 'Kadugodi',
    )!;

    test('the address comes from the parts, lower-cased for DNS', () {
      expect(target.host, PublishHost.cloudflare);
      expect(target.siteUrl, 'https://kadugodi-library.kadugodi.workers.dev/');
      expect(target.workerName.value, 'Kadugodi-Library');
      expect(target.accountSubdomain.value, 'kadugodi');
    });

    test('identity is the account plus the Worker name', () {
      expect(
        target.targetId,
        'cloudflare:0123456789abcdef0123456789abcdef:Kadugodi-Library',
      );
      expect(
        target.isSameTarget(
          CloudflarePublishTarget.create(
            accountId: '0123456789abcdef0123456789abcdef',
            workerName: 'Kadugodi-Library',
            accountSubdomain: 'kadugodi',
          )!,
        ),
        isTrue,
      );
      expect(
        target.isSameTarget(
          CloudflarePublishTarget.create(
            accountId: '0123456789abcdef0123456789abcdef',
            workerName: 'other',
            accountSubdomain: 'kadugodi',
          )!,
        ),
        isFalse,
      );
    });

    test('a target never renders a secret', () {
      expect(
        target.toString(),
        'CloudflarePublishTarget('
        'https://kadugodi-library.kadugodi.workers.dev/)',
      );
    });

    for (final parts in <({String? account, String? worker, String? sub})>[
      (account: null, worker: 'lib', sub: 'name'),
      (account: '0123456789abcdef0123456789abcdef', worker: null, sub: 'name'),
      (account: '0123456789abcdef0123456789abcdef', worker: 'lib', sub: null),
      (account: 'not-hex', worker: 'lib', sub: 'name'),
      (
        account: '0123456789abcdef0123456789abcdef',
        worker: 'li b',
        sub: 'name',
      ),
      (
        account: '0123456789abcdef0123456789abcdef',
        worker: 'lib',
        sub: 'na me',
      ),
      (account: '0123456789abcdef0123456789abcdef', worker: 'lib', sub: 'a.b'),
    ]) {
      test('refuses $parts', () {
        expect(
          CloudflarePublishTarget.create(
            accountId: parts.account,
            workerName: parts.worker,
            accountSubdomain: parts.sub,
          ),
          isNull,
        );
      });
    }
  });
}
