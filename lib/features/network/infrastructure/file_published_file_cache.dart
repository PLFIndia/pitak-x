/// Saved copies of published files, on disk (network infrastructure;
/// ADR 0018). Implements the domain [PublishedFileCache] port.
///
/// Layout, under the OS **cache** directory (never Documents):
///
/// ```text
/// <app cache>/published_copies/
///   index.json                      ← PublishedFileCacheIndex
///   <sha256(site URL)>/catalogue.bin
///   <sha256(site URL)>/events.bin
/// ```
///
/// Why the cache directory (beginner note): it is the OS's place for data an
/// app can download again. Android and iOS exclude it from cloud/device
/// backups, and the OS may delete it when storage runs low — both are right
/// for a copy of someone else's public file. Pitak's own `.pitabak` backup
/// never includes it either. If the OS deletes it, the next open simply
/// downloads the file again.
///
/// Safety rules, each tested:
///  - **Serialized.** Every operation runs on one [SerialOpQueue], so the
///    catalogue and events loads of the same screen can never interleave a
///    read-modify-write of `index.json`. DI keeps ONE instance alive for the
///    whole app so there is exactly one queue.
///  - **Atomic writes.** A file is written to `*.tmp`, flushed, then renamed
///    over the real name; a crash leaves the old file or the new one.
///  - **Write order.** The data file is written BEFORE the index that vouches
///    for it, and the index is written BEFORE evicted files are deleted. A
///    crash in between leaves a copy whose hash no longer matches (rejected on
///    read) or an orphan folder (swept by `retainOnly`) — never an index entry
///    that vouches for the wrong bytes.
///  - **Verified reads.** Bytes are handed out only when their size and
///    SHA-256 match the index; anything else is deleted and reported absent.
///  - **Never fatal.** Every IO failure becomes a typed result plus a
///    debug-only log line carrying the exception TYPE (file-system messages
///    contain paths, which are never logged).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:fpdart/fpdart.dart';
import 'package:path/path.dart' as p;
import 'package:pitaka/core/async/serial_op_queue.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/platform/app_log.dart';
import 'package:pitaka/features/network/domain/repositories/published_file_cache.dart';
import 'package:pitaka/features/network/infrastructure/published_file_cache_index.dart';

/// Computes the lowercase hex SHA-256 of [bytes] (injectable for tests).
typedef ContentHasher = Future<String> Function(Uint8List bytes);

/// See the file header.
final class FilePublishedFileCache implements PublishedFileCache {
  /// Creates the store. [resolveRoot] returns the folder that holds
  /// `index.json` (resolved lazily, on first use, so constructing the store
  /// never touches the platform). [maxTotalBytes] is injectable so tests can
  /// exercise eviction with small files.
  FilePublishedFileCache({
    required Future<String> Function() resolveRoot,
    this.maxTotalBytes = PublishedFileCache.maxTotalBytes,
    ContentHasher hash = sha256Hex,
  }) : _resolveRoot = resolveRoot,
       _hash = hash;

  /// The size cap for all saved copies together.
  final int maxTotalBytes;

  final Future<String> Function() _resolveRoot;
  final ContentHasher _hash;
  final SerialOpQueue _queue = SerialOpQueue();
  String? _root;

  static const String _indexName = 'index.json';
  static const String _tempSuffix = '.tmp';
  static const Failure _storageFailed = StorageFailure(
    'Could not update the saved copy.',
  );

  /// Bytes below this size are hashed inline; larger ones in a worker
  /// isolate, so hashing a 64 MiB catalogue never stalls a frame.
  static const int _inlineHashLimit = 1024 * 1024;

  /// The production hasher.
  static Future<String> sha256Hex(Uint8List bytes) async {
    if (bytes.length < _inlineHashLimit) {
      return sha256.convert(bytes).toString();
    }
    return Isolate.run(
      () => sha256.convert(bytes).toString(),
      debugName: 'pitaka-saved-copy-hash',
    );
  }

