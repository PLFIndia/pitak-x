import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/database/app_database.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/import_export/application/import_library_use_case.dart';
import 'package:pitaka/features/import_export/domain/bundle_cover_files.dart';
import 'package:pitaka/features/import_export/domain/import_bundle.dart';
import 'package:pitaka/features/import_export/domain/import_payload.dart';
import 'package:pitaka/features/import_export/infrastructure/file_bundle_cover_store.dart';
import 'package:pitaka/features/import_export/infrastructure/pitaka_json_importer.dart';
import 'package:pitaka/features/library/domain/cover_file_coordinator.dart';
import 'package:pitaka/features/library/domain/repositories/book_repository.dart';
import 'package:pitaka/features/library/infrastructure/drift_book_repository.dart';
import 'package:pitaka/features/wishlist/domain/repositories/wishlist_repository.dart';
import 'package:pitaka/features/wishlist/infrastructure/drift_wishlist_repository.dart';

/// Synthetic files + real, shared, in-memory Drift for cross-store assertions.
final class BundleTestFixture {
  final directory = Directory.systemTemp.createTempSync('bundle_transaction');
  final database = AppDatabase(NativeDatabase.memory());
  final coordinator = CoverFileCoordinator();
  late final books = DriftBookRepository(database);
  late final wishlist = DriftWishlistRepository(database);
  late final files = FileBundleCoverStore(coversDir: directory.path);

  File cover(String reference) =>
      File('${directory.path}/${reference.substring(7)}');
  List<File> get images => directory.listSync().whereType<File>().toList();

  Future<Either<Failure, ImportSummary>> apply(
    ImportPayload payload, {
    Map<String, Uint8List> images = const {},
    BundleCoverFiles? coverFiles,
    BookRepository? bookRepository,
    WishlistRepository? wishlistRepository,
  }) async {
    final validated = ImportBundle.validate(payload, images);
    return validated.match(
      (failure) async => left(failure),
      (bundle) =>
          ImportLibraryUseCase(
            jsonParser: const PitakaJsonImporter(),
            bookRepo: bookRepository ?? books,
            wishlistRepo: wishlistRepository ?? wishlist,
          ).importBundle(
            bundle,
            coverFiles: coverFiles ?? files,
            coordinator: coordinator,
          ),
    );
  }

  Future<void> dispose() async {
    await database.close();
    directory.deleteSync(recursive: true);
  }
}
