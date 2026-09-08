# PLAN.md — Session 10: M05 archive resource limits

## Understanding

Only M05 is in scope (`fix-schedule.md` §1 NEXT). Three screens accept a
user-picked ZIP (`.pitabak` restore, `.pitabundle`/`.zip` import, vault
unlock-from-archive) and hand the whole file to
`lib/features/import_export/domain/bounded_zip_extractor.dart`. Today the caps
in `ZipLimits` are enforced only AFTER the dangerous allocations happen:

1. **No compressed-input cap.** `restore_page.dart:68`,
   `vault_unlock_page.dart:57` call `file.readAsBytes()` unconditionally;
   `import_page.dart:71–77` has a byte-length guard for text but explicitly
   skips it for ZIPs. A multi-GB pick is fully buffered before anything checks.
2. **Entry count checked after every header is parsed.**
   `ZipDecoder.decodeBytes` (`archive-3.6.1/lib/src/zip_decoder.dart:19–74`)
   builds the full `ZipDirectory` + one `ArchiveFile` per header first; our
   `entryCount > maxEntries` check runs on the finished list.
3. **Each entry fully decompresses before its real size is checked.**
   `entry.content` → `zip_file.dart:161–167` → `inflateBuffer` → `dart:io`
   `ZLibDecoder(raw: true).convert(...)` which has NO output bound. The header
   `uncompressedSize` we pre-check is attacker-supplied. Probe on the pinned
   SDK: a 65 232-byte archive inflates to 64 MiB (ratio 1028) in one shot.
4. **No integrity check.** `decodeBytes(verify: false)` is the default; a
   bit-flipped body passes into the restore/import path silently. Both the
   native and the pure-Dart inflater return truncated/garbage output without
   throwing on corrupt input (probe: 100 000-byte payload, one flipped byte →
   99 326 bytes, no exception). CRC-32 is the only detector.

Expected size per schedule: **two sessions**. Slice for this session: the
extractor hardening + input caps at all three pages + tests. Anything left is
recorded in Steps.

## Privacy & threat notes

- **Who:** anyone who can get a file onto the device and have the user pick it
  (messaging attachment, download, shared drive). No trust in the file at all.
- **What:** memory-exhaustion DoS (zip bomb, lying headers, millions of
  headers, a very large pick); silent acceptance of corrupted content.
- **What stops them after this fix:** bounded read at the picker
  (compressed-byte cap enforced while streaming, never trusting `length()`
  alone), EOCD pre-check (entry count + central-directory size) BEFORE
  `ZipDecoder` runs, streaming inflate that throws the moment the running
  output exceeds the per-entry / total budget, CRC-32 verification against the
  central directory, and explicit rejection of encrypted / non-deflate /
  zip64 entries our writer never produces.
- **Data minimization / local-first:** nothing leaves the device; no new
  logging (rejection messages carry entry names only inside the typed
  exception, which the UI already maps to fixed safe copy). No new permissions.
