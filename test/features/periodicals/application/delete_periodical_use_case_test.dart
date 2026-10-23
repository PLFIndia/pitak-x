import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/periodicals/application/delete_periodical_use_case.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';

import 'periodical_fakes.dart';

/// `DeletePeriodicalUseCase` (plan S12; ADR 0013 D8): fail-closed while
/// issues still link to the series, idempotent for a missing row, and the
/// cover file released only AFTER a successful delete (decision Q12).
void main() {
  late FakePeriodicals periodicals;
  late List<String?> released;
  late DeletePeriodicalUseCase useCase;

  setUp(() {
    periodicals = FakePeriodicals();
    released = [];
    useCase = DeletePeriodicalUseCase(
      periodicals: periodicals,
      releaseCover: (ref) async => released.add(ref),
    );
  });

  const cover = 'covers/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa.jpg';

  test('a missing id is a successful no-op; nothing released', () async {
    ok(await useCase(404));
    expect(periodicals.calls, ['getById']);
    expect(released, isEmpty);
  });

  test('deletes a series without issues and releases its cover', () async {
    final series = periodicals.seed(
      const Periodical(title: 'Chandamama', coverUrl: cover),
    );
    ok(await useCase(series.id));
    expect(periodicals.rows, isEmpty);
    expect(periodicals.calls, ['getById', 'countIssues', 'delete']);
    expect(released, [cover]);
  });

  test('a series without a cover releases null (janitor ignores it)', () async {
    final series = periodicals.seed(const Periodical(title: 'Chandamama'));
    ok(await useCase(series.id));
    expect(released, [null]);
  });

  test('refuses while issues reference the series (D8)', () async {
    final series = periodicals.seed(
      const Periodical(title: 'Chandamama', coverUrl: cover),
    );
    final uid = series.periodicalUid!;
    periodicals.issues[uid] = [
      CatalogueItem(
        id: 1,
        title: 'Chandamama — No 1',
        details: IssueOf(periodicalUid: uid, issueNumber: 1),
      ),
      CatalogueItem(
        id: 2,
        title: 'Chandamama — No 2',
        removed: true,
        details: IssueOf(periodicalUid: uid, issueNumber: 2),
      ),
    ];
    final failure = failureOf(await useCase(series.id));
    expect(failure, isA<PeriodicalHasIssuesFailure>());
    expect(
      (failure as PeriodicalHasIssuesFailure).issueCount,
      2,
      reason: 'soft-removed issues still link to the series',
    );
    expect(periodicals.rows, hasLength(1), reason: 'row kept');
    expect(periodicals.calls, isNot(contains('delete')));
    expect(released, isEmpty);
  });

  test('a failed row read aborts before anything is deleted', () async {
    periodicals
      ..seed(const Periodical(title: 'Chandamama'))
      ..getByIdFailure = const StorageFailure('db closed');
    final failure = failureOf(await useCase(1));
    expect(failure, isA<StorageFailure>());
    expect(periodicals.rows, hasLength(1));
    expect(periodicals.calls, ['getById']);
    expect(released, isEmpty);
  });

  test('a failed issue count aborts before anything is deleted', () async {
    final series = periodicals.seed(const Periodical(title: 'Chandamama'));
    periodicals.countIssuesFailure = const StorageFailure('db closed');
    final failure = failureOf(await useCase(series.id));
    expect(failure, isA<StorageFailure>());
    expect(periodicals.rows, hasLength(1));
    expect(periodicals.calls, isNot(contains('delete')));
    expect(released, isEmpty);
  });

  test(
    "the repository's own refusal (the race) is returned; no release",
    () async {
      // An issue added between the pre-check and the delete is caught by the
      // repository's in-transaction check; the use case passes it through.
      final series = periodicals.seed(
        const Periodical(title: 'Chandamama', coverUrl: cover),
      );
      periodicals.deleteFailure = const PeriodicalHasIssuesFailure(1);
      final failure = failureOf(await useCase(series.id));
      expect(failure, isA<PeriodicalHasIssuesFailure>());
      expect(released, isEmpty);
    },
  );

  test('a failed delete does NOT release the cover', () async {
    final series = periodicals.seed(
      const Periodical(title: 'Chandamama', coverUrl: cover),
    );
    periodicals.deleteFailure = const StorageFailure('locked');
    expect((await useCase(series.id)).isLeft(), isTrue);
    expect(released, isEmpty);
  });

  test('the release hook defaults to a no-op', () async {
    final series = periodicals.seed(
      const Periodical(title: 'Chandamama', coverUrl: cover),
    );
    final bare = DeletePeriodicalUseCase(periodicals: periodicals);
    ok(await bare(series.id));
    expect(periodicals.rows, isEmpty);
  });
}
