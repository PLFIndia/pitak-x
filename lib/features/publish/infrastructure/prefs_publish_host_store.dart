/// `shared_preferences`-backed host journal (infrastructure, AGENTS.md §3.3;
/// Cloudflare plan E.3/E.5).
///
/// ONE key holds the whole record. Why one (beginner note): the active host and
/// the verified target must never disagree — a two-key store can be interrupted
/// between writes and leave "Cloudflare active" pointing at a GitHub address.
/// One JSON value is written in one call, so a reader sees the old record or
/// the new one.
///
/// The record is PUBLIC data (host, repo, public URL). It contains no token,
/// no account id and no credential — those live in secure storage.
///
/// Decoding fails CLOSED (C3/R1): the address inside the file is never trusted
/// as-is. The identity parts are used to rebuild the sealed target, and the
/// stored URL must equal the one derived from those parts. A record whose URL
/// disagrees with its identity is treated as absent, because accepting it would
/// be accepting an arbitrary `{host, siteUrl}` pair.
library;

import 'dart:convert';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/site/publish_host_state_repository.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/publish_host.dart';
import 'package:pitaka/features/publish/domain/site/publish_host_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the host journal in [SharedPreferences].
final class PrefsPublishHostStore implements PublishHostStateStore {
  /// Creates the store over [_prefs].
  const PrefsPublishHostStore(this._prefs);

  final SharedPreferences _prefs;

  /// Storage key. Public so tests can seed `setMockInitialValues`.
  static const String key = 'publish_host_state';

  /// The schema this build writes. An unknown/newer schema reads as absent.
  static const int schema = 1;

  @override
  PublishHostState? load() {
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['schema'] != schema) return null;
      final host = _hostFrom(decoded['activeHost']);
      final state = PublishHostState(
        activeHost: host,
        verifiedTarget: _targetFrom(decoded['verifiedTarget'], host),
      );
      // A record whose two facts disagree is corrupt: trust neither.
      return state.isConsistent ? state : null;
    } on FormatException {
      // Corrupt JSON is "no record", never a partial one.
      return null;
    }
  }

  @override
  Future<Either<Failure, Unit>> save(PublishHostState state) async {
    final target = state.verifiedTarget;
    final encoded = jsonEncode({
      'schema': schema,
      if (state.activeHost case final host?) 'activeHost': host.name,
      if (target != null)
        'verifiedTarget': {
          ..._identityOf(target),
          'host': target.host.name,
          'targetId': target.targetId,
          'siteUrl': target.siteUrl,
        },
    });
    try {
      // `setString` reports success as a bool; a `false` is a real failure the
      // caller must not paper over (M17).
      if (!await _prefs.setString(key, encoded)) {
        return left(const StorageFailure('publish host state write'));
      }
      return right(unit);
    } on Exception {
      // No response text or key value in the failure (P2).
      return left(const StorageFailure('publish host state write'));
    }
  }

  /// The parts that rebuild a sealed target; never the URL alone.
  Map<String, Object?> _identityOf(PublishTarget target) => switch (target) {
    GitHubPublishTarget() => {'repo': target.ownerRepo},
  };

  static PublishHost? _hostFrom(Object? raw) {
    for (final host in PublishHost.values) {
      if (host.name == raw) return host;
    }
    return null;
  }

  PublishTarget? _targetFrom(Object? raw, PublishHost? activeHost) {
    if (raw is! Map<String, dynamic>) return null;
    final host = _hostFrom(raw['host']);
    if (host == null || host != activeHost) return null;
    final PublishTarget? target = switch (host) {
      PublishHost.github => GitHubPublishTarget.create(
        raw['repo'] is String ? raw['repo'] as String : null,
      ),
      // No Cloudflare adapter exists yet, so no such target can be rebuilt.
      // (The value exists so the schema can grow without a rewrite.)
      PublishHost.cloudflare => null,
    };
    if (target == null) return null;
    // C3: identity is derived, so a stored URL that disagrees with the
    // derived one is a forged/stale record, not an address to trust.
    if (raw['siteUrl'] != target.siteUrl) return null;
    if (raw['targetId'] != target.targetId) return null;
    return target;
  }
}
