/// The one place a settings write reports failure to the user (fix-plan M8).
///
/// Setters now return `Either<Failure, Unit>` instead of publishing an
/// `AsyncError`, so a failed SAVE can never turn a loaded screen into
/// "Couldn't load settings". Each screen shows this fixed sentence instead.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';

/// Fixed copy for a failed settings write. Never a raw failure message.
const String settingsSaveFailedMessage =
    'Couldn’t save that setting. Try again.';

/// Awaits [write], shows the fixed message when it fails, and reports
/// whether the value was persisted (item 14: `EditableTextField` collapses
/// only on true, so an unsaved value is never displayed as saved).
///
/// The write never throws for expected failures (the controller folds them
/// into the `Either`).
Future<bool> saveSettingAndReport(
  BuildContext context,
  Future<Either<Failure, Unit>> write,
) async {
  final result = await write;
  if (result.isRight()) return true;
  if (context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text(settingsSaveFailedMessage)));
  }
  return false;
}

/// Fire-and-forget form of [saveSettingAndReport] for controls that have no
/// pending state of their own (switches, segmented buttons).
void saveSetting(BuildContext context, Future<Either<Failure, Unit>> write) {
  unawaited(saveSettingAndReport(context, write));
}
