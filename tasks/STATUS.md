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

Model export preflight now includes conservative working-copy estimates for geometry and unique photo textures (256 MB staging admission budget, 25 MB per texture). GLB/USDZ validate texture checksums and report missing or corrupt originals instead of silently exporting untextured surfaces. OBJ/PLY remain explicitly geometry-only. Room/stage splitting is the recovery path when the budget is exceeded. Native tests exercise unique-asset accounting, a deliberately insufficient budget, missing texture and content corruption. These admission estimates do not replace physical-device peak-memory qualification.

Store upgrades now use SQLite `user_version`, refuse newer incompatible stores before modifying them, and apply additive schema changes inside one transaction. Existing stores receive a SQLite backup-API snapshot (including committed WAL data), integrity check, fsync and SHA manifest before migration. Original assets are not duplicated. Snapshot creation has a 30-second deadline and free-space admission. Native diagnostics cover rollback, verified snapshot, evidence preservation and future-version refusal; CI additionally kills an isolated app fixture inside the schema transaction and reopens it in a new process. These new checks await the current native build and do not claim physical power-loss qualification.

Subpixel attempt `cc711acc` failed the development matrix: 12/15 nominal queries accepted, with inconsistent source poses causing abstention; the six-view joint fixture also worsened to 11.93 mm worst accepted error. Frozen rendered replay still passed. Evidence is retained under `docs/evidence/subpixel-cc711`. The next candidate computes descriptors at the refined coordinates and removes identical descriptors, so moved corner coordinates no longer retain a descriptor centred elsewhere. Existing pose, consensus, and negative gates are unchanged. This candidate must earn new passing evidence.

Native CI now continues independent process-recovery and UI checks after a recorded native diagnostic failure, then exits nonzero with the original failure retained. This collects useful evidence in one bounded run instead of repeatedly blocking later checks on the same movie fault. The on-phone diagnostic panel yields between native checks so progress can paint; synthetic launch initializes the sample before diagnostics.

Recomputed-descriptor candidate `5d632c54` improved the six-view joint fixture to 4.22 mm worst accepted error and the 36-photo session to 4.26 mm; the five development configurations passed. Its four-room replay accepted only 9/12 (p95/worst 9.03 mm), while the frozen rendered fixture accepted 1/4 because spatial feature support did not cover enough image regions. Both failures remain release blockers and are retained under `docs/evidence/refined-descriptors-5d632`. The next bounded candidate increases the detection budget from 1,200 to 2,000 features per image, with matching buffers and maximum map size increased consistently (120 views, 240,000 points). No acceptance threshold changes.

Native source `6137ce01` passed 75/76 checks, including migration rollback/snapshot/future-version refusal and texture export admission. The movie checker incorrectly assumed one sample per `CMSampleBuffer`; Core Media also supports packed samples and empty timing markers. It now uses `CMSampleBufferGetSampleTimingInfo` for each actual sample, retaining exact frame-count, timestamp, duration, FPS and decode requirements. Official API: https://developer.apple.com/documentation/coremedia/cmsamplebuffergetsampletiminginfo(_:at:timinginfoout:) .

The complete 70-configuration multi-view stress at `875d7d55` accepted 977/1000 nominal queries, observed 0 false accepts in 3,354 actually executed critical challenges, and scored 10.758 mm p95 / 21.065 mm worst accepted error. It fails the unchanged 10 mm p95 target (development 10.653 mm, protected 10.899 mm). Protected replay records were not opened. Retained under `docs/evidence/stress-875d7`; this is still an analytic corner suite, not full-house or field qualification.

Original-asset integrity verification now runs in the cancellation-aware local worker instead of blocking the phone interface. Coordinated snapshot metadata reads also enforce their byte limit during the read, not only before it.

Capture start now requests cancellation of an active heavy operation and waits at most ten seconds for its safe checkpoint before enabling AR. Encoder readiness has a 15-second bound; shot finalization and final assembly have cancellation watchdogs (30/60 seconds). Completed verified shots remain resumable. These protect against application-level waits in addition to the existing CI watchdogs; actual device interruption behavior still requires qualification.

The 2,000-feature candidate `7366a2e8` passed frozen rendered replay, the six-view raw/joint fixtures, the 36-photo session and five development geometries. Its four-room replay still accepted 9/12; accepted p95/worst improved to 7.164 mm, and the three abstentions reported inconsistent source poses. Retained in `docs/evidence/visual-budget-7366a`.

The next query candidate uses a deterministic, bounded pairwise consensus to handle isolated source-pose errors. Every retained pair must satisfy the existing 3 cm / 3 degree agreement and source baseline requirements. Excluding a source requires at least three agreeing views and a two-thirds majority; a second agreeing, separated pair outside that group forces abstention. There is no two-view fallback when a larger set disagrees. Final fused PnP still passes all previous geometry/image gates and agrees with every retained source. Native fixtures cover isolated outliers, competing hypotheses and insufficient baseline. This is an explicit estimator change requiring new positive, negative and protected evaluation—not a passed qualification claim.
