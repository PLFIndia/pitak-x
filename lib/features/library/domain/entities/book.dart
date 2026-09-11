/// Pure domain model for a book in the user's library.
///
/// Mirror of Kotlin `dev.khoj.pitaka.domain.model.Book` (source app). Pure
/// Dart: no Flutter/Drift/Riverpod imports (AGENTS.md §3.1). Immutable;
/// `copyWith` for edits.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/features/library/domain/catalogue_rules.dart';

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

  /// Validates [book] against the shared [CatalogueRules] (M15) and returns
  /// a normalised copy (title trimmed) or every field error found.
  ///
  /// This is the single gate every ingress — add/edit forms, JSON/CSV import,
  /// merge, backup restore — must pass a row through BEFORE persistence, so a
  /// crafted file cannot plant values that crash normal screens later (see
  /// `catalogue_rules.dart` for the threat model). The plain constructor stays
  /// for already-trusted data (DB mapper, `copyWith` on a persisted row).
  static Either<List<FieldError>, Book> validate(Book book) {
    final errors = <FieldError>[];

    final title = book.title.trim();
    if (title.isEmpty) {
      errors.add(const FieldError('title', 'is required'));
    }

    // Every persisted text field is capped (M4/M15): one giant cell must not
    // bloat the database. Importers truncate + report; forms reject.
    final textFields = <String, String?>{
      'title': title,
      'bookUid': book.bookUid,
      'titleTransliteration': book.titleTransliteration,
      'author': book.author,
      'isbn': book.isbn,
      'publisher': book.publisher,
      'genre': book.genre,
      'language': book.language,
      'notes': book.notes,
      'location': book.location,
      'sourceDetail': book.sourceDetail,
      'addedBy': book.addedBy,
    };
    for (final entry in textFields.entries) {
      if (!CatalogueRules.isValidFieldText(entry.value)) {
        errors.add(
          FieldError(
            entry.key,
            'must be at most ${CatalogueRules.maxFieldChars} characters',
          ),
        );
      }
    }

    if (!CatalogueRules.isValidDateMillis(book.addedDate)) {
      errors.add(const FieldError('addedDate', 'is not a representable date'));
    }
    if (!CatalogueRules.isValidOptionalDateMillis(book.removedAt)) {
      errors.add(const FieldError('removedAt', 'is not a representable date'));
    }
    if (!CatalogueRules.isValidCount(book.copyCount)) {
      errors.add(const FieldError('copyCount', 'must be at least 1'));
    }
    if (!CatalogueRules.isValidCount(book.pageCount)) {
      errors.add(const FieldError('pageCount', 'must be at least 1'));
    }
    if (!CatalogueRules.isValidYear(book.publishedYear)) {
      errors.add(
        const FieldError(
          'publishedYear',
          'must be between ${CatalogueRules.minYear} and '
              '${CatalogueRules.maxYear}',
        ),
      );
    }
    // The cover is NORMALISED, never a rejection (M15): a row already in the
    // database from before this rule could carry a now-disallowed URL, and
    // rejecting would make that book uneditable forever — the edit form
    // copies `base.coverUrl` verbatim and has no UI to clear it. The ref is
    // inert regardless (display and publish re-check the allow-list), so it
    // is simply dropped. Importers notice the drop and report it as a
    // warning; `copyWith` cannot null a field, so rebuild explicitly.
    final safeCover = CatalogueRules.isValidCoverRef(book.coverUrl)
        ? (book.coverUrl?.trim().isEmpty ?? true ? null : book.coverUrl!.trim())
        : null;

    if (errors.isNotEmpty) return left(errors);
    if (title == book.title && safeCover == book.coverUrl) return right(book);
    return right(
      Book(
        id: book.id,
        bookUid: book.bookUid,
        title: title,
        titleTransliteration: book.titleTransliteration,
        author: book.author,
        isbn: book.isbn,
        publisher: book.publisher,
        publishedYear: book.publishedYear,
        genre: book.genre,
        coverUrl: safeCover,
        pageCount: book.pageCount,
        language: book.language,
        notes: book.notes,
        location: book.location,
        sourceType: book.sourceType,
        sourceDetail: book.sourceDetail,
        ageGroup: book.ageGroup,
        addedDate: book.addedDate,
        copyCount: book.copyCount,
        needsMetadata: book.needsMetadata,
        removed: book.removed,
        removedAt: book.removedAt,
        addedBy: book.addedBy,
      ),
    );
  }

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
