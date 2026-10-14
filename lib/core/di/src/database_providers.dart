/// Database + preferences DI bindings (AGENTS.md §4; SOLID-PLAN S3).
///
/// What lives here: the Drift catalogue database (opened inside the active
/// data generation), its path companions, and SharedPreferences — the
/// storage base every repository module builds on.
///
/// Why `wishlistRepository` sits here and not in the wishlist module: the
/// library cover janitor needs it (M11 — wishlist rows keep cover files
/// alive) AND the wishlist module's mark-purchased use case needs the
/// library module's bookRepository. Housing this pure Drift binding with
/// the database breaks that would-be import cycle between feature modules
/// (the plan's cycle rule: the binding moves to a shared base module).
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:pitaka/core/database/app_database.dart';
import 'package:pitaka/core/storage/active_data_generation.dart';
import 'package:pitaka/features/wishlist/domain/repositories/wishlist_repository.dart';
import 'package:pitaka/features/wishlist/infrastructure/drift_wishlist_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'database_providers.g.dart';

/// The non-secret Drift database (books + wishlist), opened inside the active
/// data generation (M02) — switching generations closes and reopens it.
///
/// `keepAlive`: the open DB must survive navigation; reopening per-screen would
/// thrash the connection. Closed when the provider is finally disposed.
@Riverpod(keepAlive: true)
Future<AppDatabase> appDatabase(AppDatabaseRef ref) async {
  final generation = await ref.watch(activeDataGenerationProvider.future);
  final file = File(generation.catalogueDbPath);
  final db = AppDatabase(NativeDatabase.createInBackground(file));
  ref.onDispose(db.close);
  return db;
}

/// Absolute path to the covers directory inside the active data generation
/// (M02), where local book covers are stored. Used by cover-rendering widgets.
@riverpod
Future<String> coversDir(CoversDirRef ref) async {
  final generation = await ref.watch(activeDataGenerationProvider.future);
  return generation.coversDir;
}

/// The app's shared (non-secret) key-value preferences store.
@Riverpod(keepAlive: true)
Future<SharedPreferences> sharedPreferences(SharedPreferencesRef ref) =>
    SharedPreferences.getInstance();

/// Wishlist repository. Lives with the database bindings (not the wishlist
/// module) to keep the feature-module graph acyclic — see the file header.
@riverpod
Future<WishlistRepository> wishlistRepository(WishlistRepositoryRef ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return DriftWishlistRepository(db);
}
