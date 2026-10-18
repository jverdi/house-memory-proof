#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p build/vision-evaluation
if [ ! -f build/opencv-host/opencv2.framework/opencv2 ]; then
  if [ ! -d build/opencv-source/.git ]; then
    git clone --depth 1 --branch 4.13.0 https://github.com/opencv/opencv.git build/opencv-source
  fi
  test "$(git -C build/opencv-source rev-parse HEAD)" = fe38fc608f6acb8b68953438a62305d8318f4fcd
  python3 -m venv build/opencv-host-env
  build/opencv-host-env/bin/pip install cmake==3.31.10 setuptools==80.9.0
  export PATH="$PWD/build/opencv-host-env/bin:$PATH"
  python3 build/opencv-source/platforms/osx/build_framework.py build/opencv-host \
    --macos_archs arm64 --build_only_specified_archs --macosx_deployment_target 14.0 \
    --without=objc --without=java --without=dnn --without=highgui \
    --without=imgcodecs --without=ml --without=photo --without=stitching \
    --without=video --without=videoio --without=objdetect --without=gapi --without=world --without=ts \
    2>&1 | tee build/vision-evaluation/sdk-build.log
fi
bash tooling/solver/build.sh host
bash tooling/references/build.sh host
clang -std=c11 -O2 -arch arm64 -mmacosx-version-min=14.0 -I build/apriltag/host/include \
  -c packages/reference-core/hx_tags.c -o build/reference-tags.o
clang++ -std=c++17 -O2 -arch arm64 -mmacosx-version-min=14.0 \
  -F build/opencv-host -c packages/visual-core/hx_vision.cpp -o build/vision-core.o
clang++ -std=c++17 -O2 -arch arm64 -mmacosx-version-min=14.0 \
  -F build/opencv-host -c packages/visual-core/hx_vision_test.cpp -o build/vision-core-test.o
clang++ -std=c++17 -O2 -arch arm64 -mmacosx-version-min=14.0 -F build/opencv-host -I build/ceres/host/include -c packages/visual-core/hx_graph.cpp -o build/graph-core.o
clang++ -std=c++17 -O2 -arch arm64 -mmacosx-version-min=14.0 -I build/ceres/host/include -c packages/visual-core/hx_bundle.cpp -o build/bundle-core.o
clang++ -std=c++17 -O2 -arch arm64 -mmacosx-version-min=14.0 -F build/opencv-host -I build/ceres/host/include -c packages/reference-core/hx_reference_pose.cpp -o build/reference-pose.o
swiftc -O -swift-version 5 -parse-as-library -target arm64-apple-macos14.0 \
  -import-objc-header packages/visual-core/hx_replay.h \
  HouseMemoryProof/Domain.swift HouseMemoryProof/EvidenceModels.swift HouseMemoryProof/ServiceDetails.swift HouseMemoryProof/PointCloudImport.swift HouseMemoryProof/IFCProperties.swift HouseMemoryProof/DrawingMarks.swift HouseMemoryProof/ServiceEnvelope.swift \
  HouseMemoryProof/PoseRefinement.swift HouseMemoryProof/VisualMapping.swift HouseMemoryProof/PoseGraph.swift HouseMemoryProof/ReferenceRegistration.swift HouseMemoryProof/PhotoReconstruction.swift HouseMemoryProof/BundleRefinement.swift HouseMemoryProof/CodedReferences.swift \
  tooling/simulation/VisionReplay.swift build/vision-core.o build/vision-core-test.o build/graph-core.o build/bundle-core.o build/reference-pose.o build/reference-tags.o build/apriltag/host/lib/libapriltag.a build/ceres/host/lib/libceres.a \
  -F build/opencv-host -framework opencv2 -framework Accelerate -framework OpenCL \
  -framework Foundation -framework CoreGraphics -framework ImageIO -lc++ -lz \
  -o build/vision-replay
build/vision-replay --self-test > build/vision-evaluation/core-diagnostics.json
