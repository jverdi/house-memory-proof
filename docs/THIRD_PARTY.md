# Third-party components

Runtime:
- Apple SwiftUI, ARKit, SceneKit (Metal rendering), Vision, PDFKit, AVFoundation, WebKit and CryptoKit: system frameworks under Apple's SDK terms.
- SQLite: iOS system SQLite, public-domain upstream. No third-party Swift wrapper is bundled.
- web-ifc **0.0.72**: Mozilla Public License 2.0. Unmodified browser JavaScript and single-threaded WASM are packaged by `tooling/prepare-ifc.sh`. Its LICENSE.md is included in the app's IFC resource folder. Corresponding source: https://github.com/ThatOpen/engine_web-ifc/tree/v0.0.72 . The app's bridge and HTML wrapper are separately authored. Original IFC sources are preserved. CI retains the npm integrity lockfile.

Development-only validation:
- trimesh **5.1.1**, MIT, https://github.com/mikedh/trimesh . Independent PLY/OBJ geometry reader used only in CI, with NumPy **2.3.5**. Neither is shipped in the app.
- Khronos glTF Validator **2.0.0-dev.3.10**, Apache-2.0, https://github.com/KhronosGroup/glTF-Validator . Not shipped in the app.
- OpenUSD `usd-core` **25.11**, Pixar/Apache-2.0 licensing as distributed upstream, https://github.com/PixarAnimationStudios/OpenUSD . Not shipped in the app.

The procedural house, geometry kernel, archive/export writers and image-reference patterns are authored for this project. No stock textures, external model weights, runtime CDN, remote reconstruction or analytics service is included.

## OpenCV native vision dependency

OpenCV 4.13.0, official source commit `fe38fc608f6acb8b68953438a62305d8318f4fcd`, is built as separate arm64 iOS and simulator slices. Source: https://github.com/opencv/opencv/tree/4.13.0 . Apache License 2.0; complete license is copied into `IFC/OPENCV-LICENSE.txt` at build time. Native AKAZE/MLDB feature matching and robust PnP operate locally. Their image residuals are not physical accuracy certification. Dependency and vision integration are still under test.

## Joint optimization

Ceres Solver 2.2.0 (BSD-3-Clause), official source commit `85331393dc0dff09f6fb9903ab0c4bfa3e134b01`, and Eigen 3.4.0 (MPL-2.0), official commit `3147391d946bb4b6c68edd901f2add6ac1f31f8c`, are statically compiled with `EIGEN_MPL2_ONLY`, minimal Ceres logging, and no CUDA, SuiteSparse, LAPACK or external logging dependency. Unmodified library source: https://github.com/ceres-solver/ceres-solver/tree/2.2.0 and https://gitlab.com/libeigen/eigen/-/tree/3.4.0 . Both complete license files are included in the app's IFC resources. Packaging and native integration are under qualification; no field-precision claim follows from using this solver.

