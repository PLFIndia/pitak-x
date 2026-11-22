import 'dart:async';

import 'package:pitaka/features/periodicals/application/periodicals_controller.dart';

/// A Magazines list that reads nothing and hears nothing.
///
/// The real list listens to the app's "catalogue changed" signal, and
/// several providers listen to the list. With this in its place a test can
/// tell whether such a provider hears the signal ITSELF or only because the
/// Magazines list passes it on (review finding P3-M4, ADR 0031).
class QuietSeriesList extends PeriodicalsController {
  @override
  FutureOr<List<PeriodicalListEntry>> build() => const [];
}
