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
| P3 Reconstruction | ARKit mesh ingestion, bounded 2 cm point and signed-distance triangle fusion with distinct-view support, two-reference consensus drift constraints, bounded RGB-D pose graph refinement, source-linked texture projection and occlusion rejection, stale candidate check | Whole-house bundle adjustment/pose graph, thin-service reconstruction; current fusion uses raw ARKit poses, consistent reference constraints, or a saved local pose graph covering up to 12 textured views |
| P4 Capture | Native photos/pose/calibration/depth/confidence, one-frame retention, periodic mesh checkpoint, thermal/storage pause, documentary import, observed-surface photo coverage, printable image references | Replay parity, stronger next-view guidance, wall/ceiling identity, metadata/time calibration, exhaustive interruption and memory tests |
| P5 Localization/stages | Separate session frames, explicit rigid manual registration with independent check, AR world-map/image-reference reveal, hidden overlay on lost eligibility; stage isolation | OpenCV feature/PnP maps passed one native image fixture; protected wrong-room/floor rejection qualification, measured finish offsets, boundary-specific reveal, calibrated uncertainty. This is a critical blocker |
| P6 Walkthrough | Touch/controller movement, free fly, sample collision/doorway constraints, real recorded-camera corridor, picking, bookmarks, room jump, layer/ceiling switches | Real-house navigation proxy, stairs/verified portals, LOD/streaming, owner-device FPS/memory qualification, accessibility/landscape matrix |
| P7 Tours | Deterministic short recorded-camera moves checked against observed geometry, captured-viewpoint turns, explicit cuts, common offscreen renderer, H.264, five-second resumable chunks, cache includes source/layers, share output | Long continuous route planning, choreography/presets, all interruption cases, native 1080p sustained qualification, optional 4K |
| P8 Labels/plans/import | Trade taxonomy, route tracing, endpoint labels, explicit user-confirmed links, OCR, source photos, PDF/image scale, independently checked drawing-to-house design overlays, bounded offline IFC and PLY | Drawing revision comparison, confidence/review propagation, broader IFC units/placements/unsupported cases, optional Core ML suggestions |
| P9 Exports/recovery | GLB, textured USDZ, PLY/OBJ, metadata, streaming ZIP64, offline image index, fresh identity restore; independent readers in CI | Animated cameras/hierarchy, interactive offline 3D archive viewer, large-file stress/legacy matrix, all semantic export cases |
| P10 iCloud/resources | Local-only operation, coordinated full snapshots to a user-selected Files/iCloud Drive folder, optional daily-on-open scheduling, capture/storage/thermal guards, bounded buffers and mesh budgets | Incremental chunks, real-provider partial arrivals/conflicts/quota/account changes, continued-processing resource governor, full owner-device stress |
| P11 Qualification | Native self-tests, integration workflow, portable core tests, independent export readers, XCUITest added | Full protected synthetic suite and native lifecycle matrix. Feature-complete candidate gate is not passed |
| P12 Field | Approximate status throughout UI, no enabled precision profile, independent manual registration check | Actual camera/pose/depth correctness, device performance, physical calibration and independent validation |
| P13 Sustained use | Export/recovery instructions, source checkpoints and delivery proof | Enable and verify prepared expiry/renewal, completed handoff and restore cycle, maintenance checks, production release manifest |

## Important implementation boundaries

1. Reconstruction is currently point/signed-distance surface fusion and ARKit surface capture, not general photogrammetry from arbitrary photos. Existing photographs remain useful documentary originals.
2. Image-reference boards are ARKit image targets, not a surveyed AprilTag system. Moving or resizing a board invalidates pose associations. Manual alignment is approximate even if a small set of checks fits.
3. Unregistered sessions are never silently overlaid. A view/export selects one unregistered frame; cross-session whole-house composition requires registration. Registered geometry may be composed in the house frame.
4. Rough/finished visibility uses the selected stage and stage naming convention. It is not a fully modeled wall-side/finish-offset system.
5. Coverage considers only mesh surfaces already observed. It cannot establish completeness of invisible cavities, far surfaces or absent mesh regions.
6. SceneKit uses Metal for the shared viewer/movie scene. A custom Metal renderer and full tiled scene system have not been implemented.
7. Tours use short consecutive recorded-camera segments only after observed-geometry clearance and camera-corridor checks, otherwise turn at known viewpoints. Cuts separate shots and rooms; unseen obstacles and continuous whole-house routes are not established. Completed encoded chunks and triangle-fusion checkpoints resume; point fusion restarts from originals.
8. The archive streams file bytes in 1 MiB chunks. Metadata is bounded to 100 MB; large-house/large-archive device stress is unqualified. The format supports ZIP64 but a format limit is not a tested capacity claim.
9. Runtime processing remains local. GitHub, Apple signing and TestFlight are development/distribution services. Optional full snapshots use a user-selected Files folder and file coordination; native container-based incremental iCloud sync is absent. Provider lifecycle behavior is not qualified.
10. No real-device capture, performance or precision result is inferred from simulator CI.

