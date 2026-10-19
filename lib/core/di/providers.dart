/// Dependency-injection barrel (AGENTS.md §4: Riverpod codegen is the DI
/// container — no GetIt, no service locators).
///
/// Every provider lives in a per-feature module under `src/`; this file
/// only re-exports them, so all call sites keep importing
/// `core/di/providers.dart` and a feature edit touches one small module
/// instead of a 985-line monolith.
///
/// The non-secret Drift database and the repositories/use cases over it are
/// wired in `src/database_providers.dart` + the feature modules; the
/// encrypted vault is reached through the Rust FFI core via
/// `vaultRepository` (`src/vault_providers.dart`) — the vault key never
/// enters Dart.
///
/// Module dependency direction: feature modules may import
/// `src/platform_providers.dart` / `src/database_providers.dart` (the shared
/// base) and selected sibling feature modules, one direction only — the
/// module headers document each cross-feature import. A cycle would mean a
/// binding belongs in a base module instead.
library;

export 'package:pitaka/core/di/src/app_update_providers.dart';
export 'package:pitaka/core/di/src/backup_providers.dart';
export 'package:pitaka/core/di/src/database_providers.dart';
export 'package:pitaka/core/di/src/events_providers.dart';
export 'package:pitaka/core/di/src/import_export_providers.dart';
export 'package:pitaka/core/di/src/library_providers.dart';
export 'package:pitaka/core/di/src/lookup_providers.dart';
export 'package:pitaka/core/di/src/network_providers.dart';
export 'package:pitaka/core/di/src/platform_providers.dart';
export 'package:pitaka/core/di/src/publish_providers.dart';
export 'package:pitaka/core/di/src/settings_providers.dart';
export 'package:pitaka/core/di/src/vault_providers.dart';
export 'package:pitaka/core/di/src/wishlist_providers.dart';
