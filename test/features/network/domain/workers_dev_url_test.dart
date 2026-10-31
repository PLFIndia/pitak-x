import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/network/workers_dev_url.dart';

/// Cloudflare Workers address grammar (Cloudflare plan R15, B.1).
///
/// The grammar is the ONE shared rule for the reader (`BookmarkUrl`) and the
/// publisher (`CloudflareSiteUrl`, S5), so every hostile shape the plan names
/// is pinned here: the apex, one-label and extra-label forms, bad worker
/// /subdomain labels, trailing dots, userinfo, ports, queries and non-root
/// paths.
void main() {
  group('WorkersDevUrl.parseHost — accepted', () {
    test('splits the two leading labels', () {
      final site = WorkersDevUrl.parseHost(
        'kadugodi-library.kadugodi.workers.dev',
      );
      expect(site, isNotNull);
      expect(site!.workerName, 'kadugodi-library');
      expect(site.accountSubdomain, 'kadugodi');
      expect(site.host, 'kadugodi-library.kadugodi.workers.dev');
      expect(site.siteUrl, 'https://kadugodi-library.kadugodi.workers.dev/');
    });

    test('is case-insensitive and returns the lower-case canonical host', () {
      final site = WorkersDevUrl.parseHost('My-Worker.My-Sub.WORKERS.dev');
      expect(site, isNotNull);
      expect(site!.host, 'my-worker.my-sub.workers.dev');
    });

    test('accepts a single-character worker and subdomain', () {
      expect(WorkersDevUrl.parseHost('a.b.workers.dev'), isNotNull);
    });

    test('accepts 63-character labels', () {
      final worker = 'a' * 63;
      final sub = 'b' * 63;
      expect(WorkersDevUrl.parseHost('$worker.$sub.workers.dev'), isNotNull);
    });
  });

  group('WorkersDevUrl.parseHost — refused shapes', () {
    const refused = <String, String>{
      '': 'empty host',
      'workers.dev': 'apex (no labels)',
      'name.workers.dev': 'one leading label',
      'a.b.c.workers.dev': 'three leading labels',
      'a.b.workers.dev.evil.com': 'evil suffix after the real one',
      'evilworkers.dev': 'suffix without a dot boundary',
      'workers.dev.evil.com': 'apex plus attacker suffix',
      'a.b.workers.dev.': 'trailing dot',
      'a.b.workers.com': 'wrong TLD',
      'a.b.workers.devv': 'wrong TLD with suffix',
      'a-b.-c.workers.dev': 'subdomain starting with a hyphen',
      'a-b.c-.workers.dev': 'subdomain ending with a hyphen',
      '-ab.c.workers.dev': 'worker starting with a hyphen',
      'ab-.c.workers.dev': 'worker ending with a hyphen',
      'a b.c.workers.dev': 'space in the worker label',
      'a_b.c.workers.dev': 'underscore in the worker label',
      'a.b_c.workers.dev': 'underscore in the subdomain',
      'ü.b.workers.dev': 'non-ASCII (un-punycoded) label',
      'a.b.workers.dev..': 'double trailing dot',
    };
    for (final entry in refused.entries) {
      test('refuses ${entry.value}: "${entry.key}"', () {
        expect(WorkersDevUrl.parseHost(entry.key), isNull);
      });
    }

    test('refuses a 64-character label', () {
      final worker = 'a' * 64;
      expect(WorkersDevUrl.parseHost('$worker.b.workers.dev'), isNull);
      expect(WorkersDevUrl.parseHost('a.${'b' * 64}.workers.dev'), isNull);
    });

    test('refuses an IDN punycode label (only [a-z0-9-] is a Worker name)', () {
      // Punycode contains hyphens and digits but starts with `xn--`, which is
      // label-shaped — it is refused only because `--` is legal in a DNS
      // label yet the WORKER label forbids nothing extra. This pins the
      // decision: a punycode worker name parses (Cloudflare accepts it as
      // [a-z0-9-]), so it must NOT be rejected here.
      expect(WorkersDevUrl.parseHost('xn--bcher-kva.b.workers.dev'), isNotNull);
    });
  });

  group('WorkersDevUrl.parse — full address', () {
    test('accepts the canonical root', () {
      final site = WorkersDevUrl.parse(
        'https://kadugodi-library.kadugodi.workers.dev/',
      );
      expect(site?.workerName, 'kadugodi-library');
      expect(site?.accountSubdomain, 'kadugodi');
    });

    test('accepts an address with no path (same site as the root)', () {
      expect(WorkersDevUrl.parse('https://w.s.workers.dev'), isNotNull);
    });

    test('accepts the root when a default https port is written', () {
      expect(WorkersDevUrl.parse('https://w.s.workers.dev:443/'), isNotNull);
    });

    test('trims surrounding whitespace', () {
      expect(WorkersDevUrl.parse('  https://w.s.workers.dev/  '), isNotNull);
    });

    const refused = <String, String>{
      'http://w.s.workers.dev/': 'plain http',
      'ftp://w.s.workers.dev/': 'wrong scheme',
      'https://user@w.s.workers.dev/': 'userinfo',
      'https://user:pw@w.s.workers.dev/': 'userinfo with password',
      'https://w.s.workers.dev:8443/': 'non-default port',
      'https://w.s.workers.dev/?x=1': 'query',
      'https://w.s.workers.dev/#top': 'fragment',
      'https://w.s.workers.dev/books.json': 'non-root path',
      'https://w.s.workers.dev/library/': 'deeper directory',
      'https://w.s.workers.dev//': 'doubled slash',
      'https://workers.dev/': 'apex',
      'https://name.workers.dev/': 'one label',
      'https://a.b.c.workers.dev/': 'extra label',
      'https://a.b.workers.dev.evil.com/': 'evil suffix',
      '': 'empty',
      'not a url': 'not a URL',
    };
    for (final entry in refused.entries) {
      test('refuses ${entry.value}: "${entry.key}"', () {
        expect(WorkersDevUrl.parse(entry.key), isNull);
      });
    }

    test('a file path is accepted only when the caller allows it', () {
      // The reader stores/compares ROOTS, but the viewer must be able to fetch
      // `books.json` from a site it already validated at the root.
      expect(WorkersDevUrl.parse('https://w.s.workers.dev/books.json'), isNull);
      expect(
        WorkersDevUrl.parse(
          'https://w.s.workers.dev/books.json',
          requireRootPath: false,
        ),
        isNotNull,
      );
    });
  });

  group('claimsWorkersSuffix', () {
    test('claims the apex and every dotted suffix form', () {
      expect(WorkersDevUrl.claimsWorkersSuffix('workers.dev'), isTrue);
      expect(WorkersDevUrl.claimsWorkersSuffix('a.b.workers.dev'), isTrue);
      expect(WorkersDevUrl.claimsWorkersSuffix('A.B.Workers.Dev'), isTrue);
    });

    test('does not claim look-alikes', () {
      expect(WorkersDevUrl.claimsWorkersSuffix('evilworkers.dev'), isFalse);
      expect(
        WorkersDevUrl.claimsWorkersSuffix('workers.dev.evil.com'),
        isFalse,
      );
      expect(WorkersDevUrl.claimsWorkersSuffix('pages.dev'), isFalse);
    });
  });
}
