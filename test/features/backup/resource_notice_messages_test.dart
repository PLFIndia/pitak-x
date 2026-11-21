/// The sentences of the resource notice (backup rework BR9, decisions D49,
/// D51 and D54), word for word. A changed sentence must change here too.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/backup/domain/resource_notice.dart';
import 'package:pitaka/features/backup/presentation/resource_notice_messages.dart';

const int _mb = 1024 * 1024;
const int _gb = 1024 * _mb;

const String _storageTight =
    'Storage is tight. It will probably work, but it can fail if the phone '
    'fills up while it runs. Freeing some storage first is safer.';
const String _storageShort =
    'This phone does not have enough free storage for it. It will probably '
    'fail.';
const String _memoryTight =
    'This phone is low on memory right now. Closing other apps first is '
    'safer.';
const String _memoryShort =
    'This phone has very little memory available right now, and may stop '
    'Pitak in the middle. Closing other apps first is safer.';
const String _unknown =
    'Pitak could not read this on this device, so it cannot say whether it '
    'is enough.';
const String _backupFails =
    'If it fails, nothing is changed and no backup is made.';
const String _restoreFails =
    'If it fails, your library stays exactly as it is.';

/// A notice from plain figures. The defaults are a phone with plenty.
ResourceNotice _notice({
  int? need = 18 * _mb,
  int? free = 12 * _gb,
  int? available = 2355 * _mb,
  int? lowMark = 300 * _mb,
  bool? low = false,
}) => ResourceNotice.judge(
  storageNeedBytes: need,
  storageFreeBytes: free,
  memoryAvailableBytes: available,
  memoryLowThresholdBytes: lowMark,
  memoryLow: low,
);

