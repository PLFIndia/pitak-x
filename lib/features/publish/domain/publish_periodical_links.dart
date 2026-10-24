/// Canonical periodical/issue soft-link validation for world-facing publish.
///
/// A published issue must resolve to exactly one stored series, including a
/// soft-removed series whose cover it may still inherit. Otherwise the viewer
/// would silently render an ungrouped issue or an incomplete cover fallback.
/// This pure-Dart check runs before cover IO or artifact construction.
library;

import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/periodical_identity.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';

/// Resolves the canonical series lookup used by publish, or null on bad data.
final class PublishPeriodicalLinks {
  const PublishPeriodicalLinks._();

  /// Returns one unambiguous series per UID when every link is publishable.
  ///
  /// Null means a series UID is missing, blank, noncanonical, or duplicated,
  /// or a live issue has a noncanonical UID or no matching series. [books]
  /// must already exclude removed items. Removed series intentionally remain
  /// in the returned map: their live issues keep the established cover
  /// fallback even though the series itself publishes no top-level entry.
  static Map<String, Periodical>? resolve({
    required List<CatalogueItem> books,
    required List<Periodical> periodicals,
  }) {
    final byUid = <String, Periodical>{};
    for (final series in periodicals) {
      final uid = series.periodicalUid;
      if (uid == null ||
          uid.isEmpty ||
          canonicalPeriodicalUid(uid) != uid ||
          byUid.containsKey(uid)) {
        return null;
      }
      byUid[uid] = series;
    }
    for (final item in books) {
      final issue = item.issue;
      if (issue == null) continue;
      final uid = issue.periodicalUid;
      if (uid.isEmpty ||
          canonicalPeriodicalUid(uid) != uid ||
          !byUid.containsKey(uid)) {
        return null;
      }
    }
    return Map<String, Periodical>.unmodifiable(byUid);
  }
}
