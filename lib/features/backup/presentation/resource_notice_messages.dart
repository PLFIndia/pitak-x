/// The sentences of the resource notice (backup presentation, backup
/// rework BR9, decisions D49 and D51).
///
/// WHY THIS FILE EXISTS (beginner note): the notice before a backup and
/// before a restore is one dialog with many possible sentences. They live
/// here, as plain functions of the [ResourceNotice], so that every sentence
/// can be tested without building a screen, and so that the dialog itself
/// holds no wording.
///
/// Rules the sentences keep:
///  - the two sizes of one line share ONE unit when both reach the same
///    unit, and each has its own otherwise (`formatSizesFarApart`,
///    decision D54): a small need next to a large supply must not read
///    "0.0 GB";
///  - a need is always "about": it is an estimate;
///  - nothing here blocks. The sentences inform; the dialog always offers
///    the button that starts the run.
library;

import 'package:pitaka/core/text/display_number.dart';
import 'package:pitaka/features/backup/domain/resource_notice.dart';

/// Which run the notice stands in front of.
enum ResourceNoticeRun {
  /// Creating a backup.
  backup,

  /// Restoring a backup, which replaces the library.
  restore,
}

/// The dialog's title.
String resourceNoticeTitle(ResourceNoticeRun run) => switch (run) {
  ResourceNoticeRun.backup => 'Before you create the backup',
  ResourceNoticeRun.restore => 'Restore this backup?',
};

/// What the button that starts the run says (decision D51): the dialog
/// that replaces a library names what it does.
String resourceNoticeConfirmLabel(ResourceNoticeRun run) => switch (run) {
  ResourceNoticeRun.backup => 'Go on',
  ResourceNoticeRun.restore => 'Restore',
};

/// What the other button says.
const String resourceNoticeCancelLabel = 'Cancel';

/// Shown while the figures are being read.
const String resourceNoticeCheckingMessage = 'Checking this phone…';

/// The sentence that makes the notice the confirmation of a restore
/// (decision D49).
const String resourceNoticeReplacesLibraryMessage =
    'This replaces your library: the books, wishlist and cover pictures on '
    'this phone are replaced by what is in the backup. This cannot be '
    'undone.';

/// The verdict when nothing can be said.
const String resourceNoticeUnknownMessage =
    'Pitak could not read this on this device, so it cannot say whether it '
    'is enough.';

/// One size on its own, as the other pages write sizes ("100.0 MB").
String _size(int bytes) => formatSizePair(bytes, bytes).first;

/// The line about storage: what the run needs and what the phone has.
String resourceNoticeStorageLine(ResourceNotice notice) {
  final need = notice.storageNeedBytes;
  final free = notice.storageFreeBytes;
  if (need == null) {
    return 'Storage: how much this needs could not be worked out.';
  }
  if (free == null) {
    return 'Storage: this needs about ${_size(need)}. How much this phone '
        'has free could not be read.';
  }
  final sizes = formatSizesFarApart(need, free);
  return 'Storage: this needs about ${sizes.first}. This phone has '
      '${sizes.second} free.';
}

/// The line about memory: what the run needs and what is available.
String resourceNoticeMemoryLine(ResourceNotice notice) {
  final need = notice.memoryNeedBytes;
  final available = notice.memoryAvailableBytes;
  if (available == null) {
    return 'Memory: this needs about ${_size(need)}. How much is available '
        'could not be read.';
  }
  final sizes = formatSizesFarApart(need, available);
  return 'Memory: this needs about ${sizes.first}. ${sizes.second} are '
      'available right now.';
}

/// What a failed run leaves behind. Said after every verdict but
/// "enough". Both sentences are true by how the runs are built: a backup
/// that fails leaves no file, and a restore switches over only at its end.
String _ifItFails(ResourceNoticeRun run) => switch (run) {
  ResourceNoticeRun.backup =>
    'If it fails, nothing is changed and no backup is made.',
  ResourceNoticeRun.restore =>
    'If it fails, your library stays exactly as it is.',
};

/// The verdict in words: storage first, then memory, then what a failure
/// would mean. One entry per paragraph.
List<String> resourceNoticeVerdictLines(
  ResourceNotice notice,
  ResourceNoticeRun run,
) {
  if (notice.overall == ResourceVerdict.enough) {
    return const ['That is enough.'];
  }
  final storage = switch (notice.storage) {
    ResourceVerdict.tight =>
      'Storage is tight. It will probably work, but it can fail if the '
          'phone fills up while it runs. Freeing some storage first is '
          'safer.',
    ResourceVerdict.notEnough =>
      'This phone does not have enough free storage for it. It will '
          'probably fail.',
    ResourceVerdict.enough || ResourceVerdict.unknown => null,
  };
  final memory = switch (notice.memory) {
    ResourceVerdict.tight =>
      'This phone is low on memory right now. Closing other apps first is '
          'safer.',
    ResourceVerdict.notEnough =>
      'This phone has very little memory available right now, and may '
          'stop Pitak in the middle. Closing other apps first is safer.',
    ResourceVerdict.enough || ResourceVerdict.unknown => null,
  };
  return [
    ?storage,
    ?memory,
    // Neither is tight or short, and yet it is not "enough": something
    // could not be read.
    if (storage == null && memory == null) resourceNoticeUnknownMessage,
    _ifItFails(run),
  ];
}

/// Everything the dialog says about the figures once they are read: the
/// storage line, the memory line, and the verdict.
List<String> resourceNoticeLines(
  ResourceNotice notice,
  ResourceNoticeRun run,
) => [
  resourceNoticeStorageLine(notice),
  resourceNoticeMemoryLine(notice),
  ...resourceNoticeVerdictLines(notice, run),
];

/// What the dialog says when the notice itself could not be worked out.
List<String> resourceNoticeUnreadLines(ResourceNoticeRun run) => [
  resourceNoticeUnknownMessage,
  _ifItFails(run),
];
