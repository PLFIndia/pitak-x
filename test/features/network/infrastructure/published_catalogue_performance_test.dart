import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/network/domain/published_catalogue_query.dart';
import 'package:pitaka/features/network/infrastructure/published_catalogue_codec.dart';

/// A realistic large-fixture check (viewer plan S6), deliberately ONE test
/// instead of allocating 64 MiB in every suite.
///
/// The budgets are generous regression guards, not benchmarks: a correct
/// linear reader/engine finishes far inside them, while an accidental
/// quadratic pass (re-scanning the list per row, stringifying per comparison,
/// …) does not. The 100 000-row / 64 MiB ceilings are OUTER limits; this
/// fixture is the size a real large library actually publishes.
void main() {
  test('a 20 000-row catalogue decodes and queries within budget', () {
    final rows = <Map<String, Object?>>[
      for (var i = 0; i < 20000; i++)
        {
          'title': 'Bulk Title $i',
          'kind': switch (i % 10) {
            0 => 'other',
            1 => 'magazine-issue',
            _ => 'book',
          },
          if (i % 10 == 1)
            'issue': {'periodicalUid': 'series-${i % 7}', 'issueNumber': i},
          'author': 'Author ${i % 500}',
          'language': switch (i % 4) {
            0 => 'English',
            1 => 'Hindi',
            2 => 'Kannada',
            _ => null,
          },
          'publishedYear': 1900 + (i % 120),
          'ageGroup': switch (i % 5) {
            0 => 'above-3',
            1 => 'above-6',
            2 => 'above-10',
            3 => 'above-15',
            _ => 'advanced',
          },
        },
    ];
    final bytes = utf8.encode(
      jsonEncode({
        'schemaVersion': 1,
        'exportedAt': 1760000000000,
        'books': rows,
        'periodicals': [
          for (var s = 0; s < 7; s++)
            {'periodicalUid': 'series-$s', 'title': 'Bulk Series $s'},
        ],
      }),
    );

    final decodeWatch = Stopwatch()..start();
    final result = const PublishedCatalogueCodec().decode(bytes);
    decodeWatch.stop();

    expect(result.isRight(), isTrue);
    final catalogue = result.toNullable()!;
    expect(catalogue.items, hasLength(20000));
    expect(catalogue.periodicals, hasLength(7));
    expect(
      decodeWatch.elapsed,
      lessThan(const Duration(seconds: 10)),
      reason: 'a linear reader must not become quadratic',
    );

    final queryWatch = Stopwatch()..start();
    final searched = PublishedQueryEngine.apply(
      catalogue,
      const PublishedCatalogueQuery(
        search: 'bulk title 199',
        sort: PublishedSortOrder.language,
      ),
    );
    // The default sort is the published order — the 20 000-item path a user
    // actually opens the viewer on.
    final grouped = PublishedQueryEngine.apply(
      catalogue,
      const PublishedCatalogueQuery(),
    );
    queryWatch.stop();

    expect(searched.shownItems, greaterThan(0));
    expect(searched.entries, isNotEmpty);
    // The grouped view must contain the series headers, not 20 000 widgets.
    expect(grouped.entries.length, lessThan(20000));
    expect(
      queryWatch.elapsed,
      lessThan(const Duration(seconds: 5)),
      reason: 'filter + sort + group must stay linear-ish',
    );
  });

  test('the row cap is still the documented 100 000', () {
    expect(PublishedCatalogueCodec.defaultMaxRows, 100000);
  });
}