  /// The folder name for [siteUrl]: SHA-256 of its UTF-8 bytes, hex.
  static String keyFor(String siteUrl) =>
      sha256.convert(utf8.encode(siteUrl)).toString();

  @override
  Future<SavedPublishedFileInfo?> info(
    String siteUrl,
    PublishedFileKind kind,
  ) => _run('info', () async {
    final root = await _rootDir();
    final index = await _loadIndex(root);
    final key = keyFor(siteUrl);
    final entry = index.libraries[key]?.files[kind];
    if (entry == null) return null;
    // A cheap size check before promising the host we hold this copy: if the
    // OS purged the file, sending its tag would earn a useless `304`.
    final file = _dataFile(root, key, kind);
    if (!file.existsSync() || await file.length() != entry.size) {
      await _dropEntry(root, index, key, kind);
      return null;
    }
    return SavedPublishedFileInfo(
      contentHash: entry.sha256,
      checkedAt: entry.checkedAt,
      validator: entry.validator,
    );
  }, orElse: null);

  @override
  Future<Uint8List?> readBytes(
    String siteUrl,
    PublishedFileKind kind, {
    required String contentHash,
  }) => _run('read', () async {
    final root = await _rootDir();
    final index = await _loadIndex(root);
    final key = keyFor(siteUrl);
    final entry = index.libraries[key]?.files[kind];
    if (entry == null || entry.sha256 != contentHash) return null;
    final file = _dataFile(root, key, kind);
    if (!file.existsSync()) {
      await _dropEntry(root, index, key, kind);
      return null;
    }
    final bytes = await file.readAsBytes();
    if (bytes.length != entry.size || await _hash(bytes) != entry.sha256) {
      appLog('published copies: a saved copy failed verification');
      await _dropEntry(root, index, key, kind);
      return null;
    }
    return bytes;
  }, orElse: null);

  @override
  Future<Either<Failure, Unit>> save(
    String siteUrl,
    PublishedFileKind kind, {
    required Uint8List bytes,
    required int checkedAt,
    String? validator,
  }) => _write('save', () async {
    // Larger than the whole budget: keep nothing rather than evict everything.
    if (bytes.length > maxTotalBytes) return const Left(_storageFailed);
    final root = await _rootDir();
    final index = await _loadIndex(root);
    final key = keyFor(siteUrl);
    final hash = await _hash(bytes);
    final library = index.libraries[key] ??= CachedLibraryEntry(
      lastOpenedAt: checkedAt,
      files: {},
    );
    final previous = library.files[kind];
    final file = _dataFile(root, key, kind);
    // GitHub Pages changes its tag on every deploy even when this file did
    // not change. Comparing our own SHA-256 avoids rewriting identical bytes.
    final unchanged =
        previous != null &&
        previous.sha256 == hash &&
        file.existsSync() &&
        await file.length() == bytes.length;
    if (!unchanged) await _atomicWrite(file, bytes);
    library.files[kind] = CachedFileEntry(
      sha256: hash,
      size: bytes.length,
      checkedAt: checkedAt,
      validator: validator,
    );
    final evicted = _evictOverCap(index, keep: key, keepKind: kind);
    await _saveIndex(root, index);
    for (final gone in evicted) {
      await _deleteQuietly(gone.call(root));
    }
    return const Right(unit);
  });

  @override
  Future<Either<Failure, Unit>> markChecked(
    String siteUrl,
    PublishedFileKind kind, {
    required String contentHash,
    required int checkedAt,
  }) => _write('markChecked', () async {
    final root = await _rootDir();
    final index = await _loadIndex(root);
    final key = keyFor(siteUrl);
    final library = index.libraries[key];
    final entry = library?.files[kind];
    // Replaced meanwhile: the confirmation was about a different copy.
    if (library == null || entry == null || entry.sha256 != contentHash) {
      return const Right(unit);
    }
    library.files[kind] = entry.confirmedAt(checkedAt);
    await _saveIndex(root, index);
    return const Right(unit);
  });

