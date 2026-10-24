import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/publish/domain/publish_export.dart';
import 'package:pitaka/features/publish/domain/publish_redaction.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() {
    temporaryDirectory = Directory.systemTemp.createTempSync(
      'pitaka-viewer-runtime-',
    );
  });

  tearDown(() {
    if (temporaryDirectory.existsSync()) {
      temporaryDirectory.deleteSync(recursive: true);
    }
  });

  String viewerScript() {
    final html = File('assets/publish/index.html').readAsStringSync();
    final match = RegExp(
      r'<script>\n(.*?)</script>',
      dotAll: true,
    ).firstMatch(html);
    expect(match, isNotNull, reason: 'the viewer must have one inline script');
    return match!.group(1)!;
  }

  test('viewer JavaScript passes the Node syntax check', () async {
    final script = File('${temporaryDirectory.path}/viewer.js')
      ..writeAsStringSync(viewerScript());
    final result = await Process.run('node', ['--check', script.path]);
    expect(
      result.exitCode,
      0,
      reason: 'Node syntax check failed:\n${result.stdout}\n${result.stderr}',
    );
  });

  test('Other layouts omit excluded fields and placeholders; grouping and '
      'escaping survive at runtime', () async {
    const hostileTitle = 'Other <img src=x onerror=alert(2)> & "quoted"';
    final other = redactForPublish(
      const CatalogueItem(
        id: 9,
        title: hostileTitle,
        titleTransliteration: 'OTHER_EXCLUDED_TRANSLITERATION',
        author: 'OTHER_EXCLUDED_AUTHOR',
        isbn: 'OTHER_EXCLUDED_ISBN',
        publisher: 'OTHER_EXCLUDED_PUBLISHER',
        publishedYear: 19497,
        genre: 'OTHER_EXCLUDED_GENRE',
        language: 'te',
        notes: 'OTHER_EXCLUDED_DESCRIPTION',
        ageGroup: AgeGroup.above10,
        details: OtherItemOf(),
      ),
      resolveCoverUrl: (_) =>
          'https://covers.openlibrary.org/cover.jpg" onerror="alert(1)',
      availability: PublishItem.out,
    ).toJson();
    final payload = <String, dynamic>{
      'schemaVersion': 1,
      'exportedAt': 1000,
      'books': [
        other,
        {
          'title': 'Older issue',
          'kind': 'magazine-issue',
          'issue': {
            'periodicalUid': 'series-uid',
            'issueNumber': 10,
            'issueDate': 1000,
          },
        },
        {
          'title': 'Newer issue',
          'kind': 'magazine-issue',
          'issue': {
            'periodicalUid': 'series-uid',
            'issueNumber': 2,
            'issueDate': 2000,
          },
        },
        {
          'title': 'Ordinary book',
          'kind': 'book',
          'titleTransliteration': 'Visible transliteration',
          'author': 'Visible author',
          'isbn': 'VISIBLE_ISBN',
          'publisher': 'Visible publisher',
          'publishedYear': 2001,
        },
      ],
      'periodicals': [
        {
          'periodicalUid': 'series-uid',
          'title': 'Series <One> & "One"',
          'publisher': 'Publisher <Two>',
        },
      ],
    };
    final payloadFile = File('${temporaryDirectory.path}/books.json')
      ..writeAsStringSync(jsonEncode(payload));
    final harness = File(
      'test/features/publish/viewer_runtime_harness.js',
    ).absolute;

    final result = await Process.run('node', [harness.path, payloadFile.path]);
    expect(
      result.exitCode,
      0,
      reason:
          'Viewer runtime checks failed:\n${result.stdout}\n${result.stderr}',
    );
    expect(result.stdout, contains('viewer runtime checks passed'));
  });
}
