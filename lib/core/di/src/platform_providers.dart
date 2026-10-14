/// Platform/OS-level DI bindings (AGENTS.md §4; SOLID-PLAN S3).
///
/// What lives here: document/generation paths, the wall clock (+ the periodic
/// tick), the bounded HTTP clients, OS screen-security and share-sheet seams,
/// and the passphrase-field visibility counter. These are the shared base of
/// the composition root — every feature module may import this file, and this
/// file imports no other DI module, so the dependency graph stays acyclic.
library;

import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:pitaka/core/network/lookup_http_client.dart';
import 'package:pitaka/core/network/timeout_http_client.dart';
import 'package:pitaka/core/platform/file_share.dart';
import 'package:pitaka/core/platform/screen_security.dart';
import 'package:pitaka/core/storage/data_generations.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'platform_providers.g.dart';

/// The app's document directory (where the DB + covers live). Resolved once.
@Riverpod(keepAlive: true)
Future<Directory> appDocsDir(AppDocsDirRef ref) =>
    getApplicationDocumentsDirectory();

/// Versioned data-generation store under `<appDocs>/data` (M02). The
/// catalogue DB, covers and vault live INSIDE the active generation so a
/// restore can build a complete new set and switch to it atomically.
@Riverpod(keepAlive: true)
Future<DataGenerations> dataGenerations(DataGenerationsRef ref) async {
  final dir = await ref.watch(appDocsDirProvider.future);
  return DataGenerations(docsDir: dir.path);
}

/// Shared HTTP client (#30, closes audit m1; N08). Every request through it
/// is bounded four ways and ABORTED (socket closed) when a bound trips, so a
/// dead socket (OEM app freezers, dropped mobile data), a trickling body or
/// an oversized reply fails closed instead of hanging or filling memory:
///  - 60 s to connect, 60 s between body chunks (per-phase `timeout`);
///  - 60 s for the whole request (`totalDeadline`; a body that sends one
///    byte every 59 s used to live forever);
///  - 64 MiB of body (`maxResponseBytes`, the default — sized to the largest
///    legitimate reply, a 100 000-row `books.json` read-back).
/// Closed when disposed.
@Riverpod(keepAlive: true)
http.Client httpClient(HttpClientRef ref) {
  final client = TimeoutHttpClient(
    http.Client(),
    totalDeadline: const Duration(seconds: 60),
  );
  ref.onDispose(client.close);
  return client;
}

/// HTTP client for the public book-metadata APIs only. Differs from the
/// shared [httpClient] in two ways (REVIEW: lookup — "fails quite often"):
///  - 10 s per phase and 30 s total, not 60: lookups are interactive (user
///    watching a spinner); a slow provider should fail over to the fallback
///    quickly, not pin the button for a minute. 30 s total is 3× the phase
///    limit so a healthy-but-slow JSON reply still completes (N08, D1).
///  - [LookupHttpClient] on top: descriptive User-Agent (Open Library's API
///    policy throttles anonymous clients) + one jittered retry on 429/5xx.
@Riverpod(keepAlive: true)
http.Client lookupHttpClient(LookupHttpClientRef ref) {
  final client = LookupHttpClient(
    TimeoutHttpClient(
      http.Client(),
      timeout: const Duration(seconds: 10),
      totalDeadline: const Duration(seconds: 30),
    ),
  );
  ref.onDispose(client.close);
  return client;
}

/// OS-level screen-capture protection toggle (Android FLAG_SECURE) for vault
/// PII screens (#34/F-12). A narrow platform channel; no-op off Android.
@riverpod
ScreenSecurity screenSecurity(ScreenSecurityRef ref) =>
    const MethodChannelScreenSecurity();

/// Hands generated files (exports, backups) to the OS share sheet. Overridden
/// in widget tests with a fake to assert what would be shared.
@riverpod
FileShareService fileShareService(FileShareServiceRef ref) =>
    const SharePlusFileShareService();

/// The wall clock as epoch milliseconds, behind a provider so tests can
/// inject a fake (N04). Same idiom as the `int Function()? clock` constructor
/// parameters in the lookup/publish use cases.
@riverpod
int Function() clock(ClockRef ref) =>
    () => DateTime.now().millisecondsSinceEpoch;

/// Periodic "time has passed" signal (N04), watched by providers and widgets
/// whose output depends on the wall clock (overdue badges, due-soon reminders,
/// borrower stats) so a screen left open rolls over — a loan due at 15:00
/// turns overdue at 15:00, not at the next app start.
///
/// The value is the current epoch millis (NOT a constant event): Riverpod
/// only rebuilds dependents when the watched value changes, so a
/// `Stream.periodic` of identical events would never propagate. A self-
/// invalidating timer reschedules itself after every rebuild.
///
/// AutoDispose on purpose: the timer only runs while a screen is actually
/// watching, and `onDispose` cancels it (a pending timer would otherwise
/// outlive widget tests). Tests drive the same rebuild path by overriding
/// [clockProvider] and invalidating this provider instead of waiting out the
/// interval.
@riverpod
int nowTick(NowTickRef ref) {
  final timer = Timer(const Duration(seconds: 60), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  return ref.watch(clockProvider)();
}

/// Count of currently-visible passphrase entry fields (vault create / unlock
/// / change-passphrase / restore flows). Incremented by
/// `SecurePassphraseField.initState`, decremented on dispose.
///
/// keepAlive is deliberate: the field captures this notifier in initState and
/// calls it again from dispose(), which is only safe if the notifier can
/// never be auto-disposed out from under the widget.
@Riverpod(keepAlive: true)
class PassphraseEntryVisibility extends _$PassphraseEntryVisibility {
  @override
  int build() => 0;

  /// A passphrase field appeared on screen.
  void markVisible() => state = state + 1;

  /// A passphrase field left the screen. Clamped at zero: an unbalanced call
  /// is a caller bug, but it must never drive the count negative (that would
  /// silently turn protection OFF later — fail closed).
  void markHidden() => state = state > 0 ? state - 1 : 0;
}
