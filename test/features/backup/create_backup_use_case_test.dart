import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/backup/application/create_backup_use_case.dart';
import 'package:pitaka/features/backup/domain/backup_archive_builder.dart';
import 'package:pitaka/features/backup/domain/backup_identity.dart';
import 'package:pitaka/features/backup/domain/backup_progress.dart';
import 'package:pitaka/features/backup/domain/backup_work_area.dart';
import 'package:pitaka/features/backup/domain/create_backup_result.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/repositories/catalogue_item_repository.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/network/domain/network_archive_codec.dart';
import 'package:pitaka/features/network/domain/repositories/network_repository.dart';
import 'package:pitaka/features/network/domain/value_objects/library_fingerprint.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/domain/repositories/periodical_repository.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_state_backup.dart';
import 'package:pitaka/features/publish/domain/publish_state_backup_codec.dart';
import 'package:pitaka/features/publish/domain/publish_state_backup_ports.dart';
import 'package:pitaka/features/settings/domain/library_namespace.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';
import 'package:pitaka/features/wishlist/domain/repositories/wishlist_repository.dart';

/// Tests for the §7 S6 gather logic: the library identity and the network
/// list are BEST-EFFORT entries — their failure must never block (or fail)
/// a catalogue backup, and the result flags must tell the truth about what
/// went in.
void main() {
  final writer = _RecordingWriter();
  // BR4: the folder a build works in comes from this port, and goes back
  // to it. A fake that records both, so no test touches the disk.
  final workArea = _WorkArea();

  const identity = LibraryIdentity(
    id: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    name: 'Meera Road',
  );
  const row = NetworkLibrary(id: 1, siteUrl: 'https://hub.github.io/x/');

  CreateBackupUseCase useCase({
    LibraryNamespace? namespace,
    NetworkRepository? network,
    PeriodicalRepository? periodicals,
    PublishStateBackupSource? publishState,
  }) => CreateBackupUseCase(
    books: _Books(),
    wishlist: _Wishlist(),
    periodicals: periodicals ?? _Periodicals(),
    writer: writer,
    workArea: workArea,
    namespace: namespace ?? _Namespace(right(identity)),
    network: network ?? _Network([row]),
    publishState: publishState ?? _PublishState(right(null)),
  );

  setUp(() {
    writer.calls.clear();
    workArea.reset();
  });

  test('happy path: both entries gathered and flagged', () async {
    final result = await useCase()();
    final r = result.getOrElse((f) => fail('unexpected left: $f'));
    expect(r.includesIdentity, isTrue);
    expect(r.includesNetwork, isTrue);

    final call = writer.calls.single;
    // identity.json carries the namespace values…
    expect(
      call.identityJson,
      contains('"libraryId":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"'),
    );
    expect(call.identityJson, contains('"libraryName":"Meera Road"'));
    // …and network.json the encoded rows under the §3.4 envelope.
    expect(call.networkJson, contains('"schemaVersion":1'));
    expect(call.networkJson, contains('https://hub.github.io/x/'));
  });

  test('a recovered published fingerprint reaches identity.json', () async {
    final fingerprint = 'f' * 64;
    final result = await useCase(
      namespace: _Namespace(
        right(
          LibraryIdentity(
            id: identity.id,
            name: identity.name,
            publishedFingerprint: fingerprint,
          ),
        ),
      ),
    )();
    expect(fingerprint, isNot(LibraryFingerprint.of(identity.id)));
    expect(result.isRight(), isTrue);
    final decoded = BackupIdentity.fromJson(writer.calls.single.identityJson!);
    expect(decoded?.publishedFingerprint, fingerprint);
  });

  test('an identity Left does NOT block the backup — it proceeds and says '
      'so', () async {
    final result = await useCase(
      namespace: _Namespace(left(const StorageFailure('prefs exploded'))),
    )();
    final r = result.getOrElse((f) => fail('unexpected left: $f'));
    expect(r.includesIdentity, isFalse);
    expect(r.includesNetwork, isTrue);
    expect(writer.calls.single.identityJson, isNull);
  });

  test('a throwing namespace is contained the same way', () async {
    final result = await useCase(namespace: _ThrowingNamespace())();
    final r = result.getOrElse((f) => fail('unexpected left: $f'));
    expect(r.includesIdentity, isFalse);
  });

  test('a network read failure skips network.json, keeping identity', () async {
    final result = await useCase(network: _ThrowingNetwork())();
    final r = result.getOrElse((f) => fail('unexpected left: $f'));
    expect(r.includesIdentity, isTrue);
    expect(r.includesNetwork, isFalse);
    expect(writer.calls.single.networkJson, isNull);
  });

  test('an empty network list still writes the entry (honest "[]")', () async {
    final result = await useCase(network: _Network(const []))();
    final r = result.getOrElse((f) => fail('unexpected left: $f'));
    expect(r.includesNetwork, isTrue);
    expect(writer.calls.single.networkJson, contains('"libraries":[]'));
  });

  test(
    'a books read failure is still a Left (the catalogue is the point)',
    () async {
      final failing = CreateBackupUseCase(
        books: _FailingBooks(),
        wishlist: _Wishlist(),
        periodicals: _Periodicals(),
        writer: writer,
        workArea: workArea,
        namespace: _Namespace(right(identity)),
        network: _Network([row]),
        publishState: _PublishState(right(null)),
      );
      final result = await failing();
      expect(result.isLeft(), isTrue);
      expect(writer.calls, isEmpty);
    },
  );

  // S5 (L5): a catalogue too large for the format is an EXPECTED refusal. It
  // must reach the caller as the typed failure (the page has specific copy),
  // never be re-wrapped as a generic StorageFailure.
  test('a too-large refusal is propagated, never masked', () async {
    final tooLarge = _TooLargeWriter();
    final failing = CreateBackupUseCase(
      books: _Books(),
      wishlist: _Wishlist(),
      periodicals: _Periodicals(),
      writer: tooLarge,
      workArea: workArea,
      namespace: _Namespace(right(identity)),
      network: _Network([row]),
      publishState: _PublishState(right(null)),
    );
    final result = await failing();
    expect(result.getLeft().toNullable(), isA<BackupTooLargeFailure>());
    expect(tooLarge.calls, 1);
  });

  // BR3: an optional entry the RESTORE reader would drop for its size is
  // left out by the use case and reported with the existing flags, so the
  // page never claims something travels inside that would not come back.
  group('BR3 — optional entries are checked against the reader caps', () {
    /// An identity whose encoded entry is exactly [bytes] long.
    LibraryIdentity identityOfEncodedSize(int bytes) {
      final overhead = BackupIdentity.encode(id: identity.id, name: '').length;
      return LibraryIdentity(id: identity.id, name: 'n' * (bytes - overhead));
    }

    /// A saved-libraries list whose encoded entry is exactly [bytes] long.
    List<NetworkLibrary> networkOfEncodedSize(int bytes) {
      NetworkLibrary rowWithUrl(String url) =>
          NetworkLibrary(id: 1, siteUrl: url);
      final overhead = NetworkArchiveCodec.encode([rowWithUrl('')]).length;
      return [rowWithUrl('u' * (bytes - overhead))];
    }

    test('identity.json exactly at its cap is inside', () async {
      final result = await useCase(
        namespace: _Namespace(
          right(identityOfEncodedSize(BackupIdentity.maxBytes)),
        ),
      )();
      final r = result.getOrElse((f) => fail('unexpected left: $f'));
      expect(r.includesIdentity, isTrue);
      expect(
        utf8.encode(writer.calls.single.identityJson!),
        hasLength(BackupIdentity.maxBytes),
      );
    });

    test('identity.json one byte over is left out and flagged; the backup '
        'still happens', () async {
      final result = await useCase(
        namespace: _Namespace(
          right(identityOfEncodedSize(BackupIdentity.maxBytes + 1)),
        ),
      )();
      final r = result.getOrElse((f) => fail('unexpected left: $f'));
      expect(r.includesIdentity, isFalse);
      expect(r.includesNetwork, isTrue);
      expect(writer.calls.single.identityJson, isNull);
    });

    test('the identity cap counts UTF-8 bytes, not characters', () async {
      // A name of two-byte letters: fewer characters than the cap, more
      // bytes than the cap.
      final result = await useCase(
        namespace: _Namespace(
          right(
            LibraryIdentity(
              id: identity.id,
              name: 'é' * (BackupIdentity.maxBytes ~/ 2),
            ),
          ),
        ),
      )();
      final r = result.getOrElse((f) => fail('unexpected left: $f'));
      expect(r.includesIdentity, isFalse);
      expect(writer.calls.single.identityJson, isNull);
    });

    test('network.json exactly at its cap is inside', () async {
      final result = await useCase(
        network: _Network(networkOfEncodedSize(NetworkArchiveCodec.maxBytes)),
      )();
      final r = result.getOrElse((f) => fail('unexpected left: $f'));
      expect(r.includesNetwork, isTrue);
      expect(
        utf8.encode(writer.calls.single.networkJson!),
        hasLength(NetworkArchiveCodec.maxBytes),
      );
    });

    test('network.json one byte over is left out and flagged; the backup '
        'still happens', () async {
      final result = await useCase(
        network: _Network(
          networkOfEncodedSize(NetworkArchiveCodec.maxBytes + 1),
        ),
      )();
      final r = result.getOrElse((f) => fail('unexpected left: $f'));
      expect(r.includesNetwork, isFalse);
      expect(r.includesIdentity, isTrue);
      expect(writer.calls.single.networkJson, isNull);
    });
  });

  // BR3 (decision D10): the builder names the items whose cover picture it
  // had to leave out; the use case hands the names on to the page.
  test('titles of left-out covers reach the result', () async {
    final withLeftOut = CreateBackupUseCase(
      books: _Books(),
      wishlist: _Wishlist(),
      periodicals: _Periodicals(),
      writer: _LeavingOutWriter(const ['Big picture', 'Bigger picture']),
      workArea: workArea,
      namespace: _Namespace(right(identity)),
      network: _Network([row]),
      publishState: _PublishState(right(null)),
    );
    final r = (await withLeftOut()).getOrElse((f) => fail('left: $f'));
    expect(r.coversLeftOut, ['Big picture', 'Bigger picture']);
    expect(r.sizeBytes, 3);
  });

  // BR4: the backup is a FILE in a private folder. The use case gets that
  // folder from the work area, and makes sure it does not stay behind when
  // no backup came out of it.
  group('BR4 — the work folder of a build', () {
    CreateBackupUseCase withWriter(BackupArchiveBuilder builder) =>
        CreateBackupUseCase(
          books: _Books(),
          wishlist: _Wishlist(),
          periodicals: _Periodicals(),
          writer: builder,
          workArea: workArea,
          namespace: _Namespace(right(identity)),
          network: _Network([row]),
          publishState: _PublishState(right(null)),
        );

    test('the builder works in a fresh run folder, and the path and size '
        'of the finished file reach the result', () async {
      final r = (await useCase()()).getOrElse((f) => fail('left: $f'));

      expect(workArea.created, hasLength(1));
      expect(writer.calls.single.workDir, workArea.created.single);
      expect(r.path, '${workArea.created.single}/$_fakeFileName');
      expect(r.sizeBytes, 3);
      // The caller owns the file now; the use case must not remove it.
      expect(workArea.discarded, isEmpty);
    });

    test('every build gets its own run folder', () async {
      await useCase()();
      await useCase()();

      expect(workArea.created, hasLength(2));
      expect(workArea.created.toSet(), hasLength(2));
      expect(writer.calls.map((c) => c.workDir), workArea.created);
    });

    test('a refused build discards its run folder', () async {
      final result = await withWriter(_TooLargeWriter())();

      expect(result.getLeft().toNullable(), isA<BackupTooLargeFailure>());
      expect(workArea.discarded, workArea.created);
      expect(workArea.created, hasLength(1));
    });

    test('a throwing builder gives a StorageFailure and discards its run '
        'folder', () async {
      final result = await withWriter(_ThrowingWriter())();

      expect(result.getLeft().toNullable(), isA<StorageFailure>());
      expect(workArea.discarded, workArea.created);
      expect(workArea.created, hasLength(1));
    });

    test('when no run folder can be made, the failure is returned and the '
        'builder is never called', () async {
      workArea.createFailure = const StorageFailure('no room');

      final result = await useCase()();

      final failure = result.getLeft().toNullable();
      expect(failure, isA<StorageFailure>());
      expect((failure! as StorageFailure).reason, 'no room');
      expect(writer.calls, isEmpty);
      expect(workArea.discarded, isEmpty);
    });

    test('a catalogue that cannot be read asks for no run folder', () async {
      final failing = CreateBackupUseCase(
        books: _FailingBooks(),
        wishlist: _Wishlist(),
        periodicals: _Periodicals(),
        writer: writer,
        workArea: workArea,
        namespace: _Namespace(right(identity)),
        network: _Network([row]),
        publishState: _PublishState(right(null)),
      );

      expect((await failing()).isLeft(), isTrue);
      expect(workArea.created, isEmpty);
    });

    test('discard hands the finished file back to the work area', () async {
      final create = useCase();
      final r = (await create()).getOrElse((f) => fail('left: $f'));

      await create.discard(r);

      expect(workArea.discarded, [r.path]);
    });

    test('discard does not throw when the work area could not remove the '
        'folder', () async {
      workArea.discardFailure = const StorageFailure('busy');

      await useCase().discard(
        const CreateBackupResult(
          path: '/somewhere/run-x/file.pitabak',
          sizeBytes: 1,
          includesIdentity: true,
          includesNetwork: true,
        ),
      );

      expect(workArea.discarded, ['/somewhere/run-x/file.pitabak']);
    });
  });

  // BR4 rider 3: the page wants to show "Cover 1,234 of 9,000". The use
  // case does not count anything itself; it hands the listener on.
  group('BR4 rider 3 — progress', () {
    BackupProgress progress(int done, int total) =>
        BackupProgress.tryCreate(coversDone: done, coversTotal: total)!;

    test('what the builder reports reaches the listener, in order', () async {
      final reporting = _ReportingWriter([progress(1, 3), progress(3, 3)]);
      final create = CreateBackupUseCase(
        books: _Books(),
        wishlist: _Wishlist(),
        periodicals: _Periodicals(),
        writer: reporting,
        workArea: workArea,
        namespace: _Namespace(right(identity)),
        network: _Network([row]),
        publishState: _PublishState(right(null)),
      );
      final seen = <String>[];

      final result = await create(onProgress: (p) => seen.add('$p'));

      expect(result.isRight(), isTrue);
      expect(seen, ['BackupProgress(1 of 3)', 'BackupProgress(3 of 3)']);
    });

    test('the builder gets the very listener the caller gave', () async {
      void listener(BackupProgress _) {}

      await useCase()(onProgress: listener);

      expect(writer.calls.single.onProgress, same(listener));
    });

    test('without a listener the builder gets none', () async {
      await useCase()();

      expect(writer.calls.single.onProgress, isNull);
    });
  });

  test('no cover left out is the normal case', () async {
    final r = (await useCase()()).getOrElse((f) => fail('left: $f'));
    expect(r.coversLeftOut, isEmpty);
  });

  test(
    'a periodicals read failure is a Left (no partial backup, W2)',
    () async {
      final result = await useCase(periodicals: _FailingPeriodicals())();
      expect(result.isLeft(), isTrue);
      // The writer was never reached: half a snapshot is not a backup.
      expect(writer.calls, isEmpty);
    },
  );

  test('the periodicals list reaches the writer (listAll entities)', () async {
    final result = await useCase()();
    result.getOrElse((f) => fail('unexpected left: $f'));
    expect(writer.calls.single.periodicals, hasLength(1));
    expect(writer.calls.single.periodicals.single.title, 'Chandamama');
  });

  group('plan CV6 — the website publishing record is best-effort too', () {
    final salt = List<int>.generate(16, (i) => i + 1);
    PublishStateBackup state({Map<String, String> files = const {}}) =>
        PublishStateBackup.tryCreate(
          coverSalt: salt,
          gitHubRecord: PublishManifest(
            repo: 'degt3rt/my-library',
            branch: 'main',
            fileShas: files,
          ),
        )!;

    test('a library without a website carries no entry and no note', () async {
      final r = (await useCase()()).getOrElse((f) => fail('left: $f'));
      expect(writer.calls.single.publishStateJson, isNull);
      expect(r.missingPublishState, isFalse);
    });

    test('a record is encoded with the codec and reads back', () async {
      final r = (await useCase(
        publishState: _PublishState(
          right(state(files: {'books.json': 'a' * 40})),
        ),
      )()).getOrElse((f) => fail('left: $f'));
      expect(r.missingPublishState, isFalse);
      final json = writer.calls.single.publishStateJson!;
      final decoded = PublishStateBackupCodec.decode(json)!;
      expect(decoded.coverSalt, salt);
      expect(decoded.gitHubRecord.repo, 'degt3rt/my-library');
      expect(decoded.gitHubRecord.shaFor('books.json'), 'a' * 40);
    });

    test(
      'an unreadable record does NOT block the backup and is named',
      () async {
        final r = (await useCase(
          publishState: _PublishState(left(const StorageFailure('x'))),
        )()).getOrElse((f) => fail('left: $f'));
        expect(writer.calls.single.publishStateJson, isNull);
        expect(r.missingPublishState, isTrue);
        expect(r.includesIdentity, isTrue);
      },
    );

    test('a throwing source is contained the same way', () async {
      final r = (await useCase(
        publishState: _ThrowingPublishState(),
      )()).getOrElse((f) => fail('left: $f'));
      expect(writer.calls.single.publishStateJson, isNull);
      expect(r.missingPublishState, isTrue);
    });

    test('an entry the restore reader would refuse is left out, never '
        'written (S5 rule)', () async {
      // A record claiming a path that is not Pitak's: encodable, but the
      // reader refuses it, so the writer must not emit it.
      final r = (await useCase(
        publishState: _PublishState(
          right(state(files: {'notes/private.txt': 'b' * 40})),
        ),
      )()).getOrElse((f) => fail('left: $f'));
      expect(writer.calls.single.publishStateJson, isNull);
      expect(r.missingPublishState, isTrue);
    });
  });
}

