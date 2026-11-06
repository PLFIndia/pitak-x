import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/restore/restore_identity_journal.dart';
import 'package:pitaka/features/publish/infrastructure/prefs_restore_identity_journal_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('journal round-trips and clears', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = PrefsRestoreIdentityJournalStore(prefs);
    final journal = RestoreIdentityJournal(
      siteUrl: 'https://me.github.io/lib/',
      fingerprint: 'a' * 64,
    );

    expect((await store.save(journal)).isRight(), isTrue);
    final loaded = (await store.load()).toNullable();
    expect(loaded?.siteUrl, journal.siteUrl);
    expect(loaded?.fingerprint, journal.fingerprint);
    expect((await store.clear()).isRight(), isTrue);
    expect((await store.load()).toNullable(), isNull);
  });

  test('corrupt or hostile journal state fails closed', () async {
    SharedPreferences.setMockInitialValues({
      'publish_restore_identity_journal': '{not json',
    });
    final prefs = await SharedPreferences.getInstance();
    final store = PrefsRestoreIdentityJournalStore(prefs);
    expect((await store.load()).isLeft(), isTrue);

    await prefs.setString(
      'publish_restore_identity_journal',
      '{"schemaVersion":1,"siteUrl":"https://me.github.io/lib/",'
          '"fingerprint":"NOT-HEX"}',
    );
    expect((await store.load()).isLeft(), isTrue);
  });
}
