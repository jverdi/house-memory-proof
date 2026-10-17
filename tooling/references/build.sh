#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mode="${1:-host}"
root="$PWD/build/apriltag"
revision=94be783968e5091bcc9972c72c84fd63efce2935
mkdir -p "$root"
if [ ! -d build/apriltag-source/.git ]; then
  python3 ci/run_bounded.py 90 git clone --depth 1 --branch v3.4.5 https://github.com/AprilRobotics/apriltag.git build/apriltag-source
fi
test "$(git -C build/apriltag-source rev-parse HEAD)" = "$revision"
# Keep this small detector package independently buildable.
python3 -m venv build/apriltag-env
python3 ci/run_bounded.py 120 build/apriltag-env/bin/pip install --timeout 30 cmake==3.31.10
export PATH="$PWD/build/apriltag-env/bin:$PATH"
build_slice() {
  slice="$1"
  if [ -f "$root/$slice/lib/libapriltag.a" ]; then return; fi
  extra=()
  if [ "$slice" = host ]; then
    extra=(-DCMAKE_OSX_DEPLOYMENT_TARGET=14.0)
  else
    extra=(-DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT="$slice" -DCMAKE_OSX_DEPLOYMENT_TARGET=26.0 -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY)
  fi
  python3 ci/run_bounded.py 120 cmake -S build/apriltag-source -B "build/apriltag-build-$slice" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_INSTALL_PREFIX="$root/$slice" \
    -DBUILD_SHARED_LIBS=OFF -DBUILD_EXAMPLES=OFF -DBUILD_TESTING=OFF -DBUILD_PYTHON_WRAPPER=OFF "${extra[@]}"
  python3 ci/run_bounded.py 300 cmake --build "build/apriltag-build-$slice" --parallel 3
  python3 ci/run_bounded.py 60 cmake --install "build/apriltag-build-$slice"
}
if [ "$mode" = ios ]; then
  build_slice iphoneos
  build_slice iphonesimulator
  if [ ! -f "$root/apriltag.xcframework/Info.plist" ]; then
    xcodebuild -create-xcframework -library "$root/iphoneos/lib/libapriltag.a" -headers "$root/iphoneos/include" \
      -library "$root/iphonesimulator/lib/libapriltag.a" -headers "$root/iphonesimulator/include" -output "$root/apriltag.xcframework"
  fi
elif [ "$mode" = host ]; then build_slice host
else echo 'Expected host or ios'; exit 1
fi
cp build/apriltag-source/LICENSE.md "$root/APRILTAG-LICENSE.txt"
