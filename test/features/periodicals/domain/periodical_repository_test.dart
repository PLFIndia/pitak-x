import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/domain/repositories/periodical_repository.dart';

// The repository is an interface (implemented in S11); only its value type
// has behaviour to pin here.
void main() {
  test('PeriodicalSummary carries the series and its issue facts', () {
    const s = PeriodicalSummary(
      periodical: Periodical(title: 'Chandamama'),
      issueCount: 3,
      latestIssueDate: 42,
    );
    expect(s.periodical.title, 'Chandamama');
    expect(s.issueCount, 3);
    expect(s.latestIssueDate, 42);
    expect(
      s.toString(),
      'PeriodicalSummary(Chandamama, issues: 3, latest: 42)',
    );
    const none = PeriodicalSummary(
      periodical: Periodical(title: 'X'),
      issueCount: 0,
    );
    expect(none.latestIssueDate, isNull);
  });
}
