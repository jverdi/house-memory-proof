#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p build/opencv-evidence
source_revision=fe38fc608f6acb8b68953438a62305d8318f4fcd
if [ ! -f build/opencv/opencv2.xcframework/Info.plist ]; then
  if [ ! -d build/opencv-source/.git ]; then
    git clone --depth 1 --branch 4.13.0 https://github.com/opencv/opencv.git build/opencv-source
  fi
  test "$(git -C build/opencv-source rev-parse HEAD)" = "$source_revision"
  python3 -m venv build/opencv-env
  build/opencv-env/bin/pip install cmake==3.31.10 setuptools==80.9.0
  export PATH="$PWD/build/opencv-env/bin:$PATH"
  python3 build/opencv-source/platforms/apple/build_xcframework.py \
    --out build/opencv --iphoneos_archs arm64 --iphonesimulator_archs arm64 \
    --build_only_specified_archs --iphoneos_deployment_target 26.0 \
    --without=objc --without=java --without=dnn --without=highgui \
    --without=imgcodecs --without=ml --without=photo --without=stitching \
    --without=video --without=videoio --without=objdetect --without=gapi \
    --without=world --without=ts \
    2>&1 | tee build/opencv-evidence/build.log
  cp build/opencv-source/LICENSE build/opencv/LICENSE
fi
python3 - <<'PY'
import plistlib,json,hashlib,subprocess
from pathlib import Path
root=Path('build/opencv/opencv2.xcframework')
info=plistlib.loads((root/'Info.plist').read_bytes())
report=[]
for lib in info['AvailableLibraries']:
 path=root/lib['LibraryIdentifier']/lib['LibraryPath']/'opencv2'
 report.append(dict(platform=lib['SupportedPlatform'],variant=lib.get('SupportedPlatformVariant','device'),architectures=lib['SupportedArchitectures'],sha256=hashlib.sha256(path.read_bytes()).hexdigest(),path=str(path)))
assert {x['variant'] for x in report}=={'device','simulator'}
assert all(x['architectures']==['arm64'] and x['platform']=='ios' for x in report)
Path('build/opencv-evidence/sdk.json').write_text(json.dumps(dict(source='fe38fc608f6acb8b68953438a62305d8318f4fcd',version='4.13.0',slices=report),indent=2))
print(json.dumps(report,indent=2))
PY
