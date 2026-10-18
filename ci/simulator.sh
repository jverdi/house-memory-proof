#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/evidence
mode="${1:-all}"
case "$mode" in all|prepare|compile|release|boot|verify|exercise|native|recovery|ui) ;; *) echo 'Expected all, prepare, compile, release, boot, verify, exercise, native, recovery or ui'; exit 2;; esac
native_failed=0
if [ "$mode" = all ] || [ "$mode" = prepare ]; then
python3 tooling/project.py
git diff --exit-code -- HouseMemoryProof.xcodeproj/project.pbxproj
bash tooling/prepare-ifc.sh
node tooling/ifc/test_runtime.cjs
node tooling/ifc/test_geometry_runtime.cjs
node tooling/test_tour_framing.cjs
bash tooling/prepare-simulation.sh
bash tooling/opencv/build.sh
bash tooling/solver/build.sh ios
bash tooling/references/build.sh ios
cp build/apriltag/APRILTAG-LICENSE.txt HouseMemoryProof/IFC/
cp build/ceres/CERES-LICENSE.txt build/ceres/EIGEN-LICENSE.txt HouseMemoryProof/IFC/
cp build/opencv/LICENSE HouseMemoryProof/IFC/OPENCV-LICENSE.txt
fi
if [ "$mode" = prepare ]; then exit 0; fi
if [ "$mode" = release ]; then
  # Distribution conditional compilation must pass before an owner upload.
  # This compiles device code without signing or any Apple account operation.
  python3 ci/run_bounded.py 600 xcodebuild build \
    -project HouseMemoryProof.xcodeproj -scheme HouseMemoryProof \
    -configuration Release -destination 'generic/platform=iOS' \
    -derivedDataPath build/ReleaseValidation CODE_SIGNING_ALLOWED=NO \
    CURRENT_PROJECT_VERSION="${GITHUB_RUN_NUMBER:-1}.${GITHUB_RUN_ATTEMPT:-1}" \
    PROOF_SOURCE_REVISION="$(git rev-parse --short=10 HEAD)" \
    2>&1 | tee build/evidence/release-build.log
  exit 0
fi
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
if [ "$mode" != exercise ] && [ "$mode" != native ] && [ "$mode" != recovery ] && [ "$mode" != ui ] && [ "$mode" != boot ]; then
# Compile application and UI-test targets together before native runtime work.
python3 ci/run_bounded.py 600 xcodebuild build-for-testing \
  -project HouseMemoryProof.xcodeproj -scheme HouseMemoryProof \
  -configuration Debug -destination "platform=iOS Simulator,id=$device_id" \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES \
  CURRENT_PROJECT_VERSION="$build_number" PROOF_SOURCE_REVISION="$revision" \
  2>&1 | tee build/evidence/simulator-build.log
fi
if [ "$mode" = compile ]; then exit 0; fi
if [ "$mode" != recovery ] && [ "$mode" != ui ]; then
# Fresh hosted runners usually have no booted simulator. Handle an existing one too.
if ! xcrun simctl list devices booted | grep -Fq "$device_id"; then
  xcrun simctl boot "$device_id"
fi
# Cold platform migration took 185 seconds on a fresh hosted runner. This
# startup allowance is separate from the unchanged 300-second app test gate.
python3 ci/run_bounded.py 300 xcrun simctl bootstatus "$device_id" -b
if [ "$mode" = boot ]; then exit 0; fi
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

fi
app_data="$(xcrun simctl get_app_container "$device_id" com.example.HouseMemoryProof data)"
app_root="$app_data/Documents/HouseXray"
if [ -f "$app_data/Library/Application Support/HouseXray/house.sqlite" ]; then app_root="$app_data/Library/Application Support/HouseXray"; fi
if [ "$mode" != recovery ] && [ "$mode" != ui ]; then
for attempt in $(seq 1 150); do
  if [ -f "$app_root/self-test.json" ]; then break; fi
  if [ "$((attempt % 15))" -eq 0 ] && [ -f "$app_root/self-test-progress.json" ]; then
    cat "$app_root/self-test-progress.json"
  fi
  sleep 2
