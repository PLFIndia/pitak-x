import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/images/image_downscaler.dart';
import 'package:pitaka/features/library/application/form_cover_controller.dart';
import 'package:pitaka/features/library/domain/cover_files.dart';
import 'package:pitaka/features/library/infrastructure/cover_store.dart';

import '../../support/detailed_test_image.dart';

/// A cover store whose disk is "full": every save fails.
class _FailingCoverFiles implements CoverFiles {
  @override
  Future<String> saveJpeg(Uint8List jpegBytes) async =>
      throw const FileSystemException('disk full');

  @override
  Future<void> deleteFile(String? coverRef) async {}

  @override
  List<String> listLeaves() => const [];
}

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('form_cover_ctrl_test');
  });
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  ProviderContainer makeContainer({CoverFiles? files}) {
    final store = files ?? CoverStore(coversDir: tmp.path);
    final container = ProviderContainer(
      overrides: [coverStoreProvider.overrideWith((ref) async => store)],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// Runs the real controller and returns the bytes of the file it stored.
  Future<Uint8List> storedBytes(Uint8List capture) async {
    final result = await makeContainer()
        .read(formCoverControllerProvider.notifier)
        .storeCapture(capture);
    final coverRef = result.getOrElse((f) => fail('unexpected failure: $f'));
    expect(coverRef, startsWith('covers/'));
    return File('${tmp.path}/${coverRef.split('/').last}').readAsBytesSync();
  }

  // Decision of 2026-11-10: a photographed cover is stored at most 240×360
  // at JPEG quality 70 (`PhotoCoverRecipe`). The expectations use the plain
  // numbers on purpose, so a change of the recipe has to be made here too.
  group('stored size and quality', () {
    test('a large capture is stored at 240x360, quality 70', () async {
      final capture = img.encodeJpg(
        detailedTestImage(width: 720, height: 1080),
      );

      final stored = await storedBytes(capture);

      final picture = img.decodeImage(stored)!;
      expect(picture.width, 240);
      expect(picture.height, 360);
      // Same picture, same settings, same bytes: this pins the quality too.
      final atQuality70 = ImageDownscaler.downscaleJpeg(
        capture,
        maxW: 240,
        maxH: 360,
        quality: 70,
      )!;
      final atDefaultQuality = ImageDownscaler.downscaleJpeg(
        capture,
        maxW: 240,
        maxH: 360,
      )!;
      expect(stored, orderedEquals(atQuality70));
      expect(
        stored,
        isNot(orderedEquals(atDefaultQuality)),
        reason: 'the test picture must tell quality 70 from the default 80',
      );
    });

    test('a wide capture is bounded by its width', () async {
      final capture = img.encodeJpg(
        detailedTestImage(width: 1080, height: 720),
      );

      final picture = img.decodeImage(await storedBytes(capture))!;

      expect(picture.width, 240);
      expect(picture.height, 160);
    });

    test('a small capture is not enlarged', () async {
      final capture = img.encodePng(img.Image(width: 60, height: 90));

      final picture = img.decodeImage(await storedBytes(capture))!;

      expect(picture.width, 60);
      expect(picture.height, 90);
    });

    test('EXIF, including the GPS position, is not stored', () async {
      final source = detailedTestImage(width: 720, height: 1080);
      source.exif.imageIfd[0x010F] = img.IfdValueAscii('TestMake'); // Make
      source.exif.gpsIfd[0x0002] = img.IfdValueRational(48, 1); // Latitude
      final capture = img.encodeJpg(source);
      // The test picture really carries EXIF before it is stored.
      expect(img.decodeImage(capture)!.exif.isEmpty, isFalse);

      final picture = img.decodeImage(await storedBytes(capture))!;

      expect(picture.exif.isEmpty, isTrue);
    });
  });

  test('undecodable bytes → ValidationFailure, nothing stored', () async {
    final result = await makeContainer()
        .read(formCoverControllerProvider.notifier)
        .storeCapture(Uint8List.fromList([1, 2, 3]));

    result.match(
      (f) => expect(f, isA<ValidationFailure>()),
      (_) => fail('expected a failure'),
    );
    expect(tmp.listSync(), isEmpty);
  });

  test('a failed file write → StorageFailure, not a thrown error', () async {
    final capture = img.encodePng(img.Image(width: 60, height: 90));

    final result = await makeContainer(
      files: _FailingCoverFiles(),
    ).read(formCoverControllerProvider.notifier).storeCapture(capture);

    result.match(
      (f) => expect(f, isA<StorageFailure>()),
      (_) => fail('expected a failure'),
    );
  });
}
