import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pitaka/features/import_export/infrastructure/pdf_fonts.dart';

void main() {
  // Loading the bundled fonts needs the test binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PdfFontResolver.canDraw', () {
    test('with no fonts fed, only what the built-in Helvetica knows', () {
      final resolver = PdfFontResolver.fromBytes(PdfDocument(), const []);
      expect(resolver.canDraw('Godan 1936'), isTrue);
      expect(resolver.canDraw('Émile'), isTrue); // U+00C9, Latin-1
      expect(resolver.canDraw('Šárka'), isFalse); // U+0160
      expect(resolver.canDraw('War – Peace'), isFalse); // U+2013
      expect(resolver.canDraw('गोदान'), isFalse);
    });

    test('with the Latin face fed, Latin beyond Latin-1 too', () async {
      final latin = await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
      final resolver = PdfFontResolver.fromBytes(PdfDocument(), [latin]);
      expect(resolver.canDraw('Šárka Dvořák'), isTrue);
      expect(resolver.canDraw('War – and “Peace”…'), isTrue);
      expect(resolver.canDraw('₹250'), isTrue);
      expect(resolver.canDraw('गोदान'), isFalse);
      expect(resolver.canDraw('Godan गोदान'), isFalse);
    });

    test('a later font of the bundle counts', () async {
      final latin = await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
      final hindi = await rootBundle.load(
        'assets/fonts/NotoSansDevanagari-Regular.ttf',
      );
      final resolver = PdfFontResolver.fromBytes(PdfDocument(), [latin, hindi]);
      expect(resolver.canDraw('गोदान'), isTrue);
    });
  });
}