  @override
  Future<Either<Failure, Unit>> markOpened(
    String siteUrl, {
    required int openedAt,
  }) => _write('markOpened', () async {
    final root = await _rootDir();
    final index = await _loadIndex(root);
    final library = index.libraries[keyFor(siteUrl)];
    if (library == null) return const Right(unit);
    library.lastOpenedAt = openedAt;
    await _saveIndex(root, index);
    return const Right(unit);
  });

  @override
  Future<Either<Failure, Unit>> remove(
    String siteUrl,
    PublishedFileKind kind,
  ) => _write('remove', () async {
    final root = await _rootDir();
    final index = await _loadIndex(root);
    await _dropEntry(root, index, keyFor(siteUrl), kind);
    return const Right(unit);
  });

  @override
  Future<Either<Failure, Unit>> retainOnly(Set<String> siteUrls) =>
      _write('retainOnly', () async {
        final root = await _rootDir();
        final index = await _loadIndex(root);
        final keep = {for (final url in siteUrls) keyFor(url)};
        final dropped = [
          for (final key in index.libraries.keys)
            if (!keep.contains(key)) key,
        ];
        for (final key in dropped) {
          index.libraries.remove(key);
        }
        if (dropped.isNotEmpty) await _saveIndex(root, index);
        await _sweep(root, index);
        return const Right(unit);
      });

  // ---------------------------------------------------------------- helpers

  /// Runs a read-only [op] on the queue; any IO failure yields [orElse].
  Future<T> _run<T>(
    String name,
    Future<T> Function() op, {
    required T orElse,
  }) => _queue.enqueue(() async {
    try {
      return await op();
    } on Exception catch (e) {
      appLog('published copies: $name failed (${e.runtimeType})');
      return orElse;
    }
  });

  /// Runs a mutating [op] on the queue; any IO failure is a typed Left.
  Future<Either<Failure, Unit>> _write(
    String name,
    Future<Either<Failure, Unit>> Function() op,
  ) => _run(name, op, orElse: const Left(_storageFailed));

  /// The cache folder. Resolved once on success; a failure is retried on the
  /// next operation (it may be transient).
  ///
  /// The resolver crosses the PLATFORM boundary (path_provider). Without a
  /// platform answer it can fail with a framework `Error` rather than an
  /// `Exception` (e.g. no binding yet), so every failure is mapped here to
  /// the one typed [_NoCacheFolder] that [_run] handles: "no folder" means
  /// "no saved copies", never a broken viewer or saved list (fail closed).
  Future<String> _rootDir() async {
    final known = _root;
    if (known != null) return known;
    final String resolved;
    try {
      resolved = await _resolveRoot();
    } on Object catch (e) {
      appLog('published copies: no cache folder (${e.runtimeType})');
      throw const _NoCacheFolder();
    }
    _root = resolved;
    return resolved;
  }

  File _indexFile(String root) => File(p.join(root, _indexName));

  File _dataFile(String root, String key, PublishedFileKind kind) =>
      File(p.join(root, key, '${kind.name}.bin'));

  Directory _libraryDir(String root, String key) =>
      Directory(p.join(root, key));

  /// Loads the index. A missing file is an empty index; an unreadable one
  /// wipes the whole folder (its files can no longer be vouched for) and
  /// starts empty — the next opens simply download again.
  Future<PublishedFileCacheIndex> _loadIndex(String root) async {
    final file = _indexFile(root);
    if (!file.existsSync()) return PublishedFileCacheIndex();
    final decoded = PublishedFileCacheIndex.decode(
      await file.readAsString(),
      maxFileSize: maxTotalBytes,
    );
    if (decoded != null) return decoded;
    appLog('published copies: unreadable index, clearing saved copies');
    await _deleteQuietly(Directory(root));
    return PublishedFileCacheIndex();
  }

  Future<void> _saveIndex(String root, PublishedFileCacheIndex index) =>
      _atomicWrite(_indexFile(root), utf8.encode(index.encode()));

