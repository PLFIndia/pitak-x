import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/network/domain/events_watch/poster_digest.dart';

/// PLAN.md §8 "Digest/diff": the digest must be deterministic and immune to
/// the classic concatenation ambiguity.
void main() {
  test('is deterministic and 64 lowercase hex chars', () {
    final a = PosterDigest.compute(imageRef: 'posters/x.jpg', caption: 'hi');
    final b = PosterDigest.compute(imageRef: 'posters/x.jpg', caption: 'hi');
    expect(a, b);
    expect(PosterDigest.isValid(a), isTrue);
  });

  test('ambiguous concatenations do NOT collide (length-prefixed)', () {
    final one = PosterDigest.compute(imageRef: 'ab', caption: 'c');
    final two = PosterDigest.compute(imageRef: 'a', caption: 'bc');
    final three = PosterDigest.compute(imageRef: 'abc', caption: '');
    expect(one, isNot(two));
    expect(one, isNot(three));
    expect(two, isNot(three));
  });

  test('a changed caption at the same reference changes the digest', () {
    final a = PosterDigest.compute(imageRef: 'posters/x.jpg', caption: 'v1');
    final b = PosterDigest.compute(imageRef: 'posters/x.jpg', caption: 'v2');
    expect(a, isNot(b));
  });

  test('multi-byte captions are encoded by byte length, not char count', () {
    // Both are 2 UTF-16 code units; byte lengths differ (3 vs 2 + 1).
    final a = PosterDigest.compute(imageRef: '', caption: '\u20ac');
    final b = PosterDigest.compute(imageRef: '', caption: 'ab');
    expect(a, isNot(b));
  });

  test('isValid rejects non-hex, wrong length and non-strings', () {
    expect(PosterDigest.isValid('A' * 64), isFalse);
    expect(PosterDigest.isValid('a' * 63), isFalse);
    expect(PosterDigest.isValid(42), isFalse);
    expect(PosterDigest.isValid(null), isFalse);
  });
}
