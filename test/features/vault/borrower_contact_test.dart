import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/vault/domain/value_objects/borrower_contact.dart';

void main() {
  group('decode — tagged (round-trip format)', () {
    test('reads Phone + Email lines into typed parts', () {
      final c = BorrowerContact.decode(
        'Phone: +91 98123 45678\n'
        'Email: ravi@example.com',
      );
      expect(c.phone, '+91 98123 45678');
      expect(c.email, 'ravi@example.com');
      expect(c.other, '');
    });

    test('tolerates the tags in either order + trailing free text', () {
      final c = BorrowerContact.decode(
        'Email: a@b.com\nPhone: 555-1234\nback shelf, evenings',
      );
      expect(c.email, 'a@b.com');
      expect(c.phone, '555-1234');
      expect(c.other, 'back shelf, evenings');
    });

    test('only one of phone/email present', () {
      final c = BorrowerContact.decode('Phone: 9876543210');
      expect(c.phone, '9876543210');
      expect(c.email, '');
      expect(c.hasPhone, isTrue);
      expect(c.hasEmail, isFalse);
    });
  });

  group('decode — legacy untagged detection', () {
    test('pulls an email out of free text', () {
      final c = BorrowerContact.decode('reach me at ravi@example.com please');
      expect(c.email, 'ravi@example.com');
      expect(c.hasEmail, isTrue);
      expect(c.other, contains('reach me at'));
    });

    test('pulls a phone out of free text', () {
      final c = BorrowerContact.decode('call +91 98123 45678 after 6pm');
      expect(c.phone.replaceAll(' ', ''), '+919812345678');
      expect(c.hasPhone, isTrue);
    });

    test('pulls both a phone and an email from "phone, email"', () {
      final c = BorrowerContact.decode('9876543210, ravi@example.com');
      expect(c.phone, '9876543210');
      expect(c.email, 'ravi@example.com');
    });

    test('plain note with no contact stays as other, no false positives', () {
      final c = BorrowerContact.decode('ask at the front desk');
      expect(c.hasPhone, isFalse);
      expect(c.hasEmail, isFalse);
      expect(c.other, 'ask at the front desk');
    });

    test('blank decodes to empty', () {
      expect(BorrowerContact.decode('').isEmpty, isTrue);
      expect(BorrowerContact.decode('   ').isEmpty, isTrue);
      expect(BorrowerContact.decode(null).isEmpty, isTrue);
    });
  });

  group('encode', () {
    test('emits tagged lines for structured parts', () {
      const c = BorrowerContact(
        phone: '  555 1234 ',
        email: ' a@b.com ',
        other: ' note ',
      );
      expect(c.encode(), 'Phone: 555 1234\nEmail: a@b.com\nnote');
    });

    test('stores plain legacy text when only "other" is set', () {
      const c = BorrowerContact(other: 'front desk');
      expect(c.encode(), 'front desk');
    });

    test('empty encodes to null (clears the column)', () {
      expect(const BorrowerContact().encode(), isNull);
      expect(const BorrowerContact(other: '   ').encode(), isNull);
    });

    test('round-trips through decode', () {
      const original = BorrowerContact(
        phone: '+91 98123 45678',
        email: 'ravi@example.com',
        other: 'evenings only',
      );
      final decoded = BorrowerContact.decode(original.encode());
      expect(decoded.phone, original.phone);
      expect(decoded.email, original.email);
      expect(decoded.other, original.other);
    });
  });

  group('action URIs', () {
    test('telUri keeps + and digits, drops separators', () {
      const c = BorrowerContact(phone: '+91 (981) 234-5678');
      expect(c.telUri, 'tel:+919812345678');
    });

    test('telUri for a local number without +', () {
      const c = BorrowerContact(phone: '098-765-4321');
      expect(c.telUri, 'tel:0987654321');
    });

    test('whatsappUri is digits only, no plus', () {
      const c = BorrowerContact(phone: '+91 98123 45678');
      expect(c.whatsappUri, 'https://wa.me/919812345678');
    });

    test('mailtoUri only for a plausible email', () {
      expect(
        const BorrowerContact(email: 'a@b.com').mailtoUri,
        'mailto:a@b.com',
      );
      expect(const BorrowerContact(email: 'not-an-email').mailtoUri, isNull);
    });

    test('no phone/email → null URIs', () {
      const c = BorrowerContact(other: 'note');
      expect(c.telUri, isNull);
      expect(c.whatsappUri, isNull);
      expect(c.mailtoUri, isNull);
    });
  });
}
