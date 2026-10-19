import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/network/domain/refresh_report.dart';
import 'package:pitaka/features/network/presentation/widgets/network_refresh_bar.dart';

/// Copy tests for [NetworkRefreshBar.reportSummary] (docs/ARCHITECTURE.md §5.6
/// step 5: "an honest one-line summary; truncation is reported"). Pure
/// function tests — the widget itself just renders this string.
void main() {
  group('reportSummary', () {
    test('an empty report says "nothing new"', () {
      expect(
        NetworkRefreshBar.reportSummary(const RefreshReport()),
        'Refresh: nothing new.',
      );
    });

    test('one clause per non-zero part, in order', () {
      final summary = NetworkRefreshBar.reportSummary(
        const RefreshReport(
          fetched: 3,
          unreachable: 2,
          invalid: 1,
          schemaTooNew: 4,
          discovered: 5,
          conflicts: 6,
          pendingMemberships: 7,
          noLongerListed: ['https://hub.github.io/x/'],
        ),
      );
      expect(
        summary,
        'Refresh: 3 up to date · 2 unreachable · 1 invalid · '
        '4 need a newer Pitak version · 5 discovered · 6 identity conflicts · '
        '7 membership questions below · 1 no longer list you.',
      );
    });

    test('a cancelled run says so and still lists the partials', () {
      expect(
        NetworkRefreshBar.reportSummary(
          const RefreshReport(fetched: 2, cancelled: true),
        ),
        'Cancelled — kept what arrived (2 up to date).',
      );
    });

    test('truncation: the cap covers the saved rows too (L4 copy)', () {
      // The 500-row budget includes seeds since L4, so the clause says
      // "refresh", not "discovery".
      final summary = NetworkRefreshBar.reportSummary(
        const RefreshReport(fetched: 500, truncated: true),
      );
      expect(summary, contains('refresh capped at 500 libraries'));
      expect(summary, isNot(contains('discovery capped')));
    });


  });
}
