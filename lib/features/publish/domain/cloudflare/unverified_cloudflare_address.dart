/// A Workers-shaped address that has NOT been proven (publish domain, pure
/// Dart; Cloudflare plan R15/C9/F.2).
///
/// Why a separate type (beginner note): when a scoped token cannot read the
/// account subdomain, the user may type one. That value is a GUESS until a
/// verification deploy writes a marker and the app fetches it back from that
/// exact origin. If the guess were allowed to become a `CloudflareSiteUrl`, a
/// typo would end up in `library.json`, on a QR card and in a share link —
/// pointing at somebody else's site, or at nothing.
///
/// So this type exists for exactly one job: the verification fetch. It has no
/// conversion to `CloudflareSiteUrl` and no path into a `PublishTarget`, a
/// descriptor, a share link or a move. Confirmation happens by parsing the
/// address again with `CloudflareSiteUrl.tryParse` AFTER the marker at that
/// origin matched — never by "upgrading" this object.
///
/// The shape is still validated: the verification fetch must never be pointed
/// at an arbitrary host, so only a canonical Workers root is accepted.
library;

import 'package:pitaka/core/network/workers_dev_url.dart';

/// A candidate Workers address awaiting verification.
final class UnverifiedCloudflareAddress {
  const UnverifiedCloudflareAddress._({
    required this.workerDnsLabel,
    required this.accountSubdomain,
  });

  /// The Worker's lower-case DNS label.
  final String workerDnsLabel;

  /// The account-wide subdomain label.
  final String accountSubdomain;

  /// Parses a candidate address; null when it is not a canonical Workers root.
  static UnverifiedCloudflareAddress? tryParse(String? raw) {
    final site = WorkersDevUrl.parse(raw);
    if (site == null) return null;
    return UnverifiedCloudflareAddress._(
      workerDnsLabel: site.workerName,
      accountSubdomain: site.accountSubdomain,
    );
  }

  /// The canonical host of the candidate.
  String get host => '$workerDnsLabel.$accountSubdomain.workers.dev';

  /// The exact origin the verification fetch must use.
  ///
  /// This is the ONLY consumer: `BoundedPublishedSiteVerifier` fetches the
  /// marker here. Do not pass this value to a descriptor, a share card or a
  /// journal write (C9).
  String get verificationSiteUrl => 'https://$host/';

  @override
  String toString() => 'UnverifiedCloudflareAddress($host)';
}