class _PublishState implements PublishStateBackupSource {
  _PublishState(this.result);
  final Either<Failure, PublishStateBackup?> result;

  @override
  Future<Either<Failure, PublishStateBackup?>> forBackup() async => result;
}

class _ThrowingPublishState implements PublishStateBackupSource {
  @override
  Future<Either<Failure, PublishStateBackup?>> forBackup() =>
      throw StateError('secure storage gone');
}

/// The file name the fake builders report (the real writer makes it from
/// the time of the backup).
const String _fakeFileName = 'Pitak-backup-20260101-000000.pitabak';

/// A work area without a disk: hands out made-up run folders and records
/// what was asked of it.
class _WorkArea implements BackupWorkArea {
  final List<String> created = [];
  final List<String> discarded = [];
  Failure? createFailure;
  Failure? discardFailure;

  void reset() {
    created.clear();
    discarded.clear();
    createFailure = null;
    discardFailure = null;
  }

  @override
  Future<Either<Failure, String>> createRun() async {
    final failure = createFailure;
    if (failure != null) return left(failure);
    final run = '/fake/backup_work/run-${created.length + 1}';
    created.add(run);
    return right(run);
  }

  @override
  Future<Either<Failure, Unit>> discard(String path) async {
    discarded.add(path);
    final failure = discardFailure;
    return failure == null ? right(unit) : left(failure);
  }

