/// Pure domain model for a book in the user's library.
///
/// Mirror of Kotlin `dev.khoj.pitaka.domain.model.Book` (source app). Pure
/// Dart: no Flutter/Drift/Riverpod imports (AGENTS.md §3.1). Immutable;
/// `copyWith` for edits.
library;

/// Fixed provenance categories for `Book.sourceType`. Stored as the Dart enum
/// constant name (e.g. `purchased`) — mirrors Kotlin where it is persisted as
/// the enum `name`. Tolerant parse via [BookSourceTypeX.fromToken].
enum BookSourceType {
  /// Bought.
  purchased,

  /// Received as a gift.
  gift,

  /// Donated to the library.
  donated,

  /// Inherited.
  inherited,

  /// Anything else (free-form detail in `sourceDetail`).
  other,
}

/// Tolerant parsing for [BookSourceType].
extension BookSourceTypeX on BookSourceType {
  /// The stable storage token (Kotlin enum `name`, upper-case).
  String get token => name.toUpperCase();

  /// Parses a stored value tolerantly; unknown/blank → null (never throws).
  static BookSourceType? fromToken(String? raw) {
    final key = raw?.trim().toUpperCase();
    if (key == null || key.isEmpty) return null;
    for (final v in BookSourceType.values) {
      if (v.token == key) return v;
    }
    return null;
  }
}

/// Reader age band.
///
/// Persisted as [token] (stable lowercase string), NOT the ordinal — renaming
/// or reordering can never silently change an existing row's meaning.
/// [sortRank] (not declaration order, not alphabetical) defines band order.
enum AgeGroup {
  /// Suitable for ages above 3.
  above3('above-3', 0),

  /// Suitable for ages above 6.
  above6('above-6', 1),

  /// Suitable for ages above 10.
  above10('above-10', 2),

  /// Suitable for ages above 15.
  above15('above-15', 3),

  /// Advanced / adult reading.
  advanced('advanced', 4);

  const AgeGroup(this.token, this.sortRank);

  /// Stable storage/interchange token (letters, digits, '-').
  final String token;

  /// Band order for the Age-group sort.
  final int sortRank;

  /// Tolerant parse, byte-for-byte equivalent to Kotlin `AgeGroup.fromToken`.
  ///
  /// Accepts the current [token], the current enum name (`above_3`…), AND the
  /// LEGACY pre-"above N" names (`age_0_5/age_6_10/age_11_16/advance`) so old
  /// JSON backups and exported files still import. Legacy→new mirrors the DB
  /// MIGRATION_9_10 exactly (11–16 → above-10; nothing maps to above-15).
  /// Anything unrecognised → null (treated as "unset"), never throws.
  static AgeGroup? fromToken(String? raw) {
    final key = raw?.trim().toLowerCase();
    if (key == null || key.isEmpty) return null;
    for (final v in AgeGroup.values) {
      if (v.token == key) return v;
    }
    switch (key) {
      case 'above_3':
        return AgeGroup.above3;
      case 'above_6':
        return AgeGroup.above6;
      case 'above_10':
        return AgeGroup.above10;
      case 'above_15':
        return AgeGroup.above15;
      case 'advanced':
        return AgeGroup.advanced;
      // Legacy pre-"above N" scheme (mirrors MIGRATION_9_10).
      case 'age_0_5':
        return AgeGroup.above3;
      case 'age_6_10':
        return AgeGroup.above6;
      case 'age_11_16':
        return AgeGroup.above10;
      case 'advance':
        return AgeGroup.advanced;
      default:
        return null;
    }
  }
}

/// A book in the user's library. `id == emptyId` means "not yet persisted".
class Book {
  /// Creates a book. Only [title] is required (matches Kotlin).
  const Book({
    required this.title,
    this.id = emptyId,
    this.bookUid,
    this.titleTransliteration,
    this.author,
    this.isbn,
    this.publisher,
    this.publishedYear,
    this.genre,
    this.coverUrl,
    this.pageCount,
    this.language,
    this.notes,
    this.location,
    this.sourceType,
    this.sourceDetail,
    this.ageGroup,
    this.addedDate = 0,
    this.copyCount = 1,
    this.needsMetadata = false,
    this.removed = false,
    this.removedAt,
    this.addedBy,
  });

