import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
// Test-only seams into the two cover plugins. Both packages are already
// locked transitively; keeping them out of pubspec leaves the app's dependency
// surface unchanged.
// ignore: depend_on_referenced_packages
import 'package:image_cropper_platform_interface/image_cropper_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/application/form_cover_controller.dart';

import 'async_value_gate.dart';

/// Installs gated picker/cropper platforms for one widget test and restores
/// the previous global platform instances afterward.
CoverCaptureFakes installCoverCaptureFakes() {
  final fakes = CoverCaptureFakes();
  final previousPicker = ImagePickerPlatform.instance;
  final previousCropper = ImageCropperPlatform.instance;
  ImagePickerPlatform.instance = fakes.picker;
  ImageCropperPlatform.instance = fakes.cropper;
  addTearDown(() {
    ImagePickerPlatform.instance = previousPicker;
    ImageCropperPlatform.instance = previousCropper;
  });
  return fakes;
}

/// The three independently controllable stages of FormCoverField's capture.
final class CoverCaptureFakes {
  final pickerGate = AsyncValueGate<XFile?>();
  final cropperGate = AsyncValueGate<CroppedFile?>();
  final storeGate = AsyncValueGate<Either<Failure, String>>();

  late final GatedImagePicker picker = GatedImagePicker(pickerGate);
  late final GatedImageCropper cropper = GatedImageCropper(cropperGate);
  late final GatedFormCoverController controller = GatedFormCoverController(
    storeGate,
  );

  void finishPicker() => pickerGate.succeed(XFile('shot.jpg'));

  void finishCropper() =>
      cropperGate.succeed(TestCroppedFile(Uint8List.fromList(const [1, 2, 3])));

  void finishStore(String coverRef) => storeGate.succeed(right(coverRef));
}

final class GatedImagePicker extends ImagePickerPlatform {
  GatedImagePicker(this.gate);

  final AsyncValueGate<XFile?> gate;
  int calls = 0;

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) {
    calls++;
    return gate.wait();
  }
}

final class GatedImageCropper extends ImageCropperPlatform {
  GatedImageCropper(this.gate);

  final AsyncValueGate<CroppedFile?> gate;
  int calls = 0;

  @override
  Future<CroppedFile?> cropImage({
    required String sourcePath,
    int? maxWidth,
    int? maxHeight,
    CropAspectRatio? aspectRatio,
    ImageCompressFormat compressFormat = ImageCompressFormat.jpg,
    int compressQuality = 90,
    List<PlatformUiSettings>? uiSettings,
  }) {
    calls++;
    return gate.wait();
  }
}

/// A cropped result with in-memory bytes, avoiding plugin-file IO in tests.
final class TestCroppedFile extends CroppedFile {
  TestCroppedFile(this.bytes) : super('cropped.jpg');

  final Uint8List bytes;

  @override
  Future<Uint8List> readAsBytes() async => bytes;
}

/// Holds the downscale/store tail after the real picker and cropper finish.
final class GatedFormCoverController extends FormCoverController {
  GatedFormCoverController(this.gate);

  final AsyncValueGate<Either<Failure, String>> gate;
  int calls = 0;

  @override
  Future<Either<Failure, String>> storeCapture(Uint8List rawBytes) {
    calls++;
    return gate.wait();
  }
}
