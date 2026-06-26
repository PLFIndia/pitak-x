import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/publish/domain/publish_export.dart';
import 'package:pitaka/features/publish/domain/publish_redaction.dart';

void main() {
  Book sample() => const Book(
    id: 42,
    title: 'The Odyssey',
    author: 'Homer',
    isbn: '9780140449136',
    publisher: 'Penguin',
    publishedYear: 1996,
    genre: 'Epic',
    language: 'en',
    notes: 'Borrowed from Ravi — PII',
    location: 'Shelf 3B',
    sourceType: BookSourceType.gift,
    sourceDetail: 'Gift from Ravi',
    addedDate: 1700000000000,
    addedBy: 'maintainer-x',
    needsMetadata: true,
    ageGroup: AgeGroup.above10,
    coverUrl: 'covers/abc.jpg',
  );

  test('keeps catalog fields, drops PII, applies availability', () {
    final p = redactForPublish(
      sample(),
      resolveCoverUrl: (b) => 'covers/${b.id}.jpg',
      availability: PublishBook.out,
    );
    expect(p.title, 'The Odyssey');
    expect(p.author, 'Homer');
    expect(p.isbn, '9780140449136');
    expect(p.publisher, 'Penguin');
    expect(p.publishedYear, 1996);
    expect(p.genre, 'Epic');
    expect(p.language, 'en');
    expect(p.ageGroup, 'above-10');
    expect(p.availability, PublishBook.out);
    // Cover resolved via callback (had access to the real id).
    expect(p.coverUrl, 'covers/42.jpg');
  });

  test('redacted JSON contains no PII keys', () {
    final json = redactForPublish(
      sample(),
      resolveCoverUrl: (_) => null,
    ).toJson();
    expect(json.containsKey('notes'), isFalse);
    expect(json.containsKey('location'), isFalse);
    expect(json.containsKey('sourceType'), isFalse);
    expect(json.containsKey('sourceDetail'), isFalse);
    expect(json.containsKey('addedDate'), isFalse);
    expect(json.containsKey('addedBy'), isFalse);
    expect(json.containsKey('id'), isFalse);
    expect(json.containsKey('needsMetadata'), isFalse);
    // Dropped cover ⇒ no coverUrl key.
    expect(json.containsKey('coverUrl'), isFalse);
    // Serialised string carries none of the PII values either.
    expect(json.toString(), isNot(contains('Ravi')));
    expect(json.toString(), isNot(contains('Shelf')));
  });
}
