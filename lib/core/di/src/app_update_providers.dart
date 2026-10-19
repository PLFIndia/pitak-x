/// App-update DI bindings (AGENTS.md §4; one DI module per feature) — S35.
///
/// What lives here: the Play in-app update seam. The real service gates
/// itself to Android + the `play` applicationId (the fdroid flavor has no
/// Play listing and stays inert) and degrades to silence on every platform
/// failure. Overridden with a fake in tests.
library;

import 'package:pitaka/core/platform/app_info.dart';
import 'package:pitaka/features/app_update/domain/app_update_service.dart';
import 'package:pitaka/features/app_update/infrastructure/play_app_update_service.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_update_providers.g.dart';

/// The Play in-app update seam (S35). See the file header for the flavor
/// gating; overridden with a fake in tests.
@riverpod
AppUpdateService appUpdateService(AppUpdateServiceRef ref) =>
    const PlayAppUpdateService(appInfo: MethodChannelAppInfo());
