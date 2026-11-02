/// The on-device record of what this phone published to one GitHub target
/// (publish domain, pure Dart; AGENTS.md §3.1, Cloudflare plan R5/R6/R9).
///
/// It is NOT a cache (beginner note — the previous version of this file said
/// it was, and that was the bug): a manifest answer decides which public files
/// survive a publish. "This path is no longer in the section" becomes an
/// actual DELETE on the remote, so the record must say, for one exact branch
/// and head commit, which paths this app wrote and which cover source each one
/// came from.
///
/// Schema 2 adds the identity that made schema 1 ambiguous: `repo` and
/// `branch` say WHICH site the record describes (Pages can be re-pointed at
/// another branch, and a record from the old branch must never authorise
/// deletes on the new one); `headSha` is the commit it was written from — the
/// compare-and-swap anchor every later commit passes back as `expectedHead`;
/// `state` says whether that commit is merely accepted by the API (`deployed`)
/// or has been proven to be served by the live site (`live`); and
/// `ownershipConfirmed` says whether the app owns the reserved paths it
/// records. Only app-owned paths may ever be deleted (R13).
///
/// Uncertainty has ONE safe direction. A record that does not describe the
/// target exactly (other repo, other branch) is not trusted for deletions or
/// for "this file is unchanged": `reconciledFrom` throws its claimed path set
/// away and re-derives the known shas from the remote tree. It NEVER adopts
/// paths it finds in the tree — a repository may hold files a human wrote, and
/// those are not ours to delete or to claim.
///
/// Two additive fields arrived with ADR 0019 (schema stays 2; an older record
/// simply lacks them):
///  - `proofPath` says which file proves the last commit
///    ([PublishProofPath]); absent means "use the per-section file", as
///    before;
///  - `catalogueKeyed` says the live `books.json` carries item keys written
///    by THIS phone, so the availability lane may publish against it
///    (gate 7b). Absent reads as false.
///
/// PUBLIC data only — repo paths, git blob shas, public cover URLs — so it
/// needs no encryption.
library;

import 'package:pitaka/features/publish/domain/github_models.dart';
import 'package:pitaka/features/publish/domain/site/previous_publication.dart';
import 'package:pitaka/features/publish/domain/site/publish_proof_path.dart';
import 'package:pitaka/features/publish/domain/site/publish_state.dart';

/// What was last published, for incremental diffing and exact deletions.
final class PublishManifest implements PreviousPublication {
  /// Creates a manifest. The default is the EMPTY record: no repo, no claim.
  const PublishManifest({
    this.schema = currentSchema,
    this.repo,
    this.branch,
    this.headSha,
    this.ownershipConfirmed = false,
    this.state = PublishState.deployed,
    this.fileShas = const {},
    this.coverUrlByBookId = const {},
    this.proofPath,
    this.catalogueKeyed = false,
  });

