import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/platform/document_save_messages.dart';

/// Review finding P4-M6: the sentences about saving a file that are the
/// same on every page. They were approved word for word (decisions D170,
/// D176 and D184), so a change of a word has to be a decision too, and
/// shows here.
void main() {
  test('the four shared sentences, word for word', () {
    expect(
      documentSaveNoPlaceMessage,
      'No place was chosen, so nothing was saved.',
    );
    expect(
      documentSaveUnavailableMessage,
      'Saving to a file is not available on this device.',
    );
    expect(
      documentSaveNotEmptyMessage,
      'That file already has something in it, so it was left as it is. '
      'Choose a new name in the save window and try again.',
    );
    expect(
      documentSaveUnconfirmedMessage,
      'That place cannot confirm that a file is stored, so nothing was saved '
      'there. Choose a place on this phone or on a memory card, or use Share '
      'instead.',
    );
  });

  test('no sentence names a path, a folder or an error', () {
    for (final sentence in [
      documentSaveNoPlaceMessage,
      documentSaveUnavailableMessage,
      documentSaveNotEmptyMessage,
      documentSaveUnconfirmedMessage,
    ]) {
      expect(sentence, isNotEmpty);
      expect(sentence, isNot(contains('/')));
      expect(sentence, isNot(contains('Exception')));
      expect(sentence, isNot(contains('content:')));
    }
  });
}
