/// Secret-free display projection for the ordinary publish card.
library;

import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/publish_host.dart';

/// Active host, configured target, and independently verified share address.
final class PublishSiteStatus {
  /// Creates a display projection; no credential or operation artifact is held.
  const PublishSiteStatus({
    required this.activeHost,
    required this.target,
    required this.verifiedSiteUrl,
    required this.setupMessage,
  });

  /// Host selected by the journal, or null before setup.
  final PublishHost? activeHost;

  /// Exact configured target resolved from that host's current credentials.
  final PublishTarget? target;

  /// Only the journal's read-back-proven share address, never a guessed URL.
  final String? verifiedSiteUrl;

  /// Fixed setup/routing guidance when [target] is unavailable.
  final String? setupMessage;

  /// Whether the ordinary publish action may start.
  bool get canPublish => target != null;

  /// Human-readable active host name.
  String get hostLabel => switch (activeHost) {
    PublishHost.github => 'GitHub Pages',
    PublishHost.cloudflare => 'Cloudflare Workers',
    null => 'No publishing host',
  };
}
