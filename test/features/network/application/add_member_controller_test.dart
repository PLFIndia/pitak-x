import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/application/add_member_controller.dart';
import 'package:pitaka/features/network/application/network_controller.dart';
import 'package:pitaka/features/network/domain/descriptor_fetch_result.dart';
import 'package:pitaka/features/network/domain/entities/library_descriptor.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/network/domain/repositories/network_repository.dart';
import 'package:pitaka/features/network/domain/usecases/add_member_use_case.dart';
import 'package:pitaka/features/network/domain/value_objects/library_card_payload.dart';

/// Tests for [AddMemberController] (review M10/M12): the outcome is one
/// `AsyncValue`, a successful add re-reads the network window on its own
/// (no page cooperation), and a refused add surfaces the typed failure —
/// all through `ProviderContainer` overrides (AGENTS §4/§10).
void main() {
  const fp = 'adb28b53d57009ce04d4e0b28563ebcd395375c0d719fd53986908233687f664';
  const fpOther =
      '22c2231357479c9a7b9d2d98ffc544ef97fce94c974a3a6835cceb4352139f1e';
  const site = 'https://member.github.io/lib/';
  final card = LibraryCard.tryCreate(
    siteUrl: site,
    fingerprint: fp,
    name: 'Member Library',
  )!;

  late _FakeRepo repo;
  late ProviderContainer container;

  ProviderContainer buildContainer(DescriptorFetchResult fetch) {
    final c = ProviderContainer(
      overrides: [
        networkRepositoryProvider.overrideWith((ref) async => repo),
        addMemberUseCaseProvider.overrideWith(
          (ref) async => AddMemberUseCase(
            repository: repo,
            fetchDescriptor: (_) async => fetch,
            clock: () => 1000,
          ),
        ),
        clockProvider.overrideWithValue(() => 1000),
      ],
    );
    addTearDown(c.dispose);
    // autoDispose gotcha: keep listeners so neither controller is disposed
    // between awaits (the page would be watching both in production).
    c
      ..listen(addMemberControllerProvider, (_, _) {})
      ..listen(networkControllerProvider, (_, _) {});
    return c;
  }

  setUp(() => repo = _FakeRepo());

  test('starts idle: AsyncData(null)', () async {
    container = buildContainer(
      const DescriptorRefused(DescriptorRefusal.transport),
    );
    final state = await container.read(addMemberControllerProvider.future);
    expect(state, isNull);
  });

  test('a successful add exposes the saved row AND re-reads the network '
      'window without anyone popping a route (M10)', () async {
    container = buildContainer(
      const DescriptorFetched(
        LibraryDescriptor(
          fingerprint: fp,
          name: 'Member Library',
          siteUrl: site,
          updatedAt: 1,
        ),
      ),
    );
    // Let the window build once over the empty repository.
    final before = await container.read(networkControllerProvider.future);
    expect(before.rows, isEmpty);

    await container.read(addMemberControllerProvider.notifier).add(card);

    final state = container.read(addMemberControllerProvider);
    expect(state.hasValue, isTrue);
    final added = state.value!;
    expect(added, isA<MemberAdded>());
    final row = (added as MemberAdded).row;
    expect(row.siteUrl, site);
    expect(row.isMember, isTrue);
    expect(row.memberVerified, isTrue);

    // The window was invalidated by the controller: a fresh read sees the
    // new row. Before M10 this only happened when the page popped `true`.
    final after = await container.read(networkControllerProvider.future);
    expect(after.rows.map((r) => r.siteUrl), [site]);
  });

  test('a refused add exposes the typed failure; the window is NOT '
      're-read', () async {
    repo.rows = [
      const NetworkLibrary(
        id: 1,
        siteUrl: site,
        name: 'Existing',
        fingerprint: fpOther,
      ),
    ];
    container = buildContainer(
      const DescriptorRefused(DescriptorRefusal.httpStatus),
    );
    await container.read(networkControllerProvider.future);
    final loadsBefore = repo.loadAllCalls;

    await container.read(addMemberControllerProvider.notifier).add(card);

    final state = container.read(addMemberControllerProvider);
    expect(state.hasError, isTrue);
    expect(state.error, isA<ValidationFailure>());
    expect(
      AddMemberController.messageFor(state.error!),
      AddMemberUseCase.identityMismatchMessage,
    );
    // A failed add has nothing new to show, so the window is not
    // invalidated: re-reading it hits the cache. The ONE extra loadAll is
    // the use case's own duplicate scan, not a window rebuild.
    await container.read(networkControllerProvider.future);
    expect(
      repo.loadAllCalls - loadsBefore,
      1,
      reason: 'only the use case read the repository; the window did not',
    );
  });

  test('messageFor: user-facing message for ValidationFailure, a generic '
      'sentence for anything else (no storage diagnostics leak)', () {
    expect(
      AddMemberController.messageFor(const ValidationFailure('Nope.')),
      'Nope.',
    );
    expect(
      AddMemberController.messageFor(
        const StorageFailure('SqliteException(19): UNIQUE … https://x/'),
      ),
      'Could not add that library. Please try again.',
    );
    expect(
      AddMemberController.messageFor(StateError('boom')),
      'Could not add that library. Please try again.',
    );
  });

  test('a second add while one is running is ignored', () async {
    final gate = Completer<DescriptorFetchResult>();
    container = ProviderContainer(
      overrides: [
        networkRepositoryProvider.overrideWith((ref) async => repo),
        addMemberUseCaseProvider.overrideWith(
          (ref) async => AddMemberUseCase(
            repository: repo,
            fetchDescriptor: (_) => gate.future,
            clock: () => 1000,
          ),
        ),
        clockProvider.overrideWithValue(() => 1000),
      ],
    );
    addTearDown(container.dispose);
    container
      ..listen(addMemberControllerProvider, (_, _) {})
      ..listen(networkControllerProvider, (_, _) {});

    final notifier = container.read(addMemberControllerProvider.notifier);
    final first = notifier.add(card);
    // Let the first run reach its (gated) verification fetch. By then the
    // use case has already written the row once (it saves, THEN verifies).
    await pumpEventQueue();
    expect(container.read(addMemberControllerProvider).isLoading, isTrue);
    expect(repo.upserts, hasLength(1));

    // Second call returns immediately and does not start another use case:
    // no second write, state still loading.
    await notifier.add(card);
    expect(repo.upserts, hasLength(1));
    expect(container.read(addMemberControllerProvider).isLoading, isTrue);

    gate.complete(const DescriptorRefused(DescriptorRefusal.transport));
    await first;
    // A refused verification keeps the single write (unverified member).
    expect(repo.upserts, hasLength(1));
    expect(container.read(addMemberControllerProvider).hasValue, isTrue);
  });
}

/// In-memory repository fake that counts `loadAll` calls so the tests can
/// tell "the window re-read" from "the use case looked for duplicates".
class _FakeRepo implements NetworkRepository {
  List<NetworkLibrary> rows = [];
  final List<NetworkLibrary> upserts = [];
  int loadAllCalls = 0;
  int _nextId = 1;

  @override
  Future<List<NetworkLibrary>> loadAll() async {
    loadAllCalls++;
    return List.of(rows);
  }

  @override
  Future<Either<Failure, NetworkLibrary>> upsertBySiteUrl(
    NetworkLibrary row,
  ) async {
    rows.removeWhere((r) => r.siteUrl == row.siteUrl);
    final saved = row.copyWith(id: _nextId++);
    rows.add(saved);
    upserts.add(saved);
    return right(saved);
  }

  @override
  Future<int> count() async => rows.length;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected repository operation');
}
