/// Strict JSON codec for the two documents of the background event check
/// (PLAN.md §1: schema 1, strict decoding, typed failures).
///
/// Decoding rules (beginner note): every value read back from disk is
/// treated like input from a stranger. Wrong type, unknown enum token,
/// out-of-range number, duplicate key, too many items — all of it makes the
/// whole document "corrupt", never a best-effort partial object. A
/// `schema` higher than this build's is reported separately so the caller
/// can refuse to overwrite a newer format.
library;

import 'package:pitaka/features/network/domain/events_watch/events_watch_ports.dart';
import 'package:pitaka/features/network/domain/events_watch/events_watch_settings.dart';
import 'package:pitaka/features/network/domain/events_watch/events_watch_state.dart';
import 'package:pitaka/features/network/domain/events_watch/pending_change.dart';
import 'package:pitaka/features/network/domain/events_watch/site_baseline.dart';
import 'package:pitaka/features/network/domain/events_watch/site_watch_status.dart';
import 'package:pitaka/features/network/domain/events_watch/watch_settings_token.dart';
import 'package:pitaka/features/network/domain/events_watch/watched_libraries_source.dart';
import 'package:pitaka/features/network/domain/events_watch/watched_library.dart';
import 'package:pitaka/features/network/domain/value_objects/bookmark_url.dart';

/// Hard caps on stored collections (PLAN.md decision 15).
abstract final class EventsWatchDocumentLimits {
  /// Settings file byte cap.
  static const int maxSettingsBytes = 16 * 1024;

  /// State file byte cap.
  static const int maxStateBytes = 512 * 1024;

  /// At most two pending entries per site.
  static const int maxPending = maxWatchedLibraries * SiteBaseline.maxPosters;

  /// Entity tags are opaque; bound them anyway.
  static const int maxValidatorLength = 256;

  /// JSON nesting the documents legitimately need, with headroom.
  static const int maxJsonDepth = 8;
}

/// Encoders/decoders. Stateless.
abstract final class EventsWatchJsonCodec {
  static final RegExp _generationPattern = RegExp(r'^gen-\d{6}$');
  static final RegExp _validatorPattern = RegExp(r'^[\x20-\x7e]{1,256}$');

  // --- settings -----------------------------------------------------------

  /// Encodes [settings] as a JSON-ready map.
  static Map<String, Object?> encodeSettings(EventsWatchSettings settings) => {
    'schema': EventsWatchSettings.schemaVersion,
    'enabled': settings.enabled,
    'token': _encodeToken(settings.token),
    'acknowledgedExplanationVersion': settings.acknowledgedExplanationVersion,
    'pausedForNoLibraries': settings.pausedForNoLibraries,
  };

  /// Decodes a parsed JSON value into settings.
  static WatchDocumentRead<EventsWatchSettings> decodeSettings(Object? json) {
    if (json is! Map<String, Object?>) return const WatchDocumentCorrupt();
    final schema = json['schema'];
    if (schema is! int || schema < 1) return const WatchDocumentCorrupt();
    if (schema > EventsWatchSettings.schemaVersion) {
      return const WatchDocumentNewerSchema();
    }
    final token = json['token'];
    if (token is! Map<String, Object?>) return const WatchDocumentCorrupt();
    final settings = EventsWatchSettings.validate(
      enabled: json['enabled'],
      incarnation: token['incarnation'],
      epoch: token['epoch'],
      acknowledgedExplanationVersion: json['acknowledgedExplanationVersion'],
      pausedForNoLibraries: json['pausedForNoLibraries'], // absent = false
    );
    if (settings == null) return const WatchDocumentCorrupt();
    return WatchDocumentPresent(settings);
  }

  // --- state --------------------------------------------------------------

  /// Encodes [state] as a JSON-ready map.
  static Map<String, Object?> encodeState(EventsWatchState state) => {
    'schema': EventsWatchState.schemaVersion,
    'observedToken': _encodeNullableToken(state.observedToken),
    'generation': state.generation,
    'sites': [for (final site in state.sites) _encodeSite(site)],
    'pending': [for (final change in state.pending) _encodePending(change)],
    'revocationToken': _encodeNullableToken(state.revocationToken),
    'recoveryNotice': state.recoveryNotice?.name,
    'lastRun': state.lastRun == null ? null : _encodeLastRun(state.lastRun!),
  };

