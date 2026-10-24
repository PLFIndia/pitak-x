/// The cover capture field of an add/edit form (presentation layer).
///
/// Shows the cover the form currently holds (a local `covers/<uuid>.jpg`
/// reference stored by [FormCoverController], or the placeholder when none),
/// a capture/replace button, and a remove button while a cover is set.
///
/// Division of labour (AGENTS.md §7): this widget owns ONLY the untestable
/// plugin steps — camera capture and the crop activity, plus the app-lock
/// suppression those OS activities need (each backgrounds the app, which
/// would otherwise trip the biometric gate mid-capture). The testable
/// pipeline (downscale → store) lives in [FormCoverController]; the resulting
/// reference is handed to the parent form through its `onChanged` callback,
/// and the parent stays the owner of the value (the form's state is the
/// single source of truth, like every other field).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pitaka/core/widgets/cover_crop.dart';
import 'package:pitaka/core/widgets/item_cover.dart';
import 'package:pitaka/core/widgets/lock_suppressor.dart';
import 'package:pitaka/features/library/application/form_cover_controller.dart';

/// Cover preview + capture + remove for a form.
class FormCoverField extends ConsumerStatefulWidget {
  /// Creates the field. [title] feeds the placeholder's initial letter;
  /// [coverRef] is the currently held local reference (null = none yet).
  const FormCoverField({
    required this.title,
    required this.coverRef,
    required this.onChanged,
    required this.onBusyChanged,
    super.key,
  });

  /// The entity's title (placeholder glyph).
  final String title;

  /// The form's current cover reference (`covers/<uuid>.jpg`), or null.
  final String? coverRef;

  /// Called with the new stored reference after a capture, or null when the
  /// user removes the cover. The parent form stores it in its state.
  final ValueChanged<String?> onChanged;

  /// Reports the whole capture/crop/store pending interval so the parent can
  /// keep Save disabled until the selected reference actually exists.
  final ValueChanged<bool> onBusyChanged;

  @override
  ConsumerState<FormCoverField> createState() => _FormCoverFieldState();
}

class _FormCoverFieldState extends ConsumerState<FormCoverField> {
  bool _busy = false;

  Future<void> _capture() async {
    _setBusy(true);
    try {
      // Suppress the app lock for the camera + crop activities: each launches
      // a separate OS activity that backgrounds us, which would otherwise
      // trip the biometric gate mid-capture.
      final suppressor = ref.read(lockSuppressorProvider.notifier);
      final shot = await suppressor.guard(
        () => ImagePicker().pickImage(
          source: ImageSource.camera,
          maxWidth: 1600,
          imageQuality: 90,
        ),
      );
      if (!mounted || shot == null) return;
      // Free-crop step: let the user frame the cover. A null result means the
      // user cancelled the crop — abort the whole capture (nothing is saved).
      final cropped = await suppressor.guard(
        () => ImageCropper().cropImage(
          sourcePath: shot.path,
          uiSettings: [
            AndroidUiSettings(
              toolbarTitle: 'Crop cover',
              lockAspectRatio: false,
              aspectRatioPresets: coverCropPresets,
              // REQUIRED on Android: uCrop only applies a custom preset list
              // when an initial ratio is also given; without this the list is
              // ignored and the default (landscape) presets show instead.
              initAspectRatio: coverCropInitPreset,
            ),
            IOSUiSettings(
              title: 'Crop cover',
              aspectRatioPresets: coverCropPresets,
            ),
          ],
        ),
      );
      if (!mounted || cropped == null) return;
      final raw = await cropped.readAsBytes();
      if (!mounted) return;
      final result = await ref
          .read(formCoverControllerProvider.notifier)
          .storeCapture(raw);
      if (!mounted) return;
      result.match(
        (_) => _snack('Could not save the cover.'),
        // The file is stored; the parent form owns the reference from here.
        // If the form is never saved the file is an orphan the startup sweep
        // reclaims (Q12) — nothing to undo here.
        (coverRef) => widget.onChanged(coverRef),
      );
    } on Exception {
      // Plugin (camera/crop) failure only — pipeline errors are typed above.
      _snack('Could not capture a photo.');
    } finally {
      _setBusy(false);
    }
  }

  /// Keeps the child progress indicator and parent Save gate in sync. A late
  /// async completion after route disposal must not call either State object.
  void _setBusy(bool value) {
    if (!mounted || _busy == value) return;
    setState(() => _busy = value);
    widget.onBusyChanged(value);
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final hasCover = widget.coverRef != null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // No owner: a form cover is always a LOCAL stored reference (or
        // none), so the remote-materialisation path never applies.
        ItemCover(
          // Key on the ref so a new capture forces an image reload.
          key: ValueKey(widget.coverRef),
          title: widget.title,
          coverUrl: widget.coverRef,
          width: 72,
          height: 100,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextButton.icon(
                onPressed: _busy ? null : _capture,
                icon: _busy
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.photo_camera_outlined),
                label: Text(hasCover ? 'Replace cover' : 'Add cover'),
              ),
              if (hasCover)
                TextButton.icon(
                  onPressed: _busy ? null : () => widget.onChanged(null),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Remove cover'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
