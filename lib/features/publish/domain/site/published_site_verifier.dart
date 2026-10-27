/// The bounded, origin-bound read-back used to prove a site really serves
/// what a publish just wrote (publish domain port; Cloudflare plan R16).
///
/// Why a port rather than a raw HTTP call (beginner note): "the file is live"
/// must be provable from the EXACT origin that was published to. A plain GET
/// could follow a redirect to another host, read a different library's file
/// from the same host, or accept an unbounded body — and then a publish would
/// report success for bytes it never wrote. Implementations must therefore:
///  - accept only a canonical site root + a fixed site-relative path;
///  - keep the saved site's origin AND directory on the initial URL;
///  - refuse every redirect (publish verification follows none);
///  - stream with a hard byte cap and an abortable deadline;
///  - allow one generated `rb` cache-buster (publish only — the viewer's
///    no-query rule is untouched).
///
/// Null means "not verifiable": refused, unreachable, oversize or non-2xx.
/// No exception text, URL or body ever crosses this port.
library;

/// Reads one public file from a just-published site.
///
/// One member on purpose: it is an injected SEAM (a fake answers in widget
/// tests), not a data abstraction — the repo's `PublishCoverSaltStore` is the
/// same shape for the same reason.
// ignore: one_member_abstracts
abstract interface class PublishedSiteVerifier {
  /// Returns the body of `<siteUrl><path>` when it came from exactly that
  /// site, within [maxBytes], with no redirect — else null.
  ///
  /// [cacheBuster] appends `?rb=<token>`; pass a fresh token per attempt so a
  /// CDN cannot answer with a stale copy.
  Future<List<int>?> read({
    required String siteUrl,
    required String path,
    required int maxBytes,
    String? cacheBuster,
  });
}

/// Byte cap for a publish read-back of the machine-readable catalogue
/// (`books.json`).
///
/// Mirrors the viewer's interchange cap: a bigger body could never be a valid
/// catalogue for any peer, so reading past it proves nothing. The value is
/// pinned against `PublishedCatalogueCodec.defaultMaxBodyBytes` by a test, so
/// the two copies cannot drift.
const int publishedCatalogueReadBackMaxBytes = 64 * 1024 * 1024;
