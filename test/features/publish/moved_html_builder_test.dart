import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/infrastructure/moved_html_builder.dart';

import 'support/move_fakes.dart';

void main() {
  // The builder loads assets/publish/moved.html through rootBundle.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('escapes hostile library names without raw markup', () async {
    const hostile = '<script>alert("moved")</script>&\'"';
    const escaped =
        '&lt;script&gt;alert(&quot;moved&quot;)&lt;/script&gt;&amp;&#39;&quot;';

    final html = utf8.decode(
      await MovedHtmlBuilder(
        libraryName: hostile,
        newTarget: GitHubPublishTarget.create('me/library')!,
      ).build(),
    );

    expect(html, contains('<title>$escaped has moved</title>'));
    expect(html, contains('<h1>$escaped has moved</h1>'));
    expect(html, isNot(contains(hostile)));
    expect(html, isNot(contains('<script>alert(')));
    expect(html, isNot(contains('alert("moved")')));
  });

  test('uses each sealed target exact URL in the link and refresh', () async {
    final targets = <PublishTarget>[
      GitHubPublishTarget.create('me/MyShelf')!,
      CloudflarePublishTarget.create(
        accountId: '0123456789abcdef0123456789abcdef',
        workerName: 'Kadugodi-Library',
        accountSubdomain: 'Kadugodi',
      )!,
    ];

    for (final target in targets) {
      final destination = target.siteUrl;
      final html = utf8.decode(
        await MovedHtmlBuilder(
          libraryName: 'Library',
          newTarget: target,
        ).build(),
      );

      expect(
        html,
        contains(
          '<meta http-equiv="refresh" '
          'content="5; url=$destination" />',
        ),
      );
      expect(html, contains('<a href="$destination">$destination</a>'));
    }
  });

  test(
    'pins the moved-page security metadata and static-only content',
    () async {
      const supportedCsp = "default-src 'none'; style-src 'unsafe-inline'";
      final html = utf8.decode(
        await MovedHtmlBuilder(
          libraryName: 'Library',
          newTarget: GitHubPublishTarget.create('me/library')!,
        ).build(),
      );

      expect(
        html,
        contains(
          '<meta http-equiv="Content-Security-Policy" '
          'content="$supportedCsp" />',
        ),
      );
      expect(
        RegExp('http-equiv="Content-Security-Policy"').allMatches(html),
        hasLength(1),
      );
      expect(html, contains('<meta name="robots" content="noindex" />'));
      expect(html, contains('<meta http-equiv="refresh" content="5; url='));
      expect(html, isNot(contains('<script')));
      expect(html, isNot(contains('application/ld+json')));
      expect(html, isNot(contains('movedTo')));
    },
  );

  test('loads the template and replaces every placeholder as UTF-8', () async {
    final html = utf8.decode(
      await MovedHtmlBuilder(
        libraryName: 'കേരളം & Co',
        newTarget: GitHubPublishTarget.create('me/library')!,
      ).build(),
    );

    expect(html, contains('കേരളം &amp; Co'));
    expect(html, isNot(contains('{{LIBRARY_NAME}}')));
    expect(html, isNot(contains('{{NEW_SITE_URL}}')));
    expect(html, isNot(contains(RegExp(r'\{\{[A-Z0-9_]+\}\}'))));
  });

  test('blank library names use the existing safe fallback', () async {
    for (final blank in <String>['', ' \t\n']) {
      final html = utf8.decode(
        await MovedHtmlBuilder(
          libraryName: blank,
          newTarget: GitHubPublishTarget.create('me/library')!,
        ).build(),
      );

      expect(html, contains('<title>My Library has moved</title>'));
      expect(html, contains('<h1>My Library has moved</h1>'));
    }
  });

  group('validatePending authenticates persisted bytes', () {
    test('the exact schema-1 rendering of the stored name passes', () async {
      final bytes = await MovedHtmlBuilder(
        libraryName: 'My Library',
        newTarget: moveCloudflareTarget,
      ).build();
      final pending = movePending(
        oldTarget: moveGitHubTarget,
        newTarget: moveCloudflareTarget,
        indexHtml: bytes,
      );

      expect(await MovedHtmlBuilder.validatePending(pending), isTrue);
    });

    test('a different stored name no longer matches the bytes', () async {
      final bytes = await MovedHtmlBuilder(
        libraryName: 'My Library',
        newTarget: moveCloudflareTarget,
      ).build();
      final pending = movePending(
        oldTarget: moveGitHubTarget,
        newTarget: moveCloudflareTarget,
        indexHtml: bytes,
        libraryName: 'Another Library',
      );

      expect(await MovedHtmlBuilder.validatePending(pending), isFalse);
    });

    test('an unknown renderer schema is refused', () async {
      final bytes = await MovedHtmlBuilder(
        libraryName: 'My Library',
        newTarget: moveCloudflareTarget,
      ).build();
      final pending = movePending(
        oldTarget: moveGitHubTarget,
        newTarget: moveCloudflareTarget,
        indexHtml: bytes,
        movedPageSchema: 2,
      );

      expect(await MovedHtmlBuilder.validatePending(pending), isFalse);
    });
  });
}
