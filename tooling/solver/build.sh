#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mode="${1:-host}"
root="$PWD/build/ceres"
mkdir -p "$root"
bounded() {
  python3 - "$@" <<'PYBOUND'
import subprocess,sys
limit=int(sys.argv[1]);command=sys.argv[2:]
try:
    result=subprocess.run(command,timeout=limit)
    raise SystemExit(result.returncode)
except subprocess.TimeoutExpired:
    raise SystemExit(f'Command exceeded its {limit}s budget: {command[0]}')
PYBOUND
}
if [ ! -d build/ceres-source/.git ]; then bounded 90 git clone --depth 1 --branch 2.2.0 https://github.com/ceres-solver/ceres-solver.git build/ceres-source; fi
test "$(git -C build/ceres-source rev-parse HEAD)" = 85331393dc0dff09f6fb9903ab0c4bfa3e134b01
if [ ! -d build/eigen-source/.git ]; then bounded 90 git clone --depth 1 --branch 3.4.0 https://gitlab.com/libeigen/eigen.git build/eigen-source; fi
test "$(git -C build/eigen-source rev-parse HEAD)" = 3147391d946bb4b6c68edd901f2add6ac1f31f8c
python3 -m venv build/solver-env
bounded 120 build/solver-env/bin/pip install --timeout 30 cmake==3.31.10
export PATH="$PWD/build/solver-env/bin:$PATH"
if [ ! -f "$root/eigen/share/eigen3/cmake/Eigen3Config.cmake" ]; then
  bounded 120 cmake -S build/eigen-source -B build/eigen-build -DBUILD_TESTING=OFF -DCMAKE_INSTALL_PREFIX="$root/eigen"
  bounded 120 cmake --install build/eigen-build
fi
build_slice() {
  slice="$1"
  if [ -f "$root/$slice/lib/libceres.a" ]; then
    cp -R build/ceres-source/internal/ceres/miniglog/glog "$root/$slice/include/"
    return
  fi
  extra=()
  if [ "$slice" = host ]; then extra=(-DCMAKE_OSX_DEPLOYMENT_TARGET=14.0); else extra=(-DCMAKE_SYSTEM_NAME=iOS -DIOS_DEPLOYMENT_TARGET=26.0 -DIOS_PLATFORM="$slice" -DCMAKE_OSX_SYSROOT="$slice" -DCMAKE_OSX_DEPLOYMENT_TARGET=26.0 -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY); fi
  bounded 120 cmake -S build/ceres-source -B "build/ceres-build-$slice" -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_INSTALL_PREFIX="$root/$slice" \
    -DEigen3_DIR="$root/eigen/share/eigen3/cmake" \
    -DMINIGLOG=ON -DGFLAGS=OFF -DBUILD_TESTING=OFF -DBUILD_EXAMPLES=OFF \
    -DBUILD_BENCHMARKS=OFF -DBUILD_DOCUMENTATION=OFF -DBUILD_SHARED_LIBS=OFF \
    -DSUITESPARSE=OFF -DLAPACK=OFF -DUSE_CUDA=OFF -DACCELERATESPARSE=OFF \
    -DEIGENSPARSE=ON -DEIGENMETIS=OFF -DSCHUR_SPECIALIZATIONS=OFF \
    -DCMAKE_CXX_FLAGS=-DEIGEN_MPL2_ONLY "${extra[@]}"
  bounded 900 cmake --build "build/ceres-build-$slice" --parallel 3
  bounded 120 cmake --install "build/ceres-build-$slice"
  cp -R "$root/eigen/include/eigen3/Eigen" "$root/$slice/include/"
  cp -R build/ceres-source/internal/ceres/miniglog/glog "$root/$slice/include/"
}
if [ "$mode" = ios ]; then
  build_slice iphoneos
  build_slice iphonesimulator
  if [ ! -f "$root/ceres.xcframework/Info.plist" ]; then
    xcodebuild -create-xcframework -library "$root/iphoneos/lib/libceres.a" -headers "$root/iphoneos/include" \
      -library "$root/iphonesimulator/lib/libceres.a" -headers "$root/iphonesimulator/include" -output "$root/ceres.xcframework"
  fi
elif [ "$mode" = host ]; then build_slice host
else echo 'Expected host or ios'; exit 1
fi
cp build/ceres-source/LICENSE "$root/CERES-LICENSE.txt"
cp build/eigen-source/COPYING.MPL2 "$root/EIGEN-LICENSE.txt"
