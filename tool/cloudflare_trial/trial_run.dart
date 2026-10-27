/// The trial's phases (Cloudflare plan Part L.2, T1–T16).
///
/// One method per check, in the order the plan lists them. Every method records
/// its outcome in the report and returns whether the trial may continue: a
/// failed prerequisite skips the checks that depend on it instead of producing
/// a cascade of misleading failures.
///
/// Secrets: the API token lives in `TrialHttp`, the upload/completion JWTs live
/// in private fields of this class, and neither is ever passed to the report.
/// The report only ever sees fixed labels, numbers, booleans and whitelisted
/// headers.
library;

import 'dart:convert';
import 'dart:math';

import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_account_id.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_token.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_limits.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_subdomain.dart';
import 'package:pitaka/features/publish/domain/site/publish_marker.dart';

import 'trial_assets.dart';
import 'trial_http.dart';
import 'trial_multipart.dart';
import 'trial_public.dart';
import 'trial_report.dart';

/// The trial's inputs, read from the environment.
final class TrialConfig {
  const TrialConfig({
    required this.token,
    this.accountId,
    this.createSubdomain = false,
    this.skipLarge = false,
  });

  /// The exact restricted token the production flow will use.
  final CloudflareApiToken token;

  /// A manual account id (used when listing is refused or truncated).
  final String? accountId;

  /// True only when the maintainer explicitly allows creating the permanent
  /// account subdomain on a throw-away account.
  final bool createSubdomain;

  /// True when the ~2,000-file measurement (T5b) is skipped.
  final bool skipLarge;

  /// Reads the config from [env]; null when `CF_API_TOKEN` is missing or not a
  /// plausible token.
  static TrialConfig? fromEnv(Map<String, String> env) {
    final token = CloudflareApiToken.tryParse(env['CF_API_TOKEN']);
    if (token == null) return null;
    return TrialConfig(
      token: token,
      accountId: env['CF_ACCOUNT_ID'],
      createSubdomain: _flag(env['CF_CREATE_SUBDOMAIN']),
      skipLarge: _flag(env['CF_TRIAL_SKIP_LARGE']),
    );
  }

  static bool _flag(String? raw) {
    final value = raw?.trim().toLowerCase();
    return value == '1' || value == 'true' || value == 'yes';
  }
}

/// Runs the trial against a disposable account.
final class Trial {
  /// Creates a trial.
  Trial({required this.config, required this.report});

  /// The inputs.
  final TrialConfig config;

  /// Where outcomes are recorded.
  final TrialReport report;

  late final TrialHttp _api;
  late final String _workerName;
  late final String _largeWorkerName;

  String? _accountId;
  String? _subdomain;
  String? _siteUrl;

  /// Bearer secrets for one operation. Never printed, never in the report.
  String? _uploadJwt;
  String? _completionJwt;
  List<List<String>> _buckets = const [];

  bool _largeWorkerCreated = false;

  /// Runs every phase, then always attempts cleanup.
  Future<void> run() async {
    _api = TrialHttp(
      token: config.token.use((value) => value),
      userAgent: 'pitak-trial',
    );
    _workerName = 'pitak-trial-${_hex(4)}';
    _largeWorkerName = 'pitak-trial-large-${_hex(4)}';
    report.info('T0', 'trial worker', 'name-shape=pitak-trial-<8 hex>');
    try {
      if (!await _t1Verify()) return;
      if (!await _t2Accounts()) return;
      await _t3Subdomain();
      if (_subdomain == null) {
        _skipDeployChecks('no confirmed account subdomain');
        return;
      }
      _siteUrl = 'https://$_workerName.$_subdomain.workers.dev/';
      if (!await _t4Session()) return;
      if (!await _t5Upload()) return;
      if (!await _t6Deploy()) {
        _skipDeployChecks('T6 failed: the plan stops here');
        return;
      }
      await _t7Route();
      await _t8Public();
      await _t9Deployments();
      await _t10SecondDeploy();
      await _t11VersionExposure();
      await _t12Retired();
      if (config.skipLarge) {
        report.skip('T5b', 'large asset set', 'CF_TRIAL_SKIP_LARGE set');
      } else {
        await _t5bLarge();
      }
      report.manual(
        'T14',
        'conditional deploy',
        'check current docs, Wrangler and the API for a conditional '
            'parameter; record the evidence in this report',
      );
    } finally {
      await _t13Cleanup();
      _api.close();
    }
  }

