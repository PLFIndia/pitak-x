// The "catalogue data changed" signal (review findings P3-M4, P4-M2 and
// P4-m13; decision D151): a counter that the write paths bump and that
// everything showing catalogue data watches. The Library list is one of its
// listeners, no longer the signal itself.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/library/application/catalogue_changes.dart';

void main() {
  test('starts at zero: nothing has changed in this app run yet', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(catalogueChangesProvider), 0);
  });

  test('every changed() is heard once, as the next number', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final heard = <int>[];
    final subscription = container.listen<int>(
      catalogueChangesProvider,
      (_, next) => heard.add(next),
    );
    addTearDown(subscription.close);

    container.read(catalogueChangesProvider.notifier).changed();
    container.read(catalogueChangesProvider.notifier).changed();
    container.read(catalogueChangesProvider.notifier).changed();

    expect(heard, [1, 2, 3]);
    expect(container.read(catalogueChangesProvider), 3);
  });

  test('a listener that comes later still sees what was said before it: '
      'the count is kept while nobody listens', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(catalogueChangesProvider.notifier).changed();
    // One turn of the event loop: an auto-disposed provider with no
    // listener is thrown away here, and the next read would say 0 again.
    await Future<void>.delayed(Duration.zero);

    expect(container.read(catalogueChangesProvider), 1);
  });
}
