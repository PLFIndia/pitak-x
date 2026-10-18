import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/network/domain/descriptor_fetch_result.dart';
import 'package:pitaka/features/network/domain/entities/library_descriptor.dart';
import 'package:pitaka/features/network/domain/library_descriptor_codec.dart';
import 'package:pitaka/features/network/domain/value_objects/geo_point.dart';

/// Every §3.1 wire rule, one test each (libNetwork.md S2): required-field
/// rejection, schemaTooNew, location drop-on-invalid, member truncation,
/// unknown-key tolerance, and stable byte output.
void main() {
  const fp = 'adb28b53d57009ce04d4e0b28563ebcd395375c0d719fd53986908233687f664';
  const fp2 =
      '22c2231357479c9a7b9d2d98ffc544ef97fce94c974a3a6835cceb4352139f1e';
  const site = 'https://kadugodi-library.github.io/pitak/';

  Map<String, Object?> validJson() => {
    'schemaVersion': 1,
    'fingerprint': fp,
    'name': 'Kadugodi Community Library',
    'siteUrl': site,
    'updatedAt': 1760000000000,
  };

  List<int> bytesOf(Map<String, Object?> json) => utf8.encode(jsonEncode(json));

  LibraryDescriptor decodeOk(Map<String, Object?> json) {
    final result = LibraryDescriptorCodec.decode(bytesOf(json));
    expect(result.isRight(), isTrue, reason: 'expected a valid descriptor');
    return result.toNullable()!;
  }

  void expectRefusal(Map<String, Object?> json, DescriptorRefusal expected) {
    final result = LibraryDescriptorCodec.decode(bytesOf(json));
    expect(result.isLeft(), isTrue, reason: 'expected refusal $expected');
    expect(result.swap().toNullable(), expected);
  }

  group('required fields', () {
    test('a minimal valid descriptor decodes', () {
      final d = decodeOk(validJson());
      expect(d.fingerprint, fp);
      expect(d.name, 'Kadugodi Community Library');
      expect(d.siteUrl, site);
      expect(d.updatedAt, 1760000000000);
      expect(d.location, isNull);
      expect(d.precision, isNull);
      expect(d.members, isEmpty);
      expect(d.memberOf, isEmpty);
    });

    for (final missing in [
      'schemaVersion',
      'fingerprint',
      'name',
      'siteUrl',
      'updatedAt',
    ]) {
      test('a missing "$missing" rejects the WHOLE descriptor', () {
        final json = validJson()..remove(missing);
        expectRefusal(json, DescriptorRefusal.invalid);
      });
    }

    test('non-int schemaVersion is invalid', () {
      expectRefusal(
        validJson()..['schemaVersion'] = '1',
        DescriptorRefusal.invalid,
      );
      expectRefusal(
        validJson()..['schemaVersion'] = 1.0,
        DescriptorRefusal.invalid,
      );
    });

    test('schemaVersion < 1 is invalid; > 1 is schemaTooNew', () {
      expectRefusal(
        validJson()..['schemaVersion'] = 0,
        DescriptorRefusal.invalid,
      );
      expectRefusal(
        validJson()..['schemaVersion'] = -3,
        DescriptorRefusal.invalid,
      );
      expectRefusal(
        validJson()..['schemaVersion'] = 2,
        DescriptorRefusal.schemaTooNew,
      );
      expectRefusal(
        validJson()..['schemaVersion'] = 99,
        DescriptorRefusal.schemaTooNew,
      );
    });

    test('fingerprint must be exactly 64 lowercase hex', () {
      expectRefusal(
        validJson()..['fingerprint'] = fp.toUpperCase(),
        DescriptorRefusal.invalid,
      );
      expectRefusal(
        validJson()..['fingerprint'] = fp.substring(1),
        DescriptorRefusal.invalid,
      );
      expectRefusal(
        validJson()..['fingerprint'] = 42,
        DescriptorRefusal.invalid,
      );
    });

    test('name follows the NetworkName rules', () {
      expectRefusal(validJson()..['name'] = '   ', DescriptorRefusal.invalid);
      expectRefusal(
        validJson()..['name'] = 'a' * 81,
        DescriptorRefusal.invalid,
      );
      expectRefusal(
        validJson()..['name'] = 'evil\u202ename',
        DescriptorRefusal.invalid,
      );
      // Trimming is allowed: the stored name is the trimmed one.
      expect(
        decodeOk(validJson()..['name'] = '  X Library  ').name,
        'X Library',
      );
    });

    test('siteUrl must pass the BookmarkUrl allow-list', () {
      expectRefusal(
        validJson()..['siteUrl'] = 'http://x.github.io/p/',
        DescriptorRefusal.invalid,
      );
      expectRefusal(
        validJson()..['siteUrl'] = 'https://evil.example.com/',
        DescriptorRefusal.invalid,
      );
      expectRefusal(
        validJson()..['siteUrl'] = 'https://u:p@x.github.io/',
        DescriptorRefusal.invalid,
      );
      // pages.dev is allow-listed too.
      expect(
        decodeOk(validJson()..['siteUrl'] = 'https://lib.pages.dev/').siteUrl,
        'https://lib.pages.dev/',
      );
    });

    test('updatedAt must be an int >= 0', () {
      expectRefusal(validJson()..['updatedAt'] = -1, DescriptorRefusal.invalid);
      expectRefusal(
        validJson()..['updatedAt'] = 'now',
        DescriptorRefusal.invalid,
      );
      expect(decodeOk(validJson()..['updatedAt'] = 0).updatedAt, 0);
    });

    test('a non-object body is invalid', () {
      expect(
        LibraryDescriptorCodec.decode(utf8.encode('[1,2,3]')).toNullable(),
        isNull,
      );
      expect(
        LibraryDescriptorCodec.decode(
          utf8.encode('"hello"'),
        ).swap().toNullable(),
        DescriptorRefusal.invalid,
      );
    });

    test('bad UTF-8 and bad JSON are invalid, never a throw', () {
      expect(
        LibraryDescriptorCodec.decode(const [
          0xFF,
          0xFE,
          0x00,
        ]).swap().toNullable(),
        DescriptorRefusal.invalid,
      );
      expect(
        LibraryDescriptorCodec.decode(
          utf8.encode('{not json'),
        ).swap().toNullable(),
        DescriptorRefusal.invalid,
      );
    });
  });

  group('optional location', () {
    test('a valid location block is kept with its precision', () {
      final d = decodeOk(
        validJson()
          ..['location'] = {
            'lat': 12.99,
            'lng': 77.76,
            'precision': 'approximate',
          },
      );
      expect(d.location!.lat, 12.99);
      expect(d.location!.lng, 77.76);
      expect(d.precision, LocationPrecision.approximate);
    });

    test('integer coordinates are accepted', () {
      final d = decodeOk(
        validJson()
          ..['location'] = {'lat': 12, 'lng': 77, 'precision': 'exact'},
      );
      expect(d.location!.lat, 12.0);
      expect(d.precision, LocationPrecision.exact);
    });

    for (final bad in <Object?>[
      {'lat': 91, 'lng': 0, 'precision': 'exact'}, // lat out of range
      {'lat': 0, 'lng': 181, 'precision': 'exact'}, // lng out of range
      {'lat': 12.5, 'lng': 77.5}, // precision missing
      {'lat': 12.5, 'lng': 77.5, 'precision': 'precise'}, // unknown token
      {'lat': '12.5', 'lng': 77.5, 'precision': 'exact'}, // string lat
      'not-a-map',
      42,
      [1, 2],
    ]) {
      test('an invalid location ($bad) is DROPPED, descriptor survives', () {
        final d = decodeOk(validJson()..['location'] = bad);
        expect(d.location, isNull);
        expect(d.precision, isNull);
      });
    }
  });

  group('optional members', () {
    test('valid entries are kept, invalid entries dropped', () {
      final d = decodeOk(
        validJson()
          ..['members'] = [
            {
              'fingerprint': fp2,
              'siteUrl': 'https://b.github.io/x/',
              'name': 'B',
            },
            {'fingerprint': 'nope', 'siteUrl': 'https://c.github.io/x/'},
            {'fingerprint': fp2, 'siteUrl': 'https://evil.example/'},
            {
              'fingerprint': fp2,
              'siteUrl': 'https://d.github.io/x/',
              'name': 'bad\u202ename',
            },
            'not-a-map',
            {'fingerprint': fp2, 'siteUrl': 'https://e.github.io/x/'},
          ],
      );
      expect(d.members, hasLength(2));
      expect(d.members[0].siteUrl, 'https://b.github.io/x/');
      expect(d.members[0].name, 'B');
      expect(d.members[1].siteUrl, 'https://e.github.io/x/');
      expect(d.members[1].name, isNull); // optional name stays absent
    });

    test('more than 200 entries truncates to the first 200', () {
      final d = decodeOk(
        validJson()
          ..['members'] = [
            for (var i = 0; i < 201; i++)
              {'fingerprint': fp2, 'siteUrl': 'https://m$i.github.io/x/'},
          ],
      );
      expect(d.members, hasLength(LibraryDescriptorCodec.maxMembers));
      expect(d.members.last.siteUrl, 'https://m199.github.io/x/');
    });

    test('a non-list members value decodes as none', () {
      expect(decodeOk(validJson()..['members'] = 'oops').members, isEmpty);
    });
  });

  group('optional memberOf', () {
    test('invalid URLs are dropped, valid ones normalized', () {
      final d = decodeOk(
        validJson()
          ..['memberOf'] = [
            'https://hub.github.io/pitak/',
            'https://evil.example/',
            42,
            'https://hub2.pages.dev/',
          ],
      );
      expect(d.memberOf, [
        'https://hub.github.io/pitak/',
        'https://hub2.pages.dev/',
      ]);
    });

    test('more than 20 entries truncates to the first 20', () {
      final d = decodeOk(
        validJson()
          ..['memberOf'] = [
            for (var i = 0; i < 21; i++) 'https://h$i.github.io/',
          ],
      );
      expect(d.memberOf, hasLength(LibraryDescriptorCodec.maxMemberOf));
    });
  });

  test('unknown keys are ignored (additive evolution without a bump)', () {
    final d = decodeOk(
      validJson()
        ..['futureField'] = {'anything': true}
        ..['anotherOne'] = [1, 2, 3],
    );
    expect(d.name, 'Kadugodi Community Library');
  });

  group('bounds (defence in depth)', () {
    test('a body over 64 KiB is refused as tooLarge without parsing', () {
      final big = bytesOf(validJson()..['name'] = 'x' * (64 * 1024 + 100));
      expect(big.length, greaterThan(LibraryDescriptorCodec.maxBodyBytes));
      expect(
        LibraryDescriptorCodec.decode(big).swap().toNullable(),
        DescriptorRefusal.tooLarge,
      );
    });

    test(
      'security: a deep-nesting JSON bomb is refused, not a stack crash',
      () {
        // 40 000 open brackets fit inside the byte cap; the recursive parser
        // would overflow the stack without the depth guard.
        final bomb = utf8.encode('[' * 40000);
        expect(
          LibraryDescriptorCodec.decode(bomb).swap().toNullable(),
          DescriptorRefusal.invalid,
        );
      },
    );

    test('brackets INSIDE a string never count toward the depth (M-low)', () {
      // The old naive scan counted these and would refuse a real descriptor
      // whose name happens to carry brackets.
      final bracketed = bytesOf(
        validJson()..['name'] = 'Books {{{{{{{{{{{{{{{{{{{{{{{{{{{{{{{[[',
      );
      final decoded = LibraryDescriptorCodec.decode(bracketed);
      expect(decoded.isRight(), isTrue);
      expect(decoded.toNullable()!.name, contains('{{{'));
    });

    test('escaped quotes inside strings do not confuse the depth scan', () {
      // A backslash-escaped quote must not flip the in-string state.
      final tricky = bytesOf(validJson()..['name'] = r'A "[{\" B');
      expect(LibraryDescriptorCodec.decode(tricky).isRight(), isTrue);
      // Depth still guards real structure even with strings present.
      final nested = bytesOf(
        validJson()
          ..['future'] = {
            'a': [
              {
                'b': [
                  {'c': 'd'},
                ],
              },
            ],
          },
      );
      expect(LibraryDescriptorCodec.decode(nested).isRight(), isTrue);
    });
  });

  group('encode (stable wire shape)', () {
    LibraryDescriptor descriptor({
      GeoPoint? location,
      LocationPrecision? precision,
      List<MemberEntry> members = const [],
      List<String> memberOf = const [],
    }) => LibraryDescriptor(
      fingerprint: fp,
      name: 'Kadugodi Community Library',
      siteUrl: site,
      updatedAt: 1760000000000,
      location: location,
      precision: precision,
      members: members,
      memberOf: memberOf,
    );

    test('keys come out in the exact §3.1 order', () {
      final json = utf8.decode(
        LibraryDescriptorCodec.encode(
          descriptor(
            location: GeoPoint.tryCreate(12.99, 77.76),
            precision: LocationPrecision.approximate,
            members: const [
              MemberEntry(
                fingerprint: fp2,
                siteUrl: 'https://b.github.io/x/',
                name: 'B',
              ),
            ],
            memberOf: const ['https://hub.github.io/pitak/'],
          ),
        ),
      );
      expect(json, startsWith('{"schemaVersion":1,"fingerprint":'));
      expect(json, contains('"updatedAt":1760000000000,'));
      expect(
        json,
        contains(
          '"location":{"lat":12.99,"lng":77.76,"precision":"approximate"}',
        ),
      );
      expect(
        json,
        contains(
          '"members":[{"fingerprint":"$fp2","siteUrl":"https://b.github.io/x/","name":"B"}]',
        ),
      );
      expect(json, endsWith('"memberOf":["https://hub.github.io/pitak/"]}'));
    });

    test('members are sorted by siteUrl and memberOf sorted', () {
      final bytes = LibraryDescriptorCodec.encode(
        descriptor(
          members: const [
            MemberEntry(fingerprint: fp2, siteUrl: 'https://z.github.io/'),
            MemberEntry(fingerprint: fp2, siteUrl: 'https://a.github.io/'),
          ],
          memberOf: const [
            'https://z-hub.github.io/',
            'https://a-hub.github.io/',
          ],
        ),
      );
      final decoded = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final memberUrls = (decoded['members'] as List)
          .map((m) => (m as Map<String, dynamic>)['siteUrl'])
          .toList();
      expect(memberUrls, ['https://a.github.io/', 'https://z.github.io/']);
      expect(decoded['memberOf'], [
        'https://a-hub.github.io/',
        'https://z-hub.github.io/',
      ]);
    });

    test('equal input produces equal BYTES regardless of input order', () {
      final a = LibraryDescriptorCodec.encode(
        descriptor(
          members: const [
            MemberEntry(fingerprint: fp2, siteUrl: 'https://a.github.io/'),
            MemberEntry(fingerprint: fp2, siteUrl: 'https://b.github.io/'),
          ],
        ),
      );
      final b = LibraryDescriptorCodec.encode(
        descriptor(
          members: const [
            MemberEntry(fingerprint: fp2, siteUrl: 'https://b.github.io/'),
            MemberEntry(fingerprint: fp2, siteUrl: 'https://a.github.io/'),
          ],
        ),
      );
      expect(a, b, reason: 'stable blob sha ⇒ incremental publish skips it');
    });

    test(
      'security: a location WITHOUT a declared precision is never written',
      () {
        // Privacy fail-closed: coordinates with no precision label could be
        // read as exact, so the whole block is dropped instead.
        final json = utf8.decode(
          LibraryDescriptorCodec.encode(
            descriptor(location: GeoPoint.tryCreate(12.9876, 77.5946)),
          ),
        );
        expect(json, isNot(contains('location')));
        expect(json, isNot(contains('12.9876')));
      },
    );

    test('a member without a name omits the key entirely', () {
      final json = utf8.decode(
        LibraryDescriptorCodec.encode(
          descriptor(
            members: const [
              MemberEntry(fingerprint: fp2, siteUrl: 'https://a.github.io/'),
            ],
          ),
        ),
      );
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final member =
          (decoded['members'] as List).single! as Map<String, dynamic>;
      expect(member.containsKey('name'), isFalse);
      expect(member['siteUrl'], 'https://a.github.io/');
      // The ROOT name is of course still written.
      expect(decoded['name'], 'Kadugodi Community Library');
    });

    test('decode(encode(d)) round-trips', () {
      final original = descriptor(
        location: GeoPoint.tryCreate(12.99, 77.76),
        precision: LocationPrecision.approximate,
        members: const [
          MemberEntry(
            fingerprint: fp2,
            siteUrl: 'https://b.github.io/x/',
            name: 'B Library',
          ),
        ],
        memberOf: const ['https://hub.github.io/pitak/'],
      );
      final decoded = decodeOk(
        jsonDecode(utf8.decode(LibraryDescriptorCodec.encode(original)))
            as Map<String, dynamic>,
      );
      expect(decoded.fingerprint, original.fingerprint);
      expect(decoded.name, original.name);
      expect(decoded.siteUrl, original.siteUrl);
      expect(decoded.updatedAt, original.updatedAt);
      expect(decoded.location!.sameAs(original.location!), isTrue);
      expect(decoded.precision, original.precision);
      expect(decoded.members.single.siteUrl, 'https://b.github.io/x/');
      expect(decoded.members.single.name, 'B Library');
      expect(decoded.memberOf, original.memberOf);
    });
  });
}
