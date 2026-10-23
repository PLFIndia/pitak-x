/// Periodicals-feature DI bindings (AGENTS.md §4; one DI module per
/// feature).
///
/// What lives here: the series and issue use cases (ADR 0013) and the
/// single-series read models ([periodicalById], [periodicalByUid]). The
/// periodical REPOSITORY binding lives in the database module — see its
/// header for the cycle-breaking reason (ADR 0014 W4: the library cover
/// janitor must count series covers).
///
/// Cross-feature note (beginner): this module imports the library module
/// one way — the item repository for issue writes, the janitor for a
/// deleted series' cover file. Nothing in `library_providers.dart` imports
/// this module back, so the graph stays acyclic (the rule in
/// `core/di/providers.dart`).
library;

import 'package:pitaka/core/di/src/database_providers.dart';
import 'package:pitaka/core/di/src/library_providers.dart';
import 'package:pitaka/features/library/application/library_controller.dart';
import 'package:pitaka/features/periodicals/application/add_issue_use_case.dart';
import 'package:pitaka/features/periodicals/application/add_periodical_use_case.dart';
import 'package:pitaka/features/periodicals/application/delete_periodical_use_case.dart';
import 'package:pitaka/features/periodicals/application/periodicals_controller.dart';
import 'package:pitaka/features/periodicals/application/update_issue_use_case.dart';
import 'package:pitaka/features/periodicals/application/update_periodical_use_case.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'periodical_providers.g.dart';

/// Adds a new magazine title (validation + ISSN pre-check + persist).
@riverpod
Future<AddPeriodicalUseCase> addPeriodicalUseCase(
  AddPeriodicalUseCaseRef ref,
) async {
  final periodicals = await ref.watch(periodicalRepositoryProvider.future);
  return AddPeriodicalUseCase(periodicals);
}

/// Edits a magazine title and re-projects its issues in one transaction
/// (ADR 0013 D3).
@riverpod
Future<UpdatePeriodicalUseCase> updatePeriodicalUseCase(
  UpdatePeriodicalUseCaseRef ref,
) async {
  final periodicals = await ref.watch(periodicalRepositoryProvider.future);
  final items = await ref.watch(catalogueItemRepositoryProvider.future);
  return UpdatePeriodicalUseCase(periodicals: periodicals, items: items);
}

/// Hard-deletes a magazine title that no issue references (ADR 0013 D8),
/// releasing its cover file through the janitor.
@riverpod
Future<DeletePeriodicalUseCase> deletePeriodicalUseCase(
  DeletePeriodicalUseCaseRef ref,
) async {
  final periodicals = await ref.watch(periodicalRepositoryProvider.future);
  final janitor = await ref.watch(coverFileJanitorProvider.future);
  return DeletePeriodicalUseCase(
    periodicals: periodicals,
    releaseCover: janitor.releaseReference,
  );
}

/// Adds a magazine issue or bound volume under its series (ADR 0013 D1, D4).
@riverpod
Future<AddIssueUseCase> addIssueUseCase(AddIssueUseCaseRef ref) async {
  final periodicals = await ref.watch(periodicalRepositoryProvider.future);
  final items = await ref.watch(catalogueItemRepositoryProvider.future);
  return AddIssueUseCase(periodicals: periodicals, items: items);
}

/// Edits an existing magazine issue; refuses a kind change (ADR 0013 D8).
@riverpod
Future<UpdateIssueUseCase> updateIssueUseCase(UpdateIssueUseCaseRef ref) async {
  final periodicals = await ref.watch(periodicalRepositoryProvider.future);
  final items = await ref.watch(catalogueItemRepositoryProvider.future);
  return UpdateIssueUseCase(periodicals: periodicals, items: items);
}

/// One magazine title, observed by per-device id, for the series detail
/// page and the edit form (same contract as `catalogueItemById`, N03: a
/// page stays open while the row changes underneath it, so it observes the
/// row rather than the snapshot it was pushed with).
///
/// Freshness signals (N04): BOTH mutation signals are watched, value
/// ignored. `periodicalsControllerProvider` fires on every series write
/// (form save, remove/restore, delete); `libraryControllerProvider` fires on
/// every item write — including import, merge and restore, which rewrite
/// periodicals without going through the series controller. Watching only
/// the repository OBJECT would never fire.
///
/// `null` = the row no longer exists. A repository `Left` is thrown so the
/// screen sees `AsyncError`.
@riverpod
Future<Periodical?> periodicalById(PeriodicalByIdRef ref, int id) async {
  ref
    ..watch(periodicalsControllerProvider)
    ..watch(libraryControllerProvider);
  final repo = await ref.watch(periodicalRepositoryProvider.future);
  final result = await repo.getById(id);
  return result.fold(
    // ignore: only_throw_errors, Riverpod surfaces typed errors via throw
    (failure) => throw failure,
    (periodical) => periodical,
  );
}

/// One magazine title, observed by its stable `periodicalUid` — the key an
/// issue's `IssueOf.periodicalUid` carries, so an issue's detail page can
/// resolve "Open series" and its fallback cover (ADR 0014 W4) without a
/// per-device id. Same freshness contract as [periodicalById].
///
/// `null` = no such series (a blank uid never matches).
@riverpod
Future<Periodical?> periodicalByUid(
  PeriodicalByUidRef ref,
  String periodicalUid,
) async {
  ref
    ..watch(periodicalsControllerProvider)
    ..watch(libraryControllerProvider);
  final repo = await ref.watch(periodicalRepositoryProvider.future);
  final result = await repo.findByUid(periodicalUid);
  return result.fold(
    // ignore: only_throw_errors, Riverpod surfaces typed errors via throw
    (failure) => throw failure,
    (periodical) => periodical,
  );
}
