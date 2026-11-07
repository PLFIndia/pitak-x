import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/network/application/events_watch/events_watch_tap_resolver.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/network/domain/events_watch/events_watch_payload.dart';

/// PLAN.md §7: a tap payload is re-validated against CURRENT saved rows.
void main() {
  const url = 'https://a.github.io/lib/';
  const saved = NetworkLibrary(siteUrl: url, id: 1, name: 'A');
  const discovered = NetworkLibrary(
    siteUrl: url,
    id: 2,
    source: NetworkSource.discovered,
  );

  test('a saved row is resolved', () {
    expect(
      resolveEventsWatchTap(EventsWatchPayload.library(url), [saved]),
      saved,
    );
  });

  test('a removed row → null (Network tab)', () {
    expect(resolveEventsWatchTap(EventsWatchPayload.library(url), []), isNull);
  });

  test('a discovered row with the same URL is NOT opened', () {
    expect(
      resolveEventsWatchTap(EventsWatchPayload.library(url), [discovered]),
      isNull,
    );
  });

  test('summary, null, garbage and non-canonical payloads → Network', () {
    for (final payload in [
      EventsWatchPayload.network,
      null,
      '',
      'site:',
      'site:HTTP://a.github.io/lib',
      'site:javascript:alert(1)',
      'site:https://a.github.io/lib/../x',
    ]) {
      expect(
        resolveEventsWatchTap(payload, [saved]),
        isNull,
        reason: '$payload',
      );
    }
  });
}