  /// Writes [bytes] to `<file>.tmp`, flushes, then renames over [file].
  Future<void> _atomicWrite(File file, List<int> bytes) async {
    await file.parent.create(recursive: true);
    final temp = File('${file.path}$_tempSuffix');
    await temp.writeAsBytes(bytes, flush: true);
    await temp.rename(file.path);
  }

  /// Removes one file entry (and the library when it was its last file),
  /// saving the index BEFORE deleting anything from disk.
  Future<void> _dropEntry(
    String root,
    PublishedFileCacheIndex index,
    String key,
    PublishedFileKind kind,
  ) async {
    final library = index.libraries[key];
    if (library == null || library.files.remove(kind) == null) {
      await _deleteQuietly(_dataFile(root, key, kind));
      return;
    }
    final libraryGone = library.files.isEmpty;
    if (libraryGone) index.libraries.remove(key);
    await _saveIndex(root, index);
    await _deleteQuietly(
      libraryGone ? _libraryDir(root, key) : _dataFile(root, key, kind),
    );
  }

  /// Removes whole libraries, least recently opened first (ties: key order,
  /// so the choice is deterministic), until the total fits the cap. The
  /// library being saved ([keep]) goes last and only loses its OTHER files —
  /// [save] already refused a single file larger than the whole cap.
  /// Returns what to delete once the index is safely written.
  List<FileSystemEntity Function(String root)> _evictOverCap(
    PublishedFileCacheIndex index, {
    required String keep,
    required PublishedFileKind keepKind,
  }) {
    var total = index.totalBytes;
    final doomed = <FileSystemEntity Function(String root)>[];
    if (total <= maxTotalBytes) return doomed;
    final candidates =
        index.libraries.entries.where((entry) => entry.key != keep).toList()
          ..sort((a, b) {
            final byAge = a.value.lastOpenedAt.compareTo(b.value.lastOpenedAt);
            return byAge != 0 ? byAge : a.key.compareTo(b.key);
          });
    for (final candidate in candidates) {
      if (total <= maxTotalBytes) break;
      total -= candidate.value.totalBytes;
      index.libraries.remove(candidate.key);
      doomed.add((root) => _libraryDir(root, candidate.key));
    }
    final kept = index.libraries[keep];
    if (total > maxTotalBytes && kept != null) {
      for (final kind in [...kept.files.keys]) {
        if (kind == keepKind || total <= maxTotalBytes) continue;
        total -= kept.files.remove(kind)!.size;
        doomed.add((root) => _dataFile(root, keep, kind));
      }
    }
    appLog('published copies: evicted ${doomed.length} item(s) over the cap');
    return doomed;
  }

  /// Deletes folders the index does not vouch for, and leftover `*.tmp`
  /// files from interrupted writes.
  Future<void> _sweep(String root, PublishedFileCacheIndex index) async {
    final dir = Directory(root);
    if (!dir.existsSync()) return;
    await for (final entity in dir.list(followLinks: false)) {
      final name = p.basename(entity.path);
      if (entity is Directory) {
        if (!index.libraries.containsKey(name)) {
          await _deleteQuietly(entity);
          continue;
        }
        await for (final inner in entity.list(followLinks: false)) {
          if (inner.path.endsWith(_tempSuffix)) await _deleteQuietly(inner);
        }
      } else if (name != _indexName) {
        await _deleteQuietly(entity);
      }
    }
  }

  /// Best-effort delete. A file that cannot be deleted is harmless: nothing
  /// in the index vouches for it, so it is never read, and the next sweep
  /// tries again. Logged (type only) so a stuck file is diagnosable.
  Future<void> _deleteQuietly(FileSystemEntity entity) async {
    try {
      if (entity.existsSync()) await entity.delete(recursive: true);
    } on FileSystemException catch (e) {
      appLog('published copies: delete failed (${e.runtimeType})');
    }
  }
}

/// The platform could not provide the cache folder. Private and typed so
/// `FilePublishedFileCache._run` handles it like any other IO failure.
final class _NoCacheFolder implements Exception {
  const _NoCacheFolder();

  @override
  String toString() => 'NoCacheFolder';
}