done
if [ -f "$app_root/self-test-progress.json" ]; then cp "$app_root/self-test-progress.json" build/evidence/native-progress.json; fi
# Preserve already-produced evidence before an incomplete diagnostic fails the job.
for retained in semantic.csv semantic-source.json interchange.ply interchange.obj metal-target.png coded-reference.pdf coded-reference-diagnostics.json coded-source-0.png coded-source-1.png self-test-partial.json test.hxray house-surface.glb points.glb points.usdz textured.usdz textured.glb test.glb test.usdz test-render.png drawing-baseline.png drawing-rotated-90.png drawing-rotated-180.png drawing-rotated-270.png; do
  if [ -f "$app_root/$retained" ]; then cp "$app_root/$retained" "build/evidence/$retained"; fi
done
if [ ! -f "$app_root/self-test.json" ]; then
  python3 - <<'PYDIAGNOSTIC'
import pathlib,re,subprocess
text=pathlib.Path('build/evidence/launch.log').read_text()
match=re.search(r'com\.example\.HouseMemoryProof:\s*(\d+)',text)
if match:
    try:
        result=subprocess.run(['/usr/bin/sample',match[1],'3','1','-file','build/evidence/incomplete-native-sample.txt'],timeout=15,capture_output=True,text=True)
        print('Incomplete diagnostic process sample:',result.returncode)
    except subprocess.TimeoutExpired: print('Process sampling timed out after 15 seconds')
reports=pathlib.Path.home()/'Library/Logs/DiagnosticReports'
for report in sorted(reports.glob('HouseMemoryProof*.ips'))[-3:]:
    data=report.read_bytes()
    if len(data)<=2_000_000:(pathlib.Path('build/evidence')/report.name).write_bytes(data)
raise SystemExit('Native diagnostics did not finish within the bounded run; partial evidence retained')
PYDIAGNOSTIC
fi
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
mkdir -p build/command-private
for name in ifc-source.glb ifc-registered.glb ifc-source.csv ifc-source.json ifc-properties.hxray ifc-properties.glb ifc-properties.csv drawing-marks.hxray service-envelopes.hxray service-envelopes.glb service-envelopes.csv reconstructed-navigation-private.json; do
  if [ -f "$app_root/$name" ]; then cp "$app_root/$name" "build/command-private/$name"; fi
done
if [ -f "$app_root/photo-curve.glb" ]; then cp "$app_root/photo-curve.glb" build/command-private/photo-curve.glb; fi
if [ -f "$app_root/photo-curve-viewer.html" ]; then cp "$app_root/photo-curve-viewer.html" build/command-private/photo-curve-viewer.html; fi
cp -R "$app_root/incremental-v2" build/evidence/incremental-v2
# Retain diagnostics before failing if the encoder did not produce a movie.
for media in native-navigation-benchmark.json native-reconstructed-navigation.json native-drawing-benchmark.json native-capture-runtime.json native-compatibility.json native-boundary-source.json native-service-tour.json native-ifc-geometry.json native-tour-reveal.json native-tour-framing.json test-tour.mp4 test-tour-frame.png metal-target.png large-house-render.png drawing-baseline.png drawing-rotated-90.png drawing-rotated-180.png drawing-rotated-270.png native-coverage-guidance.json; do
  if [ -f "$app_root/$media" ]; then cp "$app_root/$media" "build/evidence/$media"; fi
