/// `shared_preferences`-backed host journal (infrastructure, AGENTS.md §3.3;
/// Cloudflare plan E.3/E.5).
///
/// ONE key holds the whole record. The active host, verified target, pending
/// endpoints and immutable retirement instructions therefore change in one
/// write, never as a multi-key sequence that a crash could cut in half.
///
/// The record is PUBLIC configuration data. It contains no token or credential.
/// Decoding rebuilds sealed targets from identity parts and cross-checks every
/// derived URL/target id; malformed or inconsistent data is not trusted.
library;

import 'dart:convert';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/site/publish_host_state_repository.dart';
import 'package:pitaka/features/publish/domain/github_branch_name.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/pending_move.dart';
import 'package:pitaka/features/publish/domain/site/publish_host.dart';
import 'package:pitaka/features/publish/domain/site/publish_host_state.dart';
import 'package:pitaka/features/publish/domain/site/publish_marker.dart';
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

  /// Bounds local JSON plus at most 20,000 source paths and two moved pages.
  static const int maxRecordLength = 16 * 1024 * 1024;

  @override
  Either<Failure, PublishHostState?> load() {
    try {
      final raw = _prefs.getString(key);
      if (raw == null) return const Right(null);
      if (raw.length > maxRecordLength) return _unreadable();
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic> || decoded['schema'] != schema) {
        return _unreadable();
      }
      final host = _hostFrom(decoded['activeHost']);
      if (decoded.containsKey('activeHost') && host == null) {
        return _unreadable();
      }
      final state = PublishHostState(
        activeHost: host,
        verifiedTarget: _targetFrom(decoded['verifiedTarget'], host),
        pendingMove: _pendingFrom(decoded['pendingMove']),
      );
      // Never turn a malformed pending record into a genuinely absent one.
      if (decoded.containsKey('pendingMove') && state.pendingMove == null) {
        return _unreadable();
      }
      return state.isConsistent ? Right(state) : _unreadable();
    } on Exception {
      return _unreadable();
    }
  }

  Either<Failure, PublishHostState?> _unreadable() =>
      left(const StorageFailure('publish host state read'));

  @override
  Future<Either<Failure, Unit>> save(PublishHostState state) async {
    if (!state.isConsistent) {
      return left(const ValidationFailure('Invalid publish host state'));
    }
    final target = state.verifiedTarget;
    final encoded = jsonEncode({
      'schema': schema,
      if (state.activeHost case final host?) 'activeHost': host.name,
      if (target != null) 'verifiedTarget': _targetJson(target),
      if (state.pendingMove case final pending?)
        'pendingMove': _pendingJson(pending),
    });
    if (encoded.length > maxRecordLength) {
      return left(const ValidationFailure('Publish host state is too large'));
    }
    try {
      if (!await _prefs.setString(key, encoded)) {
        return left(const StorageFailure('publish host state write'));
      }
      return right(unit);
    } on Exception {
      // No response text or key value in the failure (P2).
      return left(const StorageFailure('publish host state write'));
    }
  }

  Map<String, Object?> _targetJson(PublishTarget target) => {
    ..._identityOf(target),
    'host': target.host.name,
    'targetId': target.targetId,
    'siteUrl': target.siteUrl,
  };

  Map<String, Object?> _pendingJson(PendingMove pending) {
    final descriptor = pending.retirement;
    final marker = descriptor.marker;
    return {
      'phase': pending.phase.name,
      'sourceAnchor': pending.sourceAnchor.value,
      'sourceOwnedPaths': pending.sourceAnchor.ownedPaths,
      if (descriptor.sourceBranch case final branch?)
        'sourceBranch': branch.value,
      'oldTarget': _targetJson(pending.oldTarget),
      'newTarget': _targetJson(pending.newTarget),
      'indexHtml': base64Encode(descriptor.indexHtml),
      'notFoundHtml': base64Encode(descriptor.notFoundHtml),
      'movedPageSchema': descriptor.movedPageSchema,
      'libraryName': descriptor.libraryName,
      if (marker != null) ...{
        'retirementPublishId': marker.publishId,
        'retirementPublishedAt': marker.publishedAt,
      },
    };
  }

  PendingMove? _pendingFrom(Object? raw) {
    if (raw == null) return null;
    if (raw is! Map<String, dynamic> ||
        raw['phase'] != PendingMovePhase.retirementPending.name) {
      return null;
    }
    final oldTarget = _targetFrom(raw['oldTarget'], null);
    final newTarget = _targetFrom(raw['newTarget'], null);
    final anchor = raw['sourceAnchor'];
    final paths = _stringList(raw['sourceOwnedPaths']);
    final index = _bytes(raw['indexHtml']);
    final notFound = _bytes(raw['notFoundHtml']);
    final movedPageSchema = raw['movedPageSchema'];
    final libraryName = raw['libraryName'];
    if (oldTarget == null ||
        newTarget == null ||
        anchor is! String ||
        paths == null ||
        index == null ||
        notFound == null ||
        movedPageSchema is! int ||
        libraryName is! String) {
      return null;
    }
    final branch = oldTarget is GitHubPublishTarget
        ? GitHubBranchName.tryParse(
            raw['sourceBranch'] is String
                ? raw['sourceBranch'] as String
                : null,
          )
        : null;
    final sourceAnchor = MoveSourceAnchor.tryCreate(
      source: oldTarget,
      value: anchor,
      branch: branch,
      ownedPaths: paths,
    );
    if (sourceAnchor == null) return null;
    final marker = oldTarget is CloudflarePublishTarget
        ? PublishMarker.tryParse({
            'schema': PublishMarker.currentSchema,
            'publishId': raw['retirementPublishId'],
            'publishedAt': raw['retirementPublishedAt'],
            'state': PublishMarkerState.retired.name,
          })
        : null;
    return PendingMove.tryCreate(
      oldTarget: oldTarget,
      newTarget: newTarget,
      sourceAnchor: sourceAnchor,
      indexHtml: index,
      notFoundHtml: notFound,
      movedPageSchema: movedPageSchema,
      libraryName: libraryName,
      retirementMarker: marker,
    );
  }

  /// The parts that rebuild a sealed target; never the URL alone.
  Map<String, Object?> _identityOf(PublishTarget target) => switch (target) {
    GitHubPublishTarget() => {'repo': target.ownerRepo},
    CloudflarePublishTarget() => {
      'accountId': target.accountId.value,
      'workerName': target.workerName.value,
      'accountSubdomain': target.accountSubdomain.value,
    },
  };

  static PublishHost? _hostFrom(Object? raw) {
    for (final host in PublishHost.values) {
      if (host.name == raw) return host;
    }
    return null;
  }

  PublishTarget? _targetFrom(Object? raw, PublishHost? expectedHost) {
    if (raw is! Map<String, dynamic>) return null;
    final host = _hostFrom(raw['host']);
    if (host == null || (expectedHost != null && host != expectedHost)) {
      return null;
    }
    final target = switch (host) {
      PublishHost.github => GitHubPublishTarget.create(
        raw['repo'] is String ? raw['repo'] as String : null,
      ),
      PublishHost.cloudflare => CloudflarePublishTarget.create(
        accountId: raw['accountId'] is String
            ? raw['accountId'] as String
            : null,
        workerName: raw['workerName'] is String
            ? raw['workerName'] as String
            : null,
        accountSubdomain: raw['accountSubdomain'] is String
            ? raw['accountSubdomain'] as String
            : null,
      ),
    };
    if (target == null) return null;
    if (raw['siteUrl'] != target.siteUrl) return null;
    if (raw['targetId'] != target.targetId) return null;
    return target;
  }

  static List<String>? _stringList(Object? raw) {
    if (raw is! List || raw.length > 20000) return null;
    final values = <String>[];
    for (final value in raw) {
      if (value is! String) return null;
      values.add(value);
    }
    return values;
  }

  static List<int>? _bytes(Object? raw) {
    if (raw is! String || raw.length > 128 * 1024) return null;
    try {
      return base64Decode(raw);
    } on FormatException {
      return null;
    }
  }
}
