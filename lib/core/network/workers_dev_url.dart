/// The ONE grammar for a Cloudflare `workers.dev` address (core, pure Dart).
///
/// Why this lives in `core/network/` and not in a feature (Cloudflare plan
/// E.2/R15): TWO features need exactly the same rule and must not drift —
///  - the **reader** (`BookmarkUrl`, network feature) must decide whether a
///    pasted licence/QR address is a real Workers site, and
///  - the **publisher** (`CloudflareSiteUrl`, publish feature, S5) must derive
///    the canonical address of a Worker target.
/// If the publish feature imported the network feature (or vice versa) the
/// layering rule (AGENTS §3.1) would break, so the shared grammar sits in a
/// core leaf both may depend on.
///
/// What a valid address is (Cloudflare plan B.1/R15):
///  - `https://<worker>.<account-subdomain>.workers.dev/`;
///  - the host has EXACTLY four labels: worker, account subdomain,
///    `workers`, `dev` — so the apex (`workers.dev`), a one-label
///    (`name.workers.dev`) and an extra-label
///    (`name.sub.extra.workers.dev`) address are all refused;
///  - the worker label is 1–63 chars of `[a-z0-9-]`, no leading/trailing
///    hyphen (Cloudflare's `workers.dev` rule);
///  - the account-subdomain label is a DNS label: 1–63 chars of `[a-z0-9-]`,
///    starting and ending alphanumeric;
///  - canonical lower-case host, no trailing dot, no userinfo, no non-default
///    port, no query, no fragment;
///  - a stored/published SITE address is the root only (no `/books.json`
///    path), because the site root is the row's identity (docs/ARCHITECTURE
///    §5.6). The fetch-time allow-list may still accept files under it — that
///    is the caller's decision (the `requireRootPath` argument).
///
/// Pure Dart: no Flutter, no IO (AGENTS.md §3.1). Historically the reader
/// accepted any `*.pages.dev` host by suffix; Workers addresses are stricter
/// on purpose — the plan's R15 requires the exact two-label root form.
library;

/// The two leading labels of an already-validated Workers host.
final class WorkersDevSite {
  const WorkersDevSite._({
    required this.workerName,
    required this.accountSubdomain,
  });

  /// The Worker name as it appears in the DNS label (lower-case).
  final String workerName;

  /// The account-wide subdomain label (lower-case).
  final String accountSubdomain;

  /// The canonical host, e.g. `kadugodi-library.kadugodi.workers.dev`.
  String get host => '$workerName.$accountSubdomain.workers.dev';

  /// The canonical site root, e.g.
  /// `https://kadugodi-library.kadugodi.workers.dev/`.
  String get siteUrl => 'https://$host/';

  @override
  String toString() => 'WorkersDevSite($host)';
}

/// Strict parser for `workers.dev` addresses (see the library doc).
abstract final class WorkersDevUrl {
  /// The shared registrable suffix.
  static const String suffix = 'workers.dev';

  /// Maximum length Cloudflare allows for each DNS label.
  static const int maxLabelLength = 63;

  /// True when [host] *claims* to be a Workers host: it is the apex or ends
  /// with `.workers.dev`. Deliberately loose — hostile forms claim the suffix
  /// too, and callers must then use [parseHost] to decide.
  static bool claimsWorkersSuffix(String host) {
    final lower = host.toLowerCase();
    return lower == suffix || lower.endsWith('.$suffix');
  }

  /// The two labels of a valid Workers host, or null.
  ///
  /// [host] is matched case-insensitively (DNS is case-insensitive) and the
  /// returned labels are lower-cased; a trailing dot is NOT accepted (a
  /// canonical address carries none, and `evil.workers.dev.` must not sneak
  /// past a suffix comparison elsewhere).
  static WorkersDevSite? parseHost(String? host) {
    final lower = host?.toLowerCase() ?? '';
    if (lower.isEmpty) return null;
    final labels = lower.split('.');
    if (labels.length != 4) return null;
    if (labels[2] != 'workers' || labels[3] != 'dev') return null;
    final worker = labels[0];
    final subdomain = labels[1];
    if (!_isWorkerLabel(worker)) return null;
    if (!_isSubdomainLabel(subdomain)) return null;
    return WorkersDevSite._(workerName: worker, accountSubdomain: subdomain);
  }

  /// Parses a full address. With [requireRootPath] (the default — the reader's
  /// stored-site rule) the path must be exactly `/`; without it, a file path
  /// under the same host is accepted so the viewer can fetch `books.json`
  /// from a site it validated at the root.
  static WorkersDevSite? parse(String? raw, {bool requireRootPath = true}) {
    final trimmed = raw?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return null;
    if (uri.scheme.toLowerCase() != 'https') return null;
    if (uri.userInfo.isNotEmpty) return null;
    if (!uri.hasAuthority) return null;
    if (uri.hasPort && uri.port != 443) return null;
    if (uri.hasQuery || uri.hasFragment) return null;
    // An address with no path (`…workers.dev`) and the root (`…workers.dev/`)
    // name the same site; every other path is a file/deeper directory.
    if (requireRootPath && uri.path.isNotEmpty && uri.path != '/') return null;
    return parseHost(uri.host);
  }

  /// Cloudflare's Worker-name rule: 1–63 of `[a-z0-9-]`, no edge hyphen.
  static bool _isWorkerLabel(String label) {
    if (label.isEmpty || label.length > maxLabelLength) return false;
    if (label.startsWith('-') || label.endsWith('-')) return false;
    for (final unit in label.codeUnits) {
      if (!_isLowerAlnum(unit) && unit != _hyphen) return false;
    }
    return true;
  }

  /// A DNS label: 1–63 of `[a-z0-9-]`, starting and ending alphanumeric.
  static bool _isSubdomainLabel(String label) {
    if (label.isEmpty || label.length > maxLabelLength) return false;
    if (!_isLowerAlnum(label.codeUnitAt(0))) return false;
    if (!_isLowerAlnum(label.codeUnitAt(label.length - 1))) return false;
    for (final unit in label.codeUnits) {
      if (!_isLowerAlnum(unit) && unit != _hyphen) return false;
    }
    return true;
  }

  static const int _hyphen = 0x2d; // '-'

  /// ASCII `a-z` or `0-9`. Non-ASCII (an internationalized name pasted
  /// without punycode) and upper-case (folded before this runs) are refused.
  static bool _isLowerAlnum(int unit) =>
      (unit >= 0x61 && unit <= 0x7a) || (unit >= 0x30 && unit <= 0x39);
}
