/// Debug-only publish timing instrumentation (publish optimisation plan,
/// Phase 0 / session S0).
///
/// Why this exists (beginner note): before making publishing faster, we need to
/// know WHERE the time goes — reading the library, deciding covers, uploading,
/// or waiting for the host to serve the new files. [PublishTimingRecorder]
/// times each stage of ONE publish and hands the result to an optional
/// [PublishTimingSink].
///
/// Privacy rule (AGENTS.md §6.2): a mark carries a stage name and NUMBERS only
/// — milliseconds, counts, bytes, rounds. It never carries a file path, a URL,
/// a key, a token or a title, because these marks are written to the device
/// log. [PublishTimings.describe] is the only string this file produces, and it
/// is built from those numbers alone.
///
/// Cost in a release build is zero: the composition root supplies a null sink
/// there, and every recorder method returns immediately (plan S0: "in release
/// the sink is null and no timing code runs").
library;

/// The measured stages of one publish.
///
/// The names are stable: the log line and the plan's Appendix A refer to them.
enum PublishTimingStage {
  /// Strict reads of the local inputs (library, settings, posters).
  reads,

  /// Pages configuration plus the remote head/tree reconciliation. Also
  /// includes the pre-publish check of an unconfirmed earlier commit, because
  /// that check is part of establishing the baseline this publish builds on.
  /// On GitHub it carries `treeReads`: 0 when the branch head was unchanged
  /// and the recursive tree read was skipped (plan SP4), 1 otherwise.
  reconcile,

  /// Cover decisions, with counts of covers read and covers reused.
  ///
  /// NOTE: this mark is NESTED inside [build] (the section builder decides its
  /// covers before it emits files), so the two durations overlap. Read
  /// [coverDecisions] as "how much of build was covers".
  coverDecisions,

  /// Building the section bytes: catalogue JSON, viewer HTML, cover assembly.
  build,

  /// Uploading blobs that the host did not already hold (Cloudflare bucket;
  /// GitHub uploads inside [commit], so it reports no separate upload mark).
  upload,

  /// Creating the Worker version (Cloudflare only).
  deploy,

  /// Creating the commit (GitHub only). Its `bytes` are the uploaded bytes.
  commit,

  /// Polling the public site until it serves exactly the bytes just published.
  readBack,
}

/// One measured stage of one publish.
///
/// Every field except [stage] and [millis] is a coarse count that only the
/// caller that did the work can answer; null means "not applicable to this
/// stage" (for example, a commit publishes no read-back rounds).
final class PublishTimingMark {
  /// Creates a mark.
  const PublishTimingMark({
    required this.stage,
    required this.millis,
    this.coversRead,
    this.coversReused,
    this.bytes,
    this.rounds,
    this.treeReads,
  });

  /// Which stage this mark times.
  final PublishTimingStage stage;

  /// How long the stage took, in whole milliseconds (never negative).
  final int millis;

  /// Covers whose bytes had to be produced this run: a local cover file was
  /// read and re-encoded, or a remote cover was fetched. This is the number
  /// Phase 2 drives to zero for an unchanged library.
  final int? coversRead;

  /// Covers reused from the publish record without reading anything.
  final int? coversReused;

  /// Bytes uploaded during this stage.
  final int? bytes;

  /// Read-back rounds spent (one round = one pass over the pending files).
  final int? rounds;

  /// Recursive GitHub tree reads made while reconciling (plan SP4): 0 when
  /// the unchanged branch head let the publish skip it.
  final int? treeReads;
}

/// The marks of one publish, in the order they finished.
final class PublishTimings {
  /// Creates an immutable snapshot of [marks].
  PublishTimings({
    required this.operation,
    required List<PublishTimingMark> marks,
    required this.totalMillis,
  }) : marks = List.unmodifiable(marks);

  /// Which publish this was: `catalogue`, `events`, `availability` or
  /// `cloudflare`. A CONSTANT name, never a path or address.
  final String operation;

  /// The marks, in the order the stages finished.
  final List<PublishTimingMark> marks;

  /// Whole-run time, in milliseconds.
  final int totalMillis;

  /// The mark for [stage], or null when that stage did not run.
  PublishTimingMark? markFor(PublishTimingStage stage) {
    for (final mark in marks) {
      if (mark.stage == stage) return mark;
    }
    return null;
  }

