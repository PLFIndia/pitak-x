import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/network/domain/library_move_candidate.dart';
import 'package:pitaka/features/network/domain/repositories/network_repository.dart';
import 'package:pitaka/features/network/domain/usecases/reconcile_library_move_use_case.dart';
import 'package:pitaka/features/network/domain/value_objects/geo_point.dart';

/// C10/R17 acceptance rules: ONE transactional merge/delete-plus-repoint,
/// the canonical row keeps its id/order/consent, the duplicate is deleted,
/// and a changed row fails closed with NOTHING written.
void main() {
  const fp = 'adb28b53d57009ce04d4e0b28563ebcd395375c0d719fd53986908233687f664';
  const oldSite = 'https://old.github.io/lib/';
  const newSite = 'https://new.github.io/lib/';

  GeoPoint point(double lat, double lng) => GeoPoint.tryCreate(lat, lng)!;

  NetworkLibrary canonical({int id = 7}) {
    final location = point(12.5, 77.5);
    return NetworkLibrary(
      id: id,
      siteUrl: oldSite,
      name: 'Saved name',
      fingerprint: fp,
      location: location,
      precision: LocationPrecision.approximate,
      isMember: true,
      memberVerified: true,
      membership: MembershipState.confirmed,
      confirmedByMember: true,
      listedByHubUrl: 'https://hub.github.io/x/',
      fetchStatus: FetchStatus.ok,
      fetchedAt: 100,
      createdAt: 42,
      sortOrder: 9,
    );
  }

  NetworkLibrary placeholder({int id = 8}) =>
      NetworkLibrary(id: id, siteUrl: newSite, createdAt: 50, sortOrder: 10);

  LibraryMoveCandidate candidate({bool hasFetchedFacts = true}) =>
      LibraryMoveCandidate(
        savedRowId: 7,
        savedSiteUrl: oldSite,
        savedName: 'Saved name',
        fetchedSiteUrl: newSite,
        fetchedName: 'New name',
        fingerprint: fp,
        fetchedLocation: point(1.5, 2.5),
        fetchedPrecision: LocationPrecision.exact,
        fetchedAt: 500,
        fetchedSource: NetworkSource.bookmark,
        hasFetchedFacts: hasFetchedFacts,
      );

  late _FakeRepo repo;
  late ReconcileLibraryMoveUseCase useCase;

  setUp(() {
    repo = _FakeRepo();
    useCase = ReconcileLibraryMoveUseCase(repository: repo, clock: () => 999);
  });

  test('use new address: repoints the canonical row and deletes the '
      'duplicate, preserving id, order and consent decisions', () async {
    repo.rows = [canonical(), placeholder()];

    final result = await useCase(
      candidate: candidate(),
      choice: LibraryMoveChoice.useNewAddress,
    );

    expect(result.isRight(), isTrue);
    final row = result.toNullable()!;
    expect(row.id, 7, reason: 'canonical id survives');
    expect(row.siteUrl, newSite, reason: 'row took the chosen address');
    expect(row.sortOrder, 9, reason: 'local order survives');
    expect(row.createdAt, 42);
    expect(row.isMember, isTrue);
    expect(row.memberVerified, isTrue);
    expect(row.membership, MembershipState.confirmed);
    expect(row.confirmedByMember, isTrue);
    expect(row.listedByHubUrl, 'https://hub.github.io/x/');
    expect(row.name, 'New name', reason: 'fresh remote name applied');
    expect(row.location!.lat, 1.5);
    expect(row.precision, LocationPrecision.exact);
    expect(row.fetchStatus, FetchStatus.ok);
    expect(row.fetchedAt, 999, reason: 'stamped with the decision clock');
    expect(row.fingerprint, fp);

    expect(repo.rows, hasLength(1), reason: 'duplicate deleted');
    expect(repo.rows.single.siteUrl, newSite);
    expect(repo.acceptCalls, 1);
  });

  test('keep saved address: deletes the duplicate and changes NOTHING on the '
      'kept row', () async {
    repo.rows = [canonical(), placeholder()];
    final before = canonical();

    final result = await useCase(
      candidate: candidate(),
      choice: LibraryMoveChoice.keepSavedAddress,
    );

    final row = result.toNullable()!;
    expect(row.id, 7);
    expect(row.siteUrl, oldSite, reason: 'address unchanged');
    // D11/L10: fresh facts belong to the OTHER address. Applying them here let
    // a public fingerprint rename or re-pin a row the user chose to keep.
    expect(row.name, before.name, reason: 'name unchanged');
    expect(row.location!.lat, before.location!.lat, reason: 'pin unchanged');
    expect(row.precision, before.precision);
    expect(row.fetchStatus, before.fetchStatus);
    expect(row.fetchedAt, before.fetchedAt, reason: 'no new fetch stamp');
    expect(repo.rows, hasLength(1));
    expect(repo.rows.single.siteUrl, oldSite);
    expect(repo.rows.single.name, before.name);
  });

  test('keep saved address never copies a spoofed pin or name', () async {
    repo.rows = [canonical(), placeholder()];

    final result = await useCase(
      candidate: LibraryMoveCandidate(
        savedRowId: 7,
        savedSiteUrl: oldSite,
        savedName: 'Saved name',
        fetchedSiteUrl: newSite,
        fetchedName: 'Spoofed name',
        fingerprint: fp,
        // A hostile descriptor claims a different pin.
        fetchedLocation: point(-1.0, -2.0),
        fetchedPrecision: LocationPrecision.exact,
        fetchedAt: 500,
      ),
      choice: LibraryMoveChoice.keepSavedAddress,
    );

    final row = result.toNullable()!;
    expect(row.name, 'Saved name');
    expect(row.location!.lat, 12.5);
    expect(row.precision, LocationPrecision.approximate);
  });

  test('a CARD offer carries no fetched facts: a null pin must not erase '
      'the stored one', () async {
    repo.rows = [canonical()];

    final result = await useCase(
      candidate: candidate(hasFetchedFacts: false),
      choice: LibraryMoveChoice.useNewAddress,
    );

    final row = result.toNullable()!;
    expect(row.siteUrl, newSite);
    expect(row.location!.lat, 12.5, reason: 'stored pin survives');
    expect(row.precision, LocationPrecision.approximate);
    expect(row.fetchStatus, FetchStatus.ok, reason: 'unchanged status');
    expect(row.fetchedAt, 100, reason: 'no fetch happened, no new stamp');
  });

  test('a candidate whose identity evidence changed since the decision is '
      'stale: NOTHING is written', () async {
    // The saved row was re-pointed/re-fetched to a different identity between
    // the offer and the decision.
    repo.rows = [canonical().copyWith(fingerprint: 'f' * 64), placeholder()];

    final result = await useCase(
      candidate: candidate(),
      choice: LibraryMoveChoice.useNewAddress,
    );

    expect(result.isLeft(), isTrue);
    expect(result.swap().toNullable(), isA<StaleStateFailure>());
    expect(repo.acceptCalls, 0);
    expect(repo.rows, hasLength(2));
  });

  test('a missing canonical row is a typed not-found failure', () async {
    repo.rows = [placeholder()];

    final result = await useCase(
      candidate: candidate(),
      choice: LibraryMoveChoice.useNewAddress,
    );

    expect(result.swap().toNullable(), isA<NotFoundFailure>());
    expect(repo.acceptCalls, 0);
  });

  test('a duplicate that already carries its own identity is an identity '
      'conflict, not a move (fail closed)', () async {
    repo.rows = [canonical(), placeholder().copyWith(fingerprint: 'b' * 64)];

    final result = await useCase(
      candidate: candidate(),
      choice: LibraryMoveChoice.useNewAddress,
    );

    expect(result.swap().toNullable(), isA<StaleStateFailure>());
    expect(repo.acceptCalls, 0);
  });

  test('a storage refusal crosses as the repository failure', () async {
    repo
      ..rows = [canonical(), placeholder()]
      ..failure = const StorageFailure('network move failed');

    final result = await useCase(
      candidate: candidate(),
      choice: LibraryMoveChoice.useNewAddress,
    );

    expect(result.swap().toNullable(), isA<StorageFailure>());
  });

  test('a candidate naming one address twice is refused before any read', () {
    const selfCandidate = LibraryMoveCandidate(
      savedRowId: 7,
      savedSiteUrl: oldSite,
      savedName: 'Saved name',
      fetchedSiteUrl: oldSite,
      fetchedName: 'Saved name',
      fingerprint: fp,
    );
    expect(selfCandidate.isDistinct, isFalse);
    final future = useCase(
      candidate: selfCandidate,
      choice: LibraryMoveChoice.useNewAddress,
    );
    expect(
      future.then((r) => r.swap().toNullable()),
      completion(isA<ValidationFailure>()),
    );
  });
}

/// In-memory repository: `loadAll` + the ONE transactional move write.
class _FakeRepo implements NetworkRepository {
  List<NetworkLibrary> rows = [];
  Failure? failure;
  int acceptCalls = 0;

  @override
  Future<List<NetworkLibrary>> loadAll() async => List.of(rows);

  @override
  Future<Either<Failure, LibraryMoveApplyResult>> acceptLibraryMove({
    required NetworkLibrary canonicalBaseline,
    required NetworkLibrary canonicalNext,
    NetworkLibrary? placeholderBaseline,
  }) async {
    acceptCalls++;
    if (failure case final f?) return left(f);
    final next = List.of(rows);
    if (placeholderBaseline != null) {
      next.removeWhere((r) => r.id == placeholderBaseline.id);
    }
    final index = next.indexWhere((r) => r.id == canonicalBaseline.id);
    next[index] = canonicalNext;
    rows = next;
    return right(
      LibraryMoveApplyResult(
        repointed: canonicalNext.siteUrl != canonicalBaseline.siteUrl,
        deletedPlaceholder: placeholderBaseline != null,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected repository operation');
}
