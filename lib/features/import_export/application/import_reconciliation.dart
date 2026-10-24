/// Plain-import reconciliation of magazine series and issues (application
/// layer; magazine remediation S4, findings H1/H2/H3/M3).
///
/// WHY THIS FILE EXISTS (beginner note): a Pitaka-JSON file names a magazine
/// series by its cross-device UID, but this library may already track the SAME
/// series under ANOTHER uid (same ISSN, different uid). Before a single issue
/// is written, something must answer: "which STORED series does each incoming
/// uid belong to?" That answer, the in-place series update, and the record of
/// which issue identities this run has already claimed are all one job. Keeping
/// them here lets `ImportLibraryUseCase` stay a short, readable sequence of
/// steps instead of a 700-line method.
///
/// Every method runs INSIDE the caller's database transaction, so a typed
/// `Either` failure here always rolls the whole import back.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/catalogue_rules.dart';
import 'package:pitaka/features/library/domain/cover_precedence.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/merge/issue_identity.dart';
import 'package:pitaka/features/library/domain/periodical_identity.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/domain/repositories/periodical_repository.dart';

/// What one file's series pass changed, plus the maps its item pass needs.
///
/// [seriesByIncomingUid] is the link between the two passes: every incoming
/// canonical UID points at the STORED series that won it, which is what lets an
/// issue filed under a foreign UID follow its series home.
final class ImportSeriesResolution {
  /// Creates a resolution.
  const ImportSeriesResolution({
    required this.added,
    required this.updated,
    required this.skipped,
    required this.seriesByIncomingUid,
    required this.storedByUid,
    required this.updatedStored,
  });

  /// An empty resolution: the file carried no series and no issue rows.
  static const empty = ImportSeriesResolution(
    added: 0,
    updated: 0,
    skipped: 0,
    seriesByIncomingUid: {},
    storedByUid: {},
    updatedStored: {},
  );

  /// Newly inserted series (W1 count for the import summary).
  final int added;

  /// Series updated in place because the file carried the same UID.
  final int updated;

  /// Series kept local because the file carried their ISSN under another UID,
  /// or because an earlier row of the same file already claimed the key.
  final int skipped;

  /// incoming canonical UID → the STORED series its issues belong to.
  final Map<String, Periodical> seriesByIncomingUid;

  /// every stored series of this library, by canonical UID — the fallback for
  /// an issue whose series the file did not carry.
  final Map<String, Periodical> storedByUid;

  /// Stored series that were updated and must be re-projected before commit
  /// (D3), keyed by UID so a repeated update cannot duplicate the work.
  final Map<String, Periodical> updatedStored;
}

/// Applies a file's series rows and answers "which series / issue does this
/// library already own?" for the item pass.
///
/// The D6 issue lookup lives here because the periodical store owns issues as
/// well as series, so the item pass asks one collaborator for both halves.
final class ImportSeriesReconciler {
  /// Creates the reconciler over the periodical store.
  const ImportSeriesReconciler({required PeriodicalRepository periodicals})
    : _periodicals = periodicals;

  final PeriodicalRepository _periodicals;