  @override
  Future<Either<Failure, Unit>> sweep() async => right(unit);
}

class _Call {
  _Call({
    required this.workDir,
    required this.identityJson,
    required this.networkJson,
    required this.periodicals,
    required this.publishStateJson,
    required this.onProgress,
  });
  final String workDir;
  final String? identityJson;
  final String? networkJson;
  final List<Periodical> periodicals;
  final String? publishStateJson;
  final BackupProgressListener? onProgress;
}

/// Records the §3.4 entry strings and the work folder; reports a finished
/// file of three bytes inside that folder (no file is really written).
class _RecordingWriter implements BackupArchiveBuilder {
  final List<_Call> calls = [];

  @override
  Future<Either<Failure, BuiltBackup>> build({
    required List<CatalogueItem> books,
    required List<WishlistBook> wishlist,
    required List<Periodical> periodicals,
    required String workDir,
    required int exportedAt,
    required String? identityJson,
    required String? networkJson,
    required String? publishStateJson,
    BackupProgressListener? onProgress,
  }) async {
    calls.add(
      _Call(
        workDir: workDir,
        identityJson: identityJson,
        networkJson: networkJson,
        periodicals: periodicals,
        publishStateJson: publishStateJson,
        onProgress: onProgress,
      ),
    );
    return right(BuiltBackup(path: '$workDir/$_fakeFileName', sizeBytes: 3));
  }
}