  /// Sentinel meaning "not yet persisted".
  static const int emptyId = 0;

  /// Per-device autoincrement id. Meaningless across installs (use [bookUid]).
  final int id;

  /// Stable globally-unique identity (UUID), minted once at first persist and
  /// carried through export/import unchanged. The cross-device merge key.
  /// Null only means "not yet persisted / not yet minted".
  final String? bookUid;

  /// Required title, native script (UTF-8).
  final String title;

  /// Optional Roman-script form for search.
  final String? titleTransliteration;

  /// Author (optional).
  final String? author;

  /// ISBN (optional, unique among non-null values).
  final String? isbn;

  /// Publisher (optional).
  final String? publisher;

  /// Year of publication (optional).
  final int? publishedYear;

  /// Genre (optional).
  final String? genre;

  /// Cover reference: relative `covers/<uuid>.jpg`, legacy `file://`, or remote
  /// `https://`.
  final String? coverUrl;

  /// Page count (optional).
  final int? pageCount;

  /// Language (optional).
  final String? language;

  /// Free-form notes (private; stripped at publish time, not write time).
  final String? notes;

  /// Free-form physical shelf location (private; stripped at publish).
  final String? location;

  /// How this copy was acquired (private; stripped at publish).
  final BookSourceType? sourceType;

  /// Free-form provenance specifics (private; stripped at publish).
  final String? sourceDetail;

  /// Reader age band (public catalog info; NOT stripped at publish).
  final AgeGroup? ageGroup;

  /// Epoch millis at insert; never edited.
  final int addedDate;

  /// Number of physical copies (defaults to 1).
  final int copyCount;

  /// True if metadata enrichment is still pending.
  final bool needsMetadata;

  /// Soft-delete flag; a removed book stays visible but actionless.
  final bool removed;

  /// Epoch millis when removed; null when active.
  final int? removedAt;

  /// Self-asserted maintainer handle that first catalogued this book.
  final String? addedBy;

  /// Returns a copy with the given fields replaced.
  Book copyWith({
    int? id,
    String? bookUid,
    String? title,
    String? titleTransliteration,
    String? author,
    String? isbn,
    String? publisher,
    int? publishedYear,
    String? genre,
    String? coverUrl,
    int? pageCount,
    String? language,
    String? notes,
    String? location,
    BookSourceType? sourceType,
    String? sourceDetail,
    AgeGroup? ageGroup,
    int? addedDate,
    int? copyCount,
    bool? needsMetadata,
    bool? removed,
    int? removedAt,
    String? addedBy,
  }) {
    return Book(
      id: id ?? this.id,
      bookUid: bookUid ?? this.bookUid,
      title: title ?? this.title,
      titleTransliteration: titleTransliteration ?? this.titleTransliteration,
      author: author ?? this.author,
      isbn: isbn ?? this.isbn,
      publisher: publisher ?? this.publisher,
      publishedYear: publishedYear ?? this.publishedYear,
      genre: genre ?? this.genre,
      coverUrl: coverUrl ?? this.coverUrl,
      pageCount: pageCount ?? this.pageCount,
      language: language ?? this.language,
      notes: notes ?? this.notes,
      location: location ?? this.location,
      sourceType: sourceType ?? this.sourceType,
      sourceDetail: sourceDetail ?? this.sourceDetail,
      ageGroup: ageGroup ?? this.ageGroup,
      addedDate: addedDate ?? this.addedDate,
      copyCount: copyCount ?? this.copyCount,
      needsMetadata: needsMetadata ?? this.needsMetadata,
      removed: removed ?? this.removed,
      removedAt: removedAt ?? this.removedAt,
      addedBy: addedBy ?? this.addedBy,
    );
  }
}