  // ---- T1: token verification ---------------------------------------------

  Future<bool> _t1Verify() async {
    final user = await _api.send(
      method: 'GET',
      path: '/user/tokens/verify',
      retry: true,
    );
    if (user.ok && (user.success ?? false)) {
      return _recordVerify('T1', 'token verify', user, 'user');
    }
    final accountId = config.accountId;
    if (accountId == null) {
      report.check(
        'T1',
        'token verify',
        pass: false,
        detail: 'endpoint=user ${user.label} no-account-id',
      );
      return false;
    }
    final account = await _api.send(
      method: 'GET',
      path: '/accounts/$accountId/tokens/verify',
      retry: true,
    );
    return _recordVerify('T1', 'token verify', account, 'account');
  }

  bool _recordVerify(
    String id,
    String label,
    TrialResponse response,
    String endpoint,
  ) {
    final status = response.result?['status'];
    final expiry = response.result?['expires_on'];
    final active =
        response.ok && (response.success ?? false) && status == 'active';
    report.check(
      id,
      label,
      pass: active,
      detail:
          'endpoint=$endpoint status=${status ?? 'unknown'} '
          'expiry=${expiry == null ? 'absent' : 'present'}',
    );
    return active;
  }

  // ---- T2: accounts --------------------------------------------------------

  Future<bool> _t2Accounts() async {
    final manual = config.accountId;
    if (manual != null) {
      final id = CloudflareAccountId.tryParse(manual);
      if (id == null) {
        report.check(
          'T2',
          'accounts',
          pass: false,
          detail: 'source=manual id=invalid',
        );
        return false;
      }
      _accountId = id.value;
      report.check('T2', 'accounts', pass: true, detail: 'source=manual');
      return true;
    }

    final ids = <String>[];
    var pages = 0;
    var truncated = false;
    for (var page = 1; page <= CloudflareLimits.maxAccountPages; page++) {
      final response = await _api.send(
        method: 'GET',
        path:
            '/accounts?per_page=${CloudflareLimits.accountsPerPage}&page=$page',
        retry: true,
      );
      if (!response.ok) {
        report.check(
          'T2',
          'accounts',
          pass: false,
          detail: 'page=$page ${response.label}',
        );
        return false;
      }
      pages++;
      final list = response.resultList ?? const [];
      for (final entry in list) {
        if (entry is Map && entry['id'] is String) {
          ids.add(entry['id'] as String);
        }
      }
      if (list.length < CloudflareLimits.accountsPerPage) break;
      if (page == CloudflareLimits.maxAccountPages) truncated = true;
    }

    if (truncated || ids.isEmpty) {
      report.check(
        'T2',
        'accounts',
        pass: false,
        detail:
            'pages=$pages accounts=${ids.length} '
            'truncated=$truncated manual-id-required',
      );
      return false;
    }
    final first = CloudflareAccountId.tryParse(ids.first);
    if (first == null) {
      report.check(
        'T2',
        'accounts',
        pass: false,
        detail: 'pages=$pages accounts=${ids.length} id=malformed',
      );
      return false;
    }
    _accountId = first.value;
    report.check(
      'T2',
      'accounts',
      pass: true,
      detail: 'source=list pages=$pages accounts=${ids.length}',
    );
    return true;
  }

  // ---- T3: account subdomain ----------------------------------------------

