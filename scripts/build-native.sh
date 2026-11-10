#!/usr/bin/env bash
# Builds the native Windows version of SmartMotion Flight into build/native/SmartMotionFlight-Windows.zip
# Needs Godot 4.6.1 with its export templates installed.  Usage:  GODOT=/path/to/godot scripts/build-native.sh
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
OUT=build/native
rm -rf "$OUT" && mkdir -p "$OUT/SmartMotionFlight"
"$GODOT" --headless --path godot --import >/dev/null 2>&1 || true
echo "Checking the flight physics..."
"$GODOT" --headless --path godot --script res://tests/test_flight.gd | grep -E "FAIL|All checks passed|failed" || true
"$GODOT" --headless --path godot --script res://tests/test_flight.gd >/dev/null   # a failing check stops the build
"$GODOT" --headless --path godot --script res://tests/test_scenery.gd | grep -E "FAIL|All checks passed|failed" || true
"$GODOT" --headless --path godot --script res://tests/test_scenery.gd >/dev/null   # scenery streaming checks
"$GODOT" --headless --path godot --script res://tests/test_race.gd | grep -E "FAIL|All checks passed|failed" || true
"$GODOT" --headless --path godot --script res://tests/test_race.gd >/dev/null   # racing car physics and race checks
"$GODOT" --headless --path godot --script res://tests/test_coaster.gd | grep -E "FAIL|All checks passed|failed" || true
"$GODOT" --headless --path godot --script res://tests/test_coaster.gd >/dev/null   # roller coaster checks
"$GODOT" --headless --path godot -- --test_panel | grep -E "PASS|FAIL" || true
! "$GODOT" --headless --path godot -- --test_panel | grep -q FAIL   # VR menu panel checks
echo "Exporting the Windows build..."
"$GODOT" --headless --path godot --export-release "Windows Desktop" "$PWD/$OUT/SmartMotionFlight/SmartMotionFlight.exe" >/dev/null 2>&1
test -s "$OUT/SmartMotionFlight/SmartMotionFlight.exe" || { echo "Export failed"; exit 1; }
VERSION="$(tr -d '[:space:]' < VERSION)"
for f in godot/package/*; do sed "s/@VERSION@/$VERSION/g" "$f" > "$OUT/SmartMotionFlight/$(basename "$f")"; done
python3 - "$OUT" <<'PY'
import os, sys, zipfile
out = sys.argv[1]; root = os.path.join(out, "SmartMotionFlight")
with zipfile.ZipFile(os.path.join(out, "SmartMotionFlight-Windows.zip"), "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for f in sorted(os.listdir(root)):
        z.write(os.path.join(root, f), "SmartMotionFlight/" + f)
print("Built", os.path.join(out, "SmartMotionFlight-Windows.zip"), round(os.path.getsize(os.path.join(out, "SmartMotionFlight-Windows.zip")) / 1048576, 1), "MB")
PY
