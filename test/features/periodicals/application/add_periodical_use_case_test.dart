import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/periodicals/application/add_periodical_use_case.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';

import 'periodical_fakes.dart';

/// `AddPeriodicalUseCase` (plan S12; ADR 0013 D2, D7): the shared
/// `Periodical.validate` gate, the ISSN pre-check that names the existing
/// title, and fail-closed behaviour when the pre-check cannot be read.
void main() {
  late FakePeriodicals periodicals;
  late AddPeriodicalUseCase useCase;

  setUp(() {
    periodicals = FakePeriodicals();
    useCase = AddPeriodicalUseCase(periodicals);
  });

  // Valid ISSNs (mod-11 check digit): 0317-8471, 1234-5679.
  const issnA = '0317-8471';
  const issnB = '1234-5679';

  test(
    'rejects a blank title with ValidationFailure; nothing inserted',
    () async {
      final failure = failureOf(await useCase(const Periodical(title: '   ')));
      expect(failure, isA<ValidationFailure>());
      expect((failure as ValidationFailure).message, 'A title is required.');
      expect(periodicals.calls, isEmpty, reason: 'no store access at all');
    },
  );

  test('rejects a malformed ISSN with ValidationFailure', () async {
    final failure = failureOf(
      await useCase(const Periodical(title: 'Chandamama', issn: '1234-5678')),
    );
    expect(failure, isA<ValidationFailure>());
    expect(
      (failure as ValidationFailure).message,
      'The ISSN is not a valid ISSN.',
    );
    expect(periodicals.calls, isEmpty);
  });

  test('inserts a valid title; the repository assigns id and uid', () async {
    final saved = ok(
      await useCase(const Periodical(title: '  Chandamama  ', addedDate: 7)),
    );
    expect(saved.id, isNot(Periodical.emptyId));
    expect(saved.periodicalUid, isNotNull);
    expect(saved.title, 'Chandamama', reason: 'the gate trims the title');
    expect(periodicals.rows[saved.id]?.title, 'Chandamama');
    expect(periodicals.calls, ['insert'], reason: 'no ISSN → no lookup');
  });

  test('normalises the ISSN before the lookup AND the insert', () async {
    final saved = ok(
      await useCase(const Periodical(title: 'Chandamama', issn: ' 03178471 ')),
    );
    expect(saved.issn, issnA);
    expect(periodicals.calls, ['findByIssn:$issnA', 'insert']);
  });

  test('a duplicate ISSN is refused, naming the existing title', () async {
    final existing = periodicals.seed(
      const Periodical(title: 'Chandamama', issn: issnA),
    );
    final failure = failureOf(
      await useCase(const Periodical(title: 'Copy', issn: issnA)),
    );
    expect(failure, isA<DuplicateIssnFailure>());
    failure as DuplicateIssnFailure;
    expect(failure.existingTitle, 'Chandamama');
    expect(failure.existingPeriodicalId, existing.id);
    expect(periodicals.calls, isNot(contains('insert')));
  });

  test('two different ISSNs both save', () async {
    ok(await useCase(const Periodical(title: 'A', issn: issnA)));
    ok(await useCase(const Periodical(title: 'B', issn: issnB)));
    expect(periodicals.rows, hasLength(2));
  });

  test('a failed ISSN lookup aborts the add (fail closed)', () async {
    periodicals.findByIssnFailure = const StorageFailure('db closed');
    final failure = failureOf(
      await useCase(const Periodical(title: 'A', issn: issnA)),
    );
    expect(failure, isA<StorageFailure>());
    expect(periodicals.calls, isNot(contains('insert')));
  });

  test('the repository failure is returned unchanged', () async {
    periodicals.insertFailure = const StorageFailure('disk full');
    final failure = failureOf(await useCase(const Periodical(title: 'A')));
    expect(failure, isA<StorageFailure>());
    expect((failure as StorageFailure).reason, 'disk full');
  });
}
