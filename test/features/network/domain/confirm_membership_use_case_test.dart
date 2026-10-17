import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/network/domain/repositories/network_repository.dart';
import 'package:pitaka/features/network/domain/usecases/confirm_membership_use_case.dart';

/// Tests for [ConfirmMembershipUseCase] (libNetwork.md §5.6 step 4): the
/// user's answer moves the row's membership state through the repository.
void main() {
  const hubUrl = 'https://hub.github.io/pitak/';
  late _FakeRepo repo;
  late ConfirmMembershipUseCase useCase;

  setUp(() {
    repo = _FakeRepo([
      const NetworkLibrary(
        id: 7,
        siteUrl: hubUrl,
        name: 'The Hub',
        membership: MembershipState.pending,
      ),
    ]);
    useCase = ConfirmMembershipUseCase(repository: repo);
  });

  NetworkLibrary hub() => repo.rows.firstWhere((row) => row.siteUrl == hubUrl);

  test('pending → confirmed', () async {
    final result = await useCase(rowId: 7, decision: MembershipState.confirmed);
    expect(result.isRight(), isTrue);
    expect(hub().membership, MembershipState.confirmed);
  });

  test('pending → declined', () async {
    await useCase(rowId: 7, decision: MembershipState.declined);
    expect(hub().membership, MembershipState.declined);
  });

  test('declined → pending ("Reconsider" re-opens the question)', () async {
    await useCase(rowId: 7, decision: MembershipState.declined);
    final result = await useCase(rowId: 7, decision: MembershipState.pending);
    expect(result.isRight(), isTrue);
    expect(hub().membership, MembershipState.pending);
  });

  test('everything else about the row is untouched', () async {
    await useCase(rowId: 7, decision: MembershipState.confirmed);
    expect(hub().id, 7);
    expect(hub().name, 'The Hub');
    expect(hub().siteUrl, hubUrl);
    expect(hub().fetchStatus, FetchStatus.never);
  });

  test('a `none` decision is refused — a user action must never erase the '
      'signal back to "unknown"', () async {
    final result = await useCase(rowId: 7, decision: MembershipState.none);
    expect(result.isLeft(), isTrue);
    expect(result.swap().toNullable(), isA<ValidationFailure>());
    expect(hub().membership, MembershipState.pending); // unchanged
    expect(repo.upserts, isEmpty); // never even hit storage
  });

  test('a missing row is a typed NotFoundFailure', () async {
    final result = await useCase(
      rowId: 999,
      decision: MembershipState.confirmed,
    );
    expect(result.swap().toNullable(), isA<NotFoundFailure>());
  });

  test('a storage failure passes through as Left', () async {
    repo.upsertResult = left(const StorageFailure('disk gone'));
    final result = await useCase(rowId: 7, decision: MembershipState.confirmed);
    expect(result.isLeft(), isTrue);
  });
}

/// Minimal repository fake: only what the use case touches is real.
class _FakeRepo implements NetworkRepository {
  _FakeRepo(this.rows);

  List<NetworkLibrary> rows;
  final List<NetworkLibrary> upserts = [];
  Either<Failure, NetworkLibrary> upsertResult = right(
    const NetworkLibrary(siteUrl: ''),
  );

  @override
  Future<List<NetworkLibrary>> loadAll() async => List.of(rows);

  @override
  Future<Either<Failure, NetworkLibrary>> upsertBySiteUrl(
    NetworkLibrary row,
  ) async {
    upserts.add(row);
    if (upsertResult.isLeft()) return upsertResult;
    final index = rows.indexWhere((r) => r.siteUrl == row.siteUrl);
    if (index >= 0) rows[index] = row;
    return right(row);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected repository operation');
}