/// Builds fine and reports [reports] on the way, like the real writer does
/// while it packs cover pictures (BR4 rider 3).
class _ReportingWriter implements BackupArchiveBuilder {
  _ReportingWriter(this.reports);
  final List<BackupProgress> reports;

  @override
  Future<Either<Failure, BuiltBackup>> build({
    required List<CatalogueItem> books,
    required List<WishlistBook> wishlist,
    required List<Periodical> periodicals,
    required String workDir,
    required int exportedAt,
    required String? identityJson,
    required String? networkJson,
    required String? publishStateJson,
    BackupProgressListener? onProgress,
  }) async {
    for (final report in reports) {
      onProgress?.call(report);
    }
    return right(BuiltBackup(path: '$workDir/$_fakeFileName', sizeBytes: 3));
  }
}

/// Fails the way a real build does when a file cannot be read or written.
class _ThrowingWriter implements BackupArchiveBuilder {
  @override
  Future<Either<Failure, BuiltBackup>> build({
    required List<CatalogueItem> books,
    required List<WishlistBook> wishlist,
    required List<Periodical> periodicals,
    required String workDir,
    required int exportedAt,
    required String? identityJson,
    required String? networkJson,
    required String? publishStateJson,
    BackupProgressListener? onProgress,
  }) => throw StateError('disk went away');
}

