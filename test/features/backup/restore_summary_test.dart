import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/backup/domain/restore_summary.dart';

/// BR6 (decisions D18 and D23): the titles of the items whose cover
/// picture a restore left out travel in the summary, from the restorer
/// through the controller to the page.
void main() {
  const plain = RestoreSummary(
    booksRestored: 2,
    wishlistRestored: 0,
    borrowersRestored: 0,
    loansRestored: 0,
  );
  const withLeftOut = RestoreSummary(
    booksRestored: 2,
    wishlistRestored: 0,
    borrowersRestored: 0,
    loansRestored: 0,
    coverPicturesLeftOut: ['गोदान', 'Second'],
  );

  test('a summary names no left-out cover picture unless told', () {
    expect(plain.coverPicturesLeftOut, isEmpty);
    expect(plain.hasAdjustments, isFalse);
  });

  test('a left-out cover picture counts as an adjustment', () {
    expect(withLeftOut.hasAdjustments, isTrue);
    // It is not a dropped cover LINK (M15); the two are told apart.
    expect(withLeftOut.coversDropped, 0);
  });

  test('the titles survive the controller filling in what it adopted', () {
    // The controller copies the summary after the switch
    // (`withAdoptionResults`). A field that is not copied there would
    // silently lose the note.
    final adopted = withLeftOut.withAdoptionResults(
      identityAdopted: true,
      networkApplied: true,
      networkRestored: 3,
    );

    expect(adopted.coverPicturesLeftOut, ['गोदान', 'Second']);
    expect(adopted.hasAdjustments, isTrue);
    expect(adopted.identityAdopted, isTrue);
    expect(adopted.networkRestored, 3);
  });
}
