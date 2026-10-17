# Implementation ledger

Delivery proof completed 2026-10-17: signed build 2.1 installed by owner. No implementation build has been uploaded.

Acceptance remains the runbook's gates. Implemented features below are not equivalent to complete package qualification. See [requirement audit](../docs/IMPLEMENTATION.md).

## Checkpoints
- [x] Preserve approved runbook; disable intermediate delivery.
- [x] Implement canonical contracts, SQLite/hashed-asset store and initial fixtures.
- [x] Implement native capture, quality guidance, reference/map paths and periodic mesh checkpoints.
- [x] Implement first-person viewing, stage/layer isolation, labels, measurements and documentary imports.
- [x] Implement drawings/IFC/PLY imports, model/video outputs and streaming archives.
- [x] Pass integrated source 94b6decb2e: 30 native tests, XCUITest, portable cases, independent GLB/USD/ZIP readers.
- [x] Validate IFC4, connections, drawing controls, tours, clearance and capture-journal recovery: source a12d1249e8, 47 native tests plus integrated UI/export workflow.
- [x] Validate native OpenCV image fixture and bounded local pose graph: source 188f337048, 54 native tests plus integrated workflow.
- [x] Validate isolated host replay and five development geometries (13/15 matching, 0/5 false accepts); native photo-point workflow and surface resume (57 checks + 2 UI flows).
- [x] Validate boundary editing/clipping, nominal-plane coverage, camera solution reloads, recorded slope following, incremental snapshots and SIGKILL journal recovery: source f300a1b0, 66 checks + 2 UI flows.
- [x] Run the frozen physically rendered reference fixture: 2/3 matching queries, 0/1 false accepts, worst accepted position error 6.8 mm; development diagnostic only.
- [x] Build pinned Ceres/Eigen for device/simulator and pass analytic optimization diagnostics.
- [x] Validate 120-camera sparse graph and longer image session; preserve and repair clone-ambiguity failures.
- [x] Implement tiled GPU residency, geometry-dependent annotations/measurements, structured animated GLB, tour presets and phone field-check records.
- [x] Complete first 70-configuration stress run; record failure at p95 14.364 mm rather than accepting it.
- [ ] Accept revised multi-view query candidate against unchanged broader targets.
- [ ] Complete protected cross-room rejection and full-house localization qualification.
- [ ] Complete robust optimization/localization, protected house-scale simulation and remaining software gates.
- [ ] Complete owner-device resource and physical precision qualification.
- [ ] Upload one final accepted build and verify Apple availability.

Every source checkpoint is committed to the repository. Reports are retained under docs/evidence. Release uploads stay disabled while critical gates remain open.

### 2026-10-17 — movie timing and house-layout failures retained

Native source `96ea8a0b4c` compiled and passed 73 of 74 native checks; the remaining movie check reported a final nominal frame rate of 29.70297 instead of 30. The next candidate disables H.264 frame reordering at each shot boundary and verifies every compressed presentation timestamp and exact frame count, in addition to duration, dimensions, FPS and decoding. No rate tolerance was relaxed. CI now prints the native failure even when movie output is missing.

The first connected four-room/two-level development replay at source `875d7d55` built all four maps, accepted 9/12 nominal queries, rejected 8/8 wrong-room/floor queries, and had 13.585 mm p95/worst accepted position error. This fails the 90% availability and 10 mm p95 gates. It is retained under `docs/evidence/house-layout-875d7`; no production qualification is claimed.

The analytic evaluator now tests parallel ray/box boundary intersections, optical-axis depth, near-foreground occlusion and camera convention independently. Four local tests pass. A near object can no longer expose background depth by falling below the depth sensor admission range. The current frozen stress run retains its original source and evaluator.

The next localization candidate refines ORB corner coordinates to subpixel precision before depth backprojection and pose fitting. Refinement is limited to a 3-pixel half-window, 20 iterations and a maximum 1.5-pixel displacement; descriptors remain attached to the original detected patch. Every existing geometric and ambiguity gate remains unchanged. The algorithm fingerprint changes so old maps are rebuilt. House-layout failures now retain per-view pose rejection reasons. This is a repair candidate, not a claimed accuracy improvement until the isolated replay passes. OpenCV API reference: https://docs.opencv.org/4.12.0/dd/d1a/group__imgproc__feature.html .
