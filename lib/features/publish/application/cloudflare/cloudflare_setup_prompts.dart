/// Prompt waits for Cloudflare setup, outside Riverpod and the queue.
///
/// Extracted from `cloudflare_connection_controller.dart` (fix-plan Phase 0.5)
/// so the state machine stays small. A prompt is one completer plus the serial
/// that lets the UI prove it is answering the prompt it is showing; no token,
/// account choice or text answer is retained here after it is delivered.
///
/// **Generations (fix-plan M11).** Riverpod keeps the notifier across a rebuild
/// but runs the previous build's `onDispose`. Without a generation, a rebuild
/// while a command waited in the queue left a completer nobody could complete:
/// the old run stayed "active" and every later command silently did nothing.
/// A new build starts a new generation, which cancels the old generation's
/// waits; a stale run can neither raise a prompt nor emit state.
library;

import 'dart:async';

import 'package:pitaka/features/publish/application/cloudflare/cloudflare_connection_ui.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_models.dart';

/// Owns the single pending prompt of one controller instance.
final class CloudflareSetupPrompts {
  /// Creates the prompts over the controller's state readers.
  ///
  /// [emit] applies a safe UI update; [current] returns the last emitted state
  /// (null before the first load). Both are supplied by the controller so this
  /// class never touches Riverpod.
  CloudflareSetupPrompts({
    required void Function(
      CloudflareConnectionUi Function(CloudflareConnectionUi) update,
    )
    emit,
    required CloudflareConnectionUi? Function() current,
  }) : _emit = emit,
       _current = current;

  final void Function(CloudflareConnectionUi Function(CloudflareConnectionUi))
  _emit;
  final CloudflareConnectionUi? Function() _current;

  Completer<Object?>? _input;
  int _serial = 0;
  int _generation = 0;

  /// The generation a new build owns.
  int get generation => _generation;

  /// Starts a new generation and cancels the previous one's pending wait.
  ///
  /// Called from `build()`, so a rebuild never leaves an old run waiting.
  int beginGeneration() {
    _generation++;
    cancel();
    return _generation;
  }

  /// True when [generation] is still the current one.
  bool isCurrent(int generation) => generation == _generation;

  /// Shows [prompt] and waits for its answer; null means the user cancelled.
  ///
  /// A stale [generation] returns null immediately and shows nothing.
  Future<T?> awaitInput<T>(
    CloudflareSetupPrompt prompt, {
    required int generation,
    List<CloudflareAccount> accounts = const [],
    String? initialValue,
    bool workerExists = false,
    bool verificationRequested = false,
    bool isActiveSite = false,
    String? message,
  }) async {
    if (!isCurrent(generation)) return null;
    final completer = Completer<Object?>();
    _input = completer;
    final serial = ++_serial;
    _emit(
      (current) => current.copyWith(
        phase: CloudflareConnectionPhase.awaitingInput,
        prompt: prompt,
        promptSerial: serial,
        promptInitialValue: initialValue,
        promptWorkerExists: workerExists,
        promptVerificationRequested: verificationRequested,
        promptIsActiveSite: isActiveSite,
        accounts: accounts,
        statusMessage: message,
      ),
    );
    final answer = await completer.future;
    // A rebuild while this wait was pending: the answer belongs to a run that
    // no longer owns the controller, so it must not move the new state.
    if (!isCurrent(generation)) return null;
    _emit(
      (current) => current.copyWith(
        phase: CloudflareConnectionPhase.working,
        prompt: null,
        accounts: const [],
      ),
    );
    return answer is T ? answer : null;
  }

  /// Delivers [answer] only to the prompt that produced [serial].
  void answer(Object? answer, int serial) {
    final current = _current();
    if (current == null ||
        current.phase != CloudflareConnectionPhase.awaitingInput ||
        current.promptSerial != serial) {
      return;
    }
    final input = _input;
    _input = null;
    input?.complete(answer);
  }

  /// Ends any pending wait with "cancelled" (a null answer).
  void cancel() {
    _input?.complete(null);
    _input = null;
  }
}
