// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'platform_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$appDocsDirHash() => r'e7479780a89d80bc60127b48a09106e777c3d88d';

/// The app's document directory (where the DB + covers live). Resolved once.
///
/// Copied from [appDocsDir].
@ProviderFor(appDocsDir)
final appDocsDirProvider = FutureProvider<Directory>.internal(
  appDocsDir,
  name: r'appDocsDirProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$appDocsDirHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef AppDocsDirRef = FutureProviderRef<Directory>;
String _$appTempDirHash() => r'331ffcb8d0558900523463fe6b1dc22d05de771a';

/// The app's temporary directory, where publish spools live (fix-plan L5).
///
/// The OS may clear it at any time and it is never backed up, so a killed
/// publish cannot leave a full copy of the site in Documents forever.
///
/// Copied from [appTempDir].
@ProviderFor(appTempDir)
final appTempDirProvider = FutureProvider<Directory>.internal(
  appTempDir,
  name: r'appTempDirProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$appTempDirHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef AppTempDirRef = FutureProviderRef<Directory>;
String _$appCacheDirHash() => r'8e7b3bf55b87c922ed208502df9677c7d8a4bb18';

/// The app's cache directory, where saved copies of other libraries'
/// published files live (ADR 0018).
///
/// Re-downloadable data belongs here, not in Documents: the OS excludes it
/// from device/cloud backups and may clear it when storage is low, and the
/// viewer simply downloads again when it does.
///
/// Copied from [appCacheDir].
@ProviderFor(appCacheDir)
final appCacheDirProvider = FutureProvider<Directory>.internal(
  appCacheDir,
  name: r'appCacheDirProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$appCacheDirHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef AppCacheDirRef = FutureProviderRef<Directory>;
String _$dataGenerationsHash() => r'5c7eb39a9f63c79decce85093ed046e046d888ce';

/// Versioned data-generation store under `<appDocs>/data` (M02). The
/// catalogue DB, covers and vault live INSIDE the active generation so a
/// restore can build a complete new set and switch to it atomically.
///
/// Copied from [dataGenerations].
@ProviderFor(dataGenerations)
final dataGenerationsProvider = FutureProvider<DataGenerations>.internal(
  dataGenerations,
  name: r'dataGenerationsProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$dataGenerationsHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef DataGenerationsRef = FutureProviderRef<DataGenerations>;
String _$httpClientHash() => r'648965b3207e4b12fb288ad3ef972854752613c6';

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
///
/// Copied from [httpClient].
@ProviderFor(httpClient)
final httpClientProvider = Provider<http.Client>.internal(
  httpClient,
  name: r'httpClientProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$httpClientHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef HttpClientRef = ProviderRef<http.Client>;
String _$lookupHttpClientHash() => r'b3c4ea0272408aceb7afd2c145148c0243ba1d72';

/// HTTP client for the public book-metadata APIs only. Differs from the
/// shared [httpClient] in two ways (REVIEW: lookup — "fails quite often"):
///  - 10 s per phase and 30 s total, not 60: lookups are interactive (user
///    watching a spinner); a slow provider should fail over to the fallback
///    quickly, not pin the button for a minute. 30 s total is 3× the phase
///    limit so a healthy-but-slow JSON reply still completes (N08, D1).
///  - [LookupHttpClient] on top: descriptive User-Agent (Open Library's API
///    policy throttles anonymous clients) + one jittered retry on 429/5xx.
///
/// Copied from [lookupHttpClient].
@ProviderFor(lookupHttpClient)
final lookupHttpClientProvider = Provider<http.Client>.internal(
  lookupHttpClient,
  name: r'lookupHttpClientProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$lookupHttpClientHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef LookupHttpClientRef = ProviderRef<http.Client>;
String _$screenSecurityHash() => r'e9cf5896b361c1d071b4ac76293d15cf98e29b89';

/// OS-level screen-capture protection toggle (Android FLAG_SECURE) for vault
/// PII screens (#34/F-12). A narrow platform channel; no-op off Android.
///
/// Copied from [screenSecurity].
@ProviderFor(screenSecurity)
final screenSecurityProvider = AutoDisposeProvider<ScreenSecurity>.internal(
  screenSecurity,
  name: r'screenSecurityProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$screenSecurityHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef ScreenSecurityRef = AutoDisposeProviderRef<ScreenSecurity>;
String _$fileShareServiceHash() => r'4caa4196352d292bcbf88099f9a02fb2e0deb5ba';

/// Hands generated files (exports, backups) to the OS share sheet. Overridden
/// in widget tests with a fake to assert what would be shared.
///
/// Copied from [fileShareService].
@ProviderFor(fileShareService)
final fileShareServiceProvider = AutoDisposeProvider<FileShareService>.internal(
  fileShareService,
  name: r'fileShareServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$fileShareServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef FileShareServiceRef = AutoDisposeProviderRef<FileShareService>;
String _$clockHash() => r'95c05edbf47d123a7fa7805bf8535316be77b11c';

/// The wall clock as epoch milliseconds, behind a provider so tests can
/// inject a fake (N04). Same idiom as the `int Function()? clock` constructor
/// parameters in the lookup/publish use cases.
///
/// Copied from [clock].
@ProviderFor(clock)
final clockProvider = AutoDisposeProvider<int Function()>.internal(
  clock,
  name: r'clockProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$clockHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef ClockRef = AutoDisposeProviderRef<int Function()>;
String _$nowTickHash() => r'819f71fe0a55e4c93a2f1358cfdc86fcc4381476';

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
///
/// Copied from [nowTick].
@ProviderFor(nowTick)
final nowTickProvider = AutoDisposeProvider<int>.internal(
  nowTick,
  name: r'nowTickProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$nowTickHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef NowTickRef = AutoDisposeProviderRef<int>;
String _$passphraseEntryVisibilityHash() =>
    r'cf6a246b57a5b9acf1fafc361cee75a0f3730746';

/// Count of currently-visible passphrase entry fields (vault create / unlock
/// / change-passphrase / restore flows). Incremented by
/// `SecurePassphraseField.initState`, decremented on dispose.
///
/// keepAlive is deliberate: the field captures this notifier in initState and
/// calls it again from dispose(), which is only safe if the notifier can
/// never be auto-disposed out from under the widget.
///
/// Copied from [PassphraseEntryVisibility].
@ProviderFor(PassphraseEntryVisibility)
final passphraseEntryVisibilityProvider =
    NotifierProvider<PassphraseEntryVisibility, int>.internal(
      PassphraseEntryVisibility.new,
      name: r'passphraseEntryVisibilityProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$passphraseEntryVisibilityHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$PassphraseEntryVisibility = Notifier<int>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
