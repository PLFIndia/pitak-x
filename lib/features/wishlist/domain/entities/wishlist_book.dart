/// A book the user wants to buy. Mirror of Kotlin `WishlistBook` (source app).
///
/// Fully separate from Library (own DB, own UI, own export bucket). No vault
/// data. Pure Dart (AGENTS.md §3.1).
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/features/library/domain/catalogue_rules.dart';

/// How a wishlist entry was created. Stored as enum `name` (upper-case).
enum WishlistSource {
  /// Manually entered by the user.
  manual,

  /// Added via barcode scan.
  scanned,
}

/// Tolerant parsing for [WishlistSource].
extension WishlistSourceX on WishlistSource {
  /// Stable storage token (Kotlin enum `name`, upper-case).
  String get token => name.toUpperCase();

  /// Parses tolerantly; unknown/blank → [WishlistSource.manual] (Kotlin default).
  static WishlistSource fromToken(String? raw) {
    final key = raw?.trim().toUpperCase();
    if (key == null || key.isEmpty) return WishlistSource.manual;
    for (final v in WishlistSource.values) {
      if (v.token == key) return v;
    }
    return WishlistSource.manual;
  }
}

/// A wished-for book. `id == emptyId` means "not yet persisted".
class WishlistBook {
  /// Creates a wishlist entry. Only [title] is required.
  const WishlistBook({
    required this.title,
    this.id = emptyId,
    this.titleTransliteration,
    this.author,
    this.isbn,
    this.publisher,
    this.publishedYear,
    this.coverUrl,
    this.priceEstimate,
    this.priority = priorityMed,
    this.notes,
    this.source = WishlistSource.manual,
    this.addedDate = 0,
    this.purchased = false,
    this.purchasedDate,
    this.needsMetadata = false,
  });

  /// Sentinel meaning "not yet persisted".
  static const int emptyId = 0;

  /// Low priority.
  static const int priorityLow = 0;

  /// Medium priority (default).
  static const int priorityMed = 1;

  /// High priority.
  static const int priorityHigh = 2;

  /// Per-device autoincrement id.
  final int id;

  /// Required title, native script.
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

  /// Cover reference (optional).
  final String? coverUrl;

  /// Estimated price (optional).
  final double? priceEstimate;

  /// Priority: 0 = low, 1 = med (default), 2 = high.
  final int priority;

  /// Free-form notes (optional).
  final String? notes;

  /// How this entry was created.
  final WishlistSource source;

  /// Epoch millis at insert.
  final int addedDate;

  /// True once the user marked it bought.
  final bool purchased;

  /// Epoch millis when purchased; null otherwise.
  final int? purchasedDate;

  /// True if metadata enrichment is still pending.
  final bool needsMetadata;

  /// Validates [book] against the shared [CatalogueRules] (M15) and returns
  /// a normalised copy (title trimmed) or every field error found.
  ///
  /// Same contract as `Book.validate`: every ingress (form, JSON/CSV import,
  /// merge, restore) passes a row through here BEFORE persistence. A priority
  /// outside 0..2 has no matching dropdown item (the edit form asserts), and
  /// a non-finite price makes `jsonEncode` throw on the next export — so both
  /// are rejected here, once, instead of at every consumer.
  static Either<List<FieldError>, WishlistBook> validate(WishlistBook book) {
    final errors = <FieldError>[];

    final title = book.title.trim();
    if (title.isEmpty) {
      errors.add(const FieldError('title', 'is required'));
    }

    final textFields = <String, String?>{
      'title': title,
      'titleTransliteration': book.titleTransliteration,
      'author': book.author,
      'isbn': book.isbn,
      'publisher': book.publisher,
      'notes': book.notes,
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
    if (!CatalogueRules.isValidOptionalDateMillis(book.purchasedDate)) {
      errors.add(
        const FieldError('purchasedDate', 'is not a representable date'),
      );
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
    if (book.priority < priorityLow || book.priority > priorityHigh) {
      errors.add(const FieldError('priority', 'must be 0 (low), 1 or 2'));
    }
    if (!CatalogueRules.isValidPrice(book.priceEstimate)) {
      errors.add(
        const FieldError(
          'priceEstimate',
          'must be a finite number, zero or more',
        ),
      );
    }
    // Cover is NORMALISED, never rejected — same rationale as Book.validate
    // (a pre-M15 row must stay editable; the ref is inert because display and
    // publish re-check the allow-list). Importers report the drop.
    final safeCover = CatalogueRules.isValidCoverRef(book.coverUrl)
        ? (book.coverUrl?.trim().isEmpty ?? true ? null : book.coverUrl!.trim())
        : null;

    if (errors.isNotEmpty) return left(errors);
    if (title == book.title && safeCover == book.coverUrl) return right(book);
    return right(
      WishlistBook(
        id: book.id,
        title: title,
        titleTransliteration: book.titleTransliteration,
        author: book.author,
        isbn: book.isbn,
        publisher: book.publisher,
        publishedYear: book.publishedYear,
        coverUrl: safeCover,
        priceEstimate: book.priceEstimate,
        priority: book.priority,
        notes: book.notes,
        source: book.source,
        addedDate: book.addedDate,
        purchased: book.purchased,
        purchasedDate: book.purchasedDate,
        needsMetadata: book.needsMetadata,
      ),
    );
  }

  /// Returns a copy with the given fields replaced.
  WishlistBook copyWith({
    int? id,
    String? title,
    String? titleTransliteration,
    String? author,
    String? isbn,
    String? publisher,
    int? publishedYear,
    String? coverUrl,
    double? priceEstimate,
    int? priority,
    String? notes,
    WishlistSource? source,
    int? addedDate,
    bool? purchased,
    int? purchasedDate,
    bool? needsMetadata,
  }) {
    return WishlistBook(
      id: id ?? this.id,
      title: title ?? this.title,
      titleTransliteration: titleTransliteration ?? this.titleTransliteration,
      author: author ?? this.author,
      isbn: isbn ?? this.isbn,
      publisher: publisher ?? this.publisher,
      publishedYear: publishedYear ?? this.publishedYear,
      coverUrl: coverUrl ?? this.coverUrl,
      priceEstimate: priceEstimate ?? this.priceEstimate,
      priority: priority ?? this.priority,
      notes: notes ?? this.notes,
      source: source ?? this.source,
      addedDate: addedDate ?? this.addedDate,
      purchased: purchased ?? this.purchased,
      purchasedDate: purchasedDate ?? this.purchasedDate,
      needsMetadata: needsMetadata ?? this.needsMetadata,
    );
  }
}