  /// Decodes a parsed JSON value into state.
  static WatchDocumentRead<EventsWatchState> decodeState(Object? json) {
    if (json is! Map<String, Object?>) return const WatchDocumentCorrupt();
    final schema = json['schema'];
    if (schema is! int || schema < 1) return const WatchDocumentCorrupt();
    if (schema > EventsWatchState.schemaVersion) {
      return const WatchDocumentNewerSchema();
    }

    final observedToken = _decodeNullableToken(json['observedToken']);
    if (observedToken == _invalidToken) return const WatchDocumentCorrupt();
    final revocationToken = _decodeNullableToken(json['revocationToken']);
    if (revocationToken == _invalidToken) return const WatchDocumentCorrupt();

    final generation = json['generation'];
    if (generation != null &&
        (generation is! String || !_generationPattern.hasMatch(generation))) {
      return const WatchDocumentCorrupt();
    }

    final rawSites = json['sites'];
    if (rawSites is! List || rawSites.length > maxWatchedLibraries) {
      return const WatchDocumentCorrupt();
    }
    final sites = <SiteWatchStatus>[];
    final seenUrls = <String>{};
    for (final raw in rawSites) {
      final site = _decodeSite(raw);
      if (site == null || !seenUrls.add(site.siteUrl)) {
        return const WatchDocumentCorrupt();
      }
      sites.add(site);
    }

    final rawPending = json['pending'];
    if (rawPending is! List ||
        rawPending.length > EventsWatchDocumentLimits.maxPending) {
      return const WatchDocumentCorrupt();
    }
    final pending = <PendingChange>[];
    final seenKeys = <String>{};
    for (final raw in rawPending) {
      final change = _decodePending(raw);
      if (change == null ||
          !seenKeys.add('${change.siteUrl}\u0000${change.imageRef}')) {
        return const WatchDocumentCorrupt();
      }
      pending.add(change);
    }

    final rawNotice = json['recoveryNotice'];
    final RecoveryNotice? notice;
    if (rawNotice == null) {
      notice = null;
    } else if (rawNotice == RecoveryNotice.stateReset.name) {
      notice = RecoveryNotice.stateReset;
    } else {
      return const WatchDocumentCorrupt();
    }

    final rawLastRun = json['lastRun'];
    LastRunOutcome? lastRun;
    if (rawLastRun != null) {
      if (rawLastRun is! Map<String, Object?>) {
        return const WatchDocumentCorrupt();
      }
      lastRun = LastRunOutcome.validate(
        finishedAt: rawLastRun['finishedAt'],
        checked: rawLastRun['checked'],
        withheld: rawLastRun['withheld'],
        failed: rawLastRun['failed'],
        capacityExceeded: rawLastRun['capacityExceeded'],
      );
      if (lastRun == null) return const WatchDocumentCorrupt();
    }

    return WatchDocumentPresent(
      EventsWatchState(
        observedToken: observedToken as WatchSettingsToken?,
        generation: generation as String?,
        sites: sites,
        pending: pending,
        revocationToken: revocationToken as WatchSettingsToken?,
        recoveryNotice: notice,
        lastRun: lastRun,
      ),
    );
  }

  // --- pieces -------------------------------------------------------------

  /// Sentinel returned by [_decodeNullableToken] for a present-but-invalid
  /// token, so null (absent) and invalid stay distinguishable.
  static const Object _invalidToken = Object();

  static Map<String, Object?> _encodeToken(WatchSettingsToken token) => {
    'incarnation': token.incarnation,
    'epoch': token.epoch,
  };

  static Map<String, Object?>? _encodeNullableToken(
    WatchSettingsToken? token,
  ) => token == null ? null : _encodeToken(token);

  static Object? _decodeNullableToken(Object? raw) {
    if (raw == null) return null;
    if (raw is! Map<String, Object?>) return _invalidToken;
    return WatchSettingsToken.validate(
          incarnation: raw['incarnation'],
          epoch: raw['epoch'],
        ) ??
        _invalidToken;
  }