  /// One log line: stage names and numbers only.
  ///
  /// Deliberately contains no path, URL, key, token or title — this string is
  /// the ONLY thing a release build ever could have logged (AGENTS.md §6.2).
  String describe() {
    final buffer = StringBuffer('publish timings $operation: total=')
      ..write('${totalMillis}ms');
    for (final mark in marks) {
      buffer
        ..write(' ${mark.stage.name}=')
        ..write('${mark.millis}ms');
      final facts = <String>[
        if (mark.coversRead case final value?) 'coversRead=$value',
        if (mark.coversReused case final value?) 'coversReused=$value',
        if (mark.bytes case final value?) 'bytes=$value',
        if (mark.rounds case final value?) 'rounds=$value',
        if (mark.treeReads case final value?) 'treeReads=$value',
      ];
      if (facts.isNotEmpty) buffer.write('(${facts.join(',')})');
    }
    return buffer.toString();
  }
}

/// Receives the timings of one finished publish.
///
/// The composition root supplies the real sink in debug builds (one `appLog`
/// line) and null in release builds, so callers must treat null as "do
/// nothing".
typedef PublishTimingSink = void Function(PublishTimings timings);

/// Times the stages of one publish.
///
/// Usage (beginner note): create ONE recorder per publish, ask [begin] for a
/// start stamp before a stage, and hand that stamp to [end] with the stage's
/// optional counts:
///
/// ```dart
/// final started = timings.begin();
/// await doTheWork();
/// timings.end(PublishTimingStage.build, started);
/// ```
///
/// [begin] returns null when recording is off, and [end] then does nothing —
/// so the "is this debug build" decision is made once, here, instead of at
/// every call site.
final class PublishTimingRecorder {
  /// Creates a recorder. A null [sink] disables it entirely.
  PublishTimingRecorder({
    required PublishTimingSink? sink,
    required this.operation,
    int Function()? clock,
  }) : _sink = sink,
       _clock = clock ?? _wallClock,
       _startedAt = sink == null ? 0 : (clock ?? _wallClock)();

  /// Wall-clock milliseconds. Only used when the caller injects no clock; the
  /// production wiring passes the app's clock port (plan G7).
  static int _wallClock() => DateTime.now().millisecondsSinceEpoch;

  final PublishTimingSink? _sink;
  final int Function() _clock;
  final int _startedAt;
  final List<PublishTimingMark> _marks = [];

  /// Which publish this recorder belongs to (`catalogue`, `events`,
  /// `availability`, `cloudflare`). A CONSTANT name, never a path or address.
  final String operation;

  /// True when a sink is wired (debug builds). False means every call below is
  /// a no-op and nothing is allocated.
  bool get enabled => _sink != null;

  /// Marks the start of a stage. Null when recording is off.
  int? begin() => enabled ? _clock() : null;

  /// Records [stage], which started at [startedAt] (from [begin]).
  ///
  /// Does nothing when [startedAt] is null or recording is off. A clock that
  /// moved backwards (a device time change) is clamped to 0 ms rather than
  /// reporting a negative duration.
  void end(
    PublishTimingStage stage,
    int? startedAt, {
    int? coversRead,
    int? coversReused,
    int? bytes,
    int? rounds,
    int? treeReads,
  }) {
    if (startedAt == null || !enabled) return;
    final elapsed = _clock() - startedAt;
    _marks.add(
      PublishTimingMark(
        stage: stage,
        millis: elapsed < 0 ? 0 : elapsed,
        coversRead: coversRead,
        coversReused: coversReused,
        bytes: bytes,
        rounds: rounds,
        treeReads: treeReads,
      ),
    );
  }

  /// Hands the finished marks to the sink. Safe to call from a `finally`: it
  /// reports at most once per recorder.
  void finish() {
    final sink = _sink;
    if (sink == null || _marks.isEmpty) return;
    final elapsed = _clock() - _startedAt;
    sink(
      PublishTimings(
        operation: operation,
        marks: _marks,
        totalMillis: elapsed < 0 ? 0 : elapsed,
      ),
    );
    // Nothing is reported twice, even if a caller finishes in error paths too.
    _marks.clear();
  }
}
