/// A book the user wants to buy. Mirror of Kotlin `WishlistBook` (source app).
///
/// Fully separate from Library (own DB, own UI, own export bucket). No vault
/// data. Pure Dart (AGENTS.md §3.1).
library;

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
