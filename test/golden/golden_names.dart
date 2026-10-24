/// The one list of golden PNGs this suite renders (test-only).
///
/// BOTH golden test files read this list, so the existence guard and the
/// rendering tests can never disagree:
///  - `golden_files_exist_test.dart` (NOT tagged — runs in the normal suite)
///    fails fast when a listed PNG is missing from `goldens/` (review H1:
///    a missing golden used to surface only inside the tagged CI run);
///  - `key_screens_test.dart`'s `expectGolden` asserts the name it renders
///    is listed here, so a rendering test can never use an unlisted name.
///
/// Adding a golden? Add its name here, render it in `key_screens_test.dart`,
/// and commit the PNG the `update_goldens` workflow regenerates on Linux
/// (never a Mac-rendered PNG — see the header of `key_screens_test.dart`).
library;

/// Every golden this suite renders.
const kGoldenNames = <String>[
  'library_empty_light',
  'library_populated_dark',
  'library_populated_light',
  'publish_connection',
  'restore_initial',
  'vault_unlock',
  'network_library_tiles',
  'periodicals_badge_states',
];