  Future<void> _t3Subdomain() async {
    final accountId = _accountId;
    if (accountId == null) return;
    final read = await _api.send(
      method: 'GET',
      path: '/accounts/$accountId/workers/subdomain',
      retry: true,
    );
    if (read.ok) {
      final raw = read.result?['subdomain'];
      final parsed = CloudflareSubdomain.tryParse(raw is String ? raw : null);
      if (parsed != null) {
        _subdomain = parsed.value;
        report.check(
          'T3',
          'account subdomain',
          pass: true,
          detail: 'read=present',
        );
        return;
      }
      report.check(
        'T3',
        'account subdomain',
        pass: false,
        detail: 'read=malformed',
      );
      return;
    }
    if (!read.errorCodes.contains(10007)) {
      report.check(
        'T3',
        'account subdomain',
        pass: false,
        detail: 'read=refused ${read.label}',
      );
      return;
    }
    // No account subdomain yet.
    if (!config.createSubdomain) {
      report.skip(
        'T3',
        'account subdomain',
        'absent; CF_CREATE_SUBDOMAIN not set',
      );
      return;
    }
    final candidate = _workerName;
    final check = await _api.send(
      method: 'GET',
      path: '/accounts/$accountId/workers/subdomains/$candidate',
      retry: true,
    );
    report.info(
      'T3a',
      'subdomain availability',
      'status=${check.status} codes=${check.errorCodes.join(',')}',
    );
    final create = await _api.send(
      method: 'PUT',
      path: '/accounts/$accountId/workers/subdomain',
      jsonBody: {'subdomain': candidate},
    );
    if (!create.ok) {
      report.check(
        'T3',
        'account subdomain',
        pass: false,
        detail: 'create=failed ${create.label}',
      );
      return;
    }
    final reread = await _api.send(
      method: 'GET',
      path: '/accounts/$accountId/workers/subdomain',
      retry: true,
    );
    final rereadSubdomain = reread.result?['subdomain'];
    final created = CloudflareSubdomain.tryParse(
      rereadSubdomain is String ? rereadSubdomain : null,
    );
    _subdomain = created?.value;
    report.check(
      'T3',
      'account subdomain',
      pass: created != null,
      detail: 'create=ok reread=${created != null ? 'present' : 'absent'}',
    );
  }

  // ---- T4: upload session --------------------------------------------------

  Future<bool> _t4Session() async {
    final accountId = _accountId;
    if (accountId == null) return false;
    final assets = TrialAssets.small();
    final manifest = <String, Object?>{
      for (final asset in assets)
        asset.manifestKey: {'hash': asset.hash, 'size': asset.size},
    };
    final response = await _api.send(
      method: 'POST',
      path:
          '/accounts/$accountId/workers/scripts/$_workerName/'
          'assets-upload-session',
      jsonBody: {'manifest': manifest},
    );
    if (!response.ok || !(response.success ?? false)) {
      report.check('T4', 'upload session', pass: false, detail: response.label);
      return false;
    }
    final jwt = response.result?['jwt'];
    final buckets = _parseBuckets(response.result?['buckets']);
    if (jwt is! String || jwt.isEmpty) {
      report.check('T4', 'upload session', pass: false, detail: 'jwt=absent');
      return false;
    }
    _uploadJwt = jwt;
    _buckets = buckets;
    final unique = {for (final asset in assets) asset.hash};
    final requested = {for (final bucket in buckets) ...bucket};
    final allRequested = requested.containsAll(unique);
    report.check(
      'T4',
      'upload session',
      pass: allRequested,
      detail:
          'paths=${assets.length} unique=${unique.length} '
          'buckets=${buckets.length} requested=${requested.length} '
          'leadingSlash=yes',
    );
    return allRequested;
  }

  // ---- T5: bucket upload ---------------------------------------------------

  Future<bool> _t5Upload() async {
    final accountId = _accountId;
    final uploadJwt = _uploadJwt;
    if (accountId == null || uploadJwt == null) return false;
    final byHash = {for (final asset in TrialAssets.small()) asset.hash: asset};
    String? completion;
    var uploaded = 0;
    for (final bucket in _buckets) {
      final assets = <TrialAsset>[];
      for (final hash in bucket) {
        final asset = byHash[hash];
        if (asset == null) {
          report.check(
            'T5',
            'bucket upload',
            pass: false,
            detail: 'requested-hash-without-bytes',
          );
          return false;
        }
        assets.add(asset);
      }
      final boundary = TrialMultipart.newBoundary();
      final body = TrialMultipart.bucketBody(
        boundary: boundary,
        assets: assets,
      );
      final response = await _api.send(
        method: 'POST',
        path: '/accounts/$accountId/workers/assets/upload?base64=true',
        body: body,
        contentType: 'multipart/form-data; boundary=$boundary',
        bearer: uploadJwt,
        deadline: CloudflareLimits.uploadDeadline,
        retry: true,
      );
      if (!response.ok) {
        report.check(
          'T5',
          'bucket upload',
          pass: false,
          detail: 'bucket=${bucket.length} ${response.label}',
        );
        return false;
      }
      uploaded += assets.length;
      final jwt = response.result?['jwt'];
      if (jwt is String && jwt.isNotEmpty) completion = jwt;
    }
    // Empty buckets mean the session JWT is already the completion token (B.2).
    completion ??= _buckets.isEmpty ? uploadJwt : null;
    _completionJwt = completion;
    report.check(
      'T5',
      'bucket upload',
      pass: completion != null,
      detail:
          'buckets=${_buckets.length} uploaded=$uploaded '
          'completion=${completion != null}',
    );
    return completion != null;
  }

