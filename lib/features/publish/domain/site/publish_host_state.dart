/// The library's publishing identity on this phone (publish domain, pure Dart;
/// Cloudflare plan E.1/E.5/R33).
///
/// Two separate facts, deliberately not merged (beginner note):
///  - `activeHost` — which host this library is configured to publish to;
///  - `verifiedTarget` — the exact site that was PROVEN live by a read-back.
///
/// They are not the same thing. A configured host whose site is not reachable
/// yet must not produce a share link, and a target change must not erase a
/// previously verified address: a failed or unverified publish would otherwise
/// make the library's QR card point somewhere that is not serving it (P1). The
/// share/QR address comes from `verifiedTarget` ONLY.
///
/// The record holds one verified target — the one for `activeHost`. A move
/// (S9) keeps the old target here until the new site is verified and the old
/// one retired, then switches in one write.
library;

import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/publish_host.dart';

/// The persisted journal of the active host and its verified site.
final class PublishHostState {
  /// Creates a journal record.
  const PublishHostState({this.activeHost, this.verifiedTarget});

  /// The record before anything was published or configured.
  static const PublishHostState empty = PublishHostState();

  /// Host this library publishes to; null until setup (or a legacy migration)
  /// establishes one.
  final PublishHost? activeHost;

  /// The site a read-back PROVED is serving this library; null while no
  /// publication has been verified.
  final PublishTarget? verifiedTarget;

  /// The public address to share/QR, or null when nothing is verified.
  String? get verifiedSiteUrl => verifiedTarget?.siteUrl;

  /// True when the record's two facts agree: a verified target always belongs
  /// to the active host. A record that says otherwise is corrupt and is read
  /// as "nothing verified" (fail closed).
  bool get isConsistent {
    final target = verifiedTarget;
    if (target == null) return true;
    return activeHost == target.host;
  }

  /// The record after a publish to [target] was proven live.
  ///
  /// The active host only moves when it was unset or already this host: a
  /// publish to a DIFFERENT host is the destination half of a move, whose
  /// switch belongs to the move state machine (S9), not to this setter.
  PublishHostState afterVerifiedPublish(PublishTarget target) {
    final active = activeHost;
    if (active != null && active != target.host) return this;
    return PublishHostState(activeHost: target.host, verifiedTarget: target);
  }

  /// True when [target] is already the verified target of this record.
  bool verifies(PublishTarget target) =>
      verifiedTarget?.targetId == target.targetId && activeHost == target.host;

  @override
  String toString() =>
      'PublishHostState(${activeHost?.name}, ${verifiedTarget?.targetId})';
}
