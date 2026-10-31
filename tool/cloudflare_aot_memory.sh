#!/usr/bin/env bash
# Records S8 Cloudflare upload memory evidence on an Android AOT build.
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <android-device-id>" >&2
  exit 64
fi

DEVICE="$1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ADB="${ADB:-adb}"
MODE="${S8_AOT_MODE:-profile}"
if [[ "$MODE" != "profile" && "$MODE" != "release" ]]; then
  echo "S8_AOT_MODE must be profile or release" >&2
  exit 64
fi
if [[ -n "${S8_MEMORY_DEVICE_PATH:-}" ]]; then
  DEVICE_PATH="$S8_MEMORY_DEVICE_PATH"
else
  DEVICE_PATH="/data/user/0/dev.khoj.pitaka.fdroid/app_flutter/pitaka_s8_memory.json"
fi
LOG="${S8_MEMORY_LOG:-$ROOT/build/cloudflare_aot_memory.log}"
DEVICE_JSON="${S8_MEMORY_DEVICE_JSON:-$ROOT/build/cloudflare_aot_memory_device.json}"
OUT="${S8_MEMORY_OUT:-$ROOT/build/cloudflare_aot_memory.json}"
mkdir -p "$(dirname "$LOG")" "$(dirname "$DEVICE_JSON")" "$(dirname "$OUT")"
rm -f "$OUT" "$DEVICE_JSON"
if [[ "$MODE" == "release" && "$DEVICE_PATH" != /sdcard/* && "$DEVICE_PATH" != /storage/* ]]; then
  if [[ "$("$ADB" -s "$DEVICE" shell id -u)" != "0" ]]; then
    echo "release evidence needs 'adb root' on the test emulator" >&2
    exit 64
  fi
fi

read_device_file() {
  if [[ "$DEVICE_PATH" == /sdcard/* || "$DEVICE_PATH" == /storage/* || "$MODE" == "release" ]]; then
    "$ADB" -s "$DEVICE" shell cat "$DEVICE_PATH"
  else
    "$ADB" -s "$DEVICE" shell run-as dev.khoj.pitaka.fdroid cat "$DEVICE_PATH"
  fi
}

delete_device_file() {
  if [[ "$DEVICE_PATH" == /sdcard/* || "$DEVICE_PATH" == /storage/* || "$MODE" == "release" ]]; then
    "$ADB" -s "$DEVICE" shell rm -f "$DEVICE_PATH"
  else
    "$ADB" -s "$DEVICE" shell run-as dev.khoj.pitaka.fdroid rm -f "$DEVICE_PATH"
  fi
}

cd "$ROOT"
fvm flutter build apk "--$MODE" --flavor fdroid \
  --dart-define="S8_MEMORY_OUTPUT=$DEVICE_PATH" \
  -t lib/main_dev_harness.dart 2>&1 | tee "$LOG"
"$ADB" -s "$DEVICE" uninstall dev.khoj.pitaka.fdroid >/dev/null 2>&1 || true
"$ADB" -s "$DEVICE" install "build/app/outputs/flutter-apk/app-fdroid-$MODE.apk"
if [[ "$DEVICE_PATH" == /sdcard/* || "$DEVICE_PATH" == /storage/* ]]; then
  "$ADB" -s "$DEVICE" shell mkdir -p "$(dirname "$DEVICE_PATH")"
  "$ADB" -s "$DEVICE" shell chmod 777 "$(dirname "$DEVICE_PATH")"
fi
delete_device_file
"$ADB" -s "$DEVICE" shell am force-stop dev.khoj.pitaka.fdroid
"$ADB" -s "$DEVICE" shell am start -W -n dev.khoj.pitaka.fdroid/dev.khoj.pitaka.MainActivity

for _ in {1..90}; do
  if read_device_file 2>/dev/null | python3 -c 'import json,sys; data=json.load(sys.stdin); valid=data.get("fileCount")==413 and data.get("uploadedAssets")==413 and data.get("requestCount")==1 and data.get("metadataOnlyBuild") is True and isinstance(data.get("peakRssBytes"),int); raise SystemExit(0 if valid else 1)' 2>/dev/null; then
    break
  fi
  sleep 1
done
read_device_file > "$DEVICE_JSON" 2>/dev/null || true

python3 - "$DEVICE_JSON" "$OUT" <<'PY'
import json
import os
import sys

device_path, out_path = sys.argv[1:]
if not os.path.exists(device_path):
    raise SystemExit("no valid S8_AOT_MEMORY record found")
with open(device_path, encoding="utf-8") as source:
    record = json.load(source)
valid = (
    record.get("fileCount") == 413
    and record.get("uploadedAssets") == 413
    and record.get("requestCount") == 1
    and record.get("metadataOnlyBuild") is True
    and isinstance(record.get("peakRssBytes"), int)
)
if not valid:
    raise SystemExit(f"invalid S8_AOT_MEMORY record: {record}")
with open(out_path, "w", encoding="utf-8") as target:
    json.dump(record, target, indent=2, sort_keys=True)
    target.write("\n")
print(json.dumps(record, indent=2, sort_keys=True))
PY
