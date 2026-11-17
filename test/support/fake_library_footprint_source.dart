import 'package:pitaka/features/backup/domain/library_footprint.dart';

/// A [LibraryFootprintSource] for tests: answers [footprint] (null means
/// "could not be read"), or throws [failure] when one is set.
///
/// The default is a small library, so that a test which is not about the
/// notice gets a small need.
final class FakeLibraryFootprintSource implements LibraryFootprintSource {
  /// Creates the fake.
  FakeLibraryFootprintSource({this.footprint = small, this.failure});

  /// A catalogue of 1 MB, covers of 8 MB, no vault.
  static const LibraryFootprint small = LibraryFootprint(
    catalogueBytes: 1024 * 1024,
    coverBytes: 8 * 1024 * 1024,
    vaultBytes: 0,
  );

  /// What [read] answers.
  LibraryFootprint? footprint;

  /// When set, [read] throws this instead of answering.
  Object? failure;

  /// How many times [read] was called.
  int reads = 0;

  @override
  Future<LibraryFootprint?> read() async {
    reads++;
    final failure = this.failure;
    // A test fake throws whatever the test asks for.
    // ignore: only_throw_errors
    if (failure != null) throw failure;
    return footprint;
  }
}
