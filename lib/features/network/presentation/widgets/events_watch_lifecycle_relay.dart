/// App-start owner of background event alerts (PLAN.md §5, §7).
///
/// Sits ABOVE `MaterialApp` next to `AppLockObserver` because it needs the
/// app's lifecycle, not a route's. It:
///  - bootstraps the plugins once after the first frame (dispatcher
///    registration, notifier init, cold-start tap payload);
///  - asks the controller to reconcile at start, on every unlock and on
///    every resume — never while the app is locked;
///  - shows the first-run offer (decision 1: default ON is OFFERED with an
///    explanation, never scheduled silently) once per app session, only
///    while unlocked and only while the setup phase is current;
///  - consumes one queued notification tap once the app is unlocked and
///    pushes the matching route, re-validating the payload against the
///    user's CURRENT saved rows (a stale or hostile payload falls back to the
///    Network tab).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/app_lock/app_lock_controller.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/widgets/root_navigator_key.dart';
import 'package:pitaka/features/network/application/events_watch/events_watch_controller.dart';
import 'package:pitaka/features/network/application/events_watch/events_watch_tap_resolver.dart';
import 'package:pitaka/features/network/application/events_watch/events_watch_view.dart';
import 'package:pitaka/features/network/application/network_controller.dart';
import 'package:pitaka/features/network/presentation/pages/network_page.dart';
import 'package:pitaka/features/network/presentation/pages/published_catalogue_page.dart';
import 'package:pitaka/features/network/presentation/widgets/events_watch_explanation_dialog.dart';

/// See the file header.
class EventsWatchLifecycleRelay extends ConsumerStatefulWidget {
  /// Creates the relay around [child].
  const EventsWatchLifecycleRelay({required this.child, super.key});

  /// The rest of the app.
  final Widget child;

  @override
  ConsumerState<EventsWatchLifecycleRelay> createState() =>
      _EventsWatchLifecycleRelayState();
}

class _EventsWatchLifecycleRelayState
    extends ConsumerState<EventsWatchLifecycleRelay>
    with WidgetsBindingObserver {
  bool _booted = false;
  bool _offerShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_boot()));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_booted) return;
    if (!ref.read(appLockControllerProvider).isUnlocked) return;
    unawaited(ref.read(eventsWatchControllerProvider.notifier).reconcile());
  }

  Future<void> _boot() async {
    if (!ref.read(eventsWatchSupportedProvider)) return;
    final bootstrap = ref.read(eventsWatchBootstrapProvider);
    final launchPayload = await bootstrap(
      (payload) =>
          ref.read(eventsWatchRouteQueueProvider.notifier).offer(payload),
    );
    if (!mounted) return;
    ref.read(eventsWatchRouteQueueProvider.notifier).offer(launchPayload);
    _booted = true;
    _onMaybeReady();
  }

  /// Runs reconciliation and consumes a queued tap once unlocked.
  void _onMaybeReady() {
    if (!_booted) return;
    if (!ref.read(appLockControllerProvider).isUnlocked) return;
    unawaited(ref.read(eventsWatchControllerProvider.notifier).reconcile());
    final payload = ref.read(eventsWatchRouteQueueProvider.notifier).take();
    if (payload != null) unawaited(_open(payload));
  }

  Future<void> _open(String payload) async {
    final navigator = ref.read(rootNavigatorKeyProvider).currentState;
    if (navigator == null) return;
    final window = await ref.read(networkControllerProvider.future);
    final row = resolveEventsWatchTap(payload, window.rows);
    if (!mounted) return;
    // Validated against current saved rows: anything else lands on the
    // Network tab (PLAN.md §7).
    final page = row == null
        ? const NetworkPage()
        : PublishedCataloguePage(row: row);
    await navigator.push<void>(MaterialPageRoute(builder: (_) => page));
  }

  Future<void> _maybeOffer(EventsWatchView view) async {
    if (_offerShown || view.phase != EventsWatchPhase.setupOffered) return;
    if (!ref.read(appLockControllerProvider).isUnlocked) return;
    final context = ref.read(rootNavigatorKeyProvider).currentContext;
    if (context == null) return;
    _offerShown = true;
    final choice = await showEventsWatchExplanationDialog(context);
    if (!mounted) return;
    final controller = ref.read(eventsWatchControllerProvider.notifier);
    switch (choice) {
      case EventsWatchExplanationChoice.turnOn:
        await controller.enable();
      case EventsWatchExplanationChoice.notNow:
        await controller.declineOffer();
      case null:
        break; // dismissed: offered again next session
    }
  }

  @override
  Widget build(BuildContext context) {
    ref
      ..listen<AsyncValue<EventsWatchView>>(eventsWatchControllerProvider, (
        _,
        next,
      ) {
        final view = next.valueOrNull;
        if (view != null) unawaited(_maybeOffer(view));
      })
      ..listen<AppLockState>(appLockControllerProvider, (previous, next) {
        final wasUnlocked = previous?.isUnlocked ?? false;
        if (next.isUnlocked && !wasUnlocked) _onMaybeReady();
      })
      ..listen<String?>(eventsWatchRouteQueueProvider, (_, payload) {
        if (payload != null) _onMaybeReady();
      });
    return widget.child;
  }
}