done
xcrun simctl io "$device_id" screenshot build/evidence/simulator.png
native_failed=0
python3 - <<'PYTEST' || native_failed=1
import json
r=json.load(open('build/evidence/native-self-test.json'))
failed=[t for t in r['tests'] if not t.get('passed')]
print(json.dumps({'nativePassed':r['passed'],'checks':len(r['tests']),'failures':failed},sort_keys=True))
if not r['passed']: raise SystemExit('Native diagnostic failures retained in native-self-test.json')
PYTEST
if [ "$native_failed" -eq 0 ]; then
  mkdir -p build/command-private
  printf '[]\n' > build/evidence/native-reader-status.json
  native_check() {
    local label="$1" status=0
    shift
    if "$@"; then status=0; else status=$?; native_failed=1; fi
    # Labels and exit codes only: retain the exact failing phase before the
    # longer UI suite, without publishing private fixture records.
    python3 - "$label" "$status" <<'PYSTATUS'
import json,pathlib,sys
path=pathlib.Path('build/evidence/native-reader-status.json')
rows=json.loads(path.read_text());rows.append(dict(check=sys.argv[1],exitCode=int(sys.argv[2]),passed=sys.argv[2]=='0'))
path.write_text(json.dumps(rows,indent=2)+'\n')
PYSTATUS
  }
  native_check navigation-benchmark-reader python3 tooling/check_navigation_benchmark.py build/evidence/native-navigation-benchmark.json --output build/evidence/navigation-benchmark-validation.json
  native_check reconstructed-navigation-reader python3 tooling/check_reconstructed_navigation.py build/evidence/native-reconstructed-navigation.json build/command-private/reconstructed-navigation-private.json --output build/evidence/reconstructed-navigation-validation.json
  native_check drawing-benchmark-reader python3 tooling/check_drawing_benchmark.py build/evidence/native-drawing-benchmark.json --output build/evidence/drawing-benchmark-validation.json
  native_check capture-runtime-reader python3 tooling/check_capture_runtime.py build/evidence/native-capture-runtime.json --output build/evidence/capture-runtime-validation.json
  native_check ifc-coordinate-contracts node tooling/ifc/test_coordinates.cjs
  native_check ifc-property-contracts node tooling/ifc/test_properties.cjs
  native_check ifc-source-reader python3 tooling/ifc/check_source.py build/command-private build/evidence
  native_check ifc-property-reader python3 tooling/ifc/check_properties.py build/command-private build/evidence
  native_check drawing-reader python3 tooling/check_drawing_marks.py build/command-private/drawing-marks.hxray build/evidence/drawing-marks-validation.json
  native_check envelope-reader python3 tooling/check_service_envelopes.py build/command-private build/evidence/service-envelope-validation.json
  native_check archive-reader python3 tooling/hm export-check --package build/evidence/test.hxray --output build/evidence/portable-package-validation.json
  native_check command-contracts python3 tooling/hm test --suite commands --output build/evidence/command-tests.json
  native_check tour-command python3 tooling/hm tour --scene "$app_root/command-reveal.hxray" --preset before-after --duration 5 --simulator "$device_id" --output build/command-private/tour > build/command-private/tour-result.json
  native_check reveal-reader python3 tooling/check_tour_reveal.py "$app_root/command-reveal.hxray" build/command-private/tour/tour.json build/evidence/tour-reveal-validation.json
  native_check tour-result python3 - <<'PYCOMMAND'
import json,pathlib,struct
root=pathlib.Path('build/command-private/tour')
try:
    result=json.loads((root/'result.json').read_text());plan=json.loads((root/'tour.json').read_text())
    assert result['independentProvenanceCheck']['passed']
    assert result['passed'] and result['frames']==150 and result['shots']==len(plan['shots'])>0
    assert sum(round(s['duration']*30) for s in plan['shots'])==150
    for name in result['previews']:
        image=(root/name).read_bytes();assert image[:8]==b'\x89PNG\r\n\x1a\n' and struct.unpack('>II',image[16:24])==(640,360)
    report=dict(passed=True,provenance=result['independentProvenanceCheck'],command='production native tour via CLI',shots=result['shots'],frames=result['frames'],previews=len(result['previews']),sourceModified=False,physicalQualification=False)