  /// Parses a manifest from [json]; tolerant of missing/odd fields.
  ///
  /// A schema-1 record (written by the previous app version, which stored only
  /// `repo`, `fileShas` and `coverUrlByBookId`) decodes as:
  ///  - [state] `deployed` — the commit was accepted, but the old app never
  ///    stored its read-back result, so "live" would be an invented claim;
  ///  - [ownershipConfirmed] `fileShas.isNotEmpty` — those paths were written
  ///    by this app, so they are app-owned by construction (R13). A record
  ///    with no paths claims nothing.
  ///
  /// [headSha] stays null for a legacy record, which is what makes every later
  /// publish treat it as "unknown state" and reconcile against the remote tree.
  ///
  /// The ADR 0019 fields:
  ///  - no `proofPath` → [proofPath] null (the per-section file, as before);
  ///  - a `proofPath` that is not a known name, or that disagrees with the
  ///    record's own files, cannot prove anything. For an unproven
  ///    (`deployed`) record the head is then forgotten too, so the record
  ///    reads exactly like a legacy one in "unknown state" and no later check
  ///    can prove it through a guessed file (plan A.1 item 8). A `live` or
  ///    `retired` record is already settled and needs no proof;
  ///  - `catalogueKeyed` is true only for a stored `true`.
  factory PublishManifest.fromJson(Map<String, dynamic> json) {
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
      ownershipConfirmed:
          json['ownershipConfirmed'] as bool? ?? fileShas.isNotEmpty,
      state: state,
      fileShas: fileShas,
      coverUrlByBookId: strMap(json['coverUrlByBookId']),
      proofPath: proofUnreadable ? null : proof,
      // A keyed catalogue without a recorded books.json is a contradiction,
      // and the safe reading of a contradiction is "not keyed".
      catalogueKeyed:
          json['catalogueKeyed'] == true &&
          fileShas.containsKey(_booksJsonPath),
    );
  }

  /// The schema this build writes.
  static const int currentSchema = 2;

  /// Schema of the record this object was read from (1 for a legacy record,
  /// 2 for one written by this build).
  final int schema;

  /// "owner/name" this manifest describes; null in the empty manifest.
  final String? repo;

  /// Branch this manifest describes; null in a legacy/empty manifest.
  final String? branch;

  /// Head commit the recorded paths were published at; null when unknown.
  final String? headSha;

  /// True when this app wrote the recorded paths on this target and may
  /// therefore delete the ones a section drops (R13).
  final bool ownershipConfirmed;

  /// How far the recorded publication has been proven (R5).
  final PublishState state;

  /// Published file path → git blob sha last uploaded for it.
  final Map<String, String> fileShas;

  /// Book id (as string) → the `coverUrl` value at last publish. Drives the
  /// source-identity skip for REMOTE covers.
  final Map<String, String> coverUrlByBookId;

  /// The file that proves the commit at [headSha] (ADR 0019 Decision 10), or
  /// null for a record written before ADR 0019 — the caller then uses the
  /// per-section file it always used.
  final PublishProofPath? proofPath;

  /// True when the `books.json` recorded here carries item keys written by
  /// this phone (ADR 0019 Decision 7b), so `availability.json` can be matched
  /// against it.
  ///
  /// It is a claim about ONE exact `books.json`: it survives only while the
  /// branch still holds that file ([reconciledFrom], [afterCommit]).
  ///
  /// INVARIANT (ADR 0019 Decision 3): keys depend on the cover salt and the
  /// internal ids. Any flow that replaces the salt or renumbers ids must
  /// clear this flag (`test/architecture/publish_salt_invariant_test.dart`).
  @override
  final bool catalogueKeyed;

  /// The empty manifest (no publication recorded on this phone).
  static const PublishManifest empty = PublishManifest();

  /// The catalogue file whose keys [catalogueKeyed] describes.
  static const String _booksJsonPath = 'books.json';

  /// True when this record predates schema 2.
  bool get isLegacy => schema < currentSchema;

  /// The last-published sha for [path], or null.
  @override
  String? shaFor(String path) => fileShas[path];

  /// The cover source URL recorded for [key] (the decider's
  /// `<itemId>` / `periodical:<uid>` key), or null.
  @override
  String? coverSourceFor(String key) => coverUrlByBookId[key];

  /// Every app-owned path this record claims.
  @override
  Iterable<String> get ownedPaths => fileShas.keys;

  /// True when this record describes exactly [ownerRepo] on [branch].
  bool describes({required String ownerRepo, required String branch}) =>
      repo == ownerRepo && this.branch == branch;

  /// The record to publish FROM, rebuilt against what the remote says now.
  ///
  /// Rules (R6), each one deliberate:
  ///  - shas always come from [tree]: a stale local sha would make a changed
  ///    file look unchanged and skip its upload, so the site would keep old
  ///    bytes;
  ///  - the claimed path set survives ONLY when this record describes the same
  ///    repo and branch. A different site (or a re-pointed Pages branch) is an
  ///    unknown target: claiming its paths would authorise deleting files we
  ///    may not have written;
  ///  - a claimed path that is gone from the tree is dropped (it is already
  ///    deleted remotely, so there is nothing left to delete);
  ///  - paths in the tree that this record does not claim are NEVER adopted —
  ///    they belong to the human, and the section merge must not be able to
  ///    delete them;
  ///  - `state` survives only while it describes this exact head; otherwise
  ///    the record is `deployed` again (an unproven commit). The proof path
  ///    describes that same head, so it follows the same rule;
  ///  - `catalogueKeyed` survives only while the branch still holds the exact
  ///    `books.json` this phone recorded. Another phone (with another salt)
  ///    or an older Pitak may have republished the catalogue since, and its
  ///    keys would not match ours (ADR 0019 Decision 7b, plan A.6 #19).
  PublishManifest reconciledFrom({
    required GitHubTreeSnapshot tree,
    required String ownerRepo,
    required String branch,
  }) {
    final sameSite = describes(ownerRepo: ownerRepo, branch: branch);
    final claimed = sameSite ? fileShas : const <String, String>{};
    final confirmed = <String, String>{};
    for (final path in claimed.keys) {
      final sha = tree.files[path];
      if (sha != null) confirmed[path] = sha;
    }
    final sameHead = sameSite && headSha != null && headSha == tree.headSha;
    final stillProven = sameHead && state != PublishState.deployed;
    final recordedBooks = claimed[_booksJsonPath];
    final stillKeyed =
        catalogueKeyed &&
        recordedBooks != null &&
        tree.files[_booksJsonPath] == recordedBooks;
    return PublishManifest(
      repo: ownerRepo,
      branch: branch,
      headSha: tree.headSha,
      ownershipConfirmed:
          sameSite && ownershipConfirmed && confirmed.isNotEmpty,
      state: stillProven ? state : PublishState.deployed,
      fileShas: confirmed,
      // Cover sources describe the LIBRARY's cover identity, not the site, so
      // they survive a target change: they only tell the next publish whether
      // a remote cover URL is still the same source.
      coverUrlByBookId: coverUrlByBookId,
      proofPath: sameHead ? proofPath : null,
      catalogueKeyed: stillKeyed,
    );
  }

  /// The record to persist right after a commit landed at [commitSha].
  ///
  /// [mergedShas] is the merge's complete app-owned set. The record's
  /// ownership flag becomes true because this app has just written those paths
  /// itself, and its state is `deployed` until a read-back proves otherwise.
  ///
  /// [wroteKeyedCatalogue] says that this commit wrote a `books.json` with
  /// item keys (a catalogue publish from plan S3 on). [catalogueKeyed] then
  /// becomes:
  ///  - true when this commit wrote a keyed `books.json`;
  ///  - unchanged when the commit left `books.json` exactly as it was (an
  ///    events or availability commit), because the keyed file is still the
  ///    one on the branch;
  ///  - false otherwise, including when no `books.json` is recorded at all.
  ///
  /// [proofPath] names the file that proves THIS commit (ADR 0019
  /// Decision 10): `booksJson` for a catalogue commit (a combined catalogue +
  /// availability commit and a move included), `eventsJson` for events,
  /// `availabilityJson` / `availabilityJsonAbsent` for the availability lane.
  /// It is required so no commit can forget it and fall back to a fixed
  /// per-section file, which is the gap of plan A.1 item 8.
  ///
  /// A proof that disagrees with [mergedShas] (it expects a file this commit
  /// does not record, or an absence this commit does record) cannot prove
  /// anything. The record then reads exactly like one decoded with a damaged
  /// proof ([PublishManifest.fromJson]): no proof and no head, so the next
  /// publish treats it as "unknown state" and its own read-back decides. Only
  /// a caller bug can cause it, and this is its fail-closed form.
  PublishManifest afterCommit({
    required String commitSha,
    required Map<String, String> mergedShas,
    required Map<String, String> coverUrlByBookId,
    required PublishProofPath proofPath,
    bool wroteKeyedCatalogue = false,
  }) {
    final books = mergedShas[_booksJsonPath];
    final booksUnchanged = books != null && books == fileShas[_booksJsonPath];
    final provable = proofPath.agreesWith(mergedShas);
    return PublishManifest(
      repo: repo,
      branch: branch,
      headSha: provable ? commitSha : null,
      ownershipConfirmed: true,
      fileShas: mergedShas,
      coverUrlByBookId: coverUrlByBookId,
      proofPath: provable ? proofPath : null,
      catalogueKeyed:
          books != null &&
          (wroteKeyedCatalogue || (booksUnchanged && catalogueKeyed)),
    );
  }

  /// The same record, now proven to be served by the live site.
  PublishManifest asLive() => PublishManifest(
    schema: schema,
    repo: repo,
    branch: branch,
    headSha: headSha,
    ownershipConfirmed: ownershipConfirmed,
    state: PublishState.live,
    fileShas: fileShas,
    coverUrlByBookId: coverUrlByBookId,
    proofPath: proofPath,
    catalogueKeyed: catalogueKeyed,
  );

  /// The same record, but no longer vouching for the keys in its
  /// `books.json` ([catalogueKeyed] false); everything else is kept.
  ///
  /// Used when the ids behind the keys may now name other items: a restore
  /// that activates a new data generation (plan J9, S6). The next catalogue
  /// publish writes fresh keys and sets the flag again.
  PublishManifest withoutCatalogueKeys() => PublishManifest(
    schema: schema,
    repo: repo,
    branch: branch,
    headSha: headSha,
    ownershipConfirmed: ownershipConfirmed,
    state: state,
    fileShas: fileShas,
    coverUrlByBookId: coverUrlByBookId,
    proofPath: proofPath,
  );

  /// The exact moved-page record after retirement read-back succeeds.
  ///
  /// The head is the retirement commit (or an already-retired head found by
  /// Retry), never the old live anchor. Only moved files remain owned. A
  /// moved page has no catalogue, so it carries no keys and needs no proof
  /// path (a retired record is never checked again).
  PublishManifest asRetired({
    required String commitSha,
    required Map<String, String> movedFileShas,
  }) => PublishManifest(
    schema: schema,
    repo: repo,
    branch: branch,
    headSha: commitSha,
    ownershipConfirmed: true,
    state: PublishState.retired,
    fileShas: Map.unmodifiable(movedFileShas),
    coverUrlByBookId: coverUrlByBookId,
  );

  /// Encodes this record. Public data only; no token, no credential.
  Map<String, Object?> toJson() => {
    'schema': schema,
    if (repo != null) 'repo': repo,
    if (branch != null) 'branch': branch,
    if (headSha != null) 'headSha': headSha,
    'ownershipConfirmed': ownershipConfirmed,
    'state': state.name,
    'fileShas': fileShas,
    'coverUrlByBookId': coverUrlByBookId,
    if (proofPath case final proofPath?) 'proofPath': proofPath.name,
    'catalogueKeyed': catalogueKeyed,
  };

  static PublishState? _stateFrom(Object? raw) {
    for (final value in PublishState.values) {
      if (value.name == raw) return value;
    }
    // An unknown state is not "live": the caller treats null as `deployed`.
    return null;
  }

  @override
  String toString() =>
      'PublishManifest($repo@$branch, $state, ${fileShas.length} files)';
}
