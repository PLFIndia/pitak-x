/// Where each guide's bottom button goes (presentation).
///
/// Two functions on purpose:
///  * [pageForGuideDestination] is a pure mapping from the domain enum to a
///    page widget — unit-testable by constructing widgets, no providers;
///  * [openGuideDestination] is the production opener that pushes the page.
///
/// `GuidePage` takes the opener as a parameter (defaulting to the real one),
/// so its tests inject a recording function and never pump the heavy target
/// pages.
library;

import 'package:flutter/material.dart';
import 'package:pitaka/features/guides/domain/guide.dart';
import 'package:pitaka/features/network/presentation/pages/network_page.dart';
import 'package:pitaka/features/publish/presentation/pages/publish_page.dart';
import 'package:pitaka/features/settings/presentation/pages/settings_page.dart';
import 'package:pitaka/features/vault/presentation/pages/vault_page.dart';

/// The page a guide's deep-link button opens. Exhaustive over the enum: a new
/// destination fails to compile until it is mapped.
Widget pageForGuideDestination(GuideDestination destination) =>
    switch (destination) {
      // `initialTab` defaults to the Connection tab.
      GuideDestination.publishConnection => const PublishPage(),
      GuideDestination.publishBasicInfo => const PublishPage(
        initialTab: PublishTab.basicInfo,
      ),
      GuideDestination.settingsData => const SettingsPage(
        initialTab: SettingsTab.data,
      ),
      GuideDestination.vault => const VaultPage(),
      GuideDestination.network => const NetworkPage(),
    };

/// Pushes the page for [destination] on top of the guide.
void openGuideDestination(BuildContext context, GuideDestination destination) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => pageForGuideDestination(destination),
    ),
  );
}
