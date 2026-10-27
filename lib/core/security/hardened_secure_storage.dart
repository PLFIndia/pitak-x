/// The ONE hardened `flutter_secure_storage` configuration for the app
/// (AGENTS.md §6.3; Cloudflare plan deviation 12 / P5).
///
/// Why a factory (beginner note): `flutter_secure_storage`'s defaults differ
/// per platform and per version, and creating it with a bare
/// `const FlutterSecureStorage()` silently gives a store with WEAKER Android
/// and iOS defaults than its siblings. Four secret-bearing stores in this app
/// (GitHub publish credentials, the cover salt, the lookup API key and the
/// biometric vault record) must not each re-declare — and slowly drift — those
/// options. They all come from here.
///
/// What is always enforced:
///  - **Android:** AES-GCM via EncryptedSharedPreferences (never plain
///    SharedPreferences).
///  - **iOS/macOS:** the item never migrates to another device through a
///    backup or iCloud Keychain restore.
///
/// The ONLY per-store choice is iOS keychain accessibility, because it is a
/// real security trade-off rather than boilerplate:
///  - [KeychainAccessibility.unlocked_this_device] (the default) for anything
///    that grants access or is secret: the GitHub token, the lookup key, the
///    biometric vault record.
///  - [KeychainAccessibility.first_unlock_this_device] for non-secret material
///    that must survive a reboot without an unlock prompt (the cover salt,
///    whose loss would silently change every published cover URL).
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Builds a secure store with the app's hardening options applied.
///
/// [accessibility] is iOS-only; Android always uses EncryptedSharedPreferences.
FlutterSecureStorage hardenedSecureStorage({
  KeychainAccessibility accessibility =
      KeychainAccessibility.unlocked_this_device,
}) => FlutterSecureStorage(
  aOptions: const AndroidOptions(encryptedSharedPreferences: true),
  iOptions: IOSOptions(accessibility: accessibility),
);
