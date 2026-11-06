import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/network/infrastructure/published_catalogue_codec.dart';
import 'package:pitaka/features/publish/application/restore/pre_restore_publish_guard.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/restore/restore_identity_journal.dart';
import 'package:pitaka/features/publish/domain/site/published_site_verifier.dart';

import 'restore_use_case_harness.dart';

void main() {
  late RestoreUseCaseHarness h;
  late PreRestorePublishGuard guard;
  late PublishTarget target;

  setUp(() {
    h = RestoreUseCaseHarness();
    target = GitHubPublishTarget.create('me/lib')!;
    guard = PreRestorePublishGuard(
      items: h.fixture.books,
      periodicals: h.fixture.periodicals,
      journal: h.journal,
      reader: h.reader,
      decode: (bytes) async => const PublishedCatalogueCodec().decode(bytes),
    );
  });
  tearDown(() => h.dispose());

  test('pending identity recovery blocks every publish', () async {
    h.journal.value = RestoreIdentityJournal(
      siteUrl: h.siteUrl,
      fingerprint: h.fingerprint,
    );

    final result = await guard.call(target);

    expect(result.isLeft(), isTrue);
  });

  test(
    'empty local catalogue plus non-empty remote catalogue blocks',
    () async {
      h.reader.outcome = PublishedSiteReadBody(
        utf8.encode(
          jsonEncode({
            'schemaVersion': 1,
            'books': [
              {'title': 'Recovery book'},
            ],
          }),
        ),
      );

      final result = await guard.call(target);

      expect(result.isLeft(), isTrue);
    },
  );

  test('an unreadable remote catalogue is not treated as empty', () async {
    h.reader.outcome = const PublishedSiteReadUnreadable();

    final result = await guard.call(target);

    expect(result.isLeft(), isTrue);
  });

  test('an actually absent remote catalogue allows a first publish', () async {
    h.reader.outcome = const PublishedSiteReadAbsent();

    final result = await guard.call(target);

    expect(result.isRight(), isTrue);
  });

  test('a valid empty remote catalogue allows publish', () async {
    h.reader.outcome = PublishedSiteReadBody(
      utf8.encode(jsonEncode({'schemaVersion': 1, 'books': <dynamic>[]})),
    );

    final result = await guard.call(target);

    expect(result.isRight(), isTrue);
  });

  test('non-empty local catalogue needs no remote recovery check', () async {
    await h.fixture.books.insert(const CatalogueItem(title: 'Local'));
    h.reader.outcome = const PublishedSiteReadUnreadable();

    final result = await guard.call(target);

    expect(result.isRight(), isTrue);
  });
}
