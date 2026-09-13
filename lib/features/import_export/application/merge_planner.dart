/// Merge-plan computation port (application layer, N10-c).
///
/// `planMerge` (`library/domain/merge/library_merge_engine.dart`) is pure
/// CPU work: after N10-b it is fast, but a 100,000 × 100,000 plan is still
/// hundreds of milliseconds, and on the UI isolate that is hundreds of
/// milliseconds of frozen frames. WHERE the plan runs is a platform concern
/// (worker isolate), and application code must not touch `dart:isolate`
/// (N14 gate: "application files perform no platform IO"). So this file only
/// names the contract; the production implementation lives in
/// `infrastructure/background_merge_planner.dart` and is injected from the
/// composition root, exactly like `LibraryJsonParser` / `PitakaJsonImporter`.
library;

import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/domain/merge/library_merge_engine.dart';

/// Computes a [MergePlan] for [incoming] against [local], possibly on another
/// isolate. `MergeLibraryUseCase` depends on this signature only; tests inject
/// a synchronous or recording planner.
typedef MergePlanner =
    Future<MergePlan> Function(List<Book> local, List<Book> incoming);
