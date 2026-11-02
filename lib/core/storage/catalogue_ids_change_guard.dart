/// The port every flow that changes what an item id names runs through
/// (core; ADR 0019 Decision 3, plan J9).
///
/// Why it exists (beginner note): the public item keys on a published site
/// are a salted hash of each item's internal id. Restoring another library's
/// backup, or overwriting the catalogue from a file, makes the same id name a
/// different book (or the same book get a new id). The live `books.json`
/// then carries keys for the OLD meaning of the ids, and an automatic
/// availability update computed from the NEW library would put wrong
/// *Available / Not available* tags on real books.
///
/// So such a flow hands its change to this guard. The publish feature's
/// implementation (`CatalogueKeysReset.beforeIdsChange`) first marks both
/// publish records as "keys no longer vouched for" and clears the lane's
/// saved sets, inside the publish queue, and only then runs the change. If
/// that cannot be saved, the change does not run (fail closed).
///
/// A restore also replaces the covers folder, so the same step makes both
/// records forget which LOCAL cover files they published (ADR 0020
/// Decision 4): the next publish reads those covers again instead of
/// trusting a file name whose bytes may have changed.
///
/// It lives in core because two features (backup, import/export) call it and
/// a third (publish) implements it; none of them imports another for it.
library;

/// Runs [change] after everything published against the old ids has been
/// marked unusable; throws instead of running it when that fails.
typedef CatalogueIdsChangeGuard =
    Future<T> Function<T>(Future<T> Function() change);
