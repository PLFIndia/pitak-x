import 'dart:math';

/// Tiny seeded generator for property-style tests (architecture.md B3, D5).
///
/// Why hand-rolled: the Dart property-testing packages are small and
/// low-maintenance, and the repo rule is "no new package for a problem an
/// existing approach solves". ~40 lines covers the need: 200 cases per
/// property, a FIXED default seed, and the seed printed in every failure
/// message so any red case reproduces exactly.
///
/// Usage:
/// ```dart
/// final fuzz = Fuzz(); // default seed
/// for (var i = 0; i < 200; i++) {
///   final input = fuzz.randomUtf8();
///   // ... assert the property ...
/// }
/// ```
/// On failure, the test message includes `fuzz.seed` — re-run one case with
/// `Fuzz(seed: <printed>)`.
final class Fuzz {
  /// Creates a generator. [seed] defaults to a fixed value so CI is
  /// deterministic; pass a printed seed to reproduce a failure.
  Fuzz({int seed = defaultSeed}) : seed = seed, _random = Random(seed);

  /// The seed every property uses unless reproducing a failure.
  static const int defaultSeed = 0x917A4;

  /// The seed driving this instance (print it in failure messages).
  final int seed;

  final Random _random;

  /// Random bytes, length 0..[maxLength].
  List<int> randomBytes({int maxLength = 256}) {
    final length = _random.nextInt(maxLength + 1);
    return [for (var i = 0; i < length; i++) _random.nextInt(256)];
  }

  /// Random valid UTF-8 text (may be empty). Includes multibyte sequences
  /// (BMP code points up to U+FFFF, excluding surrogates).
  String randomUtf8({int maxLength = 128}) {
    final length = _random.nextInt(maxLength + 1);
    final buffer = StringBuffer();
    for (var i = 0; i < length; i++) {
      // 0xD800..0xDFFF are unpaired surrogates — invalid on their own.
      var code = _random.nextInt(0xFFFF);
      if (code >= 0xD800 && code <= 0xDFFF) code = 0x41; // 'A'
      buffer.writeCharCode(code);
    }
    return buffer.toString();
  }

  /// Mutates [base] with [flips] random bit flips — simulates a corrupted
  /// fixture (truncation is a separate case; see [truncate]).
  List<int> bitFlip(List<int> base, {int flips = 4}) {
    if (base.isEmpty) return List.of(base);
    final copy = List<int>.of(base);
    for (var i = 0; i < flips; i++) {
      final index = _random.nextInt(copy.length);
      copy[index] = copy[index] ^ (1 << _random.nextInt(8));
    }
    return copy;
  }

  /// [base] truncated at a random point.
  List<int> truncate(List<int> base) =>
      base.sublist(0, base.isEmpty ? 0 : _random.nextInt(base.length));

  /// A random element of [items].
  T pick<T>(List<T> items) => items[_random.nextInt(items.length)];

  /// A random int in `[0, upper)`.
  int nextInt(int upper) => _random.nextInt(upper);
}