  /// Validates [rawSeries], applies them to this library, and returns the
  /// identity map the item pass reconciles against.
  ///
  /// [itemsCarryIssues] forces the stored-series read even when the file has no
  /// `periodicals[]` section: an issue row may point at a series this device
  /// already has, and a same-ISSN/different-UID file must still re-anchor it.
  ///
  /// Rules, in order, per incoming row:
  ///  1. a UID already resolved by an earlier row of THIS file → skip (first
  ///     valid row wins; later conflicting rows are counted, never merged);
  ///  2. the same UID exists locally → merge in place and keep the stored row;
  ///  3. the same ISSN exists under another UID → keep the local series and
  ///     map the incoming UID onto it;
  ///  4. otherwise → insert, and remember the RETURNED row (its UID may be
  ///     minted by the repository, so a later issue must never anchor to the
  ///     draft we sent).
  Future<Either<Failure, ImportSeriesResolution>> resolve({
    required List<Periodical> rawSeries,
    required bool itemsCarryIssues,
  }) async {
    final incoming = <Periodical>[];
    for (final raw in rawSeries) {
      final checked = Periodical.validate(raw);
      if (checked.isLeft()) {
        final errs = (checked as Left<List<FieldError>, Periodical>).value;
        return left(
          ValidationFailure(
            'A parsed magazine title failed validation: '
            '${errs.map((e) => '${e.field} ${e.problem}').join('; ')}.',
          ),
        );
      }
      incoming.add(checked.toNullable()!);
    }

    final seriesByIncomingUid = <String, Periodical>{};
    final storedByUid = <String, Periodical>{};
    final updatedStored = <String, Periodical>{};
    var added = 0;
    var updated = 0;
    var skipped = 0;

    if (incoming.isEmpty && !itemsCarryIssues) {
      return right(ImportSeriesResolution.empty);
    }

    final stored = await _periodicals.listAll();
    if (stored.isLeft()) return stored.map((_) => ImportSeriesResolution.empty);
    for (final summary in stored.toNullable()!) {
      final periodical = summary.periodical;
      final uid = periodical.periodicalUid;
      if (uid == null) continue;
      final canonical = canonicalPeriodicalUid(uid);
      if (canonical.isNotEmpty) storedByUid[canonical] = periodical;
    }

    for (final periodical in incoming) {
      final uid = periodical.periodicalUid?.trim() ?? '';
      final hasUid = uid.isNotEmpty;

      if (hasUid && seriesByIncomingUid.containsKey(uid)) {
        skipped++;
        continue;
      }

      // 1. Same stable identity already here → merge into that row in place.
      if (hasUid) {
        final byUid = await _periodicals.findByUid(uid);
        if (byUid.isLeft()) {
          return byUid.map((_) => ImportSeriesResolution.empty);
        }
        final existing = byUid.toNullable();
        if (existing != null) {
          final written = await _periodicals.update(
            mergeImportedPeriodical(existing: existing, incoming: periodical),
          );
          if (written.isLeft()) {
            return written.map((_) => ImportSeriesResolution.empty);
          }
          final row = written.toNullable()!;
          final storedUid = row.periodicalUid?.trim() ?? '';
          if (storedUid.isEmpty) {
            return left(
              const UnexpectedFailure(
                'Import periodical update returned no stored UID.',
              ),
            );
          }
          seriesByIncomingUid[uid] = row;
          storedByUid[storedUid] = row;
          updatedStored[storedUid] = row;
          updated++;
          continue;
        }
      }

      // 2. Same canonical ISSN under another UID → keep the local series,
      //    count this row as skipped, and map its issues to the winner.
      final issn = periodical.issn;
      if (issn != null && issn.isNotEmpty) {
        final found = await _periodicals.findByIssn(issn);
        if (found.isLeft()) {
          return found.map((_) => ImportSeriesResolution.empty);
        }
        final existing = found.toNullable();
        if (existing != null) {
          final storedUid = existing.periodicalUid?.trim() ?? '';
          if (storedUid.isEmpty) {
            return left(
              const UnexpectedFailure(
                'Import ISSN lookup returned no stored UID.',
              ),
            );
          }
          if (hasUid) seriesByIncomingUid[uid] = existing;
          storedByUid[storedUid] = existing;
          skipped++;
          continue;
        }
      }

      // 3. Genuinely new → insert and keep the row the repository RETURNED,
      //    including a minted UID, so later issues never anchor to a draft.
      final inserted = await _periodicals.insert(periodical);
      if (inserted.isLeft()) {
        return inserted.map((_) => ImportSeriesResolution.empty);
      }
      final row = inserted.toNullable()!;
      final storedUid = row.periodicalUid?.trim() ?? '';
      if (storedUid.isEmpty) {
        return left(
          const UnexpectedFailure(
            'Import periodical insert returned no stored UID.',
          ),
        );
      }
      if (hasUid) seriesByIncomingUid[uid] = row;
      storedByUid[storedUid] = row;
      added++;
    }

    return right(
      ImportSeriesResolution(
        added: added,
        updated: updated,
        skipped: skipped,
        seriesByIncomingUid: seriesByIncomingUid,
        storedByUid: storedByUid,
        updatedStored: updatedStored,
      ),
    );
  }