except Exception as error:
    report=dict(passed=False,command='production native tour via CLI',errorClass=type(error).__name__,physicalQualification=False)
pathlib.Path('build/evidence/cli-command-validation.json').write_text(json.dumps(report,indent=2)+'\n')
assert report['passed'],report
PYCOMMAND
  native_check service-tour-command python3 tooling/hm tour --scene "$app_root/command-services.hxray" --preset services --duration 10 --simulator "$device_id" --output build/command-private/service-tour > build/command-private/service-tour-result.json
  native_check service-tour-reader python3 tooling/check_tour_services.py "$app_root/command-services.hxray" build/command-private/service-tour/tour.json build/evidence/service-tour-validation.json
  native_check reconstruction-command python3 tooling/hm reconstruct --bundle "$app_root/command-capture.hxray" --kind points --simulator "$device_id" --output build/command-private/reconstruction > build/command-private/reconstruction-result.json
  native_check reconstruction-result python3 - <<'PYRECONSTRUCTION'
import json,pathlib
try:
    result=json.loads(pathlib.Path('build/command-private/reconstruction/result.json').read_text())
    assert result['passed'] and result['completed'] and not result['sourceModified']
    assert result['independentArchiveCheck']['passed'] and result['originalsVerified']>0
    assert len(result['sessions'])==1 and result['sessions'][0]['vertices']>0
    report=dict(passed=True,command='production native reconstruction via CLI',sessions=len(result['sessions']),originalsVerified=result['originalsVerified'],vertices=result['sessions'][0]['vertices'],independentArchivePassed=True,sourceModified=False,physicalQualification=False)
except Exception as error:
    report=dict(passed=False,command='production native reconstruction via CLI',errorClass=type(error).__name__,physicalQualification=False)
pathlib.Path('build/evidence/cli-reconstruction-validation.json').write_text(json.dumps(report,indent=2)+'\n')
assert report['passed'],report
PYRECONSTRUCTION
fi
fi
if [ "$mode" = native ]; then exit "$native_failed"; fi

# Kill at the journal/SQLite boundary, then verify recovery in a new process.
if [ "$mode" != ui ]; then
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
fi
if [ "$mode" = recovery ]; then exit 0; fi

set +e
# Seventeen workflows include the thirteen existing construction-record flows and
# four homeowner guidance flows. Run 222.1 exhausted the former 25-minute
# allocation during its seventeenth case. Allow 30 minutes for the expanded UI
# suite; native diagnostics and the 60-minute job keep their existing bounds.
python3 ci/run_bounded.py 1800 xcodebuild test -project HouseMemoryProof.xcodeproj -scheme HouseMemoryProof \
  -configuration Debug -destination "platform=iOS Simulator,id=$device_id" \
  -derivedDataPath build/DerivedData -resultBundlePath build/evidence/ui-tests.xcresult \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES \
  CURRENT_PROJECT_VERSION="$build_number" PROOF_SOURCE_REVISION="$revision" \
  2>&1 | tee build/evidence/ui-tests.log
ui_failed=${PIPESTATUS[0]}
set -e

if [ -d build/evidence/ui-tests.xcresult ]; then
  xcrun xcresulttool export attachments --path build/evidence/ui-tests.xcresult --output-path build/evidence/ui-attachments || true
fi

# Preserve a readable, SDK-formatted source package for the next reviewed checkpoint.
mkdir -p build/formatted-source
cp -R HouseMemoryProof HouseXrayUITests build/formatted-source/
rm -rf build/formatted-source/HouseMemoryProof/IFC build/formatted-source/HouseMemoryProof/Assets.xcassets
xcrun swift-format format --in-place --recursive build/formatted-source
tar -czf build/evidence/formatted-source.tgz -C build/formatted-source .
if [ "$native_failed" -ne 0 ]; then exit "$native_failed"; fi
exit "$ui_failed"

