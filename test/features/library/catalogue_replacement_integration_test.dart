import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/catalogue_replacement_guard.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/vault/application/vault_session_controller.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';

import 'replacement_harness.dart';

const _book = Book(id: 7, bookUid: 'stable', title: 'Loaned');
const _loan = Loan(id: 1, bookId: 7, borrowerId: 1, lentDate: 1);

void main() {
  late ReplacementHarness h;
  setUp(() => h = ReplacementHarness());
  tearDown(() => h.close());

  test(
    'real merge preserves loan IDs and never recycles historical IDs',
    () async {
      await h.books.insert(_book);
      await h.books.insert(const Book(id: 500, title: 'Deleted long ago'));
      await h.books.delete(500);
      h.vault.loans.add(_loan);
      await h.initialize();
      final result = await h.overwrite([
        const Book(id: 7, title: 'New'), // ordered before the preserved row
        _book.copyWith(id: 99, title: 'Updated'),
      ]);
      expect(result.isRight(), isTrue);
      final books = (await h.books.getAll()).toNullable()!;
      expect(books.singleWhere((b) => b.bookUid == 'stable').id, 7);
      expect(books.singleWhere((b) => b.title == 'New').id, greaterThan(500));
      expect(h.vault.loans.single.bookId, 7);
      expect(h.vault.writes, 0);
      expect(File(h.store.dbPath).readAsBytesSync(), [1, 2, 3]);
      expect(h.store.readBlob(), 'synthetic.blob.only');
      expect((await h.overwrite([_book.copyWith(id: 99)])).isRight(), isTrue);
      expect((await h.books.getById(7)).toNullable()!.bookUid, 'stable');
    },
  );

  for (final returned in [false, true]) {
    test(
      'refuses missing ${returned ? 'returned' : 'active'} loan identity',
      () async {
        await h.books.insert(_book);
        h.vault.loans.add(returned ? _loan.copyWith(returnedDate: 2) : _loan);
        await h.initialize();
        final result = await h.overwrite([
          const Book(id: 7, bookUid: 'other', title: 'Substitution'),
        ]);
        expect(result.getLeft().toNullable(), isA<ValidationFailure>());
        expect((await h.books.getAll()).toNullable()!.single.bookUid, 'stable');
        expect(h.settings.id, 'local');
        expect(h.vault.writes, 0);
      },
    );
  }

  test(
    'locked vault refuses before writes, then unlock permits retry',
    () async {
      await h.books.insert(_book);
      h.vault.loans.add(_loan);
      await h.initialize(unlock: false);
      expect((await h.overwrite([_book])).isLeft(), isTrue);
      expect(h.settings.id, 'local');
      await h.session.unlock(ReplacementHarness.secret());
      expect((await h.overwrite([_book])).isRight(), isTrue);
    },
  );

  test(
    'no vault can replace; a verified empty vault can remove all books',
    () async {
      await h.books.insert(_book);
      await h.initialize(exists: false);
      expect((await h.overwrite([])).isRight(), isTrue);
      expect(
        (await h.session.enable(ReplacementHarness.secret())).isRight(),
        isTrue,
      );
      await h.books.insert(_book);
      expect((await h.overwrite([])).isRight(), isTrue);
      expect((await h.books.getAll()).toNullable(), isEmpty);
    },
  );

  test(
    'fresh vault read failure refuses; no cached snapshot fallback',
    () async {
      await h.books.insert(_book);
      await h.initialize();
      h.vault.readFailure = const StorageFailure('synthetic failure');
      expect(
        (await h.overwrite([])).getLeft().toNullable(),
        isA<StorageFailure>(),
      );
      expect((await h.books.getAll()).toNullable()!.single.id, 7);
      expect(h.session.isUnlocked, isFalse);
      expect(h.settings.id, 'local');
    },
  );

  test(
    'replacement sees loans added since the cached unlock snapshot',
    () async {
      await h.books.insert(_book);
      await h.initialize();
      h.vault.loans.add(_loan);
      expect((await h.overwrite([])).isLeft(), isTrue);
      expect((await h.books.getAll()).toNullable()!.single.id, 7);
    },
  );

  test('FIFO includes in-flight loan writes and their refresh', () async {
    await h.books.insert(_book);
    await h.initialize();
    final entered = Completer<void>();
    final release = Completer<void>();
    h.vault.onInsert = () async {
      entered.complete();
      await release.future;
    };
    final lending = h.session.addLoan(_loan);
    await entered.future;
    final replacement = h.overwrite([]);
    release.complete();
    expect((await lending).isRight(), isTrue);
    expect((await replacement).isLeft(), isTrue);
    expect((await h.books.getById(7)).toNullable(), isNotNull);
  });

  test('queued lending rechecks a book removed by replacement', () async {
    await h.books.insert(_book);
    await h.initialize();
    final entered = Completer<void>();
    final release = Completer<void>();
    h.vault.onRead = () async {
      h.vault.onRead = null;
      entered.complete();
      await release.future;
    };
    final replacement = h.overwrite([]);
    await entered.future;
    final lending = h.session.addLoan(_loan);
    release.complete();
    expect((await replacement).isRight(), isTrue);
    expect((await lending).getLeft().toNullable(), isA<NotFoundFailure>());
    expect(h.vault.writes, 0);
  });

  test('loan-based replacement waits for in-flight vault creation', () async {
    await h.books.insert(_book);
    await h.initialize(exists: false);
    final entered = Completer<void>();
    final release = Completer<void>();
    h.vault.onCreate = () async {
      entered.complete();
      await release.future;
    };
    final enabling = h.session.enable(ReplacementHarness.secret());
    await entered.future;
    h.vault.loans.add(_loan);
    final replacement = h.overwrite([]);
    release.complete();
    expect((await enabling).isRight(), isTrue);
    expect((await replacement).isLeft(), isTrue);
  });

  for (final invalidate in [false, true]) {
    test(
      '${invalidate ? 'invalidation' : 'lock'} during check rejects stale work',
      () async {
        await h.books.insert(_book);
        await h.initialize();
        final entered = Completer<void>();
        final release = Completer<void>();
        h.vault.onRead = () async {
          h.vault.onRead = null;
          entered.complete();
          await release.future;
        };
        final replacement = h.overwrite([]);
        await entered.future;
        if (invalidate) {
          h.container.invalidate(vaultSessionControllerProvider);
        } else {
          await h.session.lock();
        }
        release.complete();
        expect((await replacement).isLeft(), isTrue);
        expect((await h.books.getAll()).toNullable()!.single.id, 7);
        expect(h.settings.id, 'local');
      },
    );
  }

  test(
    'scope is immutable and expires when the protected action completes',
    () async {
      await h.initialize();
      CatalogueReplacementScope? saved;
      await h.session.protectReplacement((scope) async {
        saved = scope;
        expect(scope.isCurrent, isTrue);
        expect(
          () => scope.retainedLoanBookIds!.add(99),
          throwsUnsupportedError,
        );
        return right(unit);
      });
      expect(saved!.isCurrent, isFalse);
    },
  );

  test(
    'dangling borrower refuses rather than claiming intact retained loans',
    () async {
      await h.books.insert(_book);
      h.vault.loans.add(_loan);
      h.vault.borrowers.clear();
      await h.initialize();
      expect((await h.overwrite([_book])).isLeft(), isTrue);
      expect(h.settings.id, 'local');
    },
  );

  test(
    'catalogue insert failure rolls back old IDs and skips adoption',
    () async {
      await h.books.insert(_book);
      h.vault.loans.add(_loan);
      await h.initialize();
      await h.db.customStatement('''
      CREATE TRIGGER reject_new BEFORE INSERT ON books
      WHEN new.title = 'Rejected'
      BEGIN SELECT RAISE(ABORT, 'synthetic rejection'); END
    ''');
      expect(
        (await h.overwrite([
          _book,
          const Book(title: 'Rejected'),
        ])).getLeft().toNullable(),
        isA<StorageFailure>(),
      );
      expect((await h.books.getAll()).toNullable()!.single.id, 7);
      expect(h.settings.id, 'local');
      expect(h.vault.writes, 0);
    },
  );

  test(
    'full-vault replacement clears old session before queued work resumes',
    () async {
      await h.initialize();
      final entered = Completer<void>();
      final release = Completer<void>();
      final replacing = h.session.protectReplacement((scope) async {
        entered.complete();
        await release.future;
        return left<Failure, Unit>(const StorageFailure('partial restore'));
      }, replacingVault: true);
      await entered.future;
      var ran = false;
      final queued = h.session.protectReplacement((scope) async {
        ran = true;
        return right(unit);
      });
      release.complete();
      expect((await replacing).isLeft(), isTrue);
      expect((await queued).isLeft(), isTrue);
      expect(ran, isFalse);
      expect(h.session.isUnlocked, isFalse);
    },
  );

  for (final succeeds in [true, false]) {
    test('M02: a retained-vault replacement that endsSession locks afterwards '
        '(${succeeds ? 'success' : 'failure'}) so no cached store/key survives '
        'the generation switch', () async {
      await h.books.insert(_book);
      await h.initialize();
      expect(h.session.isUnlocked, isTrue);
      Set<int>? seen;
      final result = await h.session.protectReplacement((scope) async {
        seen = scope.retainedLoanBookIds;
        // Still unlocked INSIDE the action: the retained vault is copied
        // while the session (and its FIFO) owns it.
        expect(h.session.isUnlocked, isTrue);
        return succeeds
            ? right<Failure, Unit>(unit)
            : left<Failure, Unit>(const StorageFailure('build failed'));
      }, endsSession: true);
      expect(result.isRight(), succeeds);
      expect(seen, isNotNull); // a verified (empty) loan set was exposed
      expect(h.session.isUnlocked, isFalse);
      // A queued write must not run with the pre-replacement key.
      expect((await h.session.addLoan(_loan)).isLeft(), isTrue);
      expect(h.vault.writes, 0);
    });
  }

  test('M02: without endsSession a retained-vault replacement stays unlocked '
      '(merge-overwrite keeps the session)', () async {
    await h.books.insert(_book);
    await h.initialize();
    final result = await h.session.protectReplacement(
      (scope) async => right<Failure, Unit>(unit),
    );
    expect(result.isRight(), isTrue);
    expect(h.session.isUnlocked, isTrue);
  });

  for (final orphanDatabase in [false, true]) {
    test(
      'partial vault (${orphanDatabase ? 'DB' : 'blob'} only) refuses',
      () async {
        await h.books.insert(_book);
        await h.initialize(exists: false);
        if (orphanDatabase) {
          File(h.store.dbPath).writeAsBytesSync([1]);
        } else {
          h.store.writeBlob('synthetic.blob.only');
        }
        final result = await h.overwrite([]);
        expect(result.getLeft().toNullable(), isA<StorageFailure>());
        expect((await h.books.getById(7)).toNullable(), isNotNull);
        expect(h.settings.id, 'local');
      },
    );
  }
}