  /// The repository twin of the pure-Dart D6 [key]: does this library already
  /// own the issue that key names?
  Future<Either<Failure, CatalogueItem?>> findOwnedIssue(IssueIdentityKey key) {
    if (key.bound) {
      return _periodicals.findBoundVolume(
        periodicalUid: key.seriesUid,
        issueDate: key.first,
        boundUntil: key.second,
      );
    }
    return _periodicals.findIssue(
      periodicalUid: key.seriesUid,
      volume: key.first,
      issueNumber: key.second,
    );
  }
}

/// The periodical twin of the import's item merge: the row to write when
/// [incoming] describes the same series as [existing] (same UID).
///
/// Local bookkeeping survives an additive re-import — `id`, `periodicalUid`,
/// `addedDate` (when the file carries none) and `addedBy` (when absent) — and
/// the cover follows [resolveIncomingCover]: a local photo is never replaced by
/// an incoming remote URL, and a file without a cover keeps the local one.
/// Every other catalogue field comes from the newer incoming row.
Periodical mergeImportedPeriodical({
  required Periodical existing,
  required Periodical incoming,
}) {
  return Periodical(
    id: existing.id,
    periodicalUid: existing.periodicalUid,
    title: incoming.title,
    titleTransliteration: incoming.titleTransliteration,
    issn: incoming.issn,
    publisher: incoming.publisher,
    language: incoming.language,
    coverUrl: resolveIncomingCover(
      existing: existing.coverUrl,
      incoming: incoming.coverUrl,
    ),
    frequency: incoming.frequency,
    subscriptionStart: incoming.subscriptionStart,
    subscriptionEnd: incoming.subscriptionEnd,
    notes: incoming.notes,
    location: incoming.location,
    sourceType: incoming.sourceType,
    sourceDetail: incoming.sourceDetail,
    ageGroup: incoming.ageGroup,
    addedDate: incoming.addedDate == 0
        ? existing.addedDate
        : incoming.addedDate,
    removed: incoming.removed,
    removedAt: incoming.removedAt,
    addedBy: incoming.addedBy ?? existing.addedBy,
  );
}

/// D6 keys claimed by SUCCESSFUL writes in one import.
///
/// Repeated item UIDs are valid import input: the later row updates the same
/// stored item. Tracking only an append-only set would wrongly reserve the old
/// key forever, so the reverse index releases that item's previous claim before
/// recording its current one.
final class ImportIssueClaims {
  final _ownerByKey = <IssueIdentityKey, String>{};
  final _keyByOwner = <String, IssueIdentityKey>{};

  /// True when a row written earlier in THIS run already owns [key].
  bool isClaimed(IssueIdentityKey key) => _ownerByKey.containsKey(key);

  /// Records the identity [stored] was written with, replacing any claim its
  /// own UID made earlier in the same file.
  void record(CatalogueItem stored) {
    final owner = stored.itemUid?.trim() ?? '';
    if (owner.isEmpty) return;
    final previous = _keyByOwner.remove(owner);
    if (previous != null && _ownerByKey[previous] == owner) {
      _ownerByKey.remove(previous);
    }
    final issue = stored.issue;
    if (issue == null) return;
    final current = issueIdentityKey(issue);
    if (current == null) return;
    _ownerByKey[current] = owner;
    _keyByOwner[owner] = current;
  }
}
