/// How often a periodical appears (periodicals domain, pure Dart).
///
/// Persisted as `token` (a stable string, not the ordinal — same rule as
/// `AgeGroup`): renaming or reordering a value can never change a stored
/// row's meaning. The frequency drives the add-issue prefill
/// (`IssueCadence`): the next issue's date is the previous one plus one
/// step, so the user types less for a regular magazine.
library;

/// Publication cadence of a periodical (ADR 0013 D2).
enum PeriodicalFrequency {
  /// Every week.
  weekly('weekly', days: 7),

  /// Every two weeks.
  fortnightly('fortnightly', days: 14),

  /// Every month.
  monthly('monthly', months: 1),

  /// Every two months.
  bimonthly('bimonthly', months: 2),

  /// Every three months.
  quarterly('quarterly', months: 3),

  /// Once a year.
  annual('annual', months: 12),

  /// No fixed cadence: nothing is prefilled from the previous issue's date.
  irregular('irregular');

  const PeriodicalFrequency(this.token, {this.days, this.months});

  /// Stable storage/interchange token (lower-case letters only).
  final String token;

  /// Step between issues in whole days, for day-based cadences.
  final int? days;

  /// Step between issues in calendar months, for month-based cadences
  /// (the day of month is kept, clamped to the target month's length).
  final int? months;

  /// True when a next-issue date can be derived from the previous one.
  bool get hasStep => days != null || months != null;

  /// User-facing name for pickers and labels.
  String get label => switch (this) {
    PeriodicalFrequency.weekly => 'Weekly',
    PeriodicalFrequency.fortnightly => 'Fortnightly',
    PeriodicalFrequency.monthly => 'Monthly',
    PeriodicalFrequency.bimonthly => 'Every two months',
    PeriodicalFrequency.quarterly => 'Quarterly',
    PeriodicalFrequency.annual => 'Annual',
    PeriodicalFrequency.irregular => 'Irregular',
  };

  /// Tolerant parse (trim, lower-case; token or enum name); unknown or blank
  /// → null, never throws — a stored value from a newer build must not crash
  /// a read.
  static PeriodicalFrequency? fromToken(String? raw) {
    final key = raw?.trim().toLowerCase();
    if (key == null || key.isEmpty) return null;
    for (final f in PeriodicalFrequency.values) {
      if (f.token == key || f.name.toLowerCase() == key) return f;
    }
    return null;
  }
}
