/// Settings persistence interface (domain, AGENTS.md §3.3).
///
/// Declared in `domain`, implemented in `infrastructure` over
/// `shared_preferences`. Reads return defaults when unset. No secrets cross
/// this interface.
///
/// M17 (astra-review.md): every write reports a typed result. The underlying
/// plugin returns a success boolean that used to be discarded, so the UI
/// could confirm preferences the device never actually stored. Writes now
/// return `Either<Failure, Unit>` (or `Either<Failure, String>` where a value
/// is minted), and callers fail closed on a left.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';

/// Loads and persists [AppSettings].
abstract interface class SettingsRepository {
  /// Reads the current settings (defaults for any unset key).
  Future<AppSettings> load();

  /// Persists the appearance mode.
  Future<Either<Failure, Unit>> setThemeMode(AppThemeMode mode);

  /// Persists the library display name.
  Future<Either<Failure, Unit>> setLibraryName(String name);

  /// Returns this app's library ID, minting and persisting a fresh one (32-char
  /// lowercase hex from a CSPRNG) on first call. Idempotent: later calls return
  /// the stored value. (PLAN-merge.md D40 `getOrCreateLibraryId`.) A failed
  /// mint/persist is a left — callers must not proceed with a phantom ID.
  Future<Either<Failure, String>> getOrCreateLibraryId();

  /// Replaces the stored library ID with [id] (adopted from an incoming file on
  /// a Join/Overwrite, or scanned from a pairing QR). The caller MUST pass a
  /// value already validated by `LibraryId.normalizeOrNull` — this method does
  /// not re-validate.
  Future<Either<Failure, Unit>> setLibraryId(String id);

  /// Mints a BRAND-NEW library ID (CSPRNG), replacing any existing one, and
  /// returns it. Used by "Start a new library" — it detaches this device from
  /// the previous namespace (PLAN-merge.md D40). Destructive to pairing, not to
  /// data, so the UI guards it behind a confirm.
  Future<Either<Failure, String>> regenerateLibraryId();

  /// Persists the maintainer name (stamped onto new books).
  Future<Either<Failure, Unit>> setMaintainerName(String name);

  /// Persists the library list sort.
  Future<Either<Failure, Unit>> setLibrarySort(BookSort sort);

  /// Persists the remote-cover opt-in (#31). Non-secret; default false.
  Future<Either<Failure, Unit>> setLoadRemoteCovers({required bool enabled});

  /// Persists the optional public publish-contact fields (#32). [address] is
  /// free-text; [gps] is a "lat, lng" pin. Both optional (blank = omitted).
  /// Fails closed on the FIRST failed field write; later fields are not
  /// attempted, so a partial contact set is never silently persisted as
  /// complete.
  Future<Either<Failure, Unit>> setPublishContact({
    required String address,
    required String gps,
    required String email,
    required String phone,
  });

  /// Persists the user's library-logo reference (`covers/<uuid>.jpg`), or blank
  /// to clear it. Non-secret; the image lives on-device under app docs.
  Future<Either<Failure, Unit>> setLibraryLogo(String reference);

  /// Persists the opt-in app-wide biometric gate flag (default false).
  Future<Either<Failure, Unit>> setAppLockBiometric({required bool enabled});
}
