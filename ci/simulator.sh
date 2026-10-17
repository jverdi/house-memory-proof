#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/evidence
mode="${1:-all}"
case "$mode" in all|prepare|compile|verify|exercise) ;; *) echo 'Expected all, prepare, compile, verify or exercise'; exit 2;; esac
if [ "$mode" = all ] || [ "$mode" = prepare ]; then
bash tooling/prepare-ifc.sh
bash tooling/prepare-simulation.sh
bash tooling/opencv/build.sh
bash tooling/solver/build.sh ios
cp build/ceres/CERES-LICENSE.txt build/ceres/EIGEN-LICENSE.txt HouseMemoryProof/IFC/
cp build/opencv/LICENSE HouseMemoryProof/IFC/OPENCV-LICENSE.txt
fi
if [ "$mode" = prepare ]; then exit 0; fi
xcodebuild -version | tee build/evidence/xcode-version.txt
xcrun simctl list devices available --json > build/evidence/simulator-inventory.json
device_id="$(python3 - <<'PY'
import json
with open('build/evidence/simulator-inventory.json') as source:
    inventory = json.load(source)
for runtime, devices in sorted(inventory['devices'].items(), reverse=True):
    if '.iOS-' not in runtime:
        continue
    for device in devices:
        if device.get('isAvailable') and device['name'].startswith('iPhone'):
            print(device['udid'])
            raise SystemExit(0)
raise SystemExit('No available iPhone simulator. Update the managed runner image.')
PY
)"
revision="$(git rev-parse --short=10 HEAD)"
build_number="${GITHUB_RUN_NUMBER:-1}.${GITHUB_RUN_ATTEMPT:-1}"
if [ "$mode" != exercise ]; then
python3 ci/run_bounded.py 600 xcodebuild build \
  -project HouseMemoryProof.xcodeproj -scheme HouseMemoryProof \
  -configuration Debug -destination "platform=iOS Simulator,id=$device_id" \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES \
  CURRENT_PROJECT_VERSION="$build_number" PROOF_SOURCE_REVISION="$revision" \
  2>&1 | tee build/evidence/simulator-build.log
fi
if [ "$mode" = compile ]; then exit 0; fi
# Fresh hosted runners usually have no booted simulator. Handle an existing one too.
if ! xcrun simctl list devices booted | grep -Fq "$device_id"; then
  xcrun simctl boot "$device_id"
fi
python3 ci/run_bounded.py 180 xcrun simctl bootstatus "$device_id" -b
xcrun simctl install "$device_id" build/DerivedData/Build/Products/Debug-iphonesimulator/HouseMemoryProof.app
xcrun simctl launch "$device_id" com.example.HouseMemoryProof --demo --self-test --video-test | tee build/evidence/launch.log
# Allow the first SwiftUI frame to render before recording CI evidence.
sleep 3
xcrun simctl io "$device_id" screenshot build/evidence/simulator.png
python3 - "$revision" "$build_number" <<'PY'
import json, sys
from pathlib import Path
Path('build/evidence/simulator-result.json').write_text(json.dumps({
    'status': 'compiled_and_launch_command_succeeded',
    'revision': sys.argv[1], 'build': sys.argv[2],
    'device': 'iPhone simulator',
    'physical_iPhone_verified': False,
    'testflight_available': False
}, indent=2) + '\n')
PY

app_data="$(xcrun simctl get_app_container "$device_id" com.example.HouseMemoryProof data)"
app_root="$app_data/Documents/HouseXray"
if [ -f "$app_data/Library/Application Support/HouseXray/house.sqlite" ]; then app_root="$app_data/Library/Application Support/HouseXray"; fi
for attempt in $(seq 1 150); do
  if [ -f "$app_root/self-test.json" ]; then break; fi
  sleep 2
done
cp "$app_root/self-test.json" build/evidence/native-self-test.json
cp "$app_root/test.hxray" build/evidence/test.hxray
cp "$app_root/house-surface.glb" build/evidence/house-surface.glb
cp "$app_root/points.glb" build/evidence/points.glb
cp "$app_root/points.usdz" build/evidence/points.usdz
cp "$app_root/textured.usdz" build/evidence/textured.usdz
cp "$app_root/textured.glb" build/evidence/textured.glb
cp "$app_root/test.glb" build/evidence/test.glb
cp "$app_root/test.usdz" build/evidence/test.usdz
cp "$app_root/test-render.png" build/evidence/test-render.png
# Retain diagnostics before failing if the encoder did not produce a movie.
for media in test-tour.mp4 test-tour-frame.png; do
  if [ -f "$app_root/$media" ]; then cp "$app_root/$media" "build/evidence/$media"; fi
done
xcrun simctl io "$device_id" screenshot build/evidence/simulator.png
python3 - <<'PYTEST'
import json
r=json.load(open('build/evidence/native-self-test.json'))
assert r['passed'], r
print('All native self-tests passed:',len(r['tests']))
PYTEST

# Kill at the journal/SQLite boundary, then verify recovery in a new process.
for fault_mode in journal capture-row migration; do
xcrun simctl terminate "$device_id" com.example.HouseMemoryProof 2>/dev/null || true
rm -f "$app_root/fault-ready.json" "$app_root/process-recovery.json"
xcrun simctl launch "$device_id" com.example.HouseMemoryProof "--$fault_mode-fault"
for attempt in $(seq 1 30); do
  if [ -f "$app_root/fault-ready.json" ]; then break; fi
  sleep 1
done
xcrun simctl terminate "$device_id" com.example.HouseMemoryProof 2>/dev/null || true
recovery_mode=journal
if [ "$fault_mode" = migration ]; then recovery_mode=migration; fi
xcrun simctl launch "$device_id" com.example.HouseMemoryProof "--$recovery_mode-recovery-check"
for attempt in $(seq 1 30); do
  if [ -f "$app_root/process-recovery.json" ]; then break; fi
  sleep 1
done
cp "$app_root/process-recovery.json" "build/evidence/process-recovery-$fault_mode.json"
python3 -c "import json; r=json.load(open('build/evidence/process-recovery-$fault_mode.json')); assert r['passed'],r"
done

python3 ci/run_bounded.py 600 xcodebuild test -project HouseMemoryProof.xcodeproj -scheme HouseMemoryProof \
  -configuration Debug -destination "platform=iOS Simulator,id=$device_id" \
  -derivedDataPath build/DerivedData -resultBundlePath build/evidence/ui-tests.xcresult \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES \
  2>&1 | tee build/evidence/ui-tests.log

xcrun xcresulttool export attachments --path build/evidence/ui-tests.xcresult --output-path build/evidence/ui-attachments

# Preserve a readable, SDK-formatted source package for the next reviewed checkpoint.
mkdir -p build/formatted-source
cp -R HouseMemoryProof HouseXrayUITests build/formatted-source/
rm -rf build/formatted-source/HouseMemoryProof/IFC build/formatted-source/HouseMemoryProof/Assets.xcassets
xcrun swift-format format --in-place --recursive build/formatted-source
tar -czf build/evidence/formatted-source.tgz -C build/formatted-source .
