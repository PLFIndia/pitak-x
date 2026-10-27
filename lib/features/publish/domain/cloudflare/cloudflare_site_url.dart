/// A CONFIRMED Cloudflare site address (publish domain, pure Dart; Cloudflare
/// plan R15/C9).
///
/// "Confirmed" is the whole point (beginner note): a manually typed account
/// subdomain is only a candidate until a verification deploy proves that the
/// address really serves this Worker. This type is the confirmed one — it is
/// what a `CloudflarePublishTarget`, `library.json.siteUrl`, a share link and a
/// QR card may be built from. The unproven candidate is a different type
/// (`UnverifiedCloudflareAddress`) and has no conversion to this one, so
/// "unverified address became a publish target" is not expressible.
///
/// The grammar is the shared `WorkersDevUrl` (core/network), the same one the
/// reader uses, so a publisher and a reader can never disagree about what a
/// `workers.dev` address is: exactly
/// `<worker>.<account-subdomain>.workers.dev`, HTTPS, canonical lower-case
/// host, no userinfo, no non-default port, no query, no fragment, root path
/// only (R15).
library;

import 'package:pitaka/core/network/workers_dev_url.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_subdomain.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_worker_name.dart';

/// The canonical root address of one Worker.
final class CloudflareSiteUrl {
  const CloudflareSiteUrl._({
    required this.workerDnsLabel,
    required this.accountSubdomain,
  });

  /// The Worker's lower-case DNS label (the API name may differ in case).
  final String workerDnsLabel;

  /// The account-wide subdomain label.
  final String accountSubdomain;

  /// Builds the address from validated parts, or null when either is invalid.
  ///
  /// [workerName] is the API name (case preserved); the address uses its
  /// lower-case DNS label, which is what Cloudflare resolves.
  static CloudflareSiteUrl? create({
    required String? workerName,
    required String? accountSubdomain,
  }) {
    final worker = CloudflareWorkerName.tryParse(workerName);
    final subdomain = CloudflareSubdomain.tryParse(accountSubdomain);
    if (worker == null || subdomain == null) return null;
    return CloudflareSiteUrl._(
      workerDnsLabel: worker.dnsLabel,
      accountSubdomain: subdomain.value,
    );
  }

  /// Parses a full address; null when it is not a canonical Workers root.
  ///
  /// A file path under the host (`…/books.json`) is refused: a site address is
  /// the root, and accepting a path here would let a target's `siteUrl` name a
  /// file.
  static CloudflareSiteUrl? tryParse(String? raw) {
    final site = WorkersDevUrl.parse(raw);
    if (site == null) return null;
    return CloudflareSiteUrl._(
      workerDnsLabel: site.workerName,
      accountSubdomain: site.accountSubdomain,
    );
  }

  /// The canonical host, e.g. `kadugodi-library.kadugodi.workers.dev`.
  String get host => '$workerDnsLabel.$accountSubdomain.workers.dev';

  /// The canonical site root, always ending in `/`.
  String get siteUrl => 'https://$host/';

  /// Identity is the address string; `==` is deliberately not overridden in
  /// this pure domain (matching `GitHubPublishTarget`).
  bool isSameSite(CloudflareSiteUrl other) => other.siteUrl == siteUrl;

  @override
  String toString() => 'CloudflareSiteUrl($host)';
}
