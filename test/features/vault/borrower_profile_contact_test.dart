import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/widgets/whatsapp_glyph.dart';
import 'package:pitaka/features/vault/domain/borrower_profile.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';
import 'package:pitaka/features/vault/presentation/pages/borrower_profile_page.dart';

BorrowerProfile _profile(String? contact) => BorrowerProfile(
  borrower: Borrower(id: 1, name: 'Ravi', contact: contact),
  active: const [],
  returned: const [],
  stats: const BorrowerStats(
    totalLoans: 0,
    averageReturnDays: null,
    overdueRate: 0,
  ),
);

Widget _app(String? contact) => ProviderScope(
  overrides: [borrowerProfileProvider(1).overrideWithValue(_profile(contact))],
  child: const MaterialApp(home: BorrowerProfilePage(borrowerId: 1)),
);

void main() {
  testWidgets('a phone shows Call + WhatsApp buttons', (tester) async {
    await tester.pumpWidget(_app('Phone: +91 98123 45678'));
    await tester.pumpAndSettle();

    expect(find.text('+91 98123 45678'), findsOneWidget);
    expect(find.byIcon(Icons.call), findsOneWidget);
    expect(find.byType(WhatsappGlyph), findsOneWidget); // WhatsApp
    expect(find.byIcon(Icons.email_outlined), findsNothing);
  });

  testWidgets('an email shows an Email button', (tester) async {
    await tester.pumpWidget(_app('Email: ravi@example.com'));
    await tester.pumpAndSettle();

    expect(find.text('ravi@example.com'), findsOneWidget);
    expect(find.byIcon(Icons.email_outlined), findsOneWidget);
    expect(find.byIcon(Icons.call), findsNothing);
  });

  testWidgets('both phone and email show all three action buttons', (
    tester,
  ) async {
    await tester.pumpWidget(_app('Phone: 9876543210\nEmail: ravi@example.com'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.call), findsOneWidget);
    expect(find.byType(WhatsappGlyph), findsOneWidget);
    expect(find.byIcon(Icons.email_outlined), findsOneWidget);
  });

  testWidgets('a legacy free-form contact still detects a phone', (
    tester,
  ) async {
    await tester.pumpWidget(_app('call 9876543210 evenings'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.call), findsOneWidget);
  });

  testWidgets('no contact renders no action buttons', (tester) async {
    await tester.pumpWidget(_app(null));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.call), findsNothing);
    expect(find.byType(WhatsappGlyph), findsNothing);
    expect(find.byIcon(Icons.email_outlined), findsNothing);
  });
}
