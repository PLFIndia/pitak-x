import 'dart:convert';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/domain/github_upload_journal.dart';
import 'package:pitaka/features/publish/domain/github_upload_journal_store.dart';

/// In-memory [GitHubUploadJournalStore] (plan J8). Every write goes through
/// `toJson` → JSON text → `decode`, exactly like the file store, so a test
/// also proves the stored shape survives a round trip.
final class MemoryGitHubUploadJournalStore implements GitHubUploadJournalStore {
  /// Starts empty, or with [initial] already saved.
  MemoryGitHubUploadJournalStore([GitHubUploadJournal? initial])
    : _raw = initial == null ? null : jsonEncode(initial.toJson());

  String? _raw;

  /// Every successful write, in order.
  final List<GitHubUploadJournal> writes = [];

  /// How many times the journal was read.
  int reads = 0;

  /// Fails every write (typed, never a throw).
  bool failWrites = false;

  /// The saved journal (empty when nothing readable is stored).
  GitHubUploadJournal get saved {
    final raw = _raw;
    if (raw == null) return GitHubUploadJournal.empty;
    return GitHubUploadJournal.decode(jsonDecode(raw)) ??
        GitHubUploadJournal.empty;
  }

  @override
  Future<GitHubUploadJournal> read() async {
    reads++;
    return saved;
  }

  @override
  Future<Either<Failure, Unit>> write(GitHubUploadJournal journal) async {
    if (failWrites) return left(const StorageFailure('test: write refused'));
    _raw = jsonEncode(journal.toJson());
    writes.add(saved);
    return right(unit);
  }
}
