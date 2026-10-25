/// Which cover an issue shows (periodicals domain, pure Dart; ADR 0014 W4).
///
/// An issue may carry its own cover; when it has none, the series cover
/// stands in — on the list, the detail page and the published site. One
/// rule, one place, so the startup cover janitor and the publish pipeline
/// cannot disagree about which files are live.
library;

import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';

/// Cover resolution for issues.
abstract final class IssueCover {
  /// The cover reference to show for [item]: its own `coverUrl` when
  /// non-blank, else the [periodical]'s cover, else null. Works for any
  /// item (a book simply has no periodical to fall back to).
  static String? resolve(CatalogueItem item, Periodical? periodical) {
    final own = item.coverUrl?.trim() ?? '';
    if (own.isNotEmpty) return own;
    final series = periodical?.coverUrl?.trim() ?? '';
    return series.isEmpty ? null : series;
  }
}
