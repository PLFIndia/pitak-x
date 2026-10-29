/// The remote facts one publish/confirmation was prepared against (F.3).
///
/// A replacement confirmation is only valid for the remote state the user
/// actually reviewed. This value object is that state, reduced to the parts
/// that can change without this device acting: whether the Worker exists and
/// what the public marker said. Route settings are deliberately excluded —
/// the Version-URL gate changes them on purpose.
///
/// `publishedAt` is ignored on purpose: a re-publish of the same version may
/// refresh it, and it is not part of what the user reviewed.
library;

import 'package:pitaka/features/publish/domain/site/publish_marker.dart';

/// What the public marker endpoint answered.
enum CloudflareMarkerKind {
  /// A real 404: no marker was ever published.
  absent,

  /// The read failed (timeout, redirect, oversize, malformed).
  unreadable,

  /// A valid marker body was read.
  present,
}

/// Immutable comparison key for "the remote state did not change".
final class CloudflareRemoteAnchor {
  /// Creates an anchor. Only [CloudflareMarkerKind.present] carries a marker.
  const CloudflareRemoteAnchor({
    required this.workerExists,
    required this.markerKind,
    this.publishId,
    this.markerState,
  });

  /// Whether the Worker-existence endpoint proved the Worker present.
  final bool workerExists;

  /// Structured marker result.
  final CloudflareMarkerKind markerKind;

  /// Marker publish id, only when [markerKind] is present.
  final String? publishId;

  /// Marker state, only when [markerKind] is present.
  final PublishMarkerState? markerState;

  /// True when [other] describes exactly the same remote facts.
  bool matches(CloudflareRemoteAnchor other) =>
      workerExists == other.workerExists &&
      markerKind == other.markerKind &&
      publishId == other.publishId &&
      markerState == other.markerState;

  /// Safe for logs: ids are public, and no token can reach this type.
  @override
  String toString() =>
      'CloudflareRemoteAnchor(workerExists: $workerExists, '
      'marker: ${markerKind.name}, publishId: $publishId)';
}
