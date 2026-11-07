import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:path/path.dart' as p;
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/domain/events_watch/events_watch_ports.dart';
import 'package:pitaka/features/network/domain/events_watch/events_watch_settings.dart';
import 'package:pitaka/features/network/domain/events_watch/events_watch_state.dart';
import 'package:pitaka/features/network/domain/events_watch/pending_change.dart';
import 'package:pitaka/features/network/domain/events_watch/site_baseline.dart';
import 'package:pitaka/features/network/domain/events_watch/site_watch_status.dart';
import 'package:pitaka/features/network/domain/events_watch/watch_settings_token.dart';
import 'package:pitaka/features/network/domain/events_watch/watched_library.dart';
import 'package:pitaka/features/network/infrastructure/events_watch/bounded_json_document_file.dart';
import 'package:pitaka/features/network/infrastructure/events_watch/events_watch_json_codec.dart';
import 'package:pitaka/features/network/infrastructure/events_watch/file_events_watch_stores.dart';

/// PLAN.md §8 "Stores/ownership": bounded round-trip, hostile decode,
/// old-or-new reads during rename, unique temps and cleanup.
void main() {
  late Directory docs;
  const inc = '0f6c1d2e-3b4a-4c5d-8e9f-0a1b2c3d4e5f';
  const token = WatchSettingsToken(incarnation: inc, epoch: 3);
  const identity = WatchedLibraryIdentity(
    rowId: 7,
    createdAt: 1700000000000,
    siteUrl: 'https://a.github.io/lib/',
  );
  final digest = 'c' * 64;

  setUp(() {
    docs = Directory.systemTemp.createTempSync('events_watch_store_test');
  });
  tearDown(() {
    if (docs.existsSync()) docs.deleteSync(recursive: true);
  });

  String settingsPath() =>
      p.join(docs.path, 'events_watch', 'events_watch_settings.json');
  String statePath() =>
      p.join(docs.path, 'events_watch', 'events_watch_state.json');

  EventsWatchState fullState() => EventsWatchState(
    observedToken: token,
    generation: 'gen-000003',
    sites: [
      SiteWatchStatus(
        identity: identity,
        notificationId: 12345,
        lastAttemptAt: 10,
        lastSuccessfulCheckAt: 9,
        lastOutcome: SiteCheckOutcome.ok,
        baseline: SiteBaseline(
          posters: [BaselinePoster(imageRef: 'posters/a.jpg', digest: digest)],
          token: token,
          validator: '"W/etag-1"',
        ),
      ),
    ],
    pending: [
      PendingChange(
        kind: PendingChangeKind.modified,
        identity: identity,
        imageRef: 'posters/a.jpg',
        safeCaption: 'New caption',
        digest: digest,
        token: token,
      ),
    ],
    revocationToken: const WatchSettingsToken(incarnation: inc, epoch: 2),
    recoveryNotice: RecoveryNotice.stateReset,
    lastRun: const LastRunOutcome(
      finishedAt: 11,
      checked: 1,
      withheld: 0,
      failed: 0,
      capacityExceeded: false,
    ),
  );

  group('settings store', () {
    test('missing → WatchDocumentMissing, and no file is created', () async {
      final store = FileEventsWatchSettingsStore(docsDir: docs.path);
      final read = (await store.read()).toNullable()!;
      expect(read, isA<WatchDocumentMissing<EventsWatchSettings>>());
      expect(File(settingsPath()).existsSync(), isFalse);
    });

    test('round-trips every field', () async {
      final store = FileEventsWatchSettingsStore(docsDir: docs.path);
      final settings = EventsWatchSettings.initial(
        inc,
      ).withEnabled(enabled: true).withExplanationAcknowledged();

      expect((await store.write(settings)).isRight(), isTrue);

      final read = (await store.read()).toNullable()!;
      final back = (read as WatchDocumentPresent<EventsWatchSettings>).value;
      expect(back.sameAs(settings), isTrue);
    });

    test('newer schema → WatchDocumentNewerSchema (never corrupt)', () async {
      File(settingsPath())
        ..createSync(recursive: true)
        ..writeAsStringSync(jsonEncode({'schema': 2, 'enabled': true}));
      final read = (await FileEventsWatchSettingsStore(
        docsDir: docs.path,
      ).read()).toNullable()!;
      expect(read, isA<WatchDocumentNewerSchema<EventsWatchSettings>>());
    });

    test('hostile contents → WatchDocumentCorrupt', () async {
      final store = FileEventsWatchSettingsStore(docsDir: docs.path);
      final cases = <String, String>{
        'not json': '{{{',
        'array': '[]',
        'no schema': jsonEncode({'enabled': true}),
        'string enabled': jsonEncode({
          'schema': 1,
          'enabled': 'true',
          'token': {'incarnation': inc, 'epoch': 0},
          'acknowledgedExplanationVersion': 0,
        }),
        'bad token': jsonEncode({
          'schema': 1,
          'enabled': true,
          'token': {'incarnation': '../x', 'epoch': 0},
          'acknowledgedExplanationVersion': 0,
        }),
        'oversized': '{"schema":1,"pad":"${'x' * (16 * 1024)}"}',
        'deep': '${'[' * 9}${']' * 9}',
      };
      for (final entry in cases.entries) {
        File(settingsPath())
          ..createSync(recursive: true)
          ..writeAsStringSync(entry.value);
        final read = (await store.read()).toNullable()!;
        expect(
          read,
          isA<WatchDocumentCorrupt<EventsWatchSettings>>(),
          reason: entry.key,
        );
      }
    });
  });

  group('state store', () {
    test(
      'round-trips every field including nested baseline + pending',
      () async {
        final store = FileEventsWatchStateStore(docsDir: docs.path);
        final state = fullState();

        expect((await store.write(state)).isRight(), isTrue);

        final back =
            ((await store.read()).toNullable()!
                    as WatchDocumentPresent<EventsWatchState>)
                .value;
        expect(back.observedToken!.sameAs(token), isTrue);
        expect(back.generation, 'gen-000003');
        expect(back.sites.single.notificationId, 12345);
        expect(back.sites.single.lastOutcome, SiteCheckOutcome.ok);
        expect(
          back.sites.single.baseline!.sameAs(state.sites.single.baseline!),
          isTrue,
        );
        expect(back.pending.single.sameAs(state.pending.single), isTrue);
        expect(back.revocationToken!.epoch, 2);
        expect(back.recoveryNotice, RecoveryNotice.stateReset);
        expect(back.lastRun!.checked, 1);
      },
    );

    test('empty state round-trips with nulls', () async {
      final store = FileEventsWatchStateStore(docsDir: docs.path);
      await store.write(EventsWatchState.empty());
      final back =
          ((await store.read()).toNullable()!
                  as WatchDocumentPresent<EventsWatchState>)
              .value;
      expect(back.observedToken, isNull);
      expect(back.generation, isNull);
      expect(back.sites, isEmpty);
      expect(back.pending, isEmpty);
      expect(back.revocationToken, isNull);
      expect(back.recoveryNotice, isNull);
      expect(back.lastRun, isNull);
    });

    test('the encoded document never contains a caption-free secret and '
        'no library name', () async {
      final json = jsonEncode(EventsWatchJsonCodec.encodeState(fullState()));
      expect(json, isNot(contains('name')));
      expect(json, isNot(contains('publicName')));
    });

    test('hostile state documents → corrupt', () async {
      final store = FileEventsWatchStateStore(docsDir: docs.path);
      Map<String, Object?> good() =>
          EventsWatchJsonCodec.encodeState(fullState());
      final cases = <String, Map<String, Object?> Function()>{
        'bad generation': () => good()..['generation'] = '../gen-000001',
        'bad site url': () {
          final m = good();
          ((m['sites']! as List).first as Map)['siteUrl'] = 'http://evil/';
          return m;
        },
        'duplicate site': () {
          final m = good();
          final sites = m['sites']! as List;
          m['sites'] = <Object?>[...sites, sites.first];
          return m;
        },
        'duplicate pending key': () {
          final m = good();
          final pending = m['pending']! as List;
          m['pending'] = <Object?>[...pending, pending.first];
          return m;
        },
        'unsafe caption': () {
          final m = good();
          ((m['pending']! as List).first as Map)['safeCaption'] = 'x\u202Ey';
          return m;
        },
        'summary id used as site id': () {
          final m = good();
          ((m['sites']! as List).first as Map)['notificationId'] = 0;
          return m;
        },
        'three baseline posters': () {
          final m = good();
          final b = ((m['sites']! as List).first as Map)['baseline'] as Map;
          b['posters'] = <Object?>[
            ...b['posters']! as List,
            {'imageRef': 'posters/b.jpg', 'digest': digest},
            {'imageRef': 'posters/c.jpg', 'digest': digest},
          ];
          return m;
        },
        'unknown recovery notice': () => good()..['recoveryNotice'] = 'lol',
        'invalid revocation token': () =>
            good()..['revocationToken'] = {'incarnation': 5, 'epoch': 0},
        'validator with control char': () {
          final m = good();
          final b = ((m['sites']! as List).first as Map)['baseline'] as Map;
          b['validator'] = 'etag\n';
          return m;
        },
      };
      for (final entry in cases.entries) {
        File(statePath())
          ..createSync(recursive: true)
          ..writeAsStringSync(jsonEncode(entry.value()));
        final read = (await store.read()).toNullable()!;
        expect(
          read,
          isA<WatchDocumentCorrupt<EventsWatchState>>(),
          reason: entry.key,
        );
      }
    });

    test('too many sites / pending in the document → corrupt', () async {
      final store = FileEventsWatchStateStore(docsDir: docs.path);
      final m = EventsWatchJsonCodec.encodeState(EventsWatchState.empty());
      m['sites'] = [
        for (var i = 0; i <= 100; i++)
          {
            'rowId': i + 1,
            'createdAt': 1,
            'siteUrl': 'https://l${i.toString().padLeft(3, '0')}.github.io/x/',
            'notificationId': null,
            'lastAttemptAt': null,
            'lastSuccessfulCheckAt': null,
            'lastOutcome': 'never',
            'baseline': null,
          },
      ];
      File(statePath())
        ..createSync(recursive: true)
        ..writeAsStringSync(jsonEncode(m));
      expect(
        (await store.read()).toNullable(),
        isA<WatchDocumentCorrupt<EventsWatchState>>(),
      );
    });

    test('a write that exceeds the cap is refused with CapacityFailure and '
        'the live file is untouched', () async {
      final store = FileEventsWatchStateStore(docsDir: docs.path);
      await store.write(EventsWatchState.empty());
      final before = File(statePath()).readAsBytesSync();
      // 100 sites × 2 pending with max captions is still < 512 KiB, so
      // force the cap through the raw document instead.
      final huge = EventsWatchJsonCodec.encodeState(EventsWatchState.empty())
        ..['pad'] = 'x' * (512 * 1024);
      // Use the underlying file directly via a second store on the same path
      // is not possible; emulate via a temp-document write of the big map.
      final result = await _writeRaw(statePath(), huge);
      expect(result.getLeft().toNullable(), isA<CapacityFailure>());
      expect(File(statePath()).readAsBytesSync(), before);
    });

    test('write is atomic: a reader during the write sees old or new, and '
        'no temp files remain', () async {
      final store = FileEventsWatchStateStore(docsDir: docs.path);
      await store.write(EventsWatchState.empty());
      final oldBytes = File(statePath()).readAsBytesSync();
      final newState = fullState();

      final writes = <Future<void>>[];
      final observed = <String>{};
      for (var i = 0; i < 20; i++) {
        writes.add(store.write(i.isEven ? newState : EventsWatchState.empty()));
        observed.add(File(statePath()).readAsStringSync());
      }
      await Future.wait(writes);

      final newBytes = utf8.encode(
        jsonEncode(EventsWatchJsonCodec.encodeState(newState)),
      );
      for (final seen in observed) {
        expect(
          seen == utf8.decode(oldBytes) || seen == utf8.decode(newBytes),
          isTrue,
          reason: 'a reader saw a torn document',
        );
      }
      final leftovers = Directory(
        p.dirname(statePath()),
      ).listSync().where((e) => e.path.endsWith('.tmp'));
      expect(leftovers, isEmpty);
    });
  });
}

/// Writes an arbitrary map through the same bounded file the state store
/// uses, to exercise the byte cap without constructing 512 KiB of valid
/// domain objects.
Future<Either<Failure, Unit>> _writeRaw(String path, Object? json) =>
    BoundedJsonDocumentFile(
      path: path,
      maxBytes: EventsWatchDocumentLimits.maxStateBytes,
      maxDepth: EventsWatchDocumentLimits.maxJsonDepth,
    ).write(json);