  // ---- T6: metadata-only deploy -------------------------------------------

  Future<bool> _t6Deploy() async {
    final accountId = _accountId;
    final completion = _completionJwt;
    if (accountId == null || completion == null) return false;
    final boundary = TrialMultipart.newBoundary();
    final body = TrialMultipart.deployBody(
      boundary: boundary,
      completionJwt: completion,
      htmlHandling: 'auto-trailing-slash',
      notFoundHandling: 'none',
      headers: TrialMultipart.liveHeaders,
    );
    final response = await _api.send(
      method: 'PUT',
      path: '/accounts/$accountId/workers/scripts/$_workerName',
      body: body,
      contentType: 'multipart/form-data; boundary=$boundary',
      deadline: CloudflareLimits.uploadDeadline,
    );
    final pass = response.ok && (response.success ?? false);
    report.check(
      'T6',
      'metadata-only deploy',
      pass: pass,
      detail: response.label,
    );
    return pass;
  }

  // ---- T7: route and version URLs -----------------------------------------

  Future<void> _t7Route() async {
    final accountId = _accountId;
    if (accountId == null) return;
    final path = '/accounts/$accountId/workers/scripts/$_workerName/subdomain';
    final enable = await _api.send(
      method: 'POST',
      path: path,
      jsonBody: {'enabled': true, 'previews_enabled': false},
    );
    final read = await _api.send(method: 'GET', path: path, retry: true);
    final enabled = read.result?['enabled'];
    final previews = read.result?['previews_enabled'];
    report.check(
      'T7',
      'route + version URLs',
      pass: enabled == true && previews == false,
      detail:
          'enable=${enable.status} enabled=$enabled previews=$previews '
          'field=previews_enabled',
    );
    // Prove the field is the one that moves.
    await _api.send(
      method: 'POST',
      path: path,
      jsonBody: {'enabled': true, 'previews_enabled': true},
    );
    final on = await _api.send(method: 'GET', path: path, retry: true);
    await _api.send(
      method: 'POST',
      path: path,
      jsonBody: {'enabled': true, 'previews_enabled': false},
    );
    final off = await _api.send(method: 'GET', path: path, retry: true);
    report.info(
      'T7b',
      'version-URL toggle',
      'on=${on.result?['previews_enabled']} '
          'off=${off.result?['previews_enabled']}',
    );
  }

  // ---- T8: public behaviour ------------------------------------------------

  Future<void> _t8Public() async {
    final site = _siteUrl;
    if (site == null) return;
    final root = Uri.parse(site);
    final ready = await _waitForRoot(root);
    if (!ready) {
      report.check('T8', 'public site', pass: false, detail: 'root=not-ready');
      return;
    }
    final index = await TrialPublic.get(root.resolve('index.html'));
    final books = await TrialPublic.get(root.resolve('books.json'));
    final events = await TrialPublic.get(root.resolve('events.json'));
    final cover = await TrialPublic.get(root.resolve('covers/sample.jpg'));
    final missing = await TrialPublic.get(root.resolve('missing.json'));
    report
      ..check('T8', 'root', pass: true, detail: 'status=200')
      ..info('T8a', 'index.html', index.label)
      ..check(
        'T8b',
        'books.json',
        pass:
            books.ok &&
            (books.headers['content-type'] ?? '').startsWith(
              'application/json',
            ),
        detail: books.label,
      )
      ..check(
        'T8c',
        'covers/sample.jpg',
        pass:
            cover.ok &&
            (cover.headers['content-type'] ?? '').startsWith('image/jpeg'),
        detail: cover.label,
      )
      ..check(
        'T8d',
        'missing file is a real 404',
        pass: missing.status == 404,
        detail: missing.label,
      )
      ..check(
        'T8e',
        'cache + CORS',
        pass:
            (books.headers['cache-control'] ?? '').contains('no-cache') &&
            books.headers['access-control-allow-origin'] == '*',
        detail: books.label,
      )
      ..info('T8f', 'events.json', events.label);
  }

