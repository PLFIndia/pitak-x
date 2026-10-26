import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/share_apps/domain/shareable_app.dart';
import 'package:pitaka/features/share_apps/presentation/share_apps_catalog.dart';

void main() {
  group('ShareableApp', () {
    test('trims metadata and builds the canonical Play Store link', () {
      final app = ShareableApp(
        name: '  Pitak  ',
        playStorePackageName: '  dev.khoj.pitaka  ',
      );

      expect(app.name, 'Pitak');
      expect(app.playStorePackageName, 'dev.khoj.pitaka');
      expect(
        app.playStoreUrl,
        'https://play.google.com/store/apps/details?id=dev.khoj.pitaka',
      );
      expect(app.playStoreUri.scheme, 'https');
      expect(app.playStoreUri.host, 'play.google.com');
      expect(app.playStoreUri.queryParameters, {'id': 'dev.khoj.pitaka'});
    });

    test('accepts the length boundaries', () {
      final longestName = List<String>.filled(80, 'a').join();
      final longestFirstSegment = List<String>.filled(249, 'a').join();
      final app = ShareableApp(
        name: longestName,
        playStorePackageName: '$longestFirstSegment.pitak',
      );

      expect(app.name, hasLength(80));
      expect(app.playStorePackageName, hasLength(255));
    });

    test('rejects blank or overlong app names', () {
      for (final invalidName in <String>[
        '',
        '   ',
        List<String>.filled(81, 'a').join(),
      ]) {
        expect(
          () => ShareableApp(
            name: invalidName,
            playStorePackageName: 'dev.khoj.pitaka',
          ),
          throwsArgumentError,
          reason: 'Name should be rejected: ${invalidName.length} characters',
        );
      }
    });

    test('rejects malformed, URL-like, or overlong package IDs', () {
      final overlongFirstSegment = List<String>.filled(250, 'a').join();
      for (final invalidId in <String>[
        '',
        'pitaka',
        'dev..pitaka',
        '.dev.khoj.pitaka',
        'dev.khoj.pitaka?x=1',
        'dev.khoj.pitaka&x=1',
        'https://evil.example/app',
        '$overlongFirstSegment.pitak',
      ]) {
        expect(
          () => ShareableApp(name: 'Pitak', playStorePackageName: invalidId),
          throwsArgumentError,
          reason: 'Package ID should be rejected: $invalidId',
        );
      }
    });
  });

  group('shareAppCatalog', () {
    test(
      'starts with only Pitak and its bundled icon, with no placeholders',
      () {
        expect(shareAppCatalog, hasLength(1));
        final entry = shareAppCatalog.single;
        expect(entry.app.name, 'Pitak');
        expect(entry.app.playStorePackageName, 'dev.khoj.pitaka');
        expect(entry.iconAssetPath, 'assets/branding/app_icon.png');
      },
    );

    test('has unique package IDs and cannot be mutated by a screen', () {
      final ids = shareAppCatalog
          .map((entry) => entry.app.playStorePackageName)
          .toList();
      expect(ids.toSet(), hasLength(ids.length));
      expect(
        () => shareAppCatalog.add(shareAppCatalog.single),
        throwsUnsupportedError,
      );
    });
  });
}
