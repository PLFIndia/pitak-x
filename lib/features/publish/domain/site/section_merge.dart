/// The ONE way a section updates a publication record (publish domain, pure
/// Dart; Cloudflare plan R7/R8/M14).
///
/// Why this exists (beginner note): before this, a catalogue publish SAVED a
/// manifest containing only its own files, so publishing the catalogue after
/// events silently forgot every poster — the next events publish then
/// re-uploaded them and could not know which old ones were obsolete. The rule
/// is now explicit: a section may only remove paths it OWNS, it always adds the
/// files it just built, and everything else is preserved untouched.
///
/// The same function serves both hosts: GitHub turns the result into a tree
/// commit (files + exact deletions), Cloudflare into a complete asset map.
library;

import 'package:pitaka/features/publish/domain/site/previous_publication.dart';
import 'package:pitaka/features/publish/domain/site/publish_file.dart';
import 'package:pitaka/features/publish/domain/site/publish_section.dart';

/// The merged record after one section changed.
final class SectionMerge {
  /// Creates the merge result.
  const SectionMerge({
    required this.fileShas,
    required this.deletePaths,
    required this.files,
  });

  /// Every app-owned path → content sha, AFTER this section's update.
  final Map<String, String> fileShas;

  /// Paths this section dropped and the host must delete (exact, owned).
  final List<String> deletePaths;

  /// The files this section wrote (bytes + upload flags for the host).
  final List<PublishFile> files;
}

/// Merges [section] into the record described by [previous].
///
/// Rules, each one deliberate:
///  - the section's previously owned paths are REMOVED from the record first
///    (the section is being fully re-sent — its live set is exactly [section]);
///  - paths owned by the OTHER section are never touched;
///  - a previously owned path that is not in the new file set becomes an exact
///    deletion (plus anything the builder already marked obsolete);
///  - unsafe paths are refused: a section can only carry safe relative paths,
///    and a record entry that fails the path policy is ignored rather than
///    echoed into a delete.
SectionMerge mergeSection({
  required PreviousPublication previous,
  required PublishSection section,
}) {
  final merged = <String, String>{};
  final dropped = <String>[];
  for (final entry in _safeEntries(previous)) {
    if (section.section.owns(entry.key)) {
      dropped.add(entry.key);
    } else {
      merged[entry.key] = entry.value;
    }
  }

  final written = <String>{};
  for (final file in section.files) {
    if (!section.section.owns(file.path)) {
      // A builder must never hand over a path another section owns: accepting
      // it would let two sections fight over one file.
      continue;
    }
    merged[file.path] = file.gitSha;
    written.add(file.path);
  }

  final deletions = <String>{};
  for (final path in [...dropped, ...section.deletePaths]) {
    if (!section.section.owns(path)) continue;
    if (written.contains(path)) continue;
    deletions.add(path);
  }

  return SectionMerge(
    fileShas: merged,
    deletePaths: deletions.toList()..sort(),
    files: section.files,
  );
}

/// Merges several [sections] into the record described by [previous], one
/// after the other, as ONE write (ADR 0019 Decision 6: a catalogue publish
/// with the lane on also writes `availability.json` in the same commit).
///
/// Each section goes through [mergeSection] against the record the previous
/// section left behind, so every ownership rule above still applies to each
/// section on its own. Sections own disjoint paths (`SiteSection.owns`), so
/// the order does not change the result; it only fixes the order of
/// [SectionMerge.files]. The result carries every written file, the union of
/// the exact deletions and the final app-owned set.
SectionMerge mergeSections({
  required PreviousPublication previous,
  required List<PublishSection> sections,
}) {
  var current = previous;
  final files = <PublishFile>[];
  final deletions = <String>{};
  var fileShas = <String, String>{
    for (final entry in _safeEntries(previous)) entry.key: entry.value,
  };
  for (final section in sections) {
    final merge = mergeSection(previous: current, section: section);
    files.addAll(merge.files);
    deletions.addAll(merge.deletePaths);
    fileShas = merge.fileShas;
    current = _MergedRecord(merge.fileShas);
  }
  return SectionMerge(
    fileShas: fileShas,
    deletePaths: deletions.toList()..sort(),
    files: files,
  );
}

/// The record one section's merge leaves behind, as the next section's
/// "previous publication". Only paths and shas matter to [mergeSection];
/// cover sources are never read by it.
final class _MergedRecord implements PreviousPublication {
  const _MergedRecord(this._fileShas);

  final Map<String, String> _fileShas;

  @override
  String? shaFor(String path) => _fileShas[path];

  @override
  String? coverSourceFor(String key) => null;

  @override
  Iterable<String> get ownedPaths => _fileShas.keys;
}

/// The previous record's entries that pass the path policy.
Iterable<MapEntry<String, String>> _safeEntries(PreviousPublication previous) =>
    previous.ownedPaths
        .where(isSafePublishPath)
        .map((path) => MapEntry(path, previous.shaFor(path) ?? ''))
        .where((entry) => entry.value.isNotEmpty);
