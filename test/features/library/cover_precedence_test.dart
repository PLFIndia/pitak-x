import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/library/domain/cover_precedence.dart';

/// M09 (user decision 2026-09-09): a cover the user produced on THIS device —
/// a photo of the physical book — is never replaced by a remote URL arriving
/// through import or merge. An incoming cover only lands when the local row
/// has no cover, or the local cover is itself just a remote URL, or the
/// incoming cover is a real local file shipped in a bundle.
void main() {
  const photo = 'covers/11111111-1111-1111-1111-111111111111.jpg';
  const legacyPhoto = 'file:///data/user/0/x/files/covers/old.jpg';
  const remoteA = 'https://covers.openlibrary.org/b/id/1-L.jpg';
  const remoteB = 'https://books.google.com/books/content?id=2';
  const bundlePhoto = 'covers/22222222-2222-2222-2222-222222222222.jpg';

  group('resolveIncomingCover', () {
    test('local photo beats an incoming remote URL', () {
      expect(resolveIncomingCover(existing: photo, incoming: remoteA), photo);
    });

    test('legacy file:// photo beats an incoming remote URL', () {
      expect(
        resolveIncomingCover(existing: legacyPhoto, incoming: remoteA),
        legacyPhoto,
      );
    });

    test('no local cover → incoming remote URL is taken', () {
      expect(resolveIncomingCover(existing: null, incoming: remoteA), remoteA);
      expect(resolveIncomingCover(existing: '', incoming: remoteA), remoteA);
      expect(resolveIncomingCover(existing: '  ', incoming: remoteA), remoteA);
    });

    test('local remote URL is replaced by a newer incoming remote URL', () {
      expect(
        resolveIncomingCover(existing: remoteA, incoming: remoteB),
        remoteB,
      );
    });

    test('incoming LOCAL bundle cover replaces a local photo', () {
      // The user moving their own photos between devices via a bundle: the
      // bundle image is a photo too, and it is the newer intent.
      expect(
        resolveIncomingCover(existing: photo, incoming: bundlePhoto),
        bundlePhoto,
      );
    });

    test('incoming LOCAL bundle cover replaces a local remote URL', () {
      expect(
        resolveIncomingCover(existing: remoteA, incoming: bundlePhoto),
        bundlePhoto,
      );
    });

    test('blank incoming keeps whatever is local', () {
      expect(resolveIncomingCover(existing: photo, incoming: null), photo);
      expect(resolveIncomingCover(existing: photo, incoming: ''), photo);
      expect(resolveIncomingCover(existing: remoteA, incoming: ' '), remoteA);
      expect(resolveIncomingCover(existing: null, incoming: null), isNull);
    });

    test('incoming is passed through untrimmed-safe (trimmed comparison)', () {
      expect(
        resolveIncomingCover(existing: null, incoming: '  $remoteA  '),
        '  $remoteA  ',
        reason: 'the helper decides precedence only; it does not rewrite',
      );
    });
  });
}
