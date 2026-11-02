/// Storage port for the GitHub upload journal (publish domain, pure Dart;
/// plan J8 (a)).
///
/// A port (beginner note) is an interface the domain declares and the
/// infrastructure layer implements — here `FileGitHubUploadJournalStore`, one
/// JSON file next to the publish record. Tests use an in-memory fake.
///
/// The contract every implementation must keep:
///  - `read` never throws: nothing stored, a damaged file and a storage
///    error all read as [GitHubUploadJournal.empty]. For this journal that
///    is the safe direction — an empty journal only means sending more —
///    so, unlike the availability lane's store, "unreadable" needs no value
///    of its own;
///  - `read` decodes ONLY through `GitHubUploadJournal.decode`;
///  - `write` reports failure as a value, never by throwing.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/domain/github_upload_journal.dart';

/// Reads and writes the GitHub upload journal.
abstract interface class GitHubUploadJournalStore {
  /// The saved journal, or [GitHubUploadJournal.empty] when there is none or
  /// it cannot be read.
  Future<GitHubUploadJournal> read();

  /// Replaces the saved journal with [journal].
  Future<Either<Failure, Unit>> write(GitHubUploadJournal journal);
}
