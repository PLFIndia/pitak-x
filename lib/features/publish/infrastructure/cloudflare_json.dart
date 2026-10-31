/// Bounded JSON decoding for hostile Cloudflare API responses.
///
/// The byte cap is enforced by the transport before this file is called. This
/// file adds the remaining R21 defenses: a string-aware depth scan BEFORE
/// `jsonDecode`, a strict Cloudflare envelope, and small typed field readers.
/// No reader ever includes response text in an error.
library;

import 'dart:convert';

import 'package:pitaka/core/text/json_nesting_depth.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_limits.dart';

/// A fixed, redacted JSON refusal. The transport maps this to its public typed
/// exception; response text and parser exception details never cross that line.
final class CloudflareJsonException implements Exception {
  /// Creates a refusal.
  const CloudflareJsonException();

  @override
  String toString() =>
      'CloudflareJsonException(malformed or unbounded response)';
}

/// Decodes one Cloudflare envelope after enforcing the depth cap.
Map<String, dynamic> decodeCloudflareEnvelope(List<int> bytes) {
  final String text;
  try {
    text = utf8.decode(bytes);
  } on FormatException {
    throw const CloudflareJsonException();
  }
  if (JsonNestingDepth.maxDepthOf(text) > CloudflareLimits.maxJsonDepth) {
    throw const CloudflareJsonException();
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    throw const CloudflareJsonException();
  }
  if (decoded is! Map<String, dynamic> || decoded['success'] is! bool) {
    throw const CloudflareJsonException();
  }
  final errors = decoded['errors'];
  if (errors != null && errors is! List) throw const CloudflareJsonException();
  return decoded;
}

/// Reads an object field with an endpoint-specific entry bound.
Map<String, dynamic> cloudflareObject(Object? value, {int maxEntries = 32}) {
  if (value is! Map<String, dynamic> || value.length > maxEntries) {
    throw const CloudflareJsonException();
  }
  return value;
}

/// Reads a list field with an endpoint-specific element bound.
List<Object?> cloudflareList(Object? value, {required int maxEntries}) {
  if (value is! List || value.length > maxEntries) {
    throw const CloudflareJsonException();
  }
  return value;
}

/// Reads a bounded string. Empty strings are refused unless explicitly allowed.
String cloudflareString(
  Object? value, {
  required int maxLength,
  bool allowEmpty = false,
}) {
  if (value is! String ||
      value.length > maxLength ||
      (!allowEmpty && value.isEmpty)) {
    throw const CloudflareJsonException();
  }
  return value;
}

/// Reads a boolean field; strings such as `"false"` are not coerced.
bool cloudflareBool(Object? value) {
  if (value is! bool) throw const CloudflareJsonException();
  return value;
}

/// Reads an integer field in the supplied inclusive range.
int cloudflareInt(Object? value, {required int min, required int max}) {
  if (value is! int || value < min || value > max) {
    throw const CloudflareJsonException();
  }
  return value;
}

/// Reads only numeric Cloudflare error codes. Raw `message` text is
/// deliberately never inspected, copied, logged, or exposed to the caller.
List<int> cloudflareErrorCodes(Map<String, dynamic> envelope) {
  final raw = envelope['errors'];
  if (raw == null) return const [];
  final errors = cloudflareList(raw, maxEntries: 32);
  final codes = <int>[];
  for (final error in errors) {
    final object = cloudflareObject(error, maxEntries: 8);
    final code = object['code'];
    // A non-numeric code is malformed rather than something to stringify.
    codes.add(cloudflareInt(code, min: 0, max: 1000000));
  }
  return List<int>.unmodifiable(codes);
}
