import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pitaka/core/network/app_user_agent.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_account_id.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_models.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_token.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_subdomain.dart';
import 'package:pitaka/features/publish/infrastructure/cloudflare_http_transport.dart';
import 'package:pitaka/features/publish/infrastructure/http_cloudflare_account_api.dart';

const _tokenValue = 'cfut_0123456789abcdefABCDEF';
const _accountIdValue = '0123456789abcdef0123456789abcdef';
final _token = CloudflareApiToken.tryParse(_tokenValue)!;
final _accountId = CloudflareAccountId.tryParse(_accountIdValue)!;
final _candidate = CloudflareSubdomain.tryParse('library')!;

HttpCloudflareAccountApi _api(http.Client client, {List<Duration>? sleeps}) =>
    HttpCloudflareAccountApi(
      CloudflareHttpTransport(
        client: client,
        sleep: (delay) async => sleeps?.add(delay),
      ),
    );

http.Response _json(
  Object? body, {
  int status = 200,
  Map<String, String>? headers,
}) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json', ...?headers},
);

Map<String, Object?> _envelope(
  Object? result, {
  bool success = true,
  List<Map<String, Object?>> errors = const [],
}) => {'success': success, 'result': result, 'errors': errors};

Map<String, Object?> _error(int code, [String message = 'fixed test error']) =>
    {'code': code, 'message': message};

String _id(int index) => index.toRadixString(16).padLeft(32, '0');

List<Map<String, Object?>> _accounts(int from, int count) => [
  for (var i = from; i < from + count; i++)
    {'id': _id(i), 'name': 'Account $i'},
];

void _expectRequest(
  http.Request request, {
  required String method,
  required String path,
  Map<String, String>? query,
}) {
  expect(request.method, method);
  expect(request.url.origin, 'https://api.cloudflare.com');
  expect(request.url.path, '/client/v4$path');
  if (query == null) {
    expect(request.url.queryParameters, isEmpty);
  } else {
    expect(request.url.queryParameters, query);
  }
  expect(request.url.userInfo, isEmpty);
  expect(request.headers['Authorization'], 'Bearer $_tokenValue');
  expect(request.headers['User-Agent'], AppUserAgent.value);
  expect(request.headers['Accept'], 'application/json');
  expect(request.followRedirects, isFalse);
  expect(request.maxRedirects, 0);
}

Future<CloudflareApiException> _failure(Future<Object?> operation) async {
  try {
    await operation;
  } on CloudflareApiException catch (error) {
    return error;
  }
  fail('Expected a CloudflareApiException');
}

