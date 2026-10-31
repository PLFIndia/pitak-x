/// HTTP account/token/subdomain adapter for the Cloudflare setup role.
library;

import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_account_id.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_models.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_token.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_limits.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_subdomain.dart';
import 'package:pitaka/features/publish/infrastructure/cloudflare_http_transport.dart';
import 'package:pitaka/features/publish/infrastructure/cloudflare_json.dart';

/// Account-side implementation of [CloudflareAccountApi].
final class HttpCloudflareAccountApi implements CloudflareAccountApi {
  /// Creates the role adapter over the shared bounded transport.
  const HttpCloudflareAccountApi(this._transport);

  final CloudflareHttpTransport _transport;

  @override
  Future<CloudflareTokenVerification> verifyUserToken(
    CloudflareApiToken token,
  ) async => _verify(token, '/user/tokens/verify');

  @override
  Future<CloudflareTokenVerification> verifyAccountToken({
    required CloudflareApiToken token,
    required CloudflareAccountId accountId,
  }) async => _verify(token, '/accounts/${accountId.value}/tokens/verify');

  Future<CloudflareTokenVerification> _verify(
    CloudflareApiToken token,
    String path,
  ) async {
    final response = requireCloudflareSuccess(await _get(token, path));
    return parseCloudflareResponse(() {
      final result = cloudflareObject(response.result, maxEntries: 8);
      final expiresRaw = result['expires_on'];
      DateTime? expires;
      if (expiresRaw != null) {
        final text = cloudflareString(expiresRaw, maxLength: 64);
        expires = DateTime.tryParse(text)?.toUtc();
        if (expires == null) throw const CloudflareJsonException();
      }
      return CloudflareTokenVerification(
        status: cloudflareString(result['status'], maxLength: 32),
        expiresOn: expires,
      );
    });
  }

  @override
  Future<CloudflareAccountListing> listAccounts(
    CloudflareApiToken token,
  ) async {
    final accounts = <CloudflareAccount>[];
    final seen = <String>{};
    var truncated = false;
    for (var page = 1; page <= CloudflareLimits.maxAccountPages; page++) {
      final response = requireCloudflareSuccess(
        await _get(
          token,
          '/accounts',
          query: {
            // 50 is Cloudflare's documented maximum; the bound lives in the
            // domain limits so a page size cannot drift from its parser.
            'per_page': '${CloudflareLimits.accountsPerPage}',
            'page': '$page',
          },
        ),
      );
      final fullPage = parseCloudflareResponse(() {
        final result = cloudflareList(
          response.result,
          maxEntries: CloudflareLimits.accountsPerPage,
        );
        for (final raw in result) {
          final entry = cloudflareObject(raw);
          final id = CloudflareAccountId.tryParse(
            cloudflareString(
              entry['id'],
              maxLength: CloudflareAccountId.length,
            ),
          );
          if (id == null || !seen.add(id.value)) {
            throw const CloudflareJsonException();
          }
          accounts.add(
            CloudflareAccount(
              id: id,
              name: cloudflareString(entry['name'], maxLength: 256),
            ),
          );
        }
        return result.length == CloudflareLimits.accountsPerPage;
      });
      if (!fullPage) break;
      if (page == CloudflareLimits.maxAccountPages) truncated = true;
    }
    return CloudflareAccountListing(accounts: accounts, truncated: truncated);
  }

  @override
  Future<CloudflareSubdomain?> readAccountSubdomain({
    required CloudflareApiToken token,
    required CloudflareAccountId accountId,
  }) async {
    final response = await _get(
      token,
      '/accounts/${accountId.value}/workers/subdomain',
    );
    // Only the confirmed 404 + 10007 pair proves absence. A permission,
    // rate-limit or server failure must never authorize creation or retry.
    if (response.statusCode == 404 &&
        !response.isSuccess &&
        response.errorCodes.contains(10007)) {
      return null;
    }
    requireCloudflareSuccess(response);
    return parseCloudflareResponse(() => _subdomainFrom(response.result));
  }

  @override
  Future<CloudflareSubdomainCheckResult> checkAccountSubdomain({
    required CloudflareApiToken token,
    required CloudflareAccountId accountId,
    required CloudflareSubdomain candidate,
  }) async {
    final response = requireCloudflareSuccess(
      await _get(
        token,
        '/accounts/${accountId.value}/workers/subdomains/${candidate.value}',
      ),
    );
    return parseCloudflareResponse(() {
      var availability = CloudflareSubdomainAvailability.unknown;
      final result = response.result;
      if (result is Map<String, dynamic> && result.containsKey('available')) {
        availability = cloudflareBool(result['available'])
            ? CloudflareSubdomainAvailability.available
            : CloudflareSubdomainAvailability.taken;
      }
      // 10031/10032 are deliberately NOT guessed into either outcome: the S2
      // report did not establish their semantics (Part M evidence gap).
      return CloudflareSubdomainCheckResult(
        candidate: candidate,
        availability: availability,
      );
    });
  }

  @override
  Future<CloudflareSubdomain> createAccountSubdomain({
    required CloudflareApiToken token,
    required CloudflareAccountId accountId,
    required CloudflareSubdomain candidate,
  }) async {
    final path = '/accounts/${accountId.value}/workers/subdomain';
    final response = await token.use(
      (bearer) => _transport.send(
        path: path,
        bearer: bearer,
        requestBuilder: cloudflareJsonRequest('PUT', {
          'subdomain': candidate.value,
        }),
        idempotent: false,
        recover: () async {
          // A timeout may happen AFTER creation. Re-read before any retry: an
          // exact match is success, absence permits retry, another value stops.
          final current = await readAccountSubdomain(
            token: token,
            accountId: accountId,
          );
          if (current == null) return false;
          return current.value == candidate.value ? true : null;
        },
      ),
    );
    if (response == null) {
      return candidate; // Recovery proved the create landed.
    }
    requireCloudflareSuccess(response, uncertain: true);
    parseCloudflareResponse(() {
      final returned = _subdomainFrom(response.result);
      if (returned.value != candidate.value) {
        throw const CloudflareJsonException();
      }
    });
    final confirmed = await readAccountSubdomain(
      token: token,
      accountId: accountId,
    );
    if (confirmed?.value != candidate.value) {
      throw CloudflareApiException(
        CloudflareApiExceptionKind.requestRejected,
        uncertain: true,
      );
    }
    return candidate;
  }

  Future<CloudflareHttpResponse> _get(
    CloudflareApiToken token,
    String path, {
    Map<String, String>? query,
  }) async {
    final response = await token.use(
      (bearer) => _transport.send(
        path: path,
        bearer: bearer,
        queryParameters: query,
        requestBuilder: cloudflareJsonRequest('GET', null),
      ),
    );
    if (response == null) {
      throw StateError('A read-only Cloudflare call cannot be recovered');
    }
    return response;
  }

  static CloudflareSubdomain _subdomainFrom(Object? raw) {
    final result = cloudflareObject(raw, maxEntries: 8);
    final subdomain = CloudflareSubdomain.tryParse(
      cloudflareString(
        result['subdomain'],
        maxLength: CloudflareSubdomain.maxLength,
      ),
    );
    if (subdomain == null) throw const CloudflareJsonException();
    return subdomain;
  }
}
