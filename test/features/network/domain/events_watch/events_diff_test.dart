import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/network/domain/entities/published_events.dart';
import 'package:pitaka/features/network/domain/events_watch/events_diff.dart';
import 'package:pitaka/features/network/domain/events_watch/pending_change.dart';
import 'package:pitaka/features/network/domain/events_watch/poster_digest.dart';
import 'package:pitaka/features/network/domain/events_watch/site_baseline.dart';
import 'package:pitaka/features/network/domain/events_watch/watch_settings_token.dart';
import 'package:pitaka/features/network/domain/events_watch/watched_library.dart';

/// PLAN.md §3 `200` row + §8 "Digest/diff".
void main() {
  const tokenA = WatchSettingsToken(incarnation: 'aaaa', epoch: 1);
  const tokenA2 = WatchSettingsToken(incarnation: 'aaaa', epoch: 2);
  const tokenB = WatchSettingsToken(incarnation: 'bbbb', epoch: 1);

  PublishedEvents events(
    List<(String, String)> posters, {
    bool partial = false,
    int schema = PublishedEvents.schemaVersion,
  }) => PublishedEvents(
    declaredSchemaVersion: schema,
    posters: [
      for (final (ref, caption) in posters)
        PublishedEventPoster(imageRef: ref, description: caption),
    ],
    hasPartialRead: partial,
  );

  SiteBaseline baselineOf(
    List<(String, String)> posters, {
    WatchSettingsToken token = tokenA,
    String? validator,
  }) => SiteBaseline(
    posters: [
      for (final (ref, caption) in posters)
        BaselinePoster(
          imageRef: ref,
          digest: PosterDigest.compute(imageRef: ref, caption: caption),
        ),
    ],
    token: token,
    validator: validator,
  );

  EventsDiffed diffed(EventsDiffResult r) => r as EventsDiffed;

  group('baseline establishment (no alerts)', () {
    test('null baseline → new baseline, zero changes (decision 5)', () {
      final r = diffPublishedEvents(
        baseline: null,
        observed: events([('posters/a.jpg', 'A')]),
        token: tokenA,
        validator: 'etag-1',
      );
      final d = diffed(r);
      expect(d.changes, isEmpty);
      expect(d.baseline.posters.single.imageRef, 'posters/a.jpg');
      expect(d.baseline.validator, 'etag-1');
      expect(d.baseline.token.sameAs(tokenA), isTrue);
    });

    test('null baseline is distinct from EMPTY: a poster after an empty '
        'baseline IS an addition', () {
      final afterNull = diffed(
        diffPublishedEvents(
          baseline: null,
          observed: events([('posters/a.jpg', 'A')]),
          token: tokenA,
          validator: null,
        ),
      );
      final afterEmpty = diffed(
        diffPublishedEvents(
          baseline: baselineOf(const []),
          observed: events([('posters/a.jpg', 'A')]),
          token: tokenA,
          validator: null,
        ),
      );
      expect(afterNull.changes, isEmpty);
      expect(afterEmpty.changes.single.kind, PendingChangeKind.added);
    });

    test('a complete EMPTY payload is authoritative (empty baseline)', () {
      final d = diffed(
        diffPublishedEvents(
          baseline: null,
          observed: events(const []),
          token: tokenA,
          validator: null,
        ),
      );
      expect(d.baseline.posters, isEmpty);
    });

    test('a baseline from another epoch or incarnation re-baselines quietly '
        '(decision 6)', () {
      for (final stale in [tokenA2, tokenB]) {
        final d = diffed(
          diffPublishedEvents(
            baseline: baselineOf([('posters/a.jpg', 'A')], token: stale),
            observed: events([('posters/a.jpg', 'A'), ('posters/b.jpg', 'B')]),
            token: tokenA,
            validator: null,
          ),
        );
        expect(d.changes, isEmpty, reason: '$stale');
        expect(d.baseline.token.sameAs(tokenA), isTrue);
        expect(d.baseline.posters.length, 2);
      }
    });
  });

  group('changes', () {
    test('new reference → added; changed caption → modified; '
        'disappearance → nothing', () {
      final d = diffed(
        diffPublishedEvents(
          baseline: baselineOf([
            ('posters/a.jpg', 'A'),
            ('posters/gone.jpg', 'G'),
          ]),
          observed: events([
            ('posters/a.jpg', 'A v2'),
            ('posters/new.jpg', 'N'),
          ]),
          token: tokenA,
          validator: null,
        ),
      );
      expect(d.changes.map((c) => (c.imageRef, c.kind)), [
        ('posters/a.jpg', PendingChangeKind.modified),
        ('posters/new.jpg', PendingChangeKind.added),
      ]);
      expect(d.currentRefs, {'posters/a.jpg', 'posters/new.jpg'});
      expect(d.baseline.posterAt('posters/gone.jpg'), isNull);
    });

    test(
      'identical content → no changes, baseline re-tagged with validator',
      () {
        final d = diffed(
          diffPublishedEvents(
            baseline: baselineOf([('posters/a.jpg', 'A')], validator: 'old'),
            observed: events([('posters/a.jpg', 'A')]),
            token: tokenA,
            validator: 'new',
          ),
        );
        expect(d.changes, isEmpty);
        expect(d.baseline.validator, 'new');
      },
    );

    test('reorder alone is not a change', () {
      final d = diffed(
        diffPublishedEvents(
          baseline: baselineOf([
            ('posters/a.jpg', 'A'),
            ('posters/b.jpg', 'B'),
          ]),
          observed: events([('posters/b.jpg', 'B'), ('posters/a.jpg', 'A')]),
          token: tokenA,
          validator: null,
        ),
      );
      expect(d.changes, isEmpty);
    });

    test('changed image bytes at an unchanged reference + caption are '
        'explicitly undetectable', () {
      // The diff only sees (imageRef, caption); same inputs → same digest.
      final d = diffed(
        diffPublishedEvents(
          baseline: baselineOf([('posters/a.jpg', 'A')]),
          observed: events([('posters/a.jpg', 'A')]),
          token: tokenA,
          validator: null,
        ),
      );
      expect(d.changes, isEmpty);
    });
  });

  group('withheld', () {
    test('partial read, newer schema, duplicate refs, >2 posters', () {
      final base = baselineOf([('posters/a.jpg', 'A')]);
      final cases = <String, PublishedEvents>{
        'partial': events([('posters/a.jpg', 'A v2')], partial: true),
        'newer schema': events([('posters/a.jpg', 'A v2')], schema: 99),
        'duplicate refs': events([
          ('posters/a.jpg', 'A'),
          ('posters/a.jpg', 'B'),
        ]),
        'three posters': events([
          ('posters/a.jpg', 'A'),
          ('posters/b.jpg', 'B'),
          ('posters/c.jpg', 'C'),
        ]),
      };
      for (final entry in cases.entries) {
        final r = diffPublishedEvents(
          baseline: base,
          observed: entry.value,
          token: tokenA,
          validator: null,
        );
        expect(r, isA<EventsDiffWithheld>(), reason: entry.key);
      }
    });
  });

  group('ObservedChange.toPending caption safety', () {
    const identity = WatchedLibraryIdentity(
      rowId: 1,
      createdAt: 1,
      siteUrl: 'https://a.github.io/lib/',
    );
    PendingChange pendingWith(String caption) => ObservedChange(
      kind: PendingChangeKind.added,
      imageRef: 'posters/a.jpg',
      caption: caption,
      digest: 'a' * 64,
    ).toPending(identity: identity, token: tokenA);

    test('a plain caption is kept (trimmed)', () {
      expect(
        pendingWith('  Book sale Sunday  ').safeCaption,
        'Book sale Sunday',
      );
    });

    test(
      'empty, control, bidi-override and over-long captions become null',
      () {
        expect(pendingWith('').safeCaption, isNull);
        expect(pendingWith('   ').safeCaption, isNull);
        expect(pendingWith('line\nbreak').safeCaption, isNull);
        expect(pendingWith('evil\u202Etext').safeCaption, isNull);
        expect(pendingWith('x' * 281).safeCaption, isNull);
      },
    );
  });
}
