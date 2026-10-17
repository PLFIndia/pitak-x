import 'dart:math';

/// Tiny seeded generator for property-style tests (architecture.md B3, D5).
///
/// Why hand-rolled: the Dart property-testing packages are small and
/// low-maintenance, and the repo rule is "no new package for a problem an
/// existing approach solves". ~40 lines covers the need: 200 cases per
/// property, a FIXED default seed, and the seed printed in every failure
/// message so any red case reproduces exactly.
///
/// Usage — ONE generator per case, so the seed in a failure message
/// reproduces that single case without replaying the ones before it:
/// ```dart
/// for (var i = 0; i < Fuzz.cases; i++) {
///   final fuzz = Fuzz.forCase(i);
///   final input = fuzz.randomUtf8();
///   expect(..., reason: 'case $i (seed ${fuzz.seed})');
/// }
/// ```
/// To replay a red case: `Fuzz(seed: <printed>)` produces the exact same
/// sequence of draws as that case did.
final class Fuzz {
  /// Creates a generator from an explicit [seed] (defaults to [defaultSeed]).
  /// Use [Fuzz.forCase] inside property loops; use this constructor to
  /// replay a printed seed.
  Fuzz({int seed = defaultSeed}) : seed = seed, _random = Random(seed);

  /// The generator for case [index] of a property: a distinct, deterministic
  /// seed per case, derived from [defaultSeed] so CI is reproducible.
  Fuzz.forCase(int index) : this(seed: defaultSeed + index);

  /// Base seed every property derives its per-case seeds from.
  static const int defaultSeed = 0x917A4;

  /// Cases per property (architecture.md B3).
  static const int cases = 200;

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
