/// One file a publish wants on the site (publish domain, pure Dart;
/// Cloudflare plan E.1/R3).
///
/// Host-neutral on purpose: the GitHub adapter turns it into a git tree
/// entry and the Cloudflare adapter into a static asset, but BOTH consume the
/// same bytes built by the same section builder (R3: build once, one
/// implementation).
///
/// `upload` is a HOST HINT, not a decision the domain makes: GitHub uses it
/// to skip re-uploading an unchanged blob; Cloudflare decides from the asset
/// hashes the API asks for, so it ignores the flag.
library;

/// One built site file.
final class PublishFile {
  /// Creates a built file. [bytes] is empty when [upload] is false and only
  /// the known content hash is carried (a reused published file).
  const PublishFile({
    required this.path,
    required this.bytes,
    required this.gitSha,
    required this.upload,
  });

  /// Site-relative path (`books.json`, `covers/<hash>.jpg`). No leading slash
  /// — the site-path policy is applied by the host adapter (R23).
  final String path;

  /// The file's bytes; empty when the file is reused unchanged.
  final List<int> bytes;

  /// The file's git blob sha — the host-neutral CONTENT identity used for the
  /// incremental diff and the snapshot digest.
  final String gitSha;

  /// True = changed/new (bytes must be uploaded); false = unchanged, the
  /// known [gitSha] may be reused.
  final bool upload;

  /// Byte length of [bytes] (0 for a reused file — the live size is known to
  /// the host, not here).
  int get size => bytes.length;
}
