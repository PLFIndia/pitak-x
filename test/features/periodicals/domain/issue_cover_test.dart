import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/domain/issue_cover.dart';

// ADR 0014 W4: own cover first, series cover as the fallback.
void main() {
  const series = Periodical(title: 'S', coverUrl: 'covers/series.jpg');

  test('an issue with its own cover shows it', () {
    const issue = CatalogueItem(title: 'x', coverUrl: 'covers/own.jpg');
    expect(IssueCover.resolve(issue, series), 'covers/own.jpg');
  });

  test('a blank own cover falls back to the series cover', () {
    expect(
      IssueCover.resolve(const CatalogueItem(title: 'x'), series),
      'covers/series.jpg',
    );
    expect(
      IssueCover.resolve(
        const CatalogueItem(title: 'x', coverUrl: '  '),
        series,
      ),
      'covers/series.jpg',
    );
  });

  test('no cover anywhere ⇒ null; own cover is trimmed', () {
    expect(IssueCover.resolve(const CatalogueItem(title: 'x'), null), isNull);
    expect(
      IssueCover.resolve(
        const CatalogueItem(title: 'x'),
        const Periodical(title: 'S', coverUrl: ' '),
      ),
      isNull,
    );
    expect(
      IssueCover.resolve(
        const CatalogueItem(title: 'x', coverUrl: ' a.jpg '),
        null,
      ),
      'a.jpg',
    );
  });
}