/// Builds fine, but reports cover pictures it had to leave out (D10).
class _LeavingOutWriter implements BackupArchiveBuilder {
  _LeavingOutWriter(this.coversLeftOut);
  final List<String> coversLeftOut;

  @override
  Future<Either<Failure, BuiltBackup>> build({
    required List<CatalogueItem> books,
    required List<WishlistBook> wishlist,
    required List<Periodical> periodicals,
    required String workDir,
    required int exportedAt,
    required String? identityJson,
    required String? networkJson,
    required String? publishStateJson,
    BackupProgressListener? onProgress,
  }) async => right(
    BuiltBackup(
      path: '$workDir/$_fakeFileName',
      sizeBytes: 3,
      coversLeftOut: coversLeftOut,
    ),
  );
}

class _TooLargeWriter implements BackupArchiveBuilder {
  int calls = 0;

  @override
  Future<Either<Failure, BuiltBackup>> build({
    required List<CatalogueItem> books,
    required List<WishlistBook> wishlist,
    required List<Periodical> periodicals,
    required String workDir,
    required int exportedAt,
    required String? identityJson,
    required String? networkJson,
    required String? publishStateJson,
    BackupProgressListener? onProgress,
  }) async {
    calls++;
    return left(const BackupTooLargeFailure('itemKindsTooLarge'));
  }
}

