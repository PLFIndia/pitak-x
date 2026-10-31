import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/infrastructure/moved_html_builder.dart';

/// The moved-page template is FROZEN per schema (fix-plan L11).
///
/// A pending move stores the exact bytes it will upload and re-renders them on
/// every Retry. If a later build edits the schema-1 asset (or the renderer's
/// escaping/name handling), an older install could never reproduce those bytes
/// and the user would be stuck with a half-finished move.
///
/// When this test fails, do NOT update the values: add `moved_v2.html`, map it
/// to schema 2, and bump `RetirementDescriptor.currentMovedPageSchema`.
const String _failedMessage =
    'The schema-1 moved page changed. Add `moved_v2.html` and bump the schema '
    'instead of editing the frozen template.';

void main() {
  // The builder loads assets/publish/moved.html through rootBundle.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the schema-1 template asset is byte-frozen', () async {
    final bytes = await File('assets/publish/moved.html').readAsBytes();

    expect(
      sha256.convert(bytes).toString(),
      '641328c43c2d1541f842ae2033a76cfc4d7e3dd71ac7d5ef8a218be071137883',
      reason: _failedMessage,
    );
  });

  test('one schema-1 rendering is byte-frozen', () async {
    final target = GitHubPublishTarget.create('me/library')!;
    final rendered = await MovedHtmlBuilder(
      libraryName: 'My Library',
      newTarget: target,
    ).build();

    expect(
      sha256.convert(rendered).toString(),
      'a611760269b416c4488999919ad8a37b86d944c47ab13c4a5bbddcbe91e3f1e3',
      reason: _failedMessage,
    );
  });

  test('the template map names one frozen asset per schema', () {
    expect(MovedHtmlBuilder.templates, {1: 'assets/publish/moved.html'});
    expect(
      MovedHtmlBuilder.templates[MovedHtmlBuilder.currentSchema],
      'assets/publish/moved.html',
    );
  });

  test('an unknown schema renders nothing', () {
    expect(
      MovedHtmlBuilder.render(
        schema: 2,
        template: '<p>{{LIBRARY_NAME}}</p>',
        libraryName: 'Library',
        newTarget: GitHubPublishTarget.create('me/library')!,
      ),
      isNull,
    );
  });

  test(
    'the renderer reproduces a stored name exactly, without re-normalizing',
    () {
      // The normalizer runs once when the pending record is created.
      // Applying it again during Retry would change bytes for a name the
      // stored document already contains (M9/L11).
      final rendered = MovedHtmlBuilder.render(
        schema: 1,
        template: '<p>{{LIBRARY_NAME}}</p>',
        libraryName: '  My Library  ',
        newTarget: GitHubPublishTarget.create('me/library')!,
      );

      expect(utf8.decode(rendered!), '<p>  My Library  </p>');
    },
  );
}
