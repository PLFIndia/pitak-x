// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'import_export_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$bundleCoverFilesHash() => r'1a39d026e0238b00f8061007a6005f7afa808372';

/// Operation-owned imported covers under the existing app-private covers dir.
///
/// Copied from [bundleCoverFiles].
@ProviderFor(bundleCoverFiles)
final bundleCoverFilesProvider =
    AutoDisposeFutureProvider<BundleCoverFiles>.internal(
      bundleCoverFiles,
      name: r'bundleCoverFilesProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$bundleCoverFilesHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef BundleCoverFilesRef = AutoDisposeFutureProviderRef<BundleCoverFiles>;
String _$importLibraryUseCaseHash() =>
    r'6e37fd19ebd1cc8cad27ee88d6bffc6ba353ad8c';

/// One-shot library/wishlist import use case.
///
/// Copied from [importLibraryUseCase].
@ProviderFor(importLibraryUseCase)
final importLibraryUseCaseProvider =
    AutoDisposeFutureProvider<ImportLibraryUseCase>.internal(
      importLibraryUseCase,
      name: r'importLibraryUseCaseProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$importLibraryUseCaseHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef ImportLibraryUseCaseRef =
    AutoDisposeFutureProviderRef<ImportLibraryUseCase>;
String _$exportLogoReaderHash() => r'a98726e103d90ec921020da91e345d46495304d5';

/// Library-logo file reader for exports (N14): file IO injected as a port;
/// the application controller no longer touches dart:io.
///
/// Copied from [exportLogoReader].
@ProviderFor(exportLogoReader)
final exportLogoReaderProvider =
    AutoDisposeFutureProvider<Future<Uint8List?> Function(String)>.internal(
      exportLogoReader,
      name: r'exportLogoReaderProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$exportLogoReaderHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef ExportLogoReaderRef =
    AutoDisposeFutureProviderRef<Future<Uint8List?> Function(String)>;
String _$exportWorkAreaHash() => r'07ebdcdcd9920dce2c828aec1febe6d631e9af17';

/// Where the file of ONE export lies while it is saved or shared (review
/// finding P4-M6): a private folder per export under the app's temporary
/// directory, and the one place that removes it again.
///
/// keepAlive (justified): this object remembers which folders are IN USE by
/// an export of this app session, so that a sweep never deletes a file that
/// is being saved or shared. An auto-disposed instance would forget that
/// between two reads (the same reason as `backupWorkArea`).
///
/// Copied from [exportWorkArea].
@ProviderFor(exportWorkArea)
final exportWorkAreaProvider = FutureProvider<ExportWorkArea>.internal(
  exportWorkArea,
  name: r'exportWorkAreaProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$exportWorkAreaHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef ExportWorkAreaRef = FutureProviderRef<ExportWorkArea>;
String _$staleExportWorkSweepHash() =>
    r'974c2a89f4f72e63a6cc1211c8b969a7f4e08a68';

/// One-time clean-up per app start: removes what an export left behind when
/// the app was killed while its file was being saved or shared (a plain
/// copy of the library). Triggered next to the backup's sweep, by the
/// Library screen's first build.
///
/// keepAlive (justified): "once per app session" is the whole point, as for
/// `staleBackupWorkSweep`. The result is not shown anywhere: when something
/// could not be removed, the next start (and the next export) tries again.
///
/// Copied from [staleExportWorkSweep].
@ProviderFor(staleExportWorkSweep)
final staleExportWorkSweepProvider = FutureProvider<void>.internal(
  staleExportWorkSweep,
  name: r'staleExportWorkSweepProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$staleExportWorkSweepHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef StaleExportWorkSweepRef = FutureProviderRef<void>;
String _$exportLibraryUseCaseHash() =>
    r'07c8a9a02aee0556a80374cade57fda5249954dc';

/// One-shot library/wishlist export use case.
///
/// Copied from [exportLibraryUseCase].
@ProviderFor(exportLibraryUseCase)
final exportLibraryUseCaseProvider =
    AutoDisposeFutureProvider<ExportLibraryUseCase>.internal(
      exportLibraryUseCase,
      name: r'exportLibraryUseCaseProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$exportLibraryUseCaseHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef ExportLibraryUseCaseRef =
    AutoDisposeFutureProviderRef<ExportLibraryUseCase>;
String _$pdfFooterIconLoaderHash() =>
    r'49130e3985bd03424e7f5bc9b78322d3152c2e76';

/// Loads the bundled footer icon for the PDF export, or null when the asset
/// is missing (a missing icon must never block an export). Behind a provider
/// because `rootBundle` is a side effect the application layer must not own.
///
/// Copied from [pdfFooterIconLoader].
@ProviderFor(pdfFooterIconLoader)
final pdfFooterIconLoaderProvider =
    AutoDisposeProvider<Future<Uint8List?> Function()>.internal(
      pdfFooterIconLoader,
      name: r'pdfFooterIconLoaderProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$pdfFooterIconLoaderHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef PdfFooterIconLoaderRef =
    AutoDisposeProviderRef<Future<Uint8List?> Function()>;
String _$pdfTextFontsLoaderHash() =>
    r'c7e53aacee5daff6da71fd727bb9ee40b892c103';

/// Loads the two fonts the PDF export writes REAL text with (ADR 0033): the
/// bundled Latin face, regular and bold. Each is the first entry of its
/// list, which is ordered base-first.
///
/// Only the Latin face is handed over, on purpose. The `pdf` package places
/// glyph after glyph and cannot shape, so a font of an Indian script would
/// make the renderer believe it can write that text, and it would come out
/// wrong. Such text is drawn by the rasterizer below instead.
///
/// Behind a provider because `rootBundle` is a side effect the application
/// layer must not own (as for the footer icon above). A font that cannot be
/// loaded is NOT skipped: the error ends the export, which says "failed".
///
/// Copied from [pdfTextFontsLoader].
@ProviderFor(pdfTextFontsLoader)
final pdfTextFontsLoaderProvider =
    AutoDisposeProvider<Future<PdfTextFonts> Function()>.internal(
      pdfTextFontsLoader,
      name: r'pdfTextFontsLoaderProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$pdfTextFontsLoaderHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef PdfTextFontsLoaderRef =
    AutoDisposeProviderRef<Future<PdfTextFonts> Function()>;
String _$pdfTextRasterizerHash() => r'841e6d7a430d6ead5467b94ed731527f70f5ef44';

/// Shaped-text rasterizer for the PDF export (needs a live Flutter engine +
/// the bundled Noto fonts — infrastructure, injected as the domain
/// `PdfTextRasterizer` port).
///
/// Copied from [pdfTextRasterizer].
@ProviderFor(pdfTextRasterizer)
final pdfTextRasterizerProvider =
    AutoDisposeProvider<PdfTextRasterizer>.internal(
      pdfTextRasterizer,
      name: r'pdfTextRasterizerProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$pdfTextRasterizerHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef PdfTextRasterizerRef = AutoDisposeProviderRef<PdfTextRasterizer>;
String _$mergeLibraryUseCaseHash() =>
    r'cbbe6fe6302b02f5d78a27642c492cb86e4355fe';

/// Multi-maintainer library merge use case (PLAN-merge.md): reconciles an
/// incoming Pitaka-JSON file with the local catalogue behind the library-ID
/// gate. The library identity (ID gate + Join/Overwrite adoption) goes through
/// `SettingsController` — the single serialised settings writer — via the
/// `LibraryNamespace` port, so the drawer/title/export name update the moment
/// a merge adopts a library (N07; same shape as the replacement guard below).
///
/// Copied from [mergeLibraryUseCase].
@ProviderFor(mergeLibraryUseCase)
final mergeLibraryUseCaseProvider =
    AutoDisposeFutureProvider<MergeLibraryUseCase>.internal(
      mergeLibraryUseCase,
      name: r'mergeLibraryUseCaseProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$mergeLibraryUseCaseHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef MergeLibraryUseCaseRef =
    AutoDisposeFutureProviderRef<MergeLibraryUseCase>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
