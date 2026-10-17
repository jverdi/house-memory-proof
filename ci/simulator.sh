#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/evidence
bash tooling/prepare-ifc.sh
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
xcodebuild build \
  -project HouseMemoryProof.xcodeproj -scheme HouseMemoryProof \
  -configuration Debug -destination "generic/platform=iOS Simulator" \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  CURRENT_PROJECT_VERSION="$build_number" PROOF_SOURCE_REVISION="$revision" \
  2>&1 | tee build/evidence/simulator-build.log
# Fresh hosted runners usually have no booted simulator. Handle an existing one too.
if ! xcrun simctl list devices booted | grep -Fq "$device_id"; then
  xcrun simctl boot "$device_id"
fi
xcrun simctl bootstatus "$device_id" -b
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
for attempt in $(seq 1 90); do
  if [ -f "$app_data/Library/Application Support/HouseXray/self-test.json" ]; then break; fi
  sleep 2
done
cp "$app_data/Library/Application Support/HouseXray/self-test.json" build/evidence/native-self-test.json
cp "$app_data/Library/Application Support/HouseXray/test.hxray" build/evidence/test.hxray
cp "$app_data/Library/Application Support/HouseXray/textured.usdz" build/evidence/textured.usdz
cp "$app_data/Library/Application Support/HouseXray/textured.glb" build/evidence/textured.glb
cp "$app_data/Library/Application Support/HouseXray/test.glb" build/evidence/test.glb
cp "$app_data/Library/Application Support/HouseXray/test.usdz" build/evidence/test.usdz
cp "$app_data/Library/Application Support/HouseXray/test-render.png" build/evidence/test-render.png
cp "$app_data/Library/Application Support/HouseXray/test-tour.mp4" build/evidence/test-tour.mp4
xcrun simctl io "$device_id" screenshot build/evidence/simulator.png
python3 - <<'PYTEST'
import json
r=json.load(open('build/evidence/native-self-test.json'))
assert r['passed'], r
print('All native self-tests passed:',len(r['tests']))
PYTEST

xcodebuild test -project HouseMemoryProof.xcodeproj -scheme HouseMemoryProof \
  -configuration Debug -destination "platform=iOS Simulator,id=$device_id" \
  -derivedDataPath build/DerivedData -resultBundlePath build/evidence/ui-tests.xcresult \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO \
  2>&1 | tee build/evidence/ui-tests.log

xcrun xcresulttool export attachments --path build/evidence/ui-tests.xcresult --output-path build/evidence/ui-attachments