class _Books implements CatalogueItemRepository {
  @override
  Future<Either<Failure, List<CatalogueItem>>> getAll() async =>
      right(const []);
  @override
  Future<Either<Failure, List<CatalogueItem>>> getAllForInterchange() async =>
      right(const []);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FailingBooks implements CatalogueItemRepository {
  @override
  Future<Either<Failure, List<CatalogueItem>>> getAll() async =>
      left(const StorageFailure('db gone'));
  @override
  Future<Either<Failure, List<CatalogueItem>>> getAllForInterchange() async =>
      left(const StorageFailure('db gone'));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Wishlist implements WishlistRepository {
  @override
  Future<Either<Failure, List<WishlistBook>>> getAll() async => right(const []);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Periodicals implements PeriodicalRepository {
  @override
  Future<Either<Failure, List<PeriodicalSummary>>> listAll() async => right([
    const PeriodicalSummary(
      periodical: Periodical(title: 'Chandamama', periodicalUid: 'puid-1'),
      issueCount: 0,
    ),
  ]);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FailingPeriodicals implements PeriodicalRepository {
  @override
  Future<Either<Failure, List<PeriodicalSummary>>> listAll() async =>
      left(const StorageFailure('db gone'));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Namespace implements LibraryNamespace {
  _Namespace(this._result);
  final Either<Failure, LibraryIdentity> _result;
  @override
  Future<Either<Failure, LibraryIdentity>> current() async => _result;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ThrowingNamespace implements LibraryNamespace {
  @override
  Future<Either<Failure, LibraryIdentity>> current() =>
      throw StateError('controller disposed');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Network implements NetworkRepository {
  _Network(this.rows);
  final List<NetworkLibrary> rows;
  @override
  Future<List<NetworkLibrary>> loadAll() async => List.of(rows);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ThrowingNetwork implements NetworkRepository {
  @override
  Future<List<NetworkLibrary>> loadAll() =>
      throw StateError('database is closed');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
