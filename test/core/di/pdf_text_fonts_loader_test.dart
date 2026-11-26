import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/import_export/infrastructure/pdf_fonts.dart';

void main() {
  // Loading assets needs the test binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the loader gives the two Latin faces, one for each weight, and '
      'no font of another script', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final fonts = await container.read(pdfTextFontsLoaderProvider)();

    final regular = await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
    final bold = await rootBundle.load('assets/fonts/NotoSans-Bold.ttf');
    expect(fonts.regular, hasLength(1));
    expect(fonts.bold, hasLength(1));
    expect(
      fonts.regular.single.buffer.asUint8List(),
      regular.buffer.asUint8List(),
    );
    expect(fonts.bold.single.buffer.asUint8List(), bold.buffer.asUint8List());
    // Regular and bold are different files: neither stands in for the other.
    expect(
      fonts.regular.single.lengthInBytes,
      isNot(fonts.bold.single.lengthInBytes),
    );
  });

  test('what it gives writes Latin text and does NOT claim an Indian script: '
      'that text has to stay a picture', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final fonts = await container.read(pdfTextFontsLoaderProvider)();
    final doc = PdfDocument();
    for (final bundle in [fonts.regular, fonts.bold]) {
      final resolver = PdfFontResolver.fromBytes(doc, bundle);
      expect(resolver.canDraw('Šárka Dvořák – “1936”…'), isTrue);
      expect(resolver.canDraw('गोदान'), isFalse);
      expect(resolver.canDraw('பொன்னியின்'), isFalse);
    }
  });
}
