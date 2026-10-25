/// Shared cover-crop presets (presentation, AGENTS.md §3.1).
///
/// Extracted from `catalogue_item_detail_page.dart` in S16 so every cover
/// capture — the detail page's replace flow AND the form cover field used by
/// the periodical/issue forms — frames covers with the SAME ratio choices
/// (AGENTS §0 "one blessed way"): a portrait 2:3 preset (the natural shape of
/// a book/magazine cover) replaces the plugin's default landscape 3:2;
/// free-form, square and original remain available.
library;

import 'package:image_cropper/image_cropper.dart';

/// A portrait 2:3 crop preset. The plugin's built-in enum only offers
/// landscape ratios (e.g. 3:2), so we supply this custom preset; `data` is
/// (ratioX, ratioY) and is passed straight to the native cropper.
class CoverRatio2x3Preset implements CropAspectRatioPresetData {
  /// Creates the preset.
  const CoverRatio2x3Preset();

  @override
  String get name => '2x3';

  @override
  (int, int)? get data => (2, 3);
}

/// The crop ratio presets offered for a cover capture.
const List<CropAspectRatioPresetData> coverCropPresets = [
  CropAspectRatioPreset.original,
  CropAspectRatioPreset.square,
  CoverRatio2x3Preset(),
];

/// Initial ratio shown when the cropper opens. Must be one of
/// [coverCropPresets]; also required for the custom list to apply on Android.
const CropAspectRatioPresetData coverCropInitPreset = CoverRatio2x3Preset();
