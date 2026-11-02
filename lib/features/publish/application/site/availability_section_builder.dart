/// Builds the AVAILABILITY section of the site (publish application layer;
/// ADR 0019 Decisions 2 and 6, plan C.2 item 2).
///
/// The section owns exactly one file, `availability.json`. A publish either
/// writes it (the lane is on and the "not available" set is known) or deletes
/// it (the lane is off and this phone's record shows the file).
///
/// Why one encoder here (beginner note): the bytes ARE the content sha, and
/// both hosts skip an upload when the sha has not changed. The snapshot keys
/// are sorted and the document's field order is fixed, so this compact
/// encoder turns the same set into the same bytes every time — an unchanged
/// set is never uploaded again. It is deliberately NOT the `books.json`
/// encoder, which indents.
library;

import 'dart:convert';

import 'package:pitaka/features/publish/domain/availability/availability_document.dart';
import 'package:pitaka/features/publish/domain/availability/availability_request.dart';
import 'package:pitaka/features/publish/domain/availability/availability_snapshot.dart';
import 'package:pitaka/features/publish/domain/git_blob_sha.dart';
import 'package:pitaka/features/publish/domain/site/previous_publication.dart';
import 'package:pitaka/features/publish/domain/site/publish_file.dart';
import 'package:pitaka/features/publish/domain/site/publish_section.dart';

/// The ONE `availability.json` encoder: compact UTF-8 JSON of
/// [AvailabilityDocument.toJson], with no whitespace.
List<int> encodeAvailabilityJsonBytes(AvailabilityDocument document) =>
    utf8.encode(jsonEncode(document.toJson()));

/// Builds the availability section, or its removal.
abstract final class AvailabilitySectionBuilder {
  /// The section that publishes [snapshot] as `availability.json`.
  ///
  /// The file is marked for upload only when its sha differs from the one
  /// [previous] records, exactly like every other section's files.
  static PublishSection write({
    required AvailabilitySnapshot snapshot,
    required PreviousPublication previous,
  }) {
    final bytes = encodeAvailabilityJsonBytes(AvailabilityDocument(snapshot));
    final sha = GitBlobSha.of(bytes);
    return PublishSection(
      section: SiteSection.availability,
      files: [
        PublishFile(
          path: AvailabilityDocument.path,
          bytes: bytes,
          gitSha: sha,
          upload: previous.shaFor(AvailabilityDocument.path) != sha,
        ),
      ],
    );
  }

  /// The section that deletes `availability.json`, or null when [previous]
  /// does not record it — then there is nothing of ours to delete.
  ///
  /// Only a RECORDED file is deleted: a path this phone never wrote is not
  /// app-owned (R13), and the section merge would refuse it anyway.
  static PublishSection? removal({required PreviousPublication previous}) {
    if (previous.shaFor(AvailabilityDocument.path) == null) return null;
    return const PublishSection(
      section: SiteSection.availability,
      files: [],
      deletePaths: [AvailabilityDocument.path],
    );
  }

  /// What a publish that writes NO fresh set does with a recorded
  /// `availability.json`: the vault is locked, or the publish builds no
  /// catalogue (an events publish). Null leaves the live file as it is.
  ///
  /// - [AvailabilityRemoval] (the lane is off): delete it (AV4, A.6 #20).
  /// - [AvailabilityFromLoanCounts] (the lane is on): keep it only while
  ///   [PreviousPublication.catalogueKeyed] still vouches for the keys it was
  ///   published against. Otherwise its keys may name other items — after a
  ///   restore of another library (plan J9), or after another writer replaced
  ///   `books.json` — so it is deleted, and readers fall back to the inline
  ///   tag. Deleting is always the safe direction (plan S6).
  ///
  /// The ONE rule for every publish that can carry the file without
  /// computing it: the snapshot builder (catalogue, Cloudflare events, moves,
  /// replacements) and the GitHub events publish.
  static PublishSection? withoutFreshSet({
    required AvailabilityRequest request,
    required PreviousPublication previous,
  }) => switch (request) {
    AvailabilityRemoval() => removal(previous: previous),
    AvailabilityFromLoanCounts() =>
      previous.catalogueKeyed ? null : removal(previous: previous),
  };
}
