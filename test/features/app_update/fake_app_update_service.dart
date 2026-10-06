/// Shared test support: a scriptable [AppUpdateService] fake (S35).
///
/// Stands in for the Play-backed service so the controller's POLICY (when to
/// check, auto-start, observe, offer restart, stay silent on error) and the
/// banner's rendering are testable without the Play Store.
library;

import 'dart:async';

import 'package:pitaka/features/app_update/domain/app_update_policy.dart';
import 'package:pitaka/features/app_update/domain/app_update_service.dart';

/// Scriptable fake: set the knobs before the controller runs, count the
/// calls, emit install-state events on demand.
class FakeAppUpdateService implements AppUpdateService {
  FakeAppUpdateService({
    this.eligible = true,
    this.availability = AppUpdateAvailability.none,
    this.startResult = true,
    this.throwOnCheck,
    this.throwOnComplete,
  });

  /// Knob: what [isEligible] answers.
  bool eligible;

  /// Knob: what [check] returns.
  AppUpdateAvailability availability;

  /// Knob: what [startFlexibleDownload] answers.
  bool startResult;

  /// Knob: when set, [check] throws it (fail-safe path).
  Exception? throwOnCheck;

  /// Knob: when set, [completeUpdate] throws it (fail-safe path).
  Exception? throwOnComplete;

  int checkCalls = 0;
  int startCalls = 0;
  int completeCalls = 0;

  final StreamController<AppUpdateStatus> _statuses =
      StreamController<AppUpdateStatus>.broadcast();

  /// Pushes an install-state event at the controller.
  void emit(AppUpdateStatus status) => _statuses.add(status);

  @override
  Future<bool> isEligible() async => eligible;

  @override
  Future<AppUpdateAvailability> check() async {
    checkCalls++;
    final error = throwOnCheck;
    if (error != null) throw error;
    return availability;
  }

  @override
  Future<bool> startFlexibleDownload() async {
    startCalls++;
    return startResult;
  }

  @override
  Stream<AppUpdateStatus> get statusChanges => _statuses.stream;

  @override
  Future<void> completeUpdate() async {
    completeCalls++;
    final error = throwOnComplete;
    if (error != null) throw error;
  }

  /// Closes the event stream (test teardown).
  Future<void> dispose() => _statuses.close();
}
