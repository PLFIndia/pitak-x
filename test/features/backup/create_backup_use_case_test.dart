import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/backup/application/create_backup_use_case.dart';
import 'package:pitaka/features/backup/domain/backup_archive_builder.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/repositories/catalogue_item_repository.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/network/domain/repositories/network_repository.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/domain/repositories/periodical_repository.dart';
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
  }) => CreateBackupUseCase(
    books: _Books(),
    wishlist: _Wishlist(),
    periodicals: periodicals ?? _Periodicals(),
    writer: writer,
    workDir: 'unused-by-the-fake',
    namespace: namespace ?? _Namespace(right(identity)),
    network: network ?? _Network([row]),
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
      );
      final result = await failing();
      expect(result.isLeft(), isTrue);
    },
  );

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
}

class _Call {
  _Call({
    required this.identityJson,
    required this.networkJson,
    required this.periodicals,
  });
  final String? identityJson;
  final String? networkJson;
  final List<Periodical> periodicals;
}

/// Records the §3.4 entry strings; returns fixed bytes for everything else.
class _RecordingWriter implements BackupArchiveBuilder {
  final List<_Call> calls = [];

  @override
  Future<Uint8List> build({
    required List<CatalogueItem> books,
    required List<WishlistBook> wishlist,
    required List<Periodical> periodicals,
    required String workDir,
    required int exportedAt,
    required String? identityJson,
    required String? networkJson,
  }) async {
    calls.add(
      _Call(
        identityJson: identityJson,
        networkJson: networkJson,
        periodicals: periodicals,
      ),
    );
    return Uint8List.fromList(const [1, 2, 3]);
  }
}

class _Books implements CatalogueItemRepository {
  @override
  Future<Either<Failure, List<CatalogueItem>>> getAll() async =>
      right(const []);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FailingBooks implements CatalogueItemRepository {
  @override
  Future<Either<Failure, List<CatalogueItem>>> getAll() async =>
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
