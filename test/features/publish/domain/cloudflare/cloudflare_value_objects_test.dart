import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_account_id.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_token.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_content_type.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_site_url.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_subdomain.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_worker_name.dart';
import 'package:pitaka/features/publish/domain/cloudflare/unverified_cloudflare_address.dart';
import 'package:pitaka/features/publish/domain/site/site_path.dart';

/// SPECIFICATION of the Cloudflare value objects (Cloudflare plan S5, J.1).
///
/// The point of these tests: every value that ends up in an API path, a public
/// address or a published file is validated at construction, and the hostile
/// spellings (traversal, userinfo, ports, evil suffixes, control characters)
/// have no representation.
void main() {
  group('CloudflareApiToken', () {
    test('accepts the three documented shapes', () {
      final user = 'cfut_${'a' * 40}';
      final account = 'cfat_${'B' * 40}';
      final legacy = 'x' * 40;

      expect(CloudflareApiToken.isValidShape(user), isTrue);
      expect(CloudflareApiToken.isValidShape(account), isTrue);
      expect(CloudflareApiToken.isValidShape(legacy), isTrue);
    });

    test('the value is readable only through use()', () {
      final token = CloudflareApiToken.tryParse('cfut_${'a' * 40}')!;

      expect(token.use((value) => value), 'cfut_${'a' * 40}');
    });

    test('toString never contains the value', () {
      final token = CloudflareApiToken.tryParse('cfut_${'a' * 40}')!;

      expect(token.toString(), 'CloudflareApiToken(***)');
      expect(token.toString().contains('cfut_'), isFalse);
    });

    for (final hostile in <String?>[
      null,
      '',
      ' ',
      ' cfut_${'a' * 40}',
      'cfut_${'a' * 40} ',
      'cfut_short',
      'cfut_${'a' * 40}.',
      'cfut_${'a' * 40}/',
      'cfut_${'a' * 40}:',
      'https://api.cloudflare.com/client/v4',
      'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.signature',
      'x' * 39,
      'x' * 41,
      'x' * (CloudflareApiToken.maxLength + 1),
      'cfut_${'a' * 40}\u0000',
      'cfut_${'a' * 40}\n',
      'cfüt_${'a' * 40}',
    ]) {
      test('refuses "$hostile"', () {
        expect(CloudflareApiToken.tryParse(hostile), isNull);
      });
    }
  });

  group('CloudflareAccountId', () {
    test('accepts 32 hex characters and folds case', () {
      final id = CloudflareAccountId.tryParse(
        '0123456789ABCDEF0123456789abcdef',
      )!;

      expect(id.value, '0123456789abcdef0123456789abcdef');
    });

    for (final hostile in <String?>[
      null,
      '',
      '0123456789abcdef0123456789abcde', // 31
      '0123456789abcdef0123456789abcdef0', // 33
      '0123456789abcdef0123456789abcdeg',
      '0123456789abcdef 123456789abcdef',
      '0123456789abcdef-123456789abcdef',
      '０123456789abcdef0123456789abcdef',
    ]) {
      test('refuses "$hostile"', () {
        expect(CloudflareAccountId.tryParse(hostile), isNull);
      });
    }
  });

  group('CloudflareWorkerName', () {
    test('keeps the API spelling and derives a lower-case DNS label', () {
      final name = CloudflareWorkerName.tryParse('Kadugodi-Library')!;

      expect(name.value, 'Kadugodi-Library');
      expect(name.dnsLabel, 'kadugodi-library');
    });

    test('accepts the 63-character boundary', () {
      expect(CloudflareWorkerName.isValid('a' * 63), isTrue);
      expect(CloudflareWorkerName.isValid('a' * 64), isFalse);
    });

    for (final hostile in <String?>[
      null,
      '',
      '-name',
      'name-',
      'na me',
      'na.me',
      'na_me',
      'na/me',
      'na\u0000me',
      'näme',
      'name\n',
    ]) {
      test('refuses "$hostile"', () {
        expect(CloudflareWorkerName.tryParse(hostile), isNull);
      });
    }
  });

  group('CloudflareSubdomain', () {
    test('folds case and accepts the DNS-label boundary', () {
      expect(CloudflareSubdomain.tryParse('Kadugodi')!.value, 'kadugodi');
      expect(CloudflareSubdomain.isValid('a' * 63), isTrue);
      expect(CloudflareSubdomain.isValid('a' * 64), isFalse);
    });

    for (final hostile in <String?>[
      null,
      '',
      '-name',
      'name-',
      'na.me',
      'na_me',
      'na me',
      'na\u0000me',
      'näme',
    ]) {
      test('refuses "$hostile"', () {
        expect(CloudflareSubdomain.tryParse(hostile), isNull);
      });
    }
  });

  group('CloudflareSiteUrl', () {
    test('is derived from the parts, never supplied', () {
      final site = CloudflareSiteUrl.create(
        workerName: 'Kadugodi-Library',
        accountSubdomain: 'Kadugodi',
      )!;

      expect(site.host, 'kadugodi-library.kadugodi.workers.dev');
      expect(site.siteUrl, 'https://kadugodi-library.kadugodi.workers.dev/');
    });

    test('parses a canonical address back to its labels', () {
      final site = CloudflareSiteUrl.tryParse(
        'https://kadugodi-library.kadugodi.workers.dev/',
      )!;

      expect(site.workerDnsLabel, 'kadugodi-library');
      expect(site.accountSubdomain, 'kadugodi');
    });

    for (final hostile in <String?>[
      null,
      '',
      'https://workers.dev/',
      'https://name.workers.dev/',
      'https://name.sub.extra.workers.dev/',
      'https://name.sub.workers.dev/books.json',
      'http://name.sub.workers.dev/',
      'https://user:pass@name.sub.workers.dev/',
      'https://name.sub.workers.dev:8443/',
      'https://name.sub.workers.dev/?x=1',
      'https://name.sub.workers.dev/#frag',
      'https://name.sub.workers.dev./',
      'https://name.sub.workers.dev.evil.example/',
      'https://evil.example/name.sub.workers.dev/',
      'https://-name.sub.workers.dev/',
      'https://name.sub_extra.workers.dev/',
    ]) {
      test('refuses "$hostile"', () {
        expect(CloudflareSiteUrl.tryParse(hostile), isNull);
      });
    }
  });

  group('UnverifiedCloudflareAddress', () {
    test('accepts a Workers-shaped candidate for the verification fetch', () {
      final candidate = UnverifiedCloudflareAddress.tryParse(
        'https://library.name.workers.dev/',
      )!;

      expect(candidate.host, 'library.name.workers.dev');
      expect(
        candidate.verificationSiteUrl,
        'https://library.name.workers.dev/',
      );
    });

    test('refuses anything that is not a canonical Workers root', () {
      for (final hostile in <String?>[
        null,
        'https://evil.example/',
        'https://library.name.workers.dev/books.json',
        'http://library.name.workers.dev/',
      ]) {
        expect(UnverifiedCloudflareAddress.tryParse(hostile), isNull);
      }
    });
  });

  group('CloudflareContentType', () {
    test('maps exactly the three published extensions', () {
      expect(
        CloudflareContentType.forExtension('html')!.header,
        'text/html; charset=utf-8',
      );
      expect(
        CloudflareContentType.forExtension('json')!.header,
        'application/json',
      );
      expect(CloudflareContentType.forExtension('jpg')!.header, 'image/jpeg');
    });

    test('is case-sensitive: X.JPG is not a published type', () {
      expect(CloudflareContentType.forExtension('JPG'), isNull);
      expect(CloudflareContentType.forExtension('HTML'), isNull);
      expect(
        CloudflareContentType.forPath(SitePath.tryParse('covers/X.JPG')!),
        isNull,
      );
    });

    test('refuses every other extension', () {
      for (final extension in <String?>[
        null,
        '',
        'png',
        'gif',
        'css',
        'js',
        'txt',
        'webp',
      ]) {
        expect(CloudflareContentType.forExtension(extension), isNull);
      }
    });

    test('round-trips through the stored header', () {
      for (final type in CloudflareContentType.values) {
        expect(CloudflareContentType.forHeader(type.header), type);
      }
      expect(CloudflareContentType.forHeader('text/plain'), isNull);
      expect(CloudflareContentType.forHeader(null), isNull);
    });
  });
}
