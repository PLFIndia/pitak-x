/// Stable Android notification ids per library (PLAN.md §4).
///
/// Why hash the URL (beginner note): Android replaces a notification when
/// the same id is posted again. Deriving the id from the canonical URL
/// makes "one alert per library, newest replaces oldest" fall out
/// naturally, and the id survives process death without a counter file.
/// Ids are persisted anyway so a retry reuses exactly the same number.
///
/// `String.hashCode` is never used: it is not stable across Dart versions
/// or platforms, so a persisted id could stop matching after an update.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Reserved for the group summary.
const int summaryNotificationId = 0;

/// Derives nonzero 31-bit ids from canonical site URLs.
abstract final class NotificationIdAllocator {
  /// A candidate id for [siteUrl] that is nonzero and not in [taken].
  /// Collisions are resolved deterministically by rehashing the
  /// length-prefixed URL with a counter, so the same inputs always give the
  /// same answer.
  static int allocate(String siteUrl, {required Set<int> taken}) {
    for (var counter = 0; ; counter++) {
      final candidate = _candidate(siteUrl, counter);
      if (candidate != summaryNotificationId && !taken.contains(candidate)) {
        return candidate;
      }
    }
  }

  static int _candidate(String siteUrl, int counter) {
    final encoded = utf8.encode(siteUrl);
    final input = <int>[
      ...ascii.encode('${encoded.length}:'),
      ...encoded,
      ...ascii.encode(':$counter'),
    ];
    final bytes = sha256.convert(input).bytes;
    return ((bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3]) &
        0x7fffffff;
  }
}
