import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/domain/descriptor_fetch_result.dart';
import 'package:pitaka/features/network/domain/entities/library_descriptor.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/network/domain/repositories/network_repository.dart';
import 'package:pitaka/features/network/domain/usecases/add_member_use_case.dart';
import 'package:pitaka/features/network/domain/value_objects/library_card_payload.dart';

/// Every §5.7 path of [AddMemberUseCase]: new row, bookmark upgrade,
/// identity contradiction, and the three verification-fetch outcomes.
void main() {
  const fpCard =
      'adb28b53d57009ce04d4e0b28563ebcd395375c0d719fd53986908233687f664';
  const fpOther =
      '22c2231357479c9a7b9d2d98ffc544ef97fce94c974a3a6835cceb4352139f1e';
  const site = 'https://member.github.io/lib/';

  /// Simple in-memory repo. The use case does its own merge decisions, so
  /// the fake only needs honest insert/replace-by-URL semantics.
  _FakeRepo repoWith([List<NetworkLibrary> seed = const []]) {
    final repo = _FakeRepo();
    var id = 1;
    for (final row in seed) {
      repo.rows[row.siteUrl] = row.copyWith(id: id++);
    }
    repo.nextId = id;
    return repo;
  }

  LibraryCard card({String fingerprint = fpCard}) => LibraryCard.tryCreate(
    siteUrl: site,
    fingerprint: fingerprint,
    name: 'Member Library',
  )!;

  test('a fresh card creates a verified member row', () async {
    final repo = repoWith();
    final fetched = <String>[];
    final useCase = AddMemberUseCase(
      repository: repo,
      fetchDescriptor: (url) async {
        fetched.add(url);
        return const DescriptorFetched(
          LibraryDescriptor(
            fingerprint: fpCard,
            name: 'Member Library',
            siteUrl: site,
            updatedAt: 1,
          ),
        );
      },
      clock: () => 1000,
    );

    final result = await useCase(card());
    final row = result.toNullable()!;
    expect(row.id, isNot(0));
    expect(row.source, NetworkSource.card);
    expect(row.isMember, isTrue);
    expect(row.memberVerified, isTrue);
    expect(row.fetchStatus, FetchStatus.ok);
    expect(row.fetchedAt, 1000);
    expect(row.fingerprint, fpCard);
    expect(row.name, 'Member Library');
    expect(row.createdAt, 1000);
    expect(row.sortOrder, 1); // first row → after max(0)
    expect(fetched, [
      '${site}library.json',
    ], reason: 'the fetch targets <siteUrl>library.json');
  });

  test('sortOrder appends after the existing maximum', () async {
    final repo = repoWith([
      const NetworkLibrary(siteUrl: 'https://a.github.io/', sortOrder: 4),
      const NetworkLibrary(siteUrl: 'https://b.github.io/', sortOrder: 2),
    ]);
    final useCase = AddMemberUseCase(
      repository: repo,
      fetchDescriptor: (_) async =>
          const DescriptorRefused(DescriptorRefusal.httpStatus),
      clock: () => 7,
    );
    final row = (await useCase(card())).toNullable()!;
    expect(row.sortOrder, 5);
    expect(row.createdAt, 7);
  });

  test('an existing bookmark row is upgraded in place', () async {
    final repo = repoWith([
      // A plain bookmark row (bookmark is the default source).
      const NetworkLibrary(
        siteUrl: site,
        name: 'Saved earlier',
        sortOrder: 9,
        createdAt: 42,
      ),
    ]);
    final useCase = AddMemberUseCase(
      repository: repo,
      fetchDescriptor: (_) async => const DescriptorFetched(
        LibraryDescriptor(
          fingerprint: fpCard,
          name: 'Member Library',
          siteUrl: site,
          updatedAt: 1,
        ),
      ),
      clock: () => 1000,
    );

    final row = (await useCase(card())).toNullable()!;
    expect(repo.rows, hasLength(1), reason: 'no second row for one URL');
    expect(row.isMember, isTrue);
    expect(row.fingerprint, fpCard); // null ⇒ set
    expect(row.source, NetworkSource.bookmark); // source stays (§5.7)
    expect(row.name, 'Saved earlier'); // a known name is kept
    expect(row.sortOrder, 9);
    expect(row.createdAt, 42);
    expect(row.memberVerified, isTrue);
  });

  test('a nameless existing row takes the card name', () async {
    final repo = repoWith([const NetworkLibrary(siteUrl: site)]);
    final useCase = AddMemberUseCase(
      repository: repo,
      fetchDescriptor: (_) async =>
          const DescriptorRefused(DescriptorRefusal.transport),
      clock: () => 1,
    );
    final row = (await useCase(card())).toNullable()!;
    expect(row.name, 'Member Library');
  });

  test(
    'SECURITY: a contradicting fingerprint is refused and changes nothing',
    () async {
      final repo = repoWith([
        const NetworkLibrary(
          siteUrl: site,
          name: 'Impostor target',
          fingerprint: fpOther, // a DIFFERENT identity lives at this URL
        ),
      ]);
      var fetches = 0;
      final useCase = AddMemberUseCase(
        repository: repo,
        fetchDescriptor: (_) async {
          fetches++;
          return const DescriptorRefused(DescriptorRefusal.httpStatus);
        },
        clock: () => 1,
      );

      final result = await useCase(card());
      expect(result.isLeft(), isTrue);
      final failure = result.swap().toNullable()!;
      expect(failure, isA<ValidationFailure>());
      expect(
        (failure as ValidationFailure).message,
        AddMemberUseCase.identityMismatchMessage,
      );
      // Nothing was written, nothing was fetched (fail closed BEFORE the
      // network): the row keeps its old identity and is not a member.
      final stored = repo.rows[site]!;
      expect(stored.isMember, isFalse);
      expect(stored.fingerprint, fpOther);
      expect(fetches, 0);
    },
  );

  test(
    'a matching existing fingerprint is kept and membership applied',
    () async {
      final repo = repoWith([
        const NetworkLibrary(siteUrl: site, fingerprint: fpCard),
      ]);
      final useCase = AddMemberUseCase(
        repository: repo,
        fetchDescriptor: (_) async =>
            const DescriptorRefused(DescriptorRefusal.timedOut),
        clock: () => 1,
      );
      final row = (await useCase(card())).toNullable()!;
      expect(row.fingerprint, fpCard);
      expect(row.isMember, isTrue);
    },
  );

  group('the verification fetch is best-effort (§5.7)', () {
    test('a refusal leaves the member saved but unverified', () async {
      final repo = repoWith();
      final useCase = AddMemberUseCase(
        repository: repo,
        fetchDescriptor: (_) async =>
            const DescriptorRefused(DescriptorRefusal.transport),
        clock: () => 5,
      );
      final result = await useCase(card());
      expect(result.isRight(), isTrue, reason: 'offline is NOT an error');
      final row = result.toNullable()!;
      expect(row.isMember, isTrue);
      expect(row.memberVerified, isFalse);
      expect(row.fetchStatus, FetchStatus.never);
    });

    test(
      'a fetched fingerprint that differs from the CARD flags a conflict',
      () async {
        // The card shown in person and the site's published descriptor
        // disagree — visible (D12 shape), never auto-merged, still not an
        // error that blocks the in-person add.
        final repo = repoWith();
        final useCase = AddMemberUseCase(
          repository: repo,
          fetchDescriptor: (_) async => const DescriptorFetched(
            LibraryDescriptor(
              fingerprint: fpOther,
              name: 'Someone else',
              siteUrl: site,
              updatedAt: 1,
            ),
          ),
          clock: () => 5,
        );
        final row = (await useCase(card())).toNullable()!;
        expect(row.memberVerified, isFalse);
        expect(row.fetchStatus, FetchStatus.identityConflict);
        expect(row.fingerprint, fpCard, reason: 'the scanned identity stays');
      },
    );
  });

  test('a repository failure crosses as a typed Left', () async {
    final repo = _FailingRepo();
    final useCase = AddMemberUseCase(
      repository: repo,
      fetchDescriptor: (_) async =>
          const DescriptorRefused(DescriptorRefusal.httpStatus),
      clock: () => 1,
    );
    final result = await useCase(card());
    expect(result.isLeft(), isTrue);
    expect(result.swap().toNullable(), isA<StorageFailure>());
  });
}

class _FakeRepo implements NetworkRepository {
  final rows = <String, NetworkLibrary>{};
  int nextId = 1;

  @override
  Future<List<NetworkLibrary>> loadAll() async => rows.values.toList();

  @override
  Future<Either<Failure, NetworkLibrary>> upsertBySiteUrl(
    NetworkLibrary row,
  ) async {
    final existing = rows[row.siteUrl];
    final saved = existing == null
        ? row.copyWith(id: nextId++)
        : row.copyWith(id: existing.id);
    rows[row.siteUrl] = saved;
    return right(saved);
  }

  @override
  Future<int> count() async => rows.length;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected repository operation');
}

class _FailingRepo implements NetworkRepository {
  @override
  Future<List<NetworkLibrary>> loadAll() async => const [];

  @override
  Future<Either<Failure, NetworkLibrary>> upsertBySiteUrl(
    NetworkLibrary row,
  ) async => left(const StorageFailure('disk on fire'));

  @override
  Future<int> count() async => 0;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected repository operation');
}
