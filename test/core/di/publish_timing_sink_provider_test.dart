import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/di/providers.dart';

/// Publish optimisation plan S0: the timing sink is instrumentation, and the
/// app must ship WITHOUT it.
///
/// Two properties are pinned here:
///  1. an ordinary build wires NO sink, so no publish times anything;
///  2. the sink only ever produces the `describe()` line (numbers only), which
///     is the string the timings test separately proves carries no path, URL,
///     key, token or title.
void main() {
  test('an ordinary build wires no publish-timings sink', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // The flag is a compile-time constant that defaults to false, so the whole
    // timing branch is removed from a normal build. This assertion fails loudly
    // if someone ever makes instrumentation unconditional.
    expect(container.read(publishTimingSinkProvider), isNull);
  });

  test('the sink can be supplied by an override (instrumented build)', () {
    final captured = <String>[];
    final container = ProviderContainer(
      overrides: [
        publishTimingSinkProvider.overrideWithValue(
          (timings) => captured.add(timings.describe()),
        ),
      ],
    );
    addTearDown(container.dispose);

    final sink = container.read(publishTimingSinkProvider);
    expect(sink, isNotNull);
    // Reading the provider must not have produced a line by itself.
    expect(captured, isEmpty);
  });
}
