import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/network/domain/value_objects/library_fingerprint.dart';

/// Tests for the published-identity fingerprint (libNetwork.md §3.3).
/// The known vectors were computed independently (shasum) so a change to the
/// domain prefix or the hash input encoding breaks these loudly — the prefix
/// is a cross-device wire contract.
void main() {
  group('of', () {
    test('known vector: 32-hex ID', () {
      expect(
        LibraryFingerprint.of('0123456789abcdef0123456789abcdef'),
        'adb28b53d57009ce04d4e0b28563ebcd395375c0d719fd53986908233687f664',
      );
    });

    test('known vector: minimum-length (16-hex) ID', () {
      expect(
        LibraryFingerprint.of('ffffffffffffffff'),
        '22c2231357479c9a7b9d2d98ffc544ef97fce94c974a3a6835cceb4352139f1e',
      );
    });

    test('never equals the ID itself (the raw ID stays private, D3)', () {
      // Security case: the published fingerprint must not leak the ID —
      // neither verbatim nor as a prefix/substring of the hash input.
      const id = '0123456789abcdef0123456789abcdef';
      final fp = LibraryFingerprint.of(id)!;
      expect(fp, isNot(contains(id)));
      expect(fp, isNot(id));
    });

    test('is deterministic and distinguishes different IDs', () {
      final a = LibraryFingerprint.of('aaaaaaaaaaaaaaaa');
      final b = LibraryFingerprint.of('aaaaaaaaaaaaaaaa');
      final c = LibraryFingerprint.of('bbbbbbbbbbbbbbbb');
      expect(a, b);
      expect(a, isNot(c));
    });

    test('trims surrounding whitespace like LibraryId does', () {
      expect(
        LibraryFingerprint.of('  aaaaaaaaaaaaaaaa  '),
        LibraryFingerprint.of('aaaaaaaaaaaaaaaa'),
      );
    });

    test('rejects invalid IDs BEFORE hashing (never hashes junk)', () {
      expect(LibraryFingerprint.of(''), isNull);
      expect(LibraryFingerprint.of('hello'), isNull); // too short, non-hex
      expect(LibraryFingerprint.of('AAAAAAAAAAAAAAAA'), isNull); // uppercase
      expect(LibraryFingerprint.of('zzzzzzzzzzzzzzzz'), isNull); // non-hex
      expect(LibraryFingerprint.of('a' * 65), isNull); // too long
      expect(LibraryFingerprint.of('aaaa aaaa aaaa aaaa'), isNull); // inner ws
    });
  });

  group('isValid', () {
    test('accepts exactly 64 lowercase hex', () {
      expect(LibraryFingerprint.isValid('a' * 64), isTrue);
      expect(LibraryFingerprint.isValid('0123456789abcdef' * 4), isTrue);
    });

    test('rejects wrong lengths', () {
      expect(LibraryFingerprint.isValid(''), isFalse);
      expect(LibraryFingerprint.isValid('a' * 63), isFalse);
      expect(LibraryFingerprint.isValid('a' * 65), isFalse);
    });

    test('rejects uppercase and non-hex characters', () {
      expect(LibraryFingerprint.isValid('A' * 64), isFalse);
      expect(LibraryFingerprint.isValid('${'a' * 63}g'), isFalse);
      expect(LibraryFingerprint.isValid('${'a' * 63} '), isFalse);
    });

    test('round-trips with of()', () {
      final fp = LibraryFingerprint.of('0123456789abcdef0123456789abcdef');
      expect(LibraryFingerprint.isValid(fp!), isTrue);
    });
  });

  test('domain prefix is the versioned wire contract', () {
    expect(LibraryFingerprint.domainPrefix, 'pitak-library-fingerprint-v1:');
    expect(LibraryFingerprint.length, 64);
  });
}
