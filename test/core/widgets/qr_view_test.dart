import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/widgets/qr_view.dart';

void main() {
  testWidgets('QrView paints a CustomPaint for a valid payload', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: QrView(data: 'pitaka-lib:0123456789abcdef0123456789abcdef'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The QR matrix is drawn via a CustomPaint (no exception during encode).
    expect(find.byType(QrView), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
  });
}
