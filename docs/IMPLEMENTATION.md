# Implementation and acceptance status

Updated during the October 17, 2026 implementation session. This document records actual scope; it does not replace or relax the approved architecture runbook.

## Release state

- Prior delivery proof: build 2.1 was installed by the owner.
- Current implementation: experimental, native integration in progress.
- Intermediate TestFlight uploads: disabled.
- Production readiness: **not established**.
- Field precision profile: **disabled**. No synthetic metric enables one.
- No promise that only field calibration remains: substantial software acceptance work remains below.

## Runbook package audit

| Phase | Implemented | Remaining acceptance work |
|---|---|---|
| P0 Delivery/native feasibility | Private repository, managed macOS build, Swift/C++ bridge, SQLite, Metal-backed rendering, MP4 encoding, internal TestFlight proof; offline IFC2x3 verified | Complete native dependency contract differs from planned OpenCV/Eigen/Ceres; renewal, device self-test retrieval and all IFC fixtures not qualified |
| P1 Contracts/store | Metres/Z-up adapters, rigid controls, schema validation, SHA assets, SQLite WAL/FULL transactions, prior revisions, additive decoding, recovery copies, ZIP64 | Full typed frame/dependency graph, fault injection at every persistence boundary, migration interruption matrix; history retains 20 previous JSON revisions |
| P2 Simulation | Paired synthetic three-room/two-level geometry, separate analytic evaluator, 50 noisy-plane cases, camera/depth/image generation, paired three-room noisy capture generator with isolated oracle | Diverse simulated houses, realistic pose drift, protected holdouts, sensor/lighting models, independent renderer equivalence, oracle-leakage qualification |
| P3 Reconstruction | ARKit mesh ingestion, bounded 2 cm point and signed-distance triangle fusion with distinct-view support, two-reference consensus drift constraints, source-linked texture projection and occlusion rejection, stale candidate check | Feature matching, bundle adjustment, robust pose graph, thin-service reconstruction, resumable fusion; current fusion uses raw ARKit poses unless consistent two-reference constraints are available |
| P4 Capture | Native photos/pose/calibration/depth/confidence, one-frame retention, periodic mesh checkpoint, thermal/storage pause, documentary import, observed-surface photo coverage, printable image references | Replay parity, stronger next-view guidance, wall/ceiling identity, metadata/time calibration, exhaustive interruption and memory tests |
| P5 Localization/stages | Separate session frames, explicit rigid manual registration with independent check, AR world-map/image-reference reveal, hidden overlay on lost eligibility; stage isolation | Finished visual maps, feature/PnP localization, wrong-room/floor rejection qualification, measured finish offsets, boundary-specific reveal, calibrated uncertainty. This is a critical blocker |
| P6 Walkthrough | Touch/controller movement, free fly, sample collision/doorway constraints, real recorded-camera corridor, picking, bookmarks, room jump, layer/ceiling switches | Real-house navigation proxy, stairs/verified portals, LOD/streaming, owner-device FPS/memory qualification, accessibility/landscape matrix |
| P7 Tours | Deterministic captured-viewpoint turns, explicit room cuts, common offscreen renderer, H.264, five-second resumable chunks, cache includes source/layers, share output | Collision-aware moving routes, choreography/presets, all interruption cases, native 1080p sustained qualification, optional 4K |
| P8 Labels/plans/import | Trade taxonomy, route tracing, endpoint labels, explicit user-confirmed links, OCR, source photos, PDF/image scale, bounded offline IFC and PLY | Drawing-to-house spatial alignment/revisions, confidence/review propagation, broader IFC units/placements/unsupported cases, optional Core ML suggestions |
| P9 Exports/recovery | GLB, textured USDZ, PLY/OBJ, metadata, streaming ZIP64, offline image index, fresh identity restore; independent readers in CI | Animated cameras/hierarchy, interactive offline 3D archive viewer, large-file stress/legacy matrix, all semantic export cases |
| P10 iCloud/resources | Local-only operation, portable Files/iCloud Drive archive, capture/storage/thermal guards, bounded buffers and mesh budgets | Coordinated automatic snapshots, partial arrivals/conflicts/quota/account changes, continued-processing resource governor, full owner-device stress |
| P11 Qualification | Native self-tests, integration workflow, portable core tests, independent export readers, XCUITest added | Full protected synthetic suite and native lifecycle matrix. Feature-complete candidate gate is not passed |
| P12 Field | Approximate status throughout UI, no enabled precision profile, independent manual registration check | Actual camera/pose/depth correctness, device performance, physical calibration and independent validation |
| P13 Sustained use | Export/recovery instructions, source checkpoints and delivery proof | Automated expiry/renewal, completed handoff and restore cycle, maintenance checks, production release manifest |

