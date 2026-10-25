/// The kind of a catalogue item (ADR 0013 F3) — domain, pure Dart.
///
/// Why an enum and not user-defined categories (beginner note): a kind
/// decides *behaviour* — which detail table a row has, which form opens,
/// which identity rules dedup/merge use. Behaviour is code, so kinds are
/// defined by the app; a user describes an "other" item in its notes. Adding
/// a kind is the recipe in ADR 0013, and every `switch` over the sealed
/// `ItemDetails` union stops compiling until the new kind is handled.
library;

/// What a catalogue row is. Persisted as [token] (a stable string, NOT the
/// ordinal), carried in every wire format (ADR 0014); absent ⇒ [book].
enum ItemKind {
  /// A book — the original and default kind. Its row has no detail table.
  book('book'),

  /// One magazine issue (or a bound volume of issues) belonging to a
  /// periodical; its kind-specific fields are an `IssueOf`.
  magazineIssue('magazine-issue'),

  /// Anything else (a DVD, a board game, a map): no kind-specific fields —
  /// the item's notes say what it is (ADR 0013 O1).
  other('other');

  const ItemKind(this.token);

  /// Stable storage/interchange token (letters and `-` only).
  final String token;

  /// The plural, user-facing name used by the Library kind chips
  /// (Books · Magazines · Others, ADR 0013 U1).
  String get label => switch (this) {
    ItemKind.book => 'Books',
    ItemKind.magazineIssue => 'Magazines',
    ItemKind.other => 'Others',
  };

  /// Tolerant parse, same contract as `AgeGroup.fromToken`: trims and
  /// lower-cases, accepts the token or the enum name, and returns `null` for
  /// anything unknown or blank — never throws. Callers decide what `null`
  /// means: a missing value is a book (ADR 0014), an unknown value is
  /// refused (ADR 0013 F6) — so this method does not default to [book].
  static ItemKind? fromToken(String? raw) {
    final key = raw?.trim().toLowerCase();
    if (key == null || key.isEmpty) return null;
    for (final kind in ItemKind.values) {
      if (kind.token == key || kind.name.toLowerCase() == key) return kind;
    }
    return null;
  }
}
