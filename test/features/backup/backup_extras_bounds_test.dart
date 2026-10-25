import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/backup/domain/backup_manifest.dart';
import 'package:pitaka/features/backup/infrastructure/backup_extras_reader.dart';
import 'package:pitaka/features/backup/infrastructure/item_details_archive_codec.dart';

/// Magazine remediation S5 (L5): the WRITER now refuses to emit an entry past
/// these bounds, so this test pins the reader side of the contract — the
/// exact boundary must stay "greater than the cap is unusable, equal is fine".
/// If the reader's rule ever changes, the writer's mirror must change with it.
void main() {
  const manifest = BackupManifest(
    exportedAt: 1,
    hasPeriodicals: true,
    hasItemKinds: true,
  );

  /// A minimal valid `periodicals.json`, padded with LEADING WHITESPACE to an
  /// exact byte length. `jsonDecode` ignores leading whitespace, so the
  /// envelope stays valid while the entry grows byte-for-byte.
  String paddedPeriodicals(int totalBytes) {
    const json = '{"schemaVersion":1,"periodicals":[],"issues":[]}';
    final pad = totalBytes - json.length;
    return '${' ' * pad}$json';
  }

  test('an entry of exactly maxBytes is still readable', () {
    final extras = readBackupExtras({
      periodicalsEntryName: Uint8List.fromList(
        utf8.encode(paddedPeriodicals(ItemDetailsArchiveCodec.maxBytes)),
      ),
    }, manifest);
    expect(extras.periodicals, isNotNull);
  });

  test('one byte past maxBytes is unreadable (never parsed)', () {
    final extras = readBackupExtras({
      periodicalsEntryName: Uint8List.fromList(
        utf8.encode(paddedPeriodicals(ItemDetailsArchiveCodec.maxBytes + 1)),
      ),
    }, manifest);
    expect(extras.periodicals, isNull);
  });

  test('item_kinds follows the same boundary rule', () {
    const json = '{"schemaVersion":1,"kinds":[]}';
    String padded(int totalBytes) => '${' ' * (totalBytes - json.length)}$json';

    BackupExtras read(int totalBytes) => readBackupExtras({
      itemKindsEntryName: Uint8List.fromList(utf8.encode(padded(totalBytes))),
    }, manifest);

    expect(read(ItemDetailsArchiveCodec.maxBytes).itemKinds, isNotNull);
    expect(read(ItemDetailsArchiveCodec.maxBytes + 1).itemKinds, isNull);
  });
}
