import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/backup/application/create_backup_use_case.dart';
import 'package:pitaka/features/backup/domain/backup_archive_builder.dart';
import 'package:pitaka/features/backup/domain/backup_identity.dart';
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
    workDir: 'unused-by-the-fake',
    namespace: namespace ?? _Namespace(right(identity)),
    network: network ?? _Network([row]),
    publishState: publishState ?? _PublishState(right(null)),
  );

  setUp(writer.calls.clear);

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
        workDir: 'unused-by-the-fake',
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
      workDir: 'unused-by-the-fake',
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
      workDir: 'unused-by-the-fake',
      namespace: _Namespace(right(identity)),
      network: _Network([row]),
      publishState: _PublishState(right(null)),
    );
    final r = (await withLeftOut()).getOrElse((f) => fail('left: $f'));
    expect(r.coversLeftOut, ['Big picture', 'Bigger picture']);
    expect(r.bytes, [1, 2, 3]);
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

class _Call {
  _Call({
    required this.identityJson,
    required this.networkJson,
    required this.periodicals,
    required this.publishStateJson,
  });
  final String? identityJson;
  final String? networkJson;
  final List<Periodical> periodicals;
  final String? publishStateJson;
}

/// Records the §3.4 entry strings; returns fixed bytes for everything else.
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
  }) async {
    calls.add(
      _Call(
        identityJson: identityJson,
        networkJson: networkJson,
        periodicals: periodicals,
        publishStateJson: publishStateJson,
      ),
    );
    return right(BuiltBackup(bytes: Uint8List.fromList(const [1, 2, 3])));
  }
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
  }) async => right(
    BuiltBackup(
      bytes: Uint8List.fromList(const [1, 2, 3]),
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
