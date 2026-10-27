/// Shared HTTP decoding for the GitHub adapters (infrastructure, AGENTS.md
/// §3.3).
///
/// Why this file exists (beginner note): two infrastructure classes read Git
/// Data responses — the commit adapter and the tree reader — and both must
/// apply the SAME rules: only a complete Git SHA-1 is trusted, a malformed body
/// is a typed failure, and a diagnostic never carries response text. Copying
/// those rules would let one copy drift, so they live here once.
library;

import 'dart:convert';

import 'package:pitaka/features/publish/domain/github_api.dart';

/// A complete Git SHA-1: 40 hexadecimal characters, nothing else.
final RegExp gitHubShaPattern = RegExp(r'^[0-9a-fA-F]{40}$');

/// Decodes [body] as a JSON object, or throws [GitHubApiException].
///
/// Deliberately never lets a [FormatException] escape: its message embeds a
/// slice of the response body, and a hostile network controls that text.
Map<String, dynamic> decodeGitHubObject(String body) {
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    throw const GitHubApiException('Malformed JSON response');
  }
  if (decoded is! Map<String, dynamic>) {
    throw const GitHubApiException('Expected a JSON object');
  }
  return decoded;
}

/// Reads the nested `<field>.sha` of a Git object response (a ref, commit or
/// tree), refusing anything that is not a complete SHA-1.
String gitHubObjectSha(String body, String field) {
  final object = decodeGitHubObject(body)[field];
  final sha = object is Map<String, dynamic> ? object['sha'] : null;
  if (sha is! String || !gitHubShaPattern.hasMatch(sha)) {
    throw const GitHubApiException('Malformed Git object SHA');
  }
  return sha;
}

/// A short, bounded excerpt of [body] for a diagnostic. Never user-facing.
String gitHubExcerpt(String body) =>
    body.length <= 200 ? body : body.substring(0, 200);