void main() {
  group('token verification', () {
    test(
      'user verify uses the fixed path and parses active expiry as UTC',
      () async {
        final api = _api(
          MockClient((request) async {
            _expectRequest(request, method: 'GET', path: '/user/tokens/verify');
            return _json(
              _envelope({
                'status': 'active',
                'expires_on': '2026-12-31T23:30:00+05:30',
              }),
            );
          }),
        );

        final result = await api.verifyUserToken(_token);

        expect(result.status, 'active');
        expect(result.isActive, isTrue);
        expect(result.expiresOn, DateTime.utc(2026, 12, 31, 18));
      },
    );

    test(
      'account verify includes the account and accepts absent expiry',
      () async {
        final api = _api(
          MockClient((request) async {
            _expectRequest(
              request,
              method: 'GET',
              path: '/accounts/$_accountIdValue/tokens/verify',
            );
            return _json(_envelope({'status': 'active', 'expires_on': null}));
          }),
        );

        final result = await api.verifyAccountToken(
          token: _token,
          accountId: _accountId,
        );

        expect(result.isActive, isTrue);
        expect(result.expiresOn, isNull);
      },
    );

    test('wrong result, status, and expiry shapes are malformed', () async {
      final malformedResults = <Object?>[
        42,
        {'status': 42},
        {'status': 'active', 'expires_on': 'not-a-date'},
      ];
      for (final result in malformedResults) {
        final api = _api(MockClient((_) async => _json(_envelope(result))));
        final error = await _failure(api.verifyUserToken(_token));
        expect(error.kind, CloudflareApiExceptionKind.malformedResponse);
      }
    });
  });

  group('account listing', () {
    test('one partial page is complete and requests 50 per page', () async {
      final pages = <int>[];
      final api = _api(
        MockClient((request) async {
          _expectRequest(
            request,
            method: 'GET',
            path: '/accounts',
            query: const {'per_page': '50', 'page': '1'},
          );
          pages.add(1);
          return _json(_envelope(_accounts(0, 2)));
        }),
      );

      final result = await api.listAccounts(_token);

      expect(pages, [1]);
      expect(result.truncated, isFalse);
      expect(result.accounts, hasLength(2));
      expect(result.accounts.first.id.value, _id(0));
      expect(result.accounts.last.name, 'Account 1');
    });

    test(
      'a full page followed by a partial page returns every account',
      () async {
        final pages = <String>[];
        final api = _api(
          MockClient((request) async {
            final page = request.url.queryParameters['page']!;
            _expectRequest(
              request,
              method: 'GET',
              path: '/accounts',
              query: {'per_page': '50', 'page': page},
            );
            pages.add(page);
            final number = int.parse(page);
            return _json(
              _envelope(_accounts((number - 1) * 50, number == 1 ? 50 : 2)),
            );
          }),
        );

        final result = await api.listAccounts(_token);

        expect(pages, ['1', '2']);
        expect(result.accounts, hasLength(52));
        expect(result.accounts[50].id.value, _id(50));
        expect(result.truncated, isFalse);
      },
    );

    test('four full pages stop at the budget and report truncation', () async {
      final pages = <String>[];
      final api = _api(
        MockClient((request) async {
          final page = request.url.queryParameters['page']!;
          _expectRequest(
            request,
            method: 'GET',
            path: '/accounts',
            query: {'per_page': '50', 'page': page},
          );
          pages.add(page);
          final number = int.parse(page);
          return _json(_envelope(_accounts((number - 1) * 50, 50)));
        }),
      );

      final result = await api.listAccounts(_token);

      expect(pages, ['1', '2', '3', '4']);
      expect(result.accounts, hasLength(200));
      expect(result.truncated, isTrue);
    });

    test('malformed and duplicate entries fail the whole listing', () async {
      final malformedResults = <Object?>[
        {'not': 'a list'},
        [
          {'id': 'bad', 'name': 'Bad id'},
        ],
        [
          {'id': _id(1), 'name': 42},
        ],
        [
          {'id': _id(1), 'name': 'First'},
          {'id': _id(1), 'name': 'Duplicate'},
        ],
      ];
      for (final result in malformedResults) {
        final api = _api(MockClient((_) async => _json(_envelope(result))));
        final error = await _failure(api.listAccounts(_token));
        expect(error.kind, CloudflareApiExceptionKind.malformedResponse);
      }
    });
  });

  group('account subdomain reads and availability', () {
    test('read returns the validated subdomain', () async {
      final api = _api(
        MockClient((request) async {
          _expectRequest(
            request,
            method: 'GET',
            path: '/accounts/$_accountIdValue/workers/subdomain',
          );
          return _json(_envelope({'subdomain': 'library'}));
        }),
      );

      final result = await api.readAccountSubdomain(
        token: _token,
        accountId: _accountId,
      );

      expect(result?.value, 'library');
    });

    test('explicit 10007 means absent', () async {
      final api = _api(
        MockClient(
          (_) async => _json(
            _envelope(null, success: false, errors: [_error(10007)]),
            status: 404,
          ),
        ),
      );

      final result = await api.readAccountSubdomain(
        token: _token,
        accountId: _accountId,
      );

      expect(result, isNull);
    });

    test(
      '403 is a fixed safe failure with redacted response details',
      () async {
        const rawSecret = 'raw response text that must not escape $_tokenValue';
        final api = _api(
          MockClient(
            (_) async => _json(
              _envelope(
                null,
                success: false,
                errors: [_error(10000, rawSecret)],
              ),
              status: 403,
            ),
          ),
        );

        final error = await _failure(
          api.readAccountSubdomain(token: _token, accountId: _accountId),
        );

        expect(error.kind, CloudflareApiExceptionKind.forbidden);
        expect(error.statusCode, 403);
        expect(error.errorCodes, [10000]);
        expect(error.message, CloudflareApiExceptionKind.forbidden.message);
        expect(error.toString(), isNot(contains(rawSecret)));
        expect(error.toString(), isNot(contains(_tokenValue)));
      },
    );

    test('403 remains a permission failure even with code 10007', () async {
      final api = _api(
        MockClient(
          (_) async => _json(
            _envelope(null, success: false, errors: [_error(10007)]),
            status: 403,
          ),
        ),
      );

      final error = await _failure(
        api.readAccountSubdomain(token: _token, accountId: _accountId),
      );

      expect(error.kind, CloudflareApiExceptionKind.forbidden);
      expect(error.statusCode, 403);
      expect(error.errorCodes, [10007]);
    });

    test('429 and 500 never turn code 10007 into confirmed absence', () async {
      for (final (status, kind) in [
        (429, CloudflareApiExceptionKind.rateLimited),
        (500, CloudflareApiExceptionKind.server),
      ]) {
        final api = _api(
          MockClient(
            (_) async => _json(
              _envelope(null, success: false, errors: [_error(10007)]),
              status: status,
            ),
          ),
        );
        final error = await _failure(
          api.readAccountSubdomain(token: _token, accountId: _accountId),
        );
        expect(error.kind, kind);
        expect(error.statusCode, status);
        expect(error.errorCodes, [10007]);
      }
    });

    test('availability maps explicit true, false, and unknown only', () async {
      final cases = <(CloudflareSubdomainAvailability, Object?)>[
        (CloudflareSubdomainAvailability.available, {'available': true}),
        (CloudflareSubdomainAvailability.taken, {'available': false}),
        (CloudflareSubdomainAvailability.unknown, <String, Object?>{}),
      ];
      for (final (expected, result) in cases) {
        final api = _api(
          MockClient((request) async {
            _expectRequest(
              request,
              method: 'GET',
              path:
                  '/accounts/$_accountIdValue/workers/subdomains/${_candidate.value}',
            );
            return _json(_envelope(result));
          }),
        );

        final checked = await api.checkAccountSubdomain(
          token: _token,
          accountId: _accountId,
          candidate: _candidate,
        );

        expect(checked.candidate, same(_candidate));
        expect(checked.availability, expected);
      }
    });

    test(
      '10031 and 10032 remain numeric failures, not guessed availability',
      () async {
        final api = _api(
          MockClient(
            (_) async => _json(
              _envelope(
                null,
                success: false,
                errors: [_error(10031), _error(10032)],
              ),
              status: 400,
            ),
          ),
        );

        final error = await _failure(
          api.checkAccountSubdomain(
            token: _token,
            accountId: _accountId,
            candidate: _candidate,
          ),
        );

        expect(error.kind, CloudflareApiExceptionKind.requestRejected);
        expect(error.errorCodes, [10031, 10032]);
      },
    );
  });

  group('account subdomain creation', () {
    test(
      'PUT body is followed by a mandatory matching GET confirmation',
      () async {
        final calls = <String>[];
        final api = _api(
          MockClient((request) async {
            calls.add(request.method);
            _expectRequest(
              request,
              method: calls.length == 1 ? 'PUT' : 'GET',
              path: '/accounts/$_accountIdValue/workers/subdomain',
            );
            if (request.method == 'PUT') {
              expect(request.headers['Content-Type'], 'application/json');
              expect(jsonDecode(request.body), {'subdomain': 'library'});
            }
            return _json(_envelope({'subdomain': 'library'}));
          }),
        );

        final result = await api.createAccountSubdomain(
          token: _token,
          accountId: _accountId,
          candidate: _candidate,
        );

        expect(result.value, 'library');
        expect(calls, ['PUT', 'GET']);
      },
    );

    test(
      'a different GET confirmation fails instead of returning success',
      () async {
        final calls = <String>[];
        final api = _api(
          MockClient((request) async {
            calls.add(request.method);
            return _json(
              _envelope({
                'subdomain': request.method == 'PUT'
                    ? 'library'
                    : 'someone-else',
              }),
            );
          }),
        );

        final error = await _failure(
          api.createAccountSubdomain(
            token: _token,
            accountId: _accountId,
            candidate: _candidate,
          ),
        );

        expect(calls, ['PUT', 'GET']);
        expect(error.kind, CloudflareApiExceptionKind.requestRejected);
        expect(error.uncertain, isTrue);
      },
    );

    test(
      'uncertain PUT re-reads absence before one retry and then confirms',
      () async {
        final calls = <String>[];
        final sleeps = <Duration>[];
        var puts = 0;
        var gets = 0;
        final api = _api(
          MockClient((request) async {
            calls.add(request.method);
            if (request.method == 'PUT') {
              puts++;
              if (puts == 1) {
                throw http.ClientException('connection reset', request.url);
              }
              return _json(_envelope({'subdomain': 'library'}));
            }
            gets++;
            if (gets == 1) {
              return _json(
                _envelope(null, success: false, errors: [_error(10007)]),
                status: 404,
              );
            }
            return _json(_envelope({'subdomain': 'library'}));
          }),
          sleeps: sleeps,
        );

        final result = await api.createAccountSubdomain(
          token: _token,
          accountId: _accountId,
          candidate: _candidate,
        );

        expect(result.value, 'library');
        expect(calls, ['PUT', 'GET', 'PUT', 'GET']);
        expect(sleeps, [const Duration(seconds: 1)]);
      },
    );

    test(
      'uncertain PUT returns already-created after recovery GET without retry',
      () async {
        final calls = <String>[];
        final sleeps = <Duration>[];
        final api = _api(
          MockClient((request) async {
            calls.add(request.method);
            if (request.method == 'PUT') {
              throw http.ClientException(
                'Request timed out after 30s',
                request.url,
              );
            }
            return _json(_envelope({'subdomain': 'library'}));
          }),
          sleeps: sleeps,
        );

        final result = await api.createAccountSubdomain(
          token: _token,
          accountId: _accountId,
          candidate: _candidate,
        );

        expect(result.value, 'library');
        expect(calls, ['PUT', 'GET']);
        expect(sleeps, isEmpty);
      },
    );
  });
}