## Important implementation boundaries

1. Reconstruction is currently point/signed-distance surface fusion and ARKit surface capture, not general photogrammetry from arbitrary photos. Existing photographs remain useful documentary originals.
2. Image-reference boards are ARKit image targets, not a surveyed AprilTag system. Moving or resizing a board invalidates pose associations. Manual alignment is approximate even if a small set of checks fits.
3. Unregistered sessions are never silently overlaid. A view/export selects one unregistered frame; cross-session whole-house composition requires registration. Registered geometry may be composed in the house frame.
4. Rough/finished visibility uses the selected stage and stage naming convention. It is not a fully modeled wall-side/finish-offset system.
5. Coverage considers only mesh surfaces already observed. It cannot establish completeness of invisible cavities, far surfaces or absent mesh regions.
6. SceneKit uses Metal for the shared viewer/movie scene. A custom Metal renderer and full tiled scene system have not been implemented.
7. Tours turn at known viewpoints and cut between rooms; they do not invent continuous paths through uncaptured spaces. Completed encoded chunks resume; interrupted fusion restarts from originals.
8. The archive streams file bytes in 1 MiB chunks. Metadata is bounded to 100 MB; large-house/large-archive device stress is unqualified. The format supports ZIP64 but a format limit is not a tested capacity claim.
9. Runtime processing remains local. GitHub, Apple signing and TestFlight are development/distribution services. Optional automatic iCloud sync is absent.
10. No real-device capture, performance or precision result is inferred from simulator CI.

## Verified evidence so far

- Build run 39003385692: 23 native tests passed, actual simulator launch, rendered PNG and playable assembled MP4. Render and video frames inspected.
- Build run 39003899206: 28 native tests passed, including offline IFC2x3 extent 1×2×3 m; Khronos GLB validator reported zero errors/warnings. OpenUSD setup failed because the runner Python version had no compatible wheel; fixed by pinning Python 3.12 in subsequent CI.
- Build run 39003995500: streaming archive round trip and corruption rejection passed in native tests. Same older Python setup failed afterward; not a successful full gate.
- Build run 39004157350: synthetic camera pipeline produced 10,956 fused points with maximum plane distance 0.0008895 m, but texture test failed because the target exceeded the camera's field of view. Target framing was fixed; this failed run is not recorded as a passing pipeline.
- Build run 39004499104, source `94b6decb2ebee8e09d42497da8160fae80bc0a98`: **30 native tests, XCUITest navigation, 50 portable cases, plain/textured Khronos GLB validation, plain/textured OpenUSD parsing and independent ZIP64 validation all passed**. Reports are retained under `docs/evidence/native-14/`. No TestFlight upload occurred.
- Later integration results must be recorded before delivery. A pass on an earlier source is not automatically a pass on the final source.

## Continuation priorities

1. Finish current native integration and XCUITest/export-reader failures, retain exact-source evidence.
2. Add full pose/frame graph, robust reconstruction/localization and adversarial replay qualification before enabling precision.
3. Complete large-house navigation/streaming, drawing registration and independent end-to-end synthetic house scenarios.
4. Complete iCloud/resource/lifecycle gates and release only against an explicitly declared support profile.
5. Run actual owner-device synthetic workloads, then physical capture calibration and independent field validation.
