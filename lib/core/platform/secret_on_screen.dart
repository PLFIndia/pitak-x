/// Marks "a secret is visible on screen" for the FLAG_SECURE policy
/// (presentation helper, AGENTS.md §6.6).
///
/// Why this exists: the window-level screen-capture protection is a single
/// decision (`screenCaptureProtectedProvider` in `core/di/providers.dart`)
/// fed by a counter of currently-visible secret entry widgets
/// (`PassphraseEntryVisibility`). Before this widget existed only the
/// passphrase field bumped that counter; the Google Books API-key dialog
/// showed a credential in clear text with no protection (review 2026-09-03).
///
/// Wrap ANY subtree that displays or collects a secret in [SecretOnScreen]
/// and the counter is incremented while it is mounted and decremented on
/// dispose — nothing else to remember at the call site. The bookkeeping rules
/// (post-frame scheduling, fail-closed on teardown) live in exactly one place.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/di/providers.dart';

/// Keeps the window screen-capture-protected while [child] is mounted.
class SecretOnScreen extends ConsumerStatefulWidget {
  /// Creates the marker around [child].
  const SecretOnScreen({required this.child, super.key});

  /// The subtree that shows or collects a secret.
  final Widget child;

  @override
  ConsumerState<SecretOnScreen> createState() => _SecretOnScreenState();
}

class _SecretOnScreenState extends ConsumerState<SecretOnScreen> {
  /// True once this widget has incremented the visibility count. The
  /// increment is deferred to post-frame (mutating a listened provider
  /// mid-build is forbidden), so dispose can race it; the flag keeps the
  /// increment/decrement balanced either way.
  bool _marked = false;

  /// Captured in initState because `ref` is unusable inside dispose(). The
  /// provider is keepAlive, so this notifier stays valid for the widget's
  /// whole life.
  late final PassphraseEntryVisibility _visibility;

  @override
  void initState() {
    super.initState();
    _visibility = ref.read(passphraseEntryVisibilityProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _marked) return;
      _marked = true;
      _visibility.markVisible();
    });
  }

  @override
  void dispose() {
    if (_marked) {
      // Deferred like the increment: dispose runs during tree finalization,
      // where provider modification is forbidden. A callback lost to process
      // teardown only ever leaves protection ON (fail closed).
      final visibility = _visibility;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        visibility.markHidden();
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
