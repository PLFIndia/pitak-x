/// The trial's report writer (Cloudflare plan Part L.1).
///
/// Why a dedicated type (beginner note): the report is the ONLY thing that
/// leaves the trial, and it must never contain a token, a JWT, an authorization
/// header or a raw response body. Every line is built from fixed labels and
/// whitelisted values (numbers, booleans, enum names, safe headers), so a
/// careless `print(response.body)` cannot leak anything — there is no API here
/// that accepts a raw body.
library;

/// How one check ended.
enum TrialStatus {
  /// The check ran and the expected behaviour was observed.
  pass,

  /// The check ran and the expected behaviour was NOT observed.
  fail,

  /// The check could not run (a prerequisite failed, or it was disabled).
  skip,

  /// A measurement, not a pass/fail check.
  info,

  /// A decision the maintainer must record by hand (T14).
  manual,
}

/// Collects fixed-label report lines.
final class TrialReport {
  final List<String> _lines = [];
  final Map<String, TrialStatus> _status = {};

  /// Starts a titled section.
  void section(String title) => _lines.add('\n== $title ==');

  /// Records a pass/fail check.
  void check(
    String id,
    String label, {
    required bool pass,
    String detail = '',
  }) {
    _status[id] = pass ? TrialStatus.pass : TrialStatus.fail;
    _lines.add('$id $label: ${pass ? 'PASS' : 'FAIL'}${_suffix(detail)}');
  }

  /// Records a check that could not run.
  void skip(String id, String label, String reason) {
    _status[id] = TrialStatus.skip;
    _lines.add('$id $label: SKIP${_suffix(reason)}');
  }

  /// Records a measurement.
  void info(String id, String label, String detail) {
    _status[id] = TrialStatus.info;
    _lines.add('$id $label: INFO${_suffix(detail)}');
  }

  /// Records a decision the maintainer must make by hand.
  void manual(String id, String label, String detail) {
    _status[id] = TrialStatus.manual;
    _lines.add('$id $label: MANUAL${_suffix(detail)}');
  }

  /// True only when every check ran and no check failed.
  bool get passed =>
      !_status.values.contains(TrialStatus.fail) &&
      !_status.values.contains(TrialStatus.skip);

  /// The ids that failed, in insertion order.
  List<String> get failedIds => [
    for (final entry in _status.entries)
      if (entry.value == TrialStatus.fail) entry.key,
  ];

  /// The ids that did not run, in insertion order.
  List<String> get skippedIds => [
    for (final entry in _status.entries)
      if (entry.value == TrialStatus.skip) entry.key,
  ];

  /// The whole report, one line per entry.
  String render() {
    final buffer = StringBuffer()
      ..writeln('Pitak Cloudflare trial report')
      ..writeln('(fixed labels only: no token, JWT, header or raw body)');
    for (final line in _lines) {
      buffer.writeln(line);
    }
    buffer.writeln();
    if (failedIds.isNotEmpty) {
      buffer.writeln('RESULT: FAIL (${failedIds.join(', ')})');
    } else if (skippedIds.isNotEmpty) {
      buffer.writeln('RESULT: INCOMPLETE (${skippedIds.join(', ')})');
    } else {
      buffer.writeln('RESULT: PASS');
    }
    return buffer.toString();
  }

  static String _suffix(String detail) => detail.isEmpty ? '' : ' ($detail)';
}
