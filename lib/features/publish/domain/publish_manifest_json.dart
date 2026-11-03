/// The lenient reader of this phone's own GitHub publish record
/// (`publish_manifest.json`; publish domain, pure Dart).
///
/// Why its own file (beginner note): `PublishManifest` is the record every
/// GitHub publish plans against, and it kept growing one field per plan
/// session. When plan SP4 added [PublishManifest.adoptedFromBackup], the
/// class would have passed the 500-line limit (plan G5), so its JSON reader
/// moved here unchanged. The record and its rules stay in
/// `publish_manifest.dart`; this file only turns stored JSON into a record.
///
/// "Lenient" is deliberate: this file is the phone's own, so a damaged or
/// older value must read as LESS trust (an unknown head, no keys, nothing
/// confirmed), never as a crash. Hostile input from elsewhere — a backup —
/// is checked field by field first (`PublishStateBackupCodec`).
library;

import 'package:pitaka/features/publish/domain/publish_cover_rendition.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';
import 'package:pitaka/features/publish/domain/site/publish_proof_path.dart';
import 'package:pitaka/features/publish/domain/site/publish_state.dart';

/// The catalogue file whose keys `catalogueKeyed` describes.
const String _booksJsonPath = 'books.json';

/// Parses a manifest from [json]; tolerant of missing/odd fields.
///
/// A schema-1 record (written by the previous app version, which stored only
/// `repo`, `fileShas` and `coverUrlByBookId`) decodes as:
///  - `state` `deployed` — the commit was accepted, but the old app never
///    stored its read-back result, so "live" would be an invented claim;
///  - `ownershipConfirmed` `fileShas.isNotEmpty` — those paths were written
///    by this app, so they are app-owned by construction (R13). A record
///    with no paths claims nothing.
///
/// `headSha` stays null for a legacy record, which is what makes every later
/// publish treat it as "unknown state" and reconcile against the remote tree.
///
/// The ADR 0019 fields:
///  - no `proofPath` → `proofPath` null (the per-section file, as before);
///  - a `proofPath` that is not a known name, or that disagrees with the
///    record's own files, cannot prove anything. For an unproven
///    (`deployed`) record the head is then forgotten too, so the record
///    reads exactly like a legacy one in "unknown state" and no later check
///    can prove it through a guessed file (plan A.1 item 8). A `live` or
///    `retired` record is already settled and needs no proof;
///  - `catalogueKeyed` is true only for a stored `true`.
///
/// The ADR 0020 field: `coverRendition` is kept only when it is a positive
/// whole number; anything else reads as unknown (null). The SP1 field
/// `committedAt` is kept only as a non-negative whole number. The SP4 field
/// `adoptedFromBackup` is false only when absent or a stored `false`; a
/// record without it was written by this phone.
PublishManifest decodePublishManifest(Map<String, dynamic> json) {
  Map<String, String> strMap(Object? o) => o is Map
      ? {
          for (final e in o.entries)
            if (e.value is String) '${e.key}': e.value as String,
        }
      : const {};
  final fileShas = strMap(json['fileShas']);
  final schema = json['schema'];
  // A wrong TYPE is a corrupt record, not a crash: the store must be able to
  // read a bad file as "nothing recorded" (fail closed) instead of throwing
  // a TypeError the file loader's `on Exception` would not catch.
  String? str(Object? o) => o is String ? o : null;
  final state = _stateFrom(json['state']) ?? PublishState.deployed;
  final proof = PublishProofPath.tryParse(json['proofPath']);
  final proofUnreadable =
      json.containsKey('proofPath') &&
      (proof == null || !proof.agreesWith(fileShas));
  final unknownHead = proofUnreadable && state == PublishState.deployed;
  return PublishManifest(
    schema: schema is int ? schema : 1,
    repo: str(json['repo']),
    branch: str(json['branch']),
    headSha: unknownHead ? null : str(json['headSha']),
    // Absent = a legacy record (its paths are ours by construction); a
    // value of another type is damage, read as "not confirmed" (fewer
    // deletions allowed, R13) instead of a cast that throws (plan J16).
    ownershipConfirmed: switch (json['ownershipConfirmed']) {
      final bool stored => stored,
      null => fileShas.isNotEmpty,
      _ => false,
    },
    state: state,
    fileShas: fileShas,
    coverUrlByBookId: strMap(json['coverUrlByBookId']),
    proofPath: proofUnreadable ? null : proof,
    // A keyed catalogue without a recorded books.json is a contradiction,
    // and the safe reading of a contradiction is "not keyed".
    catalogueKeyed:
        json['catalogueKeyed'] == true && fileShas.containsKey(_booksJsonPath),
    coverRendition: PublishCoverRendition.tryParse(json['coverRendition']),
    committedAt: switch (json['committedAt']) {
      final int at when at >= 0 => at,
      _ => null,
    },
    // Absent = written by this phone. A value of another type is damage,
    // read as "adopted" — the reading that trusts the record LESS: the next
    // publish reads the whole tree once instead of skipping it (plan SP4).
    adoptedFromBackup: switch (json['adoptedFromBackup']) {
      null => false,
      final bool stored => stored,
      _ => true,
    },
  );
}

PublishState? _stateFrom(Object? raw) {
  for (final value in PublishState.values) {
    if (value.name == raw) return value;
  }
  // An unknown state is not "live": the caller treats null as `deployed`.
  return null;
}
