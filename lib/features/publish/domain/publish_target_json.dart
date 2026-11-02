/// The ONE JSON shape of a publish target outside the publish records
/// (publish domain, pure Dart).
///
/// Two places store a target as JSON: the host journal on this phone
/// (`PrefsPublishHostStore`) and the backup's `publish_state.json` (plan CV6,
/// ADR 0014 amendment). They share this codec so a target written by one can
/// never be read differently by the other.
///
/// The shape stores the identity PARTS that rebuild a sealed target, plus the
/// derived `host`, `targetId` and `siteUrl`. Decoding rebuilds the target from
/// the parts through its factory and then refuses a stored URL or id that
/// disagrees with the derived one (C3): a hand-edited `siteUrl` can never point
/// a target somewhere its parts do not describe. No token, ever.
library;

import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/publish_host.dart';

/// Encodes and decodes [PublishTarget]s.
abstract final class PublishTargetJson {
  /// The JSON object for [target].
  static Map<String, Object?> encode(PublishTarget target) => {
    ...switch (target) {
      GitHubPublishTarget() => {'repo': target.ownerRepo},
      CloudflarePublishTarget() => {
        'accountId': target.accountId.value,
        'workerName': target.workerName.value,
        'accountSubdomain': target.accountSubdomain.value,
      },
    },
    'host': target.host.name,
    'targetId': target.targetId,
    'siteUrl': target.siteUrl,
  };

  /// The target [raw] describes, or null when it is not a valid target (or
  /// not one of [expectedHost], when given).
  static PublishTarget? decode(Object? raw, {PublishHost? expectedHost}) {
    if (raw is! Map<String, dynamic>) return null;
    final host = hostFrom(raw['host']);
    if (host == null || (expectedHost != null && host != expectedHost)) {
      return null;
    }
    final target = switch (host) {
      PublishHost.github => GitHubPublishTarget.create(_string(raw['repo'])),
      PublishHost.cloudflare => CloudflarePublishTarget.create(
        accountId: _string(raw['accountId']),
        workerName: _string(raw['workerName']),
        accountSubdomain: _string(raw['accountSubdomain']),
      ),
    };
    if (target == null) return null;
    if (raw['siteUrl'] != target.siteUrl) return null;
    if (raw['targetId'] != target.targetId) return null;
    return target;
  }

  /// The host named [raw] (its enum name), or null for anything else.
  static PublishHost? hostFrom(Object? raw) {
    for (final host in PublishHost.values) {
      if (host.name == raw) return host;
    }
    return null;
  }

  static String? _string(Object? raw) => raw is String ? raw : null;
}
