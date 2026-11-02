/// Forwards "the app came back to the foreground" to the availability lane
/// (presentation; ADR 0019 Decision 9, plan C.4 "Retry triggers", AV17).
///
/// A thin relay, like `AppLockObserver`: it decides nothing. On resume it
/// tells the lane, which retries what is waiting (for example a set that
/// could not go out while the phone was offline).
///
/// **Not placed before plan S8.** S8 puts it next to `AppLockObserver` in
/// `main.dart`, together with the code that starts the lane. Even if it were
/// placed earlier, it does nothing while `availabilityLaneActivated` is
/// false, so it can never start the lane by itself.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/publish/application/availability/availability_auto_publisher.dart';

/// Wraps [child] and relays app resumes to the lane.
class AvailabilityLifecycleRelay extends ConsumerStatefulWidget {
  /// Creates the relay around [child].
  const AvailabilityLifecycleRelay({required this.child, super.key});

  /// The subtree to show (the relay renders nothing of its own).
  final Widget child;

  @override
  ConsumerState<AvailabilityLifecycleRelay> createState() =>
      _AvailabilityLifecycleRelayState();
}

class _AvailabilityLifecycleRelayState
    extends ConsumerState<AvailabilityLifecycleRelay>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (!ref.read(availabilityLaneActivatedProvider)) return;
    ref.read(availabilityAutoPublisherProvider.notifier).resumed();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
