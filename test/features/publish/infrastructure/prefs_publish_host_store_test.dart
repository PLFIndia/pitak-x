import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/publish_host.dart';
import 'package:pitaka/features/publish/domain/site/publish_host_state.dart';
import 'package:pitaka/features/publish/infrastructure/prefs_publish_host_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final github = GitHubPublishTarget.create('me/lib')!;

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<PrefsPublishHostStore> store() async =>
      PrefsPublishHostStore(await SharedPreferences.getInstance());

  test('saves and loads the verified target', () async {
    final hostStore = await store();
    final saved = await hostStore.save(
      PublishHostState.empty.afterVerifiedPublish(github),
    );
    expect(saved.isRight(), isTrue);

    // A FRESH store (as after an app restart) reads the same facts.
    final loaded = (await store()).load().toNullable()!;
    expect(loaded.activeHost, github.host);
    expect(loaded.verifiedSiteUrl, 'https://me.github.io/lib/');
    expect(loaded.verifiedTarget!.targetId, 'github:me/lib');
  });

  test('an absent record is null, not an empty claim', () async {
    expect((await store()).load().toNullable(), isNull);
  });

  test('corrupt JSON is a typed unreadable record', () async {
    SharedPreferences.setMockInitialValues({
      PrefsPublishHostStore.key: '{"schema":1,"activeHost":',
    });
    expect((await store()).load().isLeft(), isTrue);
  });

  test('an unknown schema is unreadable (fail closed)', () async {
    SharedPreferences.setMockInitialValues({
      PrefsPublishHostStore.key: jsonEncode({
        'schema': 99,
        'activeHost': 'github',
      }),
    });
    expect((await store()).load().isLeft(), isTrue);
  });

  // C3: the address is DERIVED from the identity. A file that stores another
  // URL for the same repo is not an address to trust.
  test('a stored URL that disagrees with the derived one is refused', () async {
    SharedPreferences.setMockInitialValues({
      PrefsPublishHostStore.key: jsonEncode({
        'schema': 1,
        'activeHost': 'github',
        'verifiedTarget': {
          'host': 'github',
          'repo': 'me/lib',
          'targetId': 'github:me/lib',
          'siteUrl': 'https://evil.example/',
        },
      }),
    });
    final loaded = (await store()).load().toNullable()!;
    expect(loaded.activeHost, github.host);
    expect(loaded.verifiedTarget, isNull);
    expect(loaded.verifiedSiteUrl, isNull);
  });

  test('a target from another host is dropped, never adopted', () async {
    SharedPreferences.setMockInitialValues({
      PrefsPublishHostStore.key: jsonEncode({
        'schema': 1,
        'activeHost': 'cloudflare',
        'verifiedTarget': {
          'host': 'github',
          'repo': 'me/lib',
          'targetId': 'github:me/lib',
          'siteUrl': 'https://me.github.io/lib/',
        },
      }),
    });
    final loaded = (await store()).load().toNullable()!;
    expect(loaded.activeHost, PublishHost.cloudflare);
    expect(loaded.verifiedTarget, isNull);
  });

  test('a Cloudflare target round-trips through its identity parts', () async {
    final cloudflare = CloudflarePublishTarget.create(
      accountId: '0123456789abcdef0123456789abcdef',
      workerName: 'kadugodi-library',
      accountSubdomain: 'kadugodi',
    )!;
    final hostStore = await store();
    await hostStore.save(
      PublishHostState.empty.afterVerifiedPublish(cloudflare),
    );

    final loaded = (await store()).load().toNullable()!;

    expect(loaded.activeHost, PublishHost.cloudflare);
    expect(
      loaded.verifiedSiteUrl,
      'https://kadugodi-library.kadugodi.workers.dev/',
    );
    expect(
      loaded.verifiedTarget!.targetId,
      'cloudflare:0123456789abcdef0123456789abcdef:kadugodi-library',
    );
  });

  test('a Cloudflare record with a forged URL is refused', () async {
    SharedPreferences.setMockInitialValues({
      PrefsPublishHostStore.key: jsonEncode({
        'schema': 1,
        'activeHost': 'cloudflare',
        'verifiedTarget': {
          'host': 'cloudflare',
          'accountId': '0123456789abcdef0123456789abcdef',
          'workerName': 'kadugodi-library',
          'accountSubdomain': 'kadugodi',
          'targetId':
              'cloudflare:0123456789abcdef0123456789abcdef:kadugodi-library',
          'siteUrl': 'https://evil.example/',
        },
      }),
    });
    final loaded = (await store()).load().toNullable()!;
    // The configured host is a fact worth keeping; the address is not proven.
    expect(loaded.activeHost, PublishHost.cloudflare);
    expect(loaded.verifiedTarget, isNull);
  });

  test('a Cloudflare record missing an identity part is refused', () async {
    SharedPreferences.setMockInitialValues({
      PrefsPublishHostStore.key: jsonEncode({
        'schema': 1,
        'activeHost': 'cloudflare',
        'verifiedTarget': {
          'host': 'cloudflare',
          'accountId': '0123456789abcdef0123456789abcdef',
          'workerName': 'kadugodi-library',
          'siteUrl': 'https://kadugodi-library.kadugodi.workers.dev/',
        },
      }),
    });
    final loaded = (await store()).load().toNullable()!;
    expect(loaded.verifiedTarget, isNull);
  });

  test('the stored record carries no token or credential', () async {
    final hostStore = await store();
    await hostStore.save(PublishHostState.empty.afterVerifiedPublish(github));
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(PrefsPublishHostStore.key)!;
    for (final forbidden in ['token', 'secret', 'credential', 'bearer']) {
      expect(raw.toLowerCase(), isNot(contains(forbidden)));
    }
  });
}
