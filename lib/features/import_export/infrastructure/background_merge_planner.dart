/// Runs the pure merge engine off the UI isolate (infrastructure, N10-c).
///
/// The production `MergePlanner` (see `application/merge_planner.dart`):
/// `planMerge` on a one-shot worker isolate via `Isolate.run`, wired into
/// `MergeLibraryUseCase` by the composition root (`core/di/providers.dart`).
///
/// What crosses the isolate boundary: two `List<Book>` in (plain fields and
/// enums — verified sendable), one `MergePlan` back. No closures over app
/// state, no `ref`, no secrets (catalogue rows are unencrypted by the M06b
/// decision).
///
/// Always hops, even for tiny inputs (D2-a, S28): spawning costs a few
/// milliseconds, invisible next to the file pick that precedes it, and one
/// code path is simpler to reason about than a size threshold.
library;

import 'dart:isolate';

import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/domain/merge/library_merge_engine.dart';

/// `planMerge` on a worker isolate; the result is identical to calling
/// `planMerge(local, incoming)` directly.
Future<MergePlan> planMergeInBackground(
  List<Book> local,
  List<Book> incoming,
) => Isolate.run(
  () => planMerge(local, incoming),
  debugName: 'pitaka-merge-plan',
);
