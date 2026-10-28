/// The public freshness marker and its outcomes (publish domain, pure Dart;
/// Cloudflare plan R10/C5/C7).
///
/// Every Cloudflare deploy writes `pitak-publish.json` at the site root. It is
/// the ONE thing this phone can read back to answer "is the live site still the
/// one I published?". It is small, public and deliberately boring: a schema
/// number, a random publish id, a timestamp and a state. No account id, no
/// token, no deployment id, no target metadata.
///
/// What it is NOT (beginner note): a compare-and-swap. Two phones publishing at
/// the same moment can both read the same marker and both deploy; the marker
/// only detects staleness that was OBSERVED. The plan's C6 records that
/// limitation, and the trial (T14) decides whether Cloudflare offers anything
/// stronger. Nothing here may be described as atomic across devices.
///
/// The JSON decoding lives in infrastructure (E.3); this file takes an already
/// decoded map and answers the pure question "what does this mean for the
/// publish I am about to do?".
library;

import 'dart:math';

import 'package:pitaka/features/publish/domain/site/publish_state.dart';

/// The three states a deployed marker can carry.
enum PublishMarkerState {
  /// An ordinary live site.
  live,

  /// The narrow verification-only deploy (D.2). Never accepted as an ordinary
  /// live manifest.
  verification,

  /// A moved page: the site was retired on purpose (C7).
  retired,
}

/// The marker file's contents.
final class PublishMarker {
  /// Creates a marker.
  const PublishMarker({
    required this.publishId,
    required this.publishedAt,
    required this.state,
    this.schema = currentSchema,
  });

  /// The schema this build writes.
  static const int currentSchema = 1;

  /// Length of a publish id: 128 bits as lower-case hex.
  static const int publishIdLength = 32;

  /// Schema of the record this object was read from.
  final int schema;

  /// 128-bit lower-case hex id, fresh on every deploy.
  final String publishId;

  /// Epoch milliseconds. Diagnostic only — never a correctness input.
  final int publishedAt;

  /// What kind of deploy wrote this marker.
  final PublishMarkerState state;

  /// A fresh publish id from a CSPRNG (AGENTS §6.4: never `Random()`).
  static String generatePublishId() {
    final random = Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < publishIdLength ~/ 2; i++) {
      buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  /// Decodes a marker from an already-decoded JSON map, or null when it is not
  /// a well-formed marker of a schema this build understands.
  ///
  /// A malformed marker is NOT "no marker": the caller must treat it as
  /// unreadable (unknown state), never as a fresh site (R10).
  static PublishMarker? tryParse(Object? json) {
    if (json is! Map) return null;
    final schema = json['schema'];
    if (schema is! int || schema != currentSchema) return null;
    final publishId = json['publishId'];
    if (publishId is! String || !isValidPublishId(publishId)) return null;
    final publishedAt = json['publishedAt'];
    if (publishedAt is! int || publishedAt < 0) return null;
    final state = _stateFrom(json['state']);
    if (state == null) return null;
    return PublishMarker(
      publishId: publishId,
      publishedAt: publishedAt,
      state: state,
    );
  }

  /// Encodes this marker. Public data only.
  Map<String, Object?> toJson() => {
    'schema': schema,
    'publishId': publishId,
    'publishedAt': publishedAt,
    'state': state.name,
  };

  /// True when this marker says the site is a moved page.
  bool get isRetired => state == PublishMarkerState.retired;

  @override
  String toString() => 'PublishMarker(${state.name}, $publishId)';

  /// True only for a 128-bit lower-case hexadecimal publish id.
  static bool isValidPublishId(String value) {
    if (value.length != publishIdLength) return false;
    for (final unit in value.codeUnits) {
      final isDigit = unit >= 0x30 && unit <= 0x39;
      final isLowerHex = unit >= 0x61 && unit <= 0x66;
      if (!isDigit && !isLowerHex) return false;
    }
    return true;
  }

  static PublishMarkerState? _stateFrom(Object? raw) {
    for (final value in PublishMarkerState.values) {
      if (value.name == raw) return value;
    }
    return null;
  }
}

/// What the marker fetch found at the expected origin.
sealed class PublishMarkerProbe {
  const PublishMarkerProbe();
}

/// The marker was not there (HTTP 404).
final class MarkerAbsent extends PublishMarkerProbe {
  /// Creates the absent probe.
  const MarkerAbsent();
}

/// The marker was there but unreadable: malformed, over the byte cap, or an
/// unexpected body. Distinct from [MarkerAbsent] on purpose — a 404 and a
/// broken file mean different things (R10).
final class MarkerUnreadable extends PublishMarkerProbe {
  /// Creates the unreadable probe.
  const MarkerUnreadable();
}

/// A well-formed marker was read.
final class MarkerPresent extends PublishMarkerProbe {
  /// Creates the present probe.
  const MarkerPresent(this.marker);

  /// The marker that was read.
  final PublishMarker marker;
}

/// What a publish may assume about the live site.
enum PublishFreshness {
  /// The marker matches this phone's record: the live site is the one the
  /// record describes.
  known,

  /// The marker matches a record that says the site is a moved page.
  knownRetired,

  /// The live state cannot be trusted. A publish must reconcile (and, for a
  /// whole-site replacement, ask the user) before writing.
  unknown,

  /// No Worker and no record: a first-time setup.
  newSite,

  /// This phone has a record but the Worker is gone (deleted, renamed, or the
  /// account subdomain changed). Never an incremental publish (R10).
  siteUnavailable,
}

/// Classifies the live state from the local record and the marker probe.
///
/// [localState] and [localPublishId] are null when this phone has no record for
/// the target. [workerExists] is the Worker-existence read, not the marker
/// fetch: a Worker can exist and serve no marker.
PublishFreshness classifyFreshness({
  required PublishState? localState,
  required String? localPublishId,
  required PublishMarkerProbe probe,
  required bool workerExists,
}) {
  if (!workerExists) {
    // A marker cannot be served by a Worker that does not exist: a present or
    // unreadable probe here is a contradiction, not evidence.
    if (probe is! MarkerAbsent) return PublishFreshness.unknown;
    return localState == null
        ? PublishFreshness.newSite
        : PublishFreshness.siteUnavailable;
  }

  // The Worker exists. Without a readable marker nothing can be proven —
  // including when the local record says "retired" (C7: a 404 is not proof).
  if (probe is! MarkerPresent) return PublishFreshness.unknown;
  final marker = probe.marker;

  // No local record: the marker describes a site this phone did not publish.
  if (localState == null || localPublishId == null) {
    return PublishFreshness.unknown;
  }
  if (marker.publishId != localPublishId) return PublishFreshness.unknown;

  return switch (localState) {
    PublishState.retired =>
      marker.isRetired
          ? PublishFreshness.knownRetired
          : PublishFreshness.unknown,
    // A verification marker is never an ordinary live site (D.2).
    PublishState.deployed || PublishState.live =>
      marker.state == PublishMarkerState.live
          ? PublishFreshness.known
          : PublishFreshness.unknown,
  };
}