## Verified evidence so far

- Build run 39003385692: 23 native tests passed, actual simulator launch, rendered PNG and playable assembled MP4. Render and video frames inspected.
- Build run 39003899206: 28 native tests passed, including offline IFC2x3 extent 1×2×3 m; Khronos GLB validator reported zero errors/warnings. OpenUSD setup failed because the runner Python version had no compatible wheel; fixed by pinning Python 3.12 in subsequent CI.
- Build run 39003995500: streaming archive round trip and corruption rejection passed in native tests. Same older Python setup failed afterward; not a successful full gate.
- Build run 39004157350: synthetic camera pipeline produced 10,956 fused points with maximum plane distance 0.0008895 m, but texture test failed because the target exceeded the camera's field of view. Target framing was fixed; this failed run is not recorded as a passing pipeline.
- Build run 39004499104, source `94b6decb2ebee8e09d42497da8160fae80bc0a98`: **30 native tests, XCUITest navigation, 50 portable cases, plain/textured Khronos GLB validation, plain/textured OpenUSD parsing and independent ZIP64 validation all passed**. Reports are retained under `docs/evidence/native-14/`. No TestFlight upload occurred.
- Run 39005535734: native paired three-room/144-observation archive replay, surface reconstruction, reference-consensus checks and point/surface/textured exports passed the integrated simulator workflow.
- Frozen portable surface evaluation: **67/70** noisy unreferenced room cases produced surfaces; **38/70** met a nearest-surface p95 ≤10 mm comparison. The other cases were not waived. This is not a qualified precision result; source hashes, seed split, input hashes and all case results are retained in `docs/evidence/surface-evaluation/`. There is no completeness denominator or full sensor/localization qualification in this suite.
- Later integration results must be recorded before delivery. A pass on an earlier source is not automatically a pass on the final source.

## Continuation priorities

1. Finish current native integration and XCUITest/export-reader failures, retain exact-source evidence.
2. Add full pose/frame graph, robust reconstruction/localization and adversarial replay qualification before enabling precision.
3. Complete large-house navigation/streaming, drawing registration and independent end-to-end synthetic house scenarios.
4. Complete iCloud/resource/lifecycle gates and release only against an explicitly declared support profile.
5. Run actual owner-device synthetic workloads, then physical capture calibration and independent field validation.

- Drawing alignment implementation uses three fitting controls and a separate check, rejects both fitting and held-out errors above 25 mm, and keeps the rendered sheet explicitly planned. Neither a fitting residual nor a sheet overlay enables precision. Native drawing controls passed in source a12d1249e8.

- Source `a12d1249e8f939e32eebfab6240df7838dea7160`, run 39007121108: **47 native tests plus complete integrated UI/export-reader workflow passed**. Includes capture journal startup replay, original-project routing, IFC4 units/nested placement, checked drawing alignment, and conservative geometry clearance. Reports retained in `docs/evidence/native-31/`. This precedes visual localization integration.
- OpenCV 4.13.0 pinned source built successfully for arm64 device/simulator in run 39007235851. Feature extraction, multi-view PnP agreement and visual map persistence are now integrated in source; they are not yet accepted as a passing image localization path.

- Source `188f337048d93427085d23ed4243ee211d9a774b`, run 39008613250: **54 native tests plus UI and independent export readers passed**. The native image fixture localizes held camera views without supplying query poses, rejects unrelated texture, and tests metric feature alignment, injected camera drift correction, and an inconsistent pose-graph loop. Retained in `docs/evidence/native-41/`. This does not qualify complete-house localization or physical accuracy.
- The local graph is a bounded robust metric RGB-D graph using OpenCV linear algebra, anchored at its first camera. It is not the runbook's full Ceres bundle adjustment. Raw observations are immutable; invalidated solutions are not selected. Broader isolated evaluation remains pending.
- New source after that checkpoint adds three-photo manual point triangulation, derived-geometry input fingerprints, and rejection of competing saved-room visual matches. These additions need their own integrated native evidence before acceptance. Runtime competing-map search is bounded to 24 maps / 32 MB; exceeding the budget disables the visual-reference path rather than searching an incomplete set. Unmapped-room ambiguity is not solved.

