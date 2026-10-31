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

/// Awaits [write] and shows the fixed message when it fails.
///
/// Fire-and-forget is safe here: the write itself never throws for expected
/// failures (the controller folds them into the `Either`).
void saveSetting(BuildContext context, Future<Either<Failure, Unit>> write) {
  unawaited(
    write.then((result) {
      if (result.isRight() || !context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(settingsSaveFailedMessage)));
    }),
  );
}