void main() {
  group('title and buttons', () {
    test('a backup', () {
      expect(
        resourceNoticeTitle(ResourceNoticeRun.backup),
        'Before you create the backup',
      );
      expect(resourceNoticeConfirmLabel(ResourceNoticeRun.backup), 'Go on');
    });

    test('a restore: the button names what it does (D51)', () {
      expect(
        resourceNoticeTitle(ResourceNoticeRun.restore),
        'Restore this backup?',
      );
      expect(resourceNoticeConfirmLabel(ResourceNoticeRun.restore), 'Restore');
    });

    test('the fixed sentences', () {
      expect(resourceNoticeCancelLabel, 'Cancel');
      expect(resourceNoticeCheckingMessage, 'Checking this phone…');
      expect(
        resourceNoticeReplacesLibraryMessage,
        'This replaces your library: the books, wishlist and cover pictures '
        'on this phone are replaced by what is in the backup. This cannot '
        'be undone.',
      );
      expect(resourceNoticeUnknownMessage, _unknown);
    });
  });

  group('the storage line', () {
    test('a small need next to a large supply: each in its own unit '
        '(D54), never "0.0 GB"', () {
      expect(
        resourceNoticeStorageLine(_notice()),
        'Storage: this needs about 18.0 MB. This phone has 12.0 GB free.',
      );
    });

    test('two sizes of the same range share one unit', () {
      expect(
        resourceNoticeStorageLine(_notice(need: 2150 * _mb)),
        'Storage: this needs about 2.1 GB. This phone has 12.0 GB free.',
      );
      expect(
        resourceNoticeStorageLine(_notice(need: 40 * _mb, free: 140 * _mb)),
        'Storage: this needs about 40.0 MB. This phone has 140.0 MB free.',
      );
    });

    test('two different sizes never look equal', () {
      // 2 GB free against a need one megabyte above it: "2.0 GB" twice
      // would be a riddle next to "not enough".
      expect(
        resourceNoticeStorageLine(_notice(need: 2 * _gb + _mb, free: 2 * _gb)),
        'Storage: this needs about 2,049.0 MB. This phone has 2,048.0 MB '
        'free.',
      );
    });

    test('free storage could not be read', () {
      expect(
        resourceNoticeStorageLine(_notice(free: null)),
        'Storage: this needs about 18.0 MB. How much this phone has free '
        'could not be read.',
      );
    });

    test('the need could not be worked out', () {
      const sentence = 'Storage: how much this needs could not be worked out.';
      expect(resourceNoticeStorageLine(_notice(need: null)), sentence);
      expect(
        resourceNoticeStorageLine(_notice(need: null, free: null)),
        sentence,
      );
    });
  });

  group('the memory line', () {
    test('the need next to what is available', () {
      expect(
        resourceNoticeMemoryLine(_notice()),
        'Memory: this needs about 100.0 MB. 2.3 GB are available right now.',
      );
      expect(
        resourceNoticeMemoryLine(_notice(available: 380 * _mb)),
        'Memory: this needs about 100.0 MB. 380.0 MB are available right '
        'now.',
      );
    });

    test('available memory could not be read', () {
      expect(
        resourceNoticeMemoryLine(_notice(available: null)),
        'Memory: this needs about 100.0 MB. How much is available could '
        'not be read.',
      );
    });
  });

  group('the verdict', () {
    for (final run in ResourceNoticeRun.values) {
      test('enough of both, ${run.name}: one short sentence', () {
        expect(resourceNoticeVerdictLines(_notice(), run), ['That is enough.']);
      });
    }

    test('storage is tight', () {
      final notice = _notice(need: 40 * _mb, free: 40 * _mb);
      expect(notice.storage, ResourceVerdict.tight);
      expect(resourceNoticeVerdictLines(notice, ResourceNoticeRun.backup), [
        _storageTight,
        _backupFails,
      ]);
      expect(resourceNoticeVerdictLines(notice, ResourceNoticeRun.restore), [
        _storageTight,
        _restoreFails,
      ]);
    });

    test('storage is not enough', () {
      final notice = _notice(need: 40 * _mb, free: 39 * _mb);
      expect(notice.storage, ResourceVerdict.notEnough);
      expect(resourceNoticeVerdictLines(notice, ResourceNoticeRun.backup), [
        _storageShort,
        _backupFails,
      ]);
      expect(resourceNoticeVerdictLines(notice, ResourceNoticeRun.restore), [
        _storageShort,
        _restoreFails,
      ]);
    });

    test('memory is tight', () {
      final notice = _notice(low: true);
      expect(notice.memory, ResourceVerdict.tight);
      expect(resourceNoticeVerdictLines(notice, ResourceNoticeRun.backup), [
        _memoryTight,
        _backupFails,
      ]);
    });

    test('memory is not enough', () {
      final notice = _notice(available: 50 * _mb);
      expect(notice.memory, ResourceVerdict.notEnough);
      expect(resourceNoticeVerdictLines(notice, ResourceNoticeRun.restore), [
        _memoryShort,
        _restoreFails,
      ]);
    });

    test('both have something to say: storage first, then memory', () {
      final notice = _notice(need: 40 * _mb, free: 39 * _mb, low: true);
      expect(resourceNoticeVerdictLines(notice, ResourceNoticeRun.backup), [
        _storageShort,
        _memoryTight,
        _backupFails,
      ]);
    });

    test('one figure could not be read and the other is fine: it does not '
        'say "enough"', () {
      for (final notice in [
        _notice(free: null),
        _notice(need: null),
        _notice(available: null),
        _notice(need: null, free: null, available: null),
      ]) {
        expect(notice.overall, ResourceVerdict.unknown);
        expect(resourceNoticeVerdictLines(notice, ResourceNoticeRun.backup), [
          _unknown,
          _backupFails,
        ]);
        expect(resourceNoticeVerdictLines(notice, ResourceNoticeRun.restore), [
          _unknown,
          _restoreFails,
        ]);
      }
    });

    test('one figure could not be read and the other is short: the short '
        'one is named, without the "could not read" sentence', () {
      final notice = _notice(need: 40 * _mb, free: 39 * _mb, available: null);
      expect(resourceNoticeVerdictLines(notice, ResourceNoticeRun.backup), [
        _storageShort,
        _backupFails,
      ]);
    });
  });

  group('everything the dialog says', () {
    test('the storage line, the memory line, then the verdict', () {
      final notice = _notice(need: 40 * _mb, free: 40 * _mb);
      expect(resourceNoticeLines(notice, ResourceNoticeRun.restore), [
        'Storage: this needs about 40.0 MB. This phone has 40.0 MB free.',
        'Memory: this needs about 100.0 MB. 2.3 GB are available right now.',
        _storageTight,
        _restoreFails,
      ]);
    });

    test('when the notice itself could not be worked out', () {
      expect(resourceNoticeUnreadLines(ResourceNoticeRun.backup), [
        _unknown,
        _backupFails,
      ]);
      expect(resourceNoticeUnreadLines(ResourceNoticeRun.restore), [
        _unknown,
        _restoreFails,
      ]);
    });

    test('no sentence promises or forbids: nothing says "cannot" start', () {
      // D5: the notice informs, it never blocks. A wording that reads as a
      // refusal would break that promise on the screen.
      for (final notice in [
        _notice(),
        _notice(need: 40 * _mb, free: 1),
        _notice(available: 1),
        _notice(need: null, free: null, available: null),
      ]) {
        for (final run in ResourceNoticeRun.values) {
          for (final line in resourceNoticeLines(notice, run)) {
            expect(line, isNot(contains('cannot start')));
            expect(line, isNot(contains('not possible')));
            expect(line, isNot(contains('refused')));
          }
        }
      }
    });
  });
}