  Future<bool> _waitForRoot(Uri root) async {
    for (var attempt = 1; attempt <= 12; attempt++) {
      final response = await TrialPublic.get(root);
      if (response.ok) return true;
      await Future<void>.delayed(const Duration(seconds: 5));
    }
    return false;
  }

  // ---- T9: deployment diagnostic ------------------------------------------

  Future<void> _t9Deployments() async {
    final accountId = _accountId;
    if (accountId == null) return;
    final response = await _api.send(
      method: 'GET',
      path: '/accounts/$accountId/workers/scripts/$_workerName/deployments',
      retry: true,
    );
    final list = response.resultList ?? const [];
    final first = list.isEmpty ? null : list.first;
    final hasId = first is Map && first['id'] is String;
    report.info(
      'T9',
      'deployment diagnostic',
      'status=${response.status} entries=${list.length} '
          'latest-id=${hasId ? 'present' : 'absent'}',
    );
  }

  // ---- T10: second deploy (dedupe + removal) ------------------------------

  Future<void> _t10SecondDeploy() async {
    final accountId = _accountId;
    if (accountId == null) return;
    final assets = TrialAssets.withoutEvents();
    final session = await _api.send(
      method: 'POST',
      path:
          '/accounts/$accountId/workers/scripts/$_workerName/'
          'assets-upload-session',
      jsonBody: {
        'manifest': {
          for (final asset in assets)
            asset.manifestKey: {'hash': asset.hash, 'size': asset.size},
        },
      },
    );
    if (!session.ok || !(session.success ?? false)) {
      report.check(
        'T10',
        'second deploy',
        pass: false,
        detail: 'session ${session.label}',
      );
      return;
    }
    final buckets = _parseBuckets(session.result?['buckets']);
    final jwt = session.result?['jwt'];
    if (jwt is! String) {
      report.check(
        'T10',
        'second deploy',
        pass: false,
        detail: 'session jwt=absent',
      );
      return;
    }
    // Every remaining file is unchanged, so nothing should be requested.
    final deduped = buckets.isEmpty;
    final boundary = TrialMultipart.newBoundary();
    final body = TrialMultipart.deployBody(
      boundary: boundary,
      completionJwt: jwt,
      htmlHandling: 'auto-trailing-slash',
      notFoundHandling: 'none',
      headers: TrialMultipart.liveHeaders,
    );
    final deploy = await _api.send(
      method: 'PUT',
      path: '/accounts/$accountId/workers/scripts/$_workerName',
      body: body,
      contentType: 'multipart/form-data; boundary=$boundary',
      deadline: CloudflareLimits.uploadDeadline,
    );
    final site = _siteUrl;
    var removed = false;
    if (site != null) {
      await _waitForRoot(Uri.parse(site));
      final events = await TrialPublic.get(
        Uri.parse(site).resolve('events.json'),
      );
      removed = events.status == 404;
    }
    report.check(
      'T10',
      'second deploy dedupes and removes',
      pass: deduped && deploy.ok && removed,
      detail:
          'buckets=${buckets.length} deploy=${deploy.status} '
          'events404=$removed',
    );
  }

  // ---- T11/T15: version exposure ------------------------------------------

