import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/application/restore/recover_published_identity.dart';
import 'package:pitaka/features/publish/domain/restore/restore_identity_journal.dart';

import 'restore_use_case_harness.dart';

void main() {
  late RestoreUseCaseHarness h;
  setUp(() => h = RestoreUseCaseHarness());
  tearDown(() => h.dispose());

  test('a pre-commit journal is discarded without adopting identity', () async {
    h.journal.value = RestoreIdentityJournal(
      siteUrl: h.siteUrl,
      fingerprint: h.fingerprint,
    );

    final result = await h.recover.call();

    expect(result.toNullable(), PublishedIdentityRecoveryOutcome.discarded);
    expect(h.fingerprintWrites, 0);
    expect(h.journal.value, isNull);
  });

  test(
    'a different active target leaves recovery pending and untouched',
    () async {
      h.journal.value = const RestoreIdentityJournal(
        siteUrl: 'https://other.github.io/lib/',
      );

      final result = await h.recover.call();

      expect(result.toNullable(), PublishedIdentityRecoveryOutcome.pending);
      expect(h.fingerprintWrites, 0);
      expect(h.journal.value, isNotNull);
    },
  );
}
