#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/evidence
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
# Fresh hosted runners usually have no booted simulator. Handle an existing one too.
if ! xcrun simctl list devices booted | grep -Fq "$device_id"; then
  xcrun simctl boot "$device_id"
fi
xcrun simctl bootstatus "$device_id" -b
revision="$(git rev-parse --short=10 HEAD)"
build_number="${GITHUB_RUN_NUMBER:-1}.${GITHUB_RUN_ATTEMPT:-1}"
xcodebuild build \
  -project HouseMemoryProof.xcodeproj -scheme HouseMemoryProof \
  -configuration Debug -destination "platform=iOS Simulator,id=$device_id" \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  CURRENT_PROJECT_VERSION="$build_number" PROOF_SOURCE_REVISION="$revision" \
  2>&1 | tee build/evidence/simulator-build.log
xcrun simctl install "$device_id" build/DerivedData/Build/Products/Debug-iphonesimulator/HouseMemoryProof.app
xcrun simctl launch "$device_id" com.example.HouseMemoryProof | tee build/evidence/launch.log
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