  Future<void> _t11VersionExposure() async {
    final accountId = _accountId;
    final site = _siteUrl;
    if (accountId == null || site == null) return;
    final path = '/accounts/$accountId/workers/scripts/$_workerName/subdomain';
    final versions = await _api.send(
      method: 'GET',
      path: '/accounts/$accountId/workers/scripts/$_workerName/versions',
      retry: true,
    );
    final ids = _versionIds(versions);
    final before = await _api.send(method: 'GET', path: path, retry: true);
    final previewsOff = before.result?['previews_enabled'] == false;
    final probe = ids.isEmpty ? null : await _probeVersionUrl(ids.first, site);
    report.check(
      'T11',
      'old version not reachable with version URLs off',
      pass: previewsOff && probe != true,
      detail:
          'previews=$previewsOff versions=${ids.length} '
          'reachable=${probe?.toString() ?? 'unknown'}',
    );
    // T15: prove the setting is what matters.
    await _api.send(
      method: 'POST',
      path: path,
      jsonBody: {'enabled': true, 'previews_enabled': true},
    );
    final withPreviews = ids.isEmpty
        ? null
        : await _probeVersionUrl(ids.first, site);
    await _api.send(
      method: 'POST',
      path: path,
      jsonBody: {'enabled': true, 'previews_enabled': false},
    );
    final after = await _api.send(method: 'GET', path: path, retry: true);
    report
      ..info(
        'T15',
        'version-URL gate',
        'off-reachable=${probe?.toString() ?? 'unknown'} '
            'on-reachable=${withPreviews?.toString() ?? 'unknown'} '
            'restored=${after.result?['previews_enabled'] == false}',
      )
      ..manual(
        'T11b',
        'failure-to-disable path',
        'needs a token that cannot write the subdomain setting; '
            'record by hand',
      );
  }

  List<String> _versionIds(TrialResponse response) {
    final list = response.resultList ?? const [];
    return [
      for (final entry in list)
        if (entry is Map && entry['id'] is String) entry['id'] as String,
    ];
  }

  /// Probes the documented version-URL shape; null when it cannot be built.
  Future<bool?> _probeVersionUrl(String versionId, String site) async {
    final host = Uri.parse(site).host;
    final url = Uri.parse('https://$versionId-$host/');
    final response = await TrialPublic.get(url);
    if (response.status == 0) return null;
    return response.ok;
  }

  // ---- T12: retired deploy -------------------------------------------------

  Future<void> _t12Retired() async {
    final accountId = _accountId;
    final site = _siteUrl;
    if (accountId == null || site == null) return;
    final marker = PublishMarker(
      publishId: PublishMarker.generatePublishId(),
      publishedAt: DateTime.now().millisecondsSinceEpoch,
      state: PublishMarkerState.retired,
    );
    final assets = TrialAssets.retired(markerJson: jsonEncode(marker.toJson()));
    final session = await _api.send(
      method: 'POST',
      path:
          '/accounts/$accountId/workers/scripts/$_workerName/'
          'assets-upload-session',
      jsonBody: {
        'manifest': {
          for (final asset in assets)
            asset.manifestKey: {'hash': asset.hash, 'size': asset.size},
        },
      },
    );
    if (!session.ok || !(session.success ?? false)) {
      report.check(
        'T12',
        'retired deploy',
        pass: false,
        detail: 'session ${session.label}',
      );
      return;
    }
    final buckets = _parseBuckets(session.result?['buckets']);
    final sessionJwt = session.result?['jwt'];
    if (sessionJwt is! String) {
      report.check(
        'T12',
        'retired deploy',
        pass: false,
        detail: 'session jwt=absent',
      );
      return;
    }
    final byHash = {for (final asset in assets) asset.hash: asset};
    String? completion;
    for (final bucket in buckets) {
      final bucketAssets = [
        for (final hash in bucket)
          if (byHash[hash] case final asset?) asset,
      ];
      final boundary = TrialMultipart.newBoundary();
      final response = await _api.send(
        method: 'POST',
        path: '/accounts/$accountId/workers/assets/upload?base64=true',
        body: TrialMultipart.bucketBody(
          boundary: boundary,
          assets: bucketAssets,
        ),
        contentType: 'multipart/form-data; boundary=$boundary',
        bearer: sessionJwt,
        deadline: CloudflareLimits.uploadDeadline,
        retry: true,
      );
      final jwt = response.result?['jwt'];
      if (jwt is String && jwt.isNotEmpty) completion = jwt;
    }
    completion ??= buckets.isEmpty ? sessionJwt : null;
    if (completion == null) {
      report.check(
        'T12',
        'retired deploy',
        pass: false,
        detail: 'completion=absent',
      );
      return;
    }
    final boundary = TrialMultipart.newBoundary();
    final deploy = await _api.send(
      method: 'PUT',
      path: '/accounts/$accountId/workers/scripts/$_workerName',
      body: TrialMultipart.deployBody(
        boundary: boundary,
        completionJwt: completion,
        htmlHandling: 'auto-trailing-slash',
        notFoundHandling: '404-page',
        headers: TrialMultipart.retiredHeaders,
      ),
      contentType: 'multipart/form-data; boundary=$boundary',
      deadline: CloudflareLimits.uploadDeadline,
    );
    final root = Uri.parse(site);
    await _waitForRoot(root);
    final books = await TrialPublic.get(root.resolve('books.json'));
    final markerResponse = await TrialPublic.get(
      root.resolve(CloudflareLimits.markerPath),
    );
    final parsed = markerResponse.ok
        ? PublishMarker.tryParse(_tryDecode(markerResponse))
        : null;
    final csp = markerResponse.headers['content-security-policy'] ?? '';
    report.check(
      'T12',
      'retired deploy',
      pass:
          deploy.ok &&
          books.status == 404 &&
          (parsed?.isRetired ?? false) &&
          csp.contains("default-src 'none'"),
      detail:
          'deploy=${deploy.status} books404=${books.status == 404} '
          'marker=${parsed?.state.name ?? 'unreadable'} '
          'csp=${csp.isEmpty ? 'absent' : 'present'}',
    );
  }

