import 'dart:convert';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/async/serial_op_queue.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/availability/availability_lane_repository.dart';
import 'package:pitaka/features/publish/application/availability/catalogue_keys_reset.dart';
import 'package:pitaka/features/publish/domain/availability/availability_lane_state.dart';
import 'package:pitaka/features/publish/domain/availability/availability_lane_store.dart';

import 'cloudflare_s8_fakes.dart';
import 'github_lane_fakes.dart';

/// The lane store in memory, through the SAME JSON round trip the real store
/// uses, so a test sees exactly what `AvailabilityLaneState.decode` accepts.
final class MemoryAvailabilityLaneStore implements AvailabilityLaneStore {
  /// Starts empty, or with [initial] already saved.
  MemoryAvailabilityLaneStore([AvailabilityLaneState? initial])
    : _raw = initial == null ? null : jsonEncode(initial.toJson());

  /// Starts with [raw] stored verbatim (to model a damaged value).
  MemoryAvailabilityLaneStore.raw(String raw) : _raw = raw;

  String? _raw;

  /// Every successful write, in order.
  final List<AvailabilityLaneState> writes = [];

  /// Fails every write (typed, never a throw).
  bool failWrites = false;

  /// The saved state, or null when nothing (readable) is stored.
  AvailabilityLaneState? get saved => switch (_decode()) {
    AvailabilityLaneLoaded(:final state) => state,
    _ => null,
  };

  AvailabilityLaneRead _decode() {
    final raw = _raw;
    if (raw == null) return const AvailabilityLaneAbsent();
    try {
      return AvailabilityLaneState.decode(jsonDecode(raw));
    } on FormatException {
      return const AvailabilityLaneUnreadable();
    }
  }

  @override
  Future<AvailabilityLaneRead> read() async => _decode();

  @override
  Future<Either<Failure, Unit>> write(AvailabilityLaneState state) async {
    if (failWrites) return left(const StorageFailure('synthetic lane write'));
    _raw = jsonEncode(state.toJson());
    writes.add(state);
    return right(unit);
  }
}

/// A `CatalogueKeysReset` over in-memory records, for tests of the flows
/// that run through it (restore, overwrite merge) and of the reset itself.
final class MemoryKeysReset {
  /// Creates the parts and the reset over them.
  MemoryKeysReset() {
    reset = CatalogueKeysReset(
      queue: queue,
      gitHubRecord: gitHub,
      cloudflareRecord: cloudflare,
      lane: AvailabilityLaneRepository(laneStore),
      onIdsChanged: () => idsChanged++,
    );
  }

  /// The publish queue the reset uses.
  final SerialOpQueue queue = SerialOpQueue();

  /// The GitHub record.
  final LaneMemManifest gitHub = LaneMemManifest();

  /// The Cloudflare record and attempt.
  final InMemoryCloudflareManifestStore cloudflare =
      InMemoryCloudflareManifestStore();

  /// The lane store.
  final MemoryAvailabilityLaneStore laneStore = MemoryAvailabilityLaneStore();

  /// How often the reset reported a finished change.
  int idsChanged = 0;

  /// The reset under test.
  late final CatalogueKeysReset reset;
}