- Source `fbebf976c203cdb700e91c2aea50a92ab6afadef`, run 39009513936: **57 native checks and both XCUITest flows passed**, including three-photo selection/save and byte-equivalent surface checkpoint resume. Independent export readers passed. Evidence is in `docs/evidence/native-51/`. Original storage is visible in Files for new installs; legacy stores stay in place.
- Source `70f4d8e6db6d248d8fe8ab2fca877c88dc92a7e8`, run 39009362626: isolated exact-production Swift/C++ replay passed its development diagnostics. Five additional analytic room seeds accepted **13/15** matching queries, rejected **5/5** unrelated queries, and had maximum accepted position error **10.77 mm**. Mapping-camera drift corrections had maximum error **6.24 mm**. OS sandbox controls denied the oracle on every case. These are small development denominators, not protected wrong-room or precision qualification. Evidence is in `docs/evidence/visual-replay-70/`.
- Latest source adds oriented named reveal volumes with explicit cavity depth/finish offset, polygon clipping, and front-side eligibility. These need native qualification; they do not establish measured wall geometry automatically.
- Scheduled renewal is prepared but disabled until a candidate is accepted. No implementation build has been uploaded.

## October 17 continuation checkpoint

Source `f300a1b0f8ab3bace0819270347639b8f5e22ef8`, run `39011993345`, passed **66 native checks, both UI workflows, independent exports and the offline browser viewer**. Reports are retained in `docs/evidence/native-67/`. The process test actually kills the app after its durable capture journal is written and verifies exactly-once recovery in a new process; sudden power loss is not qualified.

Additional implemented behavior supersedes the older audit entries where noted:

- Explicit construction-stage categories, oriented reveal rectangles with cavity depth/finish offset, crossing-triangle clipping and opposite-side hiding. Boundaries remain user-defined and approximate.
- A nominal back-plane coverage denominator includes unseen regions, rather than only observed mesh surfaces. It identifies missing views and foreground blockage but cannot establish hidden-service completeness.
- Sparse photograph-only triangulation retains at least three image observations per point. It uses camera estimates and does not turn arbitrary documentary photos into a reconstruction.
- Three shared fixed reference boards support cross-session registration with a held-out board check. Invalidated dependency chains lose their registrations; custom decoding now preserves the dependency and saved camera-solution fields.
- Incremental Files-folder snapshots deduplicate immutable originals and restore a selected revision as a separate house. Existing remote assets are rehashed, so large-provider performance and actual cloud completion remain unqualified.
- Display-only geometry reduction and texture budgets bound rendering detail. Recorded camera paths can follow gentle changes in height; a full-house tiled scene system and verified stair/portal navigation are not complete.
- Archives include a self-contained WebGL viewer with zero external requests in browser checks. Model exports preserve their full source geometry independently of display reductions.

Frozen Cycles development fixture, source `b32b5fb9a5519c3e3328f19fbe7d6dfb0febb3c2`, run `39011589852`: **2/3** scored matching images accepted, **0/1** unrelated false accepts, worst accepted position error **6.780 mm**. Five connected camera views were optimized; one unsupported photograph was excluded. Maximum optimized camera position error was **7.105 mm** with 30 mm injected prior drift. A finished-stage exploratory query also matched, but is not included in the scored positive denominator. These denominators are too small for production claims.

The continuation adds pinned Ceres/Eigen joint image/depth/pose optimization, bounded to 120 cameras and 2,000 points at the C interface, with two fitting observations per point and remaining image observations held out of the objective. The current Swift track builder still samples at most twelve views; the C interface bound is not a proven whole-house capacity. Numerical factor derivatives, native image-track replay and independent query localization are required before accepting the integration. Packaging and validation are currently in progress. No precision profile or implementation TestFlight upload has been enabled.

The next source checkpoint extends session graphs to at most 120 keyframes and photograph tracks across overlapping twelve-view neighborhoods. Matching and solving have explicit time limits; disconnected fitting-camera components are rejected. A 120-camera analytic loop diagnostic, a longer 36-photo image session, and repeated-room/repeated-floor ambiguity checks are added. These additions are pending exact-source validation and do not establish a whole-house capacity claim.

Capture metadata now commits as a bounded SQLite row before periodic project checkpoints. Native recovery checks cover process termination on both sides of that row commit. The simulator checks have not yet run on this source. Original bytes are not rewritten by the optimization path.

Pinned Ceres packaging source `c1d29b2e6ff76f85d8dd4343222baac8fa4b560e`, run `39031457919`, passed host numerical factor/optimization diagnostics and device/simulator static-library builds. The analytic joint test's maximum point error was 0.116735 mm; this is a deterministic numerical test, not an image or physical accuracy result. Libraries were approximately 6.0/6.1 MiB. Evidence is retained under `docs/evidence/solver-c1d29b2/`.

Depth fusion no longer silently takes only the first 300 photographs: it processes all eligible observations (or only those in the current accepted camera solution) subject to the bounded fusion volume. The versioned surface checkpoint is invalidated when algorithm inputs change. Background entry, critical thermal state and memory warnings request cancellation at safe boundaries; actual phone lifecycle/resource qualification is still required.
