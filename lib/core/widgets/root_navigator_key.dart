/// The root `Navigator`'s key, so an app-level owner (the event-alert tap
/// handler) can push a route from outside the widget tree.
///
/// A provider rather than a top-level global (AGENTS §7: no global mutable
/// singletons): tests get a fresh key per `ProviderContainer`.
library;

import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'root_navigator_key.g.dart';

/// Key attached to `MaterialApp.navigatorKey`.
@Riverpod(keepAlive: true)
GlobalKey<NavigatorState> rootNavigatorKey(RootNavigatorKeyRef ref) =>
    GlobalKey<NavigatorState>();
