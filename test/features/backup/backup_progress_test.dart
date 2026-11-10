import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/backup/domain/backup_progress.dart';

/// BR4 rider 3: the two numbers behind "Cover 1,234 of 9,000". The value
/// can only be made through its checking factory, so these tests walk the
/// edges of what it accepts.
void main() {
  BackupProgress? create(int done, int total) =>
      BackupProgress.tryCreate(coversDone: done, coversTotal: total);

  test('keeps the two numbers it was given', () {
    final progress = create(1234, 9000)!;

    expect(progress.coversDone, 1234);
    expect(progress.coversTotal, 9000);
  });

  test('accepts nothing done yet, and everything done', () {
    expect(create(0, 1), isNotNull);
    expect(create(1, 1), isNotNull);
    expect(create(0, 9000), isNotNull);
    expect(create(9000, 9000), isNotNull);
  });

  test('refuses a total below one: without covers there is no progress', () {
    expect(create(0, 0), isNull);
    expect(create(0, -1), isNull);
    expect(create(-1, -1), isNull);
  });

  test('refuses more done than there are, and fewer than none', () {
    expect(create(2, 1), isNull);
    expect(create(9001, 9000), isNull);
    expect(create(-1, 5), isNull);
  });

  test('prints as its two numbers', () {
    expect('${create(3, 7)}', 'BackupProgress(3 of 7)');
  });
}