  static WatchedLibraryIdentity? _decodeIdentity(Map<String, Object?> raw) {
    final rowId = raw['rowId'];
    final createdAt = raw['createdAt'];
    final siteUrl = raw['siteUrl'];
    if (rowId is! int || rowId <= 0) return null;
    if (createdAt is! int || createdAt < 0) return null;
    if (siteUrl is! String || BookmarkUrl.normalize(siteUrl) != siteUrl) {
      return null;
    }
    return WatchedLibraryIdentity(
      rowId: rowId,
      createdAt: createdAt,
      siteUrl: siteUrl,
    );
  }

  static Map<String, Object?> _encodeIdentity(WatchedLibraryIdentity id) => {
    'rowId': id.rowId,
    'createdAt': id.createdAt,
    'siteUrl': id.siteUrl,
  };

  static Map<String, Object?> _encodeSite(SiteWatchStatus site) => {
    ..._encodeIdentity(site.identity),
    'notificationId': site.notificationId,
    'lastAttemptAt': site.lastAttemptAt,
    'lastSuccessfulCheckAt': site.lastSuccessfulCheckAt,
    'lastOutcome': site.lastOutcome.name,
    'baseline': site.baseline == null ? null : _encodeBaseline(site.baseline!),
  };

  static SiteWatchStatus? _decodeSite(Object? raw) {
    if (raw is! Map<String, Object?>) return null;
    final identity = _decodeIdentity(raw);
    if (identity == null) return null;
    final rawBaseline = raw['baseline'];
    SiteBaseline? baseline;
    if (rawBaseline != null) {
      baseline = _decodeBaseline(rawBaseline);
      if (baseline == null) return null;
    }
    return SiteWatchStatus.validate(
      identity: identity,
      notificationId: raw['notificationId'],
      lastAttemptAt: raw['lastAttemptAt'],
      lastSuccessfulCheckAt: raw['lastSuccessfulCheckAt'],
      lastOutcome: raw['lastOutcome'],
      baseline: baseline,
    );
  }

  static Map<String, Object?> _encodeBaseline(SiteBaseline baseline) => {
    'posters': [
      for (final poster in baseline.posters)
        {'imageRef': poster.imageRef, 'digest': poster.digest},
    ],
    'validator': baseline.validator,
    'token': _encodeToken(baseline.token),
  };

  static SiteBaseline? _decodeBaseline(Object? raw) {
    if (raw is! Map<String, Object?>) return null;
    final rawPosters = raw['posters'];
    if (rawPosters is! List || rawPosters.length > SiteBaseline.maxPosters) {
      return null;
    }
    final posters = <BaselinePoster>[];
    final seenRefs = <String>{};
    for (final rawPoster in rawPosters) {
      if (rawPoster is! Map<String, Object?>) return null;
      final poster = BaselinePoster.validate(
        imageRef: rawPoster['imageRef'],
        digest: rawPoster['digest'],
      );
      if (poster == null || !seenRefs.add(poster.imageRef)) return null;
      posters.add(poster);
    }
    final validator = raw['validator'];
    if (validator != null &&
        (validator is! String || !_validatorPattern.hasMatch(validator))) {
      return null;
    }
    final token = _decodeNullableToken(raw['token']);
    if (token is! WatchSettingsToken) return null;
    return SiteBaseline(
      posters: posters,
      token: token,
      validator: validator as String?,
    );
  }

  static Map<String, Object?> _encodePending(PendingChange change) => {
    'kind': change.kind.name,
    ..._encodeIdentity(change.identity),
    'imageRef': change.imageRef,
    'safeCaption': change.safeCaption,
    'digest': change.digest,
    'token': _encodeToken(change.token),
  };

  static PendingChange? _decodePending(Object? raw) {
    if (raw is! Map<String, Object?>) return null;
    final identity = _decodeIdentity(raw);
    if (identity == null) return null;
    final token = _decodeNullableToken(raw['token']);
    if (token is! WatchSettingsToken) return null;
    return PendingChange.validate(
      kind: raw['kind'],
      identity: identity,
      imageRef: raw['imageRef'],
      safeCaption: raw['safeCaption'],
      digest: raw['digest'],
      token: token,
    );
  }

  static Map<String, Object?> _encodeLastRun(LastRunOutcome run) => {
    'finishedAt': run.finishedAt,
    'checked': run.checked,
    'withheld': run.withheld,
    'failed': run.failed,
    'capacityExceeded': run.capacityExceeded,
  };
}
