/// File-backed GitHub upload journal (infrastructure; plan J8 (a)).
///
/// Plain JSON at `<app documents>/github_upload_journal.json`, next to the
/// publish record (`FilePublishManifestStore`), written the same way: to a
/// temporary file that is then renamed over the real one, so a crash
/// mid-write leaves the old journal or the new one, never half of one.
///
/// Why a file and not SharedPreferences (beginner note): a large first
/// publish can remember thousands of blob shas (about 1 MB at the cap), and
/// the journal is saved every few seconds while it uploads. SharedPreferences
/// rewrites ALL of the app's preferences on every save; a file of its own
/// only rewrites itself.
///
/// It holds public data only — repository names, blob shas of files being
/// published, times (AGENTS.md §6.3 keeps secrets out of plain storage; there
/// are none here). Every read problem reads as "nothing remembered", which
/// for this journal is the safe direction (the store port explains why).
library;

import 'dart:convert';
import 'dart:io';

import 'package:fpdart/fpdart.dart';
import 'package:path/path.dart' as p;
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/platform/app_log.dart';
import 'package:pitaka/features/publish/domain/github_upload_journal.dart';
import 'package:pitaka/features/publish/domain/github_upload_journal_store.dart';

/// Reads and writes the journal in the app documents directory.
final class FileGitHubUploadJournalStore implements GitHubUploadJournalStore {
  /// Creates the store. [directory] is resolved on first use, so building
  /// the store (inside the GitHub API provider) touches no platform channel.
  FileGitHubUploadJournalStore({required Future<String> Function() directory})
    : _directory = directory;

  final Future<String> Function() _directory;

  static const String _fileName = 'github_upload_journal.json';

  /// Suffix of the file being written; only exists until the rename.
  static const String _tempSuffix = '.tmp';

  /// The largest file read. The journal's caps keep it near 1 MB; anything
  /// much larger cannot be a journal this build wrote.
  static const int maxFileBytes = 4 * 1024 * 1024;

  /// Fixed, path-free failure: the error text of a file operation can
  /// contain a filesystem path.
  static const Failure _saveFailed = StorageFailure(
    'Could not save the GitHub upload journal.',
  );

  @override
  Future<GitHubUploadJournal> read() async {
    try {
      final file = File(p.join(await _directory(), _fileName));
      if (!file.existsSync()) return GitHubUploadJournal.empty;
      if (await file.length() > maxFileBytes) {
        appLog('GitHub upload journal ignored: too large');
        return GitHubUploadJournal.empty;
      }
      final journal = GitHubUploadJournal.decode(
        jsonDecode(await file.readAsString()),
      );
      if (journal == null) appLog('GitHub upload journal ignored: damaged');
      return journal ?? GitHubUploadJournal.empty;
    } on Exception catch (error) {
      // Malformed JSON, a platform error or an unresolvable directory: the
      // journal is an optimisation, so publishing goes on without it. Logged
      // by type only (no path, no content).
      appLog('GitHub upload journal not read: ${error.runtimeType}');
      return GitHubUploadJournal.empty;
    }
  }

  @override
  Future<Either<Failure, Unit>> write(GitHubUploadJournal journal) async {
    try {
      final directory = await _directory();
      await Directory(directory).create(recursive: true);
      final file = File(p.join(directory, _fileName));
      final temp = File('${file.path}$_tempSuffix');
      // flush, then rename in the same directory: the rename is atomic, so
      // the real path never points at unwritten data.
      await temp.writeAsString(jsonEncode(journal.toJson()), flush: true);
      await temp.rename(file.path);
      return right(unit);
    } on Exception catch (error) {
      appLog('GitHub upload journal not saved: ${error.runtimeType}');
      return left(_saveFailed);
    }
  }
}
