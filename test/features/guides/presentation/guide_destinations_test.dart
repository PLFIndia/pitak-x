/// `pageForGuideDestination` is a pure mapping: constructed, never pumped
/// (the target pages need providers and are tested in their own suites).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/guides/domain/guide.dart';
import 'package:pitaka/features/guides/presentation/guide_destinations.dart';
import 'package:pitaka/features/network/presentation/pages/network_page.dart';
import 'package:pitaka/features/periodicals/presentation/pages/periodicals_page.dart';
import 'package:pitaka/features/publish/presentation/pages/publish_page.dart';
import 'package:pitaka/features/settings/presentation/pages/settings_page.dart';
import 'package:pitaka/features/vault/presentation/pages/vault_page.dart';

void main() {
  test('magazines → PeriodicalsPage', () {
    expect(
      pageForGuideDestination(GuideDestination.magazines),
      isA<PeriodicalsPage>(),
    );
  });

  test('publishConnection → PublishPage on its default (Connection) tab', () {
    final page = pageForGuideDestination(GuideDestination.publishConnection);
    expect(page, isA<PublishPage>());
    expect((page as PublishPage).initialTab, PublishTab.connection);
  });

  test('publishBasicInfo → PublishPage on the Basic info tab', () {
    final page = pageForGuideDestination(GuideDestination.publishBasicInfo);
    expect(page, isA<PublishPage>());
    expect((page as PublishPage).initialTab, PublishTab.basicInfo);
  });

  test('settingsData → SettingsPage on the Data tab', () {
    final page = pageForGuideDestination(GuideDestination.settingsData);
    expect(page, isA<SettingsPage>());
    expect((page as SettingsPage).initialTab, SettingsTab.data);
  });

  test('vault → VaultPage', () {
    expect(pageForGuideDestination(GuideDestination.vault), isA<VaultPage>());
  });

  test('network → NetworkPage on its default tab', () {
    final page = pageForGuideDestination(GuideDestination.network);
    expect(page, isA<NetworkPage>());
    expect((page as NetworkPage).initialTab, 0);
  });

  test('every destination is mapped (exhaustive switch, no throw)', () {
    for (final destination in GuideDestination.values) {
      expect(() => pageForGuideDestination(destination), returnsNormally);
    }
  });
}