  // ---- T5b: large asset set ------------------------------------------------

  Future<void> _t5bLarge() async {
    final accountId = _accountId;
    if (accountId == null) return;
    final watch = Stopwatch()..start();
    final assets = TrialLargeAsset.build(count: 2000, size: 100 * 1024);
    final manifest = <String, Object?>{
      for (final asset in assets)
        asset.manifestKey: {'hash': asset.hash, 'size': asset.size},
    };
    final response = await _api.send(
      method: 'POST',
      path:
          '/accounts/$accountId/workers/scripts/$_largeWorkerName/'
          'assets-upload-session',
      jsonBody: {'manifest': manifest},
    );
    watch.stop();
    if (!response.ok || !(response.success ?? false)) {
      report.check(
        'T5b',
        'large asset set',
        pass: false,
        detail: response.label,
      );
      return;
    }
    _largeWorkerCreated = true;
    final buckets = _parseBuckets(response.result?['buckets']);
    var largest = 0;
    var requested = 0;
    for (final bucket in buckets) {
      requested += bucket.length;
      if (bucket.length > largest) largest = bucket.length;
    }
    report.info(
      'T5b',
      'large asset set',
      'files=${assets.length} buckets=${buckets.length} '
          'largest=$largest requested=$requested '
          'hashMs=${watch.elapsedMilliseconds} uploaded=no',
    );
  }

  // ---- T13: cleanup --------------------------------------------------------

  Future<void> _t13Cleanup() async {
    final accountId = _accountId;
    if (accountId == null) {
      report.skip('T13', 'cleanup', 'no account id');
      return;
    }
    final names = <String>[
      _workerName,
      if (_largeWorkerCreated) _largeWorkerName,
    ];
    var deleted = 0;
    var absent = 0;
    for (final name in names) {
      final delete = await _api.send(
        method: 'DELETE',
        path: '/accounts/$accountId/workers/scripts/$name',
      );
      if (delete.ok) deleted++;
      final read = await _api.send(
        method: 'GET',
        path: '/accounts/$accountId/workers/scripts/$name',
        retry: true,
      );
      if (read.status == 404) absent++;
    }
    report.check(
      'T13',
      'cleanup',
      pass: absent == names.length,
      detail: 'workers=${names.length} deleted=$deleted absent=$absent',
    );
  }

  // ---- helpers -------------------------------------------------------------

  void _skipDeployChecks(String reason) {
    for (final id in <String>['T4', 'T5', 'T6', 'T7', 'T8', 'T9', 'T10']) {
      report.skip(id, 'deploy-dependent check', reason);
    }
  }

  static List<List<String>> _parseBuckets(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final bucket in raw)
        if (bucket is List)
          [
            for (final hash in bucket)
              if (hash is String) hash,
          ],
    ];
  }

  static Map<String, Object?>? _tryDecode(PublicResponse response) {
    if (response.body.isEmpty) return null;
    try {
      final value = jsonDecode(utf8.decode(response.body));
      return value is Map<String, Object?> ? value : null;
    } on FormatException {
      return null;
    }
  }

  static String _hex(int bytes) {
    final random = Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < bytes; i++) {
      buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}
