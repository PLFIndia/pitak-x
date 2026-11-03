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
/// One more additive field arrived with ADR 0020 (schema still 2):
/// `coverRendition` says which cover recipe (`PublishCoverRendition`) made
/// the recorded covers, so an unchanged cover can be reused without reading
/// or re-encoding it (plan CV2/CV3). Absent reads as unknown: every cover is
/// produced again, as before.
///
/// And one with plan SP1 (ADR 0017 amendment of 2026-11-02, schema still 2):
/// `committedAt` is when GitHub accepted the commit at `headSha`, so the next
/// publish can tell "Pages is still building it" from "the site changed".
/// Absent reads as unknown, which keeps the older, stricter rule.
///
/// And one with plan SP4 (schema still 2): `adoptedFromBackup` says the
/// record came from a restored backup and this phone has not checked it
/// against the site yet, so `reconciledAtUnchangedHead` will not trust it.
/// Absent reads as false (written by this phone).
///
/// PUBLIC data only — repo paths, git blob shas, public cover URLs — so it
/// needs no encryption. The JSON reader is `publish_manifest_json.dart`.
library;

import 'package:pitaka/features/import_export/domain/cover_paths.dart';
import 'package:pitaka/features/publish/domain/github_models.dart';
import 'package:pitaka/features/publish/domain/publish_manifest_json.dart';
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
    this.coverRendition,
    this.committedAt,
    this.adoptedFromBackup = false,
  });

  /// Parses a manifest from [json]; tolerant of missing/odd fields: a
  /// damaged or older value reads as LESS trust, never as a crash. The rules,
  /// field by field, are on [decodePublishManifest]
  /// (`publish_manifest_json.dart`).
  factory PublishManifest.fromJson(Map<String, dynamic> json) =>
      decodePublishManifest(json);

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

  /// The cover rendition every cover recorded here was produced with
  /// (ADR 0020 Decision 3), or null when unknown.
  ///
  /// Like [catalogueKeyed] it is a claim about exact files: it survives a
  /// reconcile only while every recorded cover is still on the branch with
  /// the recorded sha ([reconciledFrom]).
  final int? coverRendition;

  /// When GitHub accepted the commit at [headSha] (epoch ms, this phone's
  /// clock), or null when unknown (plan SP1). It describes that one commit,
  /// so it follows [headSha] exactly like [proofPath] does.
  final int? committedAt;

  /// True when this record came from a restored backup (plan S11) and this
  /// phone has not yet read the site's file list or committed to it itself
  /// (plan SP4).
  ///
  /// Another phone's record is a CLAIM about the site: a backup can be old,
  /// damaged or hand-made. Such a record still works for everything that
  /// checks it against the remote tree, but [reconciledAtUnchangedHead]
  /// refuses it, so the first publish reads the whole tree once. Records this
  /// phone writes after its own read or commit ([reconciledFrom],
  /// [afterCommit], [asRetired]) are its own again (false); the copies made
  /// by [asLive] and friends keep the flag.
  final bool adoptedFromBackup;

  /// The empty manifest (no publication recorded on this phone).
  static const PublishManifest empty = PublishManifest();

  /// The catalogue file whose keys [catalogueKeyed] describes.
  static const String _booksJsonPath = 'books.json';

  /// The site folder of the covers [coverRendition] describes (the
  /// catalogue section's `covers/*`, `SiteSectionOwnership`).
  static const String _coverPathPrefix = 'covers/';

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

  /// [coverRendition]: a GitHub record that survived [reconciledFrom] still
  /// describes the exact cover files on the branch.
  @override
  int? get reusableCoverRendition => coverRendition;

  /// True when some recorded cover source is a file on this phone
  /// (`covers/…` or a legacy `file://` reference), see
  /// [withoutLocalCoverSources].
  bool get hasLocalCoverSources => coverUrlByBookId.values.any(_isLocal);

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
  ///    and the commit time describe that same head, so they follow the same
  ///    rule;
  ///  - `catalogueKeyed` survives only while the branch still holds the exact
  ///    `books.json` this phone recorded. Another phone (with another salt)
  ///    or an older Pitak may have republished the catalogue since, and its
  ///    keys would not match ours (ADR 0019 Decision 7b, plan A.6 #19);
  ///  - `coverRendition` survives only for the same site and only while no
  ///    recorded cover was changed on the branch (a recorded cover that is
  ///    gone simply drops out). If someone else edited one cover, the next
  ///    publish produces EVERY cover again and so puts this phone's own
  ///    pictures back, as every publish did before ADR 0020.
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
    final coversUntouched = claimed.entries
        .where((entry) => entry.key.startsWith(_coverPathPrefix))
        .every((entry) {
          final live = tree.files[entry.key];
          return live == null || live == entry.value;
        });
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
      coverRendition: sameSite && coversUntouched ? coverRendition : null,
      committedAt: sameHead ? committedAt : null,
    );
  }

  /// The record to publish FROM when [ownerRepo]'s [branch] still points at
  /// [headSha], WITHOUT reading the tree (plan SP4); null when this record
  /// cannot vouch for that head, and the caller must read the tree.
  ///
  /// Why no read is needed (beginner note): a git commit id is a fingerprint
  /// of the commit's whole content, so the file list at [headSha] can never
  /// change. A `live` record of this exact repo and branch at that head was
  /// written by this phone from that very file list — its own commit
  /// ([afterCommit]) or a full read ([reconciledFrom]) — so its file shas ARE
  /// what the branch holds at those paths. Feeding them to [reconciledFrom]
  /// as the tree therefore gives exactly the record a full read would give;
  /// the rules stay in ONE place.
  ///
  /// Null when the record:
  ///  - is not `live`: a commit no read has proven yet (`deployed`) must go
  ///    through the full read and its pre-publish check, as before;
  ///  - describes another repo or branch, or names another head (someone
  ///    else committed, or the record is a legacy one with no head);
  ///  - came from a backup ([adoptedFromBackup]): another phone's claim is
  ///    checked against the real tree once before it is trusted.
  PublishManifest? reconciledAtUnchangedHead({
    required String ownerRepo,
    required String branch,
    required String headSha,
  }) {
    if (state != PublishState.live ||
        adoptedFromBackup ||
        this.headSha != headSha ||
        !describes(ownerRepo: ownerRepo, branch: branch)) {
      return null;
    }
    return reconciledFrom(
      tree: GitHubTreeSnapshot(
        repo: ownerRepo,
        branch: branch,
        headSha: headSha,
        files: fileShas,
        truncated: false,
      ),
      ownerRepo: ownerRepo,
      branch: branch,
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
  ///
  /// [coverRendition] travels with [coverUrlByBookId]: a commit that wrote
  /// the catalogue passes its section's rendition and cover sources; any
  /// other commit passes this record's own, unchanged. It is required for
  /// the same reason as [proofPath]: no commit may forget it.
  ///
  /// [committedAt] is when GitHub answered the commit (the clock read AFTER
  /// it returned: a paced upload can take many minutes), required for the
  /// same reason (plan SP1).
  PublishManifest afterCommit({
    required String commitSha,
    required Map<String, String> mergedShas,
    required Map<String, String> coverUrlByBookId,
    required int? coverRendition,
    required PublishProofPath proofPath,
    required int committedAt,
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
      coverRendition: coverRendition,
      committedAt: provable ? committedAt : null,
    );
  }

  /// The same record, now proven to be served by the live site.
  PublishManifest asLive() => _copyWith(state: PublishState.live);

  /// The same record, but no longer vouching for the keys in its
  /// `books.json` ([catalogueKeyed] false); everything else is kept.
  ///
  /// Used when the ids behind the keys may now name other items: a restore
  /// that activates a new data generation (plan J9, S6). The next catalogue
  /// publish writes fresh keys and sets the flag again.
  PublishManifest withoutCatalogueKeys() => _copyWith(catalogueKeyed: false);

  /// The same record, but forgetting which LOCAL cover file each published
  /// cover came from; remote cover sources and everything else are kept.
  ///
  /// Used before a restore switches to a new data generation (ADR 0020
  /// Decision 4): the restored covers folder may hold different bytes under
  /// a file name this record names, so the next publish must read those
  /// covers again instead of trusting the name. It uploads only the ones
  /// whose bytes really differ.
  ///
  /// [exceptLeaves] keeps `covers/<leaf>` sources whose file is named there:
  /// a record adopted from a backup keeps the covers that backup carried
  /// with it (ADR 0020 Decision 7, plan S11; `coverSourcesKeptAfterNewCovers`).
  PublishManifest withoutLocalCoverSources({
    Set<String> exceptLeaves = const {},
  }) => _copyWith(
    coverUrlByBookId: coverSourcesKeptAfterNewCovers(
      coverUrlByBookId,
      keptLeaves: exceptLeaves,
    ),
  );

  /// The same record, marked as taken from a restored backup
  /// ([adoptedFromBackup] true); everything else is kept. Only the restore
  /// adopter calls it (plan S11, SP4).
  PublishManifest asAdoptedFromBackup() => _copyWith(adoptedFromBackup: true);

  /// This record with only the given fields replaced. The four derived
  /// records above share this ONE copy, so a field added later cannot be
  /// forgotten in one of them (beginner note: that is how a record silently
  /// loses a fact on its way through `asLive`).
  PublishManifest _copyWith({
    PublishState? state,
    Map<String, String>? coverUrlByBookId,
    bool? catalogueKeyed,
    bool? adoptedFromBackup,
  }) => PublishManifest(
    schema: schema,
    repo: repo,
    branch: branch,
    headSha: headSha,
    ownershipConfirmed: ownershipConfirmed,
    state: state ?? this.state,
    fileShas: fileShas,
    coverUrlByBookId: coverUrlByBookId ?? this.coverUrlByBookId,
    proofPath: proofPath,
    catalogueKeyed: catalogueKeyed ?? this.catalogueKeyed,
    coverRendition: coverRendition,
    committedAt: committedAt,
    adoptedFromBackup: adoptedFromBackup ?? this.adoptedFromBackup,
  );

  /// The exact moved-page record after retirement read-back succeeds.
  ///
  /// The head is the retirement commit (or an already-retired head found by
  /// Retry), never the old live anchor. Only moved files remain owned. A
  /// moved page has no catalogue, so it carries no keys, no cover rendition
  /// and needs no proof path or commit time (a retired record is never
  /// checked again).
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
    if (coverRendition case final rendition?) 'coverRendition': rendition,
    if (committedAt case final at?) 'committedAt': at,
    if (adoptedFromBackup) 'adoptedFromBackup': true,
  };

  /// The ONE local/remote rule for cover sources (`CoverPaths.isLocal`),
  /// shared with the cover decider.
  static bool _isLocal(String source) => CoverPaths.isLocal(source);

  @override
  String toString() =>
      'PublishManifest($repo@$branch, $state, ${fileShas.length} files)';
}
