/// Tolerant JSON field coercion for HOSTILE remote payloads (domain, pure).
///
/// Why this exists (beginner note): Open Library and Google Books responses
/// are untrusted input (AGENTS.md §1 "treat every input as hostile"). A
/// plain Dart cast such as `dto['title'] as String?` THROWS `_TypeError` when
/// the server (or a captive portal, or a tampered response) sends a number
/// where a string was expected — and `_TypeError` is an `Error`, not an
/// `Exception`, so an `on Exception` guard does NOT catch it. The result was
/// an unhandled crash from the Lookup button.
///
/// These helpers never throw: a wrong-typed value simply becomes `null`
/// (the field is "unknown"), which is exactly how a lookup should degrade.
/// They are the single blessed way to read a JSON field in the lookup feature.
library;

/// Reads [v] as a non-empty trimmed string, or null for anything else.
String? jsonString(Object? v) {
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}

/// Reads [v] as an int (accepting a whole-number double or a numeric string),
/// or null. Infinity/NaN and out-of-range doubles are rejected — `.toInt()`
/// on them would throw.
int? jsonInt(Object? v) {
  if (v is int) return v;
  if (v is double) {
    if (!v.isFinite || v.abs() > 9007199254740991) return null;
    return v.toInt();
  }
  if (v is String) return int.tryParse(v.trim());
  return null;
}

/// Reads [v] as a JSON object (string-keyed map), or null.
Map<String, dynamic>? jsonMap(Object? v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) {
    // jsonDecode produces Map<String, dynamic>, but be tolerant of Map<dynamic,
    // dynamic> from other decoders; keys that aren't strings are dropped.
    final out = <String, dynamic>{};
    for (final e in v.entries) {
      final k = e.key;
      if (k is String) out[k] = e.value;
    }
    return out;
  }
  return null;
}

/// Reads [v] as a list, or an empty list for anything else.
List<Object?> jsonList(Object? v) => v is List ? v : const [];

/// Reads [v] as a list of non-empty strings, silently skipping other items.
List<String> jsonStringList(Object? v) =>
    jsonList(v).map(jsonString).whereType<String>().toList();
