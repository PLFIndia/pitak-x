/// On-device fixture seeder for the publish-optimisation measurements.
///
/// Plan `publishOptimisation_PLAN.md`, session S0 / B.1 item 3: the "before"
/// numbers must include a library of about 1,000 items with local covers,
/// because the per-publish cover work grows with the library. Typing 1,000
/// books by hand is impossible, so this journey writes them through the app's
/// OWN repository and cover store — the same code the forms use — and can
/// remove them again.
///
/// NEVER shipped: `integration_test/` is not part of the app bundle, and no
/// release build contains this file.
///
/// Run by hand (docs/RELEASING.md §6.1 style). Use the flavour that does NOT
/// hold your real library — the two flavours are separate apps with separate
/// data — or clear the fixture afterwards:
///
/// ```bash
/// # 1. seed (default: 1000 items, one generated cover each)
/// flutter test integration_test/publish_fixture_seed_test.dart \
///     --flavor fdroid -d <device-id> --no-uninstall \
///     --dart-define=fixtureItems=1000
///
/// # 2. measure (separate command, see the plan's B.1)
/// flutter run --profile --flavor fdroid \
///     -d <device-id> --dart-define=publishTimings=true
///
/// # 3. remove the fixture and its cover files
/// flutter test integration_test/publish_fixture_seed_test.dart \
///     --flavor fdroid -d <device-id> --no-uninstall \
///     --dart-define=fixtureAction=clear
/// ```
///
/// Why `--no-uninstall` (beginner note): when an integration test finishes,
/// `flutter test` UNINSTALLS the app by default — and uninstalling an Android
/// app deletes its data. Without the flag the 1,000 seeded items vanish the
/// moment the seeder reports success (plan A.6 #11).
///
/// The vault is created with the smoke passphrase (`smokePassphrase` in
/// `smoke_support.dart`); unlock the seeded app with that one.
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/main.dart' as app;

import 'smoke_support.dart';

/// Every generated title starts with this, so seeding is idempotent and
/// clearing can never touch a real book.
const String _titlePrefix = 'Publish fixture ';

/// How many items the fixture should hold (`--dart-define=fixtureItems=N`).
const int _itemCount = int.fromEnvironment('fixtureItems', defaultValue: 1000);

/// `seed` (default) or `clear`.
const String _action = String.fromEnvironment(
  'fixtureAction',
  defaultValue: 'seed',
);

/// How many rows go in one write. Keeps each statement's parameter count well
/// under SQLite's limit and keeps a failure cheap to retry.
const int _batchSize = 100;

/// A distinct 400×600 q80 JPEG, the exact shape the publish downscaler stores
/// (AGENTS: one image choke point), sized like a photograph.
///
/// Why noise (beginner note): a flat-colour test image compresses to about
/// 20 KB, while a real camera cover in this app averages about 146 KB (plan
/// A.1). A fixture of tiny images would make the "before" numbers look better
/// than reality, so each cover gets per-pixel noise and averages ~130 KB.
/// Each item's pixels differ, so no two blob hashes match and GitHub cannot
/// dedupe them.
Uint8List _coverFor(int index) {
  final image = img.Image(width: 400, height: 600);
  final random = Random(index);
  for (var y = 0; y < 600; y++) {
    for (var x = 0; x < 400; x++) {
      final noise = random.nextInt(110);
      image.setPixelRgb(
        x,
        y,
        ((x + y + index) % 200 + noise).clamp(0, 255),
        (80 + noise + x % 40).clamp(0, 255),
        (140 + y % 60 + noise ~/ 2).clamp(0, 255),
      );
    }
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 80));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('publish fixture: $_action ($_itemCount items)', (tester) async {
    await app.main();
    await waitForLibrary(tester);
    // The catalogue lives behind the vault's SQLCipher key, so it must be
    // open before any row can be written or read.
    await openVaultUnlocked(tester);

    final container = appContainer(tester);
    final items = await container.read(catalogueItemRepositoryProvider.future);
    final covers = await container.read(coverStoreProvider.future);

    final before = (await items.getAllForInterchange()).toNullable();
    expect(before, isNotNull, reason: 'could not read the catalogue');

    if (_action == 'clear') {
      final fixture = before!
          .where((item) => item.title.startsWith(_titlePrefix))
          .toList();
      for (final item in fixture) {
        // Cover first: deleting the row first would orphan the file, which is
        // exactly the clutter the measurement must not include.
        await covers.deleteFile(item.coverUrl);
        final deleted = await items.delete(item.id);
        expect(deleted.isRight(), isTrue, reason: 'delete failed: $deleted');
      }
      final after = (await items.getAllForInterchange()).toNullable()!;
      expect(
        after.where((item) => item.title.startsWith(_titlePrefix)),
        isEmpty,
      );
      return;
    }

    final alreadySeeded = before!
        .where((item) => item.title.startsWith(_titlePrefix))
        .length;
    if (alreadySeeded >= _itemCount) {
      // Idempotent: a second run on the same install adds nothing.
      return;
    }

    var inserted = 0;
    var batch = <CatalogueItem>[];
    for (var index = alreadySeeded; index < _itemCount; index++) {
      final coverRef = await covers.saveJpeg(_coverFor(index));
      batch.add(
        CatalogueItem(
          title: '$_titlePrefix${index.toString().padLeft(4, '0')}',
          author: 'Fixture Author',
          coverUrl: coverRef,
          addedDate: DateTime.now().millisecondsSinceEpoch,
          language: 'English',
        ),
      );
      if (batch.length >= _batchSize) {
        final result = await items.insertAll(batch);
        expect(result.isRight(), isTrue, reason: 'insertAll failed: $result');
        inserted += result.toNullable() ?? 0;
        batch = <CatalogueItem>[];
      }
    }
    if (batch.isNotEmpty) {
      final result = await items.insertAll(batch);
      expect(result.isRight(), isTrue, reason: 'insertAll failed: $result');
      inserted += result.toNullable() ?? 0;
    }

    final after = (await items.getAllForInterchange()).toNullable()!;
    expect(
      after.where((item) => item.title.startsWith(_titlePrefix)).length,
      _itemCount,
      reason: 'the fixture is not complete; re-run to top it up',
    );
    expect(inserted, greaterThan(0), reason: 'nothing was written');
  });
}
