/// The only content types Pitak publishes to Cloudflare (publish domain, pure
/// Dart; Cloudflare plan B.7/R23).
///
/// Why an allow-list instead of a guess (beginner note): the upload API takes
/// the served `Content-Type` from the multipart part, so whatever the app sends
/// becomes what a browser sees. A wrong type turns `books.json` into a download
/// and an image into a broken page. Pitak publishes exactly three kinds of
/// file, so anything else is refused BEFORE the upload rather than served with
/// a guessed type.
///
/// The match is case-SENSITIVE on purpose: `X.JPG` is not `x.jpg`. Cloudflare's
/// asset hash keeps the extension's case (B.7), so folding case here would make
/// two different files share one hash and one content type.
library;

import 'package:pitaka/features/publish/domain/site/site_path.dart';

/// The published file types and the exact header each one is served with.
enum CloudflareContentType {
  /// `index.html`, `404.html`, `moved.html`.
  html('html', 'text/html; charset=utf-8'),

  /// `books.json`, `events.json`, `library.json`, `pitak-publish.json`.
  json('json', 'application/json'),

  /// Covers and event posters.
  jpeg('jpg', 'image/jpeg');

  const CloudflareContentType(this.extension, this.header);

  /// The extension this type is published under, without the dot.
  final String extension;

  /// The exact `Content-Type` header value.
  final String header;

  /// The type for [extension] (no dot, case preserved), or null when the
  /// extension is not one Pitak publishes.
  static CloudflareContentType? forExtension(String? extension) {
    if (extension == null) return null;
    for (final type in values) {
      if (type.extension == extension) return type;
    }
    return null;
  }

  /// The type for [path]'s extension, or null when the path has no extension
  /// or one Pitak does not publish.
  static CloudflareContentType? forPath(SitePath path) =>
      forExtension(path.extension);

  /// The type whose exact header is [header], or null.
  ///
  /// Used when reading a stored manifest: the record stores the header it
  /// published with, and a header this build does not know is not guessed into
  /// a type.
  static CloudflareContentType? forHeader(String? header) {
    if (header == null) return null;
    for (final type in values) {
      if (type.header == header) return type;
    }
    return null;
  }
}
