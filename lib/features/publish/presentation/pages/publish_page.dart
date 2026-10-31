/// Publish hub: hosting connections, public library info, and event posters.
///
/// The page is only a tab shell. Provider orchestration and dialog plumbing
/// live in `ConnectionTab` and the two connection controllers (S0/S7).
library;

import 'package:flutter/material.dart';
import 'package:pitaka/features/events/presentation/pages/events_page.dart';
import 'package:pitaka/features/publish/presentation/widgets/basic_info_tab.dart';
import 'package:pitaka/features/publish/presentation/widgets/connection_tab.dart';

/// Tabs of the publish hub, in order.
enum PublishTab {
  /// GitHub / Cloudflare connection + target.
  connection,

  /// Library name + public contact info.
  basicInfo,

  /// Event posters.
  events,
}

/// The publish hub screen.
class PublishPage extends StatelessWidget {
  /// Creates the publish hub, optionally opening on [initialTab].
  const PublishPage({this.initialTab = PublishTab.connection, super.key});

  /// Which tab to show first.
  final PublishTab initialTab;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: PublishTab.values.length,
      initialIndex: initialTab.index,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Publish to web'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Connection'),
              Tab(text: 'Basic info'),
              Tab(text: 'Events'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [ConnectionTab(), BasicInfoTab(), EventsView()],
        ),
      ),
    );
  }
}
