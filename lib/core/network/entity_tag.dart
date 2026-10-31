/// HTTP entity-tag (`ETag`) grammar check (core; ADR 0018).
///
/// What an ETag is (beginner note): a short fingerprint a web server sends
/// alongside a file. On Cloudflare it is a hash of the file's bytes; on GitHub
/// Pages it is built from the file's modification time and size. When the app
/// asks for the same file again with `If-None-Match: <that tag>`, the server
/// answers `304 Not Modified` with NO body if the file is unchanged, or a
/// normal `200` with the new file if it changed. That is how the viewer learns
/// "is my saved copy still current?" without downloading the file again.
///
/// Why this class exists: the tag comes from an untrusted host, is stored on
/// disk, and is later SENT BACK as a request header. A value containing CR/LF
/// could try to inject extra headers, and a huge value would bloat storage.
/// So only the RFC 9110 §8.8.3 shape is accepted —
/// `entity-tag = [ "W/" ] DQUOTE *etagc DQUOTE`, `etagc = %x21 / %x23-7E` —
/// with a length cap. The `obs-text` (non-ASCII) alternative is refused on
/// purpose: no legitimate host needs it and refusing it keeps the stored value
/// plain ASCII. Anything else becomes null, which simply means "no tag": the
/// next open downloads the whole file, the safe direction.
library;

/// See the file header.
abstract final class EntityTag {
  /// Longest accepted tag, quotes and `W/` prefix included. Real tags are
  /// tens of characters (GitHub Pages `"689c7eef-386e"`, Cloudflare 32 hex).
  static const int maxLength = 256;

  static final RegExp _grammar = RegExp(r'^(W/)?"[\x21\x23-\x7E]*"$');

  /// Returns [raw] (trimmed) when it is a well-formed entity tag, else null.
  static String? sanitize(String? raw) {
    if (raw == null) return null;
    final value = raw.trim();
    if (value.isEmpty || value.length > maxLength) return null;
    return _grammar.hasMatch(value) ? value : null;
  }
}
