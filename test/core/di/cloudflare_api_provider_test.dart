import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/di/providers.dart';

/// M1 (Cloudflare fix plan): the API facade must outlive the widget that
/// happened to be listening. With auto-dispose, switching away from the
/// Connection tab called `IOClient.close(force: true)` and cut in-flight
/// requests, so a publish could fail simply because the user changed tabs.
void main() {
  test('cloudflareApiProvider survives losing its last listener', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final subscription = container.listen(
      cloudflareApiProvider,
      (_, _) {},
      fireImmediately: true,
    );
    final first = container.read(cloudflareApiProvider);
    subscription.close();

    // No listeners remain. A keepAlive provider must return the SAME facade;
    // an auto-dispose one would have closed it and built a new instance.
    final second = container.read(cloudflareApiProvider);
    expect(identical(first, second), isTrue);
  });

  test('a different container gets its own facade', () {
    final a = ProviderContainer();
    final b = ProviderContainer();
    addTearDown(a.dispose);
    addTearDown(b.dispose);

    expect(
      identical(a.read(cloudflareApiProvider), b.read(cloudflareApiProvider)),
      isFalse,
    );
  });
}