- **Honest limits:** whole-archive-in-RAM stays the accepted posture; peak
  memory is `archive bytes (≤ maxArchiveBytes) + extracted map (≤ maxTotal)`
  + one transient inflate buffer (≤ 2× the current entry's actual size, from
  `OutputStream`'s doubling growth). The defaults (200 MiB / 500 MiB / 4096)
  are unchanged — lowering them is a product decision, not this finding.

## Investigation notes (verified this session)

- `ZipDirectory.read` (`zip_directory.dart:27–63`): backward EOCD scan over the
  WHOLE input (`_findEocdrSignature`, O(n)); parses central headers until a
  signature mismatch (the EOCD entry count is not what bounds the loop — the
  `centralDirectorySize` slice is); then `readLocalFileHeader` for each →
  `ZipFile(...)` reads the local header and takes `compressedSize` bytes as a
  **view** (`input_stream.dart:195–199`, no copy). So header parsing is
  bounded by the central-directory size, not by the entry count.
- `ArchiveFile` from the decoder exposes `rawContent` (compressed view),
  `compressionType` (0 store / 8 deflate / other), `size` (central
  `uncompressedSize`), `crc32`, `isFile`, `name` (central filename —
  spoof-safe per archive issue #266). `decoder.directory.fileHeaders[i]` is the
  parallel `ZipFileHeader` with `generalPurposeBitFlag` (bit 0 = encrypted),
  `compressionMethod` (99 = AES) and `crc32`.
- `Inflate.stream(InputStreamBase, dynamic outputStream)` (`inflate.dart:24`)
  runs `_inflate()` in the constructor and writes through `writeByte`,
  `writeBytes`, `writeInputStream` on the output; `_decodeHuffman` also calls
  `output.subset(...)`, so the sink must be an `OutputStream` (public,
  non-final class). Largest single write is ≤ 65 535 bytes (stored block).
  Probe: a subclass that throws when `length` would exceed the cap aborted a
  64 MiB bomb at 1 048 577 bytes in 17 ms, having consumed ~1 KB of input.
- Throughput probe (pinned SDK, compiled): 32 MiB JSON-like text → native
  20 ms, pure-Dart 80 ms; 16 MiB incompressible (JPEG-like) → 4 ms both.
  Worst realistic full-cap restore adds ≈ 1 s. `getCrc32` over 200 MiB:
  452 ms.
- Corruption behaviour: neither inflater throws on flipped/truncated deflate
  data (truncation of the *container* still raises `RangeError`, which the
  existing `on Object` guards wrap). CRC-32 verification is required for the
  "actual content is what the archive claims" guarantee.
- `XFile.length()` (cross_file 0.3.5+4 `io.dart:106`) is a `stat`; the picker
  fakes in `restore_page_test.dart` use `XFile.fromData(bytes, length:)`, which
  lets a widget test declare a huge length without allocating it.
- Domain purity gate (`test/architecture/domain_purity_test.dart:56–63`)
  allow-lists `package:archive` in domain specifically for this file and
  already anticipates "M05 will harden the streaming path in place".

## Proposed approach (OSS references)

**Design choice — inflater:** keep the extractor in `domain/` and stream
through `archive`'s pure-Dart `Inflate.stream` into a capped `OutputStream`
subclass (option B). The alternative (A) — `dart:io` `RawZLibFilter`
chunked inflate — is 4× faster on text but requires `dart:io`, i.e. moving the
decoder to infrastructure and splitting the sniffer/limits out for the
application/presentation importers. The speed gain (~1 s at full caps, zero on
covers) does not justify the layering churn; B is recommended. Revisit only if
device testing shows restore latency matters.

Sources adapted (credited in code):
- **Go `archive/zip` `readDirectoryEnd`** (Go 1.26 `reader.go`): bounded
  backward EOCD scan (last 64 KiB + 22 bytes, the spec's max comment) and
  central-directory CRC as the authority. BSD-3.
- **Signal Android BackupImporter** size accounting — already the basis of
  this file; the running-total-with-early-abort is extended to the inflate
  loop.
- **`archive` 3.6.1 `Inflate.stream` + `OutputStream`** — public API used
  as-is; the capped sink is a subclass, not a fork.

Changes:

1. `ZipLimits` gains `maxArchiveBytes` (compressed input cap; default
   `maxTotalBytes + 4 MiB` header slack — an honest archive can never be
   larger than what it may contain plus headers) and
   `maxCentralDirectoryBytes` (default `maxEntries × 1 KiB`; flat archives
   have short names). Asserts keep the invariants.
2. `BoundedZipExtractor.extract`:
   - reject `bytes.length > maxArchiveBytes` first;
   - own EOCD pre-scan (bounded backward search) → reject zip64 markers,
     declared entry count > `maxEntries`, central-directory size >
     `maxCentralDirectoryBytes` or beyond the input — BEFORE `ZipDecoder`;
   - per entry: existing name/dup/directory checks; reject encrypted flag /
     method ∉ {store, deflate}; early declared-size + declared-running-total
     reject; stream-inflate into the capped sink with budget
     `min(maxEntryBytes, maxTotalBytes − totalSoFar)`; verify CRC-32 against
     the central directory; copy to an exact-size `Uint8List`.
   - The post-decode entry-count check stays (defence against a lying EOCD).
3. New `lib/core/platform/bounded_file_read.dart`:
   `readPickedFileBounded(XFile, {required int maxBytes})` → `length()` early
   reject, then `openRead()` streaming with a running total, fail closed at
   `maxBytes + 1`. Single source of truth for the three pages (and the import
   page's existing text branch, which is the same pattern).
4. Pages: `restore_page.dart`, `import_page.dart`, `vault_unlock_page.dart`
   use the helper with `ZipLimits.pitakaBackup.maxArchiveBytes` and show a
   fixed safe "too large" message.
5. Fix the stale KNOWN RESIDUAL comment in the extractor header.

## Decision points

- **D1 (design):** pure-Dart streaming inflate in domain vs `dart:io` native
  inflate in infrastructure. → **User decided (2026-09-08): B** — pure-Dart
  `Inflate.stream` + capped `OutputStream` subclass; extractor stays in
  `domain/`; no new dependency.
- **D2 (execution mode):** → **User decided (2026-09-08): (a) end-to-end.**
- Pause triggers under (a): any need for a new package (§6), any change to
  the default cap values, any test that cannot be made deterministic.

## Steps

- [x] Regression tests first (`bounded_zip_extractor_test.dart`, 31 new M05
      tests via a hand-built lying-header writer `hostile_zip_builder.dart`):
      input cap; 64 MiB→65 KB bomb with 1 MiB budget stopped AT the budget
      (probe proves ≤ 1 048 576 bytes produced); lying declared size both
      directions; EOCD count/directory-size/offset lies; zip64 markers;
      encrypted flag; unsupported methods; CRC mismatch; flipped-body sweep;
      local/central disagreement; symlink-flagged bomb; UNIX dir/regular
      classification; stored-block (level 0) budget; existing
      truncation/corruption loops still typed-only.
- [x] Implement `ZipLimits` additions + EOCD pre-scan + streaming inflate +
      CRC verify. **Mid-implementation correction:** `ZipDecoder.decodeBytes`
      inflates UNIX-symlink-flagged entries while building its `Archive`
      (`zip_decoder.dart:58–60`) — an unbounded native inflate BEFORE any
      caller check. Red-proved (64 MiB bomb inflated in 48 ms under the first
      cut), then switched to `ZipDirectory.read` (headers only) and classify
      file types ourselves (`_isRegularFile`, same rule as the decoder).
- [x] `lib/core/platform/bounded_file_read.dart` + 7 unit tests (exact-fit,
      one-over, lying `length` both directions, multi-chunk real file, empty).
- [x] Wire the three pages; widget tests: restore (oversize refused,
      recovers on a sane re-pick) and import (text cap, ZIP cap, honest pick
      still imports) via `XFile.fromData(length:)`. Vault-unlock page: same
      helper, same fixed message; no existing widget test harness for that
      page (its controller chain needs the Rust FFI) — recorded, not faked.
- [x] Extractor header comment rewritten (KNOWN RESIDUAL removed — it is now
      fixed); purity-gate comment updated. README/PRIVACY: no wording claims
      about archive limits exist → no change.
- [x] Gates: analyze 0; format 381/0; Flutter **1235 passed / 0 failed**
      (+43 over 1192 baseline); Rust 32 passed / 2 expected ignored;
      `git diff --check` clean. Coverage: extractor 144/148 (97.30%),
      `bounded_file_read` 8/8, restore page 142/150, import page 78/85;
      project 68.20% (floor 64%).
- [ ] Commit request with the explicit path manifest below.

## Commit manifest (awaiting §6 approval)

```
git add PLAN.md \
  lib/core/platform/bounded_file_read.dart \
  lib/features/import_export/domain/bounded_zip_extractor.dart \
  lib/features/backup/presentation/pages/restore_page.dart \
  lib/features/import_export/presentation/pages/import_page.dart \
  lib/features/vault/presentation/pages/vault_unlock_page.dart \
  test/architecture/domain_purity_test.dart \
  test/core/platform/bounded_file_read_test.dart \
  test/features/backup/restore_page_test.dart \
  test/features/import_export/bounded_zip_extractor_test.dart \
  test/features/import_export/hostile_zip_builder.dart \
  test/features/import_export/import_page_test.dart
git commit -m "sec(archive): enforce zip limits before allocation (M05)"
```

11 paths + PLAN.md = 12. Never stage `astra-review.md` / `fix-schedule.md`.

## Out-of-scope observations

- `merge_page.dart:62–70` has the same text-size pattern (length-then-read);
  switching it to the shared helper is a one-liner but is N07/N11 territory.
- Default caps (200 MiB / 500 MiB / 4096) are unchanged; the reviewer calls
  them "substantial". Lowering is a product decision for the user.
- `BackupArchiveWriter` reads every cover into memory to build the archive
  (write-side memory posture, not a hostile-input issue).

## Result

**M05 implemented; commit pending approval.** Every `ZipLimits` cap now fires
before the allocation it protects:

| Limit | Old point of enforcement | New point of enforcement |
|---|---|---|
| Compressed input size | none (`readAsBytes` unconditionally) | picker streams under `maxArchiveBytes`, counting real bytes; extractor re-checks |
| Entry count | after every header parsed into an `Archive` | EOCD record read by us first; re-checked per header |
| Central-directory size | none | EOCD pre-check (`maxCentralDirectoryBytes`), bounds-checked against input |
| Per-entry / total bytes | after the native inflater produced the whole entry | budgeted `OutputStream` subclass refuses the write that would cross `min(entry, remaining total)` |
| Integrity | none (`verify: false`) | CRC-32 against the central directory |
| Symlink / encrypted / non-deflate / zip64 | decoded (symlink target INFLATED by the decoder itself) | refused on the header |

Default cap values are unchanged (200 MiB / 500 MiB / 4096; input cap derives
as 504 MiB; directory cap 4 MiB).

**Honest limits.** Whole-archive-in-RAM remains the posture; the pure-Dart
inflater is ~4× slower than native on compressible data (measured 139 ms for
a 20 MiB JSON-like entry through the full extractor). No physical-device or
low-memory-device verification; bombs were exercised at small budgets in unit
tests. `XFile.length()` for content-provider URIs on Android is best-effort —
which is exactly why the streaming count, not the length, is the guarantee.
The vault-unlock page's cap path has no widget test (no harness for its
FFI-backed controller); it is the same three lines as the tested restore page.

**OSS credited:** Go `archive/zip` `readDirectoryEnd`/`findSignatureInBlock`
(bounded EOCD scan, BSD-3) in code; Signal BackupImporter accounting (already
credited); `package:archive` public `Inflate.stream`/`OutputStream`/
`ZipDirectory` used as-is, no fork.

**Privacy posture:** no new logging, network, permissions or persistence.
Rejection messages carry only entry names inside the typed exception, which
the pages already map to fixed copy.
