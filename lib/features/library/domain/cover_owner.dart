/// The persisted entity that owns a cover reference (library domain, pure
/// Dart). A series cover displayed by an issue remains periodical-owned; the
/// issue is only the place where that cover happens to render.
library;

/// The two persistence namespaces that can own a cover.
enum CoverOwnerKind {
  /// A row in the shared catalogue-item store.
  catalogueItem,

  /// A magazine series, identified by its stable UID.
  periodical,
}

/// Structural cover identity: rebuilding the same kind/id compares equal, so
/// download deduplication cannot depend on class-instance identity.
typedef CoverOwner = ({CoverOwnerKind kind, String id});

/// Small factories keep owner construction consistent without introducing a
/// second identity model or importing either feature's entities.
abstract final class CoverOwners {
  /// The catalogue row with per-device integer [id].
  static CoverOwner item(int id) =>
      (kind: CoverOwnerKind.catalogueItem, id: id.toString());

  /// The periodical with stable cross-device [periodicalUid].
  static CoverOwner periodical(String periodicalUid) =>
      (kind: CoverOwnerKind.periodical, id: periodicalUid);
}
