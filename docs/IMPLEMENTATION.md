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
| P0 Delivery/native feasibility | Repository, managed macOS CI, Swift/C++ bridge, SQLite, SceneKit/Metal, H.264, internal TestFlight proof, offline IFC2x3/IFC4; pinned OpenCV 4.13 and Ceres 2.2/Eigen 3.4 | Final signed implementation build, renewal evidence and actual device workloads |
| P1 Contracts/store | Metres/Z-up adapters; SHA originals; SQLite WAL/FULL; journal plus durable capture rows; explicit store versions and verified pre-migration snapshots; additive decoding; source dependency invalidation; 20 revision checkpoints; ZIP64 | Interrupted-migration SIGKILL passed at `7366a2e8`; broader persistence fault matrix and large-device workload qualification |
| P2 Simulation | Analytic camera/depth/pose generation; frozen Cycles fixture; OS-isolated oracle; 70-configuration stress; four-room/two-level layout replay | Two stress candidates failed p95 (14.36 mm then 10.76 mm); refined descriptor candidate under development. Full protected house/sensor/topology diversity remains incomplete |
| P3 Reconstruction | AR mesh capture; 2 cm point/TSDF fusion; reference constraints; sparse Ceres graph up to 120 cameras; joint image/depth optimization; overlapping photo tracks; textures | Whole-house registration/scaling qualification, thin-service geometry and physical uncertainty |
| P4 Capture | Posed photographs/depth/confidence/intrinsics; one pending frame; durable capture rows; quality/thermal/disk guidance; classified mesh partitions; printable references | Real adapter timing/orientation, sustained capture and comprehensive interruption/resource checks |
| P5 Localization/stages | Two-source-view PnP consensus and multi-view refinement; competing-map abstention; world-map/reference paths; three-board handoff; oriented reveal volumes and stale-input hiding | 10 mm p95 stress target, finished-stage/general wrong-room qualification and field precision profile |
| P6 Walkthrough | Touch/controller, orbit/free fly, picking, bookmarks, room jumps, stage/ceiling controls, recorded-camera corridors/slopes, canonical tile streaming | Full stair/portal scenarios; new 100-space native workload awaiting results; iPhone frame time/memory and accessibility/landscape matrix |
| P7 Tours | Deterministic checked capture paths and explicit cuts; before/after and service presets; shot preview; exact-frame planning; hashed resumable chunks; H.264 sharing | 1080p encode/decode/cache reuse passed at 1ec81; latest-source regression, full interruption matrix and owner-device sustained workload. 4K remains optional and unavailable |
| P8 Labels/plans/import | Trades/routes/endpoints/confirmed connections/OCR; source revision propagation; PDF/image scale and independently checked alignment; offline IFC/PLY | Broader drawing-revision and IFC fixtures; optional model suggestions not included |
| P9 Exports/recovery | GLB level/room/stage hierarchy and tour-camera clips; textured USDZ; texture-inclusive export admission and checksums; PLY/OBJ; evidence JSON; ZIP64 restore; offline WebGL viewer | Latest-source regression after green 1ec81 official/independent readers; large-file/cross-version matrix and all semantic handoff cases |
| P10 iCloud/resources | Local operation; optional coordinated incremental Files/iCloud-folder snapshots; deduplicated assets; hash checks; restore as separate project; cancellation checkpoints | Real provider partial arrivals/quota/account transitions, actual device resource/lifecycle qualification |
| P11 Qualification | Portable/core/native tests, independent readers, UI flows, real process-kill recovery, retained failures and versioned evidence | Full runbook synthetic/lifecycle suite and final exact-source integrated pass; no production gate passed |
| P12 Field | Phone field-check recording, calibration/validation separation, source snapshots, independent truth/uncertainty, abstentions, local JSON export | Physical acquisition correctness, identifiable calibration and independent measured validation; precision remains disabled |
| P13 Sustained use | Mobile recovery guidance, source checkpoints, proof delivery, prepared renewal/expiry workflows | Enable renewal only after accepted release; final signed manifest, refresh cycle and completed handoff |

## Important implementation boundaries

1. Reconstruction combines captured depth/AR meshes with source-linked photograph tracks. Arbitrary unposed historical photographs remain documentary; they do not acquire invented spatial coordinates.
2. Reference boards are ARKit image targets, not surveyed AprilTags. Moving/resizing a board invalidates associations. A fitted residual is not a physical accuracy certificate.
3. Unregistered sessions remain separate. A scene/export selects one unregistered frame; multi-session composition requires checked registration. Ambiguous saved frames hide visual alignment.
4. Explicit stage categories and named oriented wall/ceiling reveal volumes preserve wall side, cavity depth and finish offset. Boundaries and assembly dimensions are currently entered/checked by the owner; the app does not infer hidden assembly truth.
5. Coverage includes unseen patches of an entered nominal cavity plane, and distinguishes weak support/foreground blockage. It cannot certify hidden-service completeness or prove a cavity empty.
6. SceneKit/Metal shares the viewer/movie scene. Large scenes use two-metre tiles and bounded resident geometry/textures; project metadata still loads in memory. Device capacity is not established by index limits.
7. Tours admit short recorded paths only after geometry/corridor checks, otherwise turn at captured viewpoints. Cuts separate frames/rooms; unknown passages are never invented. Before/after clips carry actual layer captions. Completed encoded chunks and TSDF checkpoints resume.
8. Archives stream originals in 1 MiB chunks using ZIP64; project metadata is capped at 100 MB. Model export preflight estimates a 256 MB staging budget including textures and offers room/stage scope. These bounds are not tested device-capacity claims.
9. Runtime processing remains local. GitHub/Apple/TestFlight serve development/distribution. Optional incremental snapshots use a user-selected Files folder; remote provider completion and account transitions require device qualification.
10. No simulator, analytic or owner-entered pooled result enables a physical precision profile. Field records retain conditions/device/build and must be evaluated in a declared support envelope.

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

## Historical checkpoint log

Entries below describe the source at that point in development. The package audit above reflects the current implementation; an earlier “pending” entry is not a current-state assertion.

### October 17 continuation checkpoint

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

Large walkthrough scenes now prepare a canonical two-metre primitive index off the main actor, retain at most 512 GPU tiles and 400,000 vertex/index entries, and load one bounded tile per display tick. Nearby tiles receive higher detail; textures are capped at 24 decoded thumbnails. Source primitives, UVs and feature identities are preserved; collision uses the original geometry. Index limits reject excessive scenes and request selecting one room. This is GPU residency management: the bounded project metadata is still loaded in memory, and iPhone frame-time/peak-memory measurements remain unqualified.

Source `480ed89bfb19d98afbbacf60e1bdfea157302586`, run `39031879328`, passed isolated joint image replay: 3/3 matching queries, 0/1 unrelated false accepts, 6.963 mm maximum accepted query position error, 5.752 mm maximum mapping-camera position error, 413 optimized photograph points and 0.770 px held-out RMS. This six-view analytic development fixture precedes the larger-session and ambiguity extensions; it is not a protected or physical precision claim. Reports are in `docs/evidence/joint-480ed89/`.

The 120-camera graph extension exposed the dense solver's time limit in run `39032082930`; this failure is retained as a scaling finding, not waived. The next source replaces dense normal equations and finite-difference optimization with Ceres sparse normal Cholesky and automatic rotation/translation derivatives. Existing correction, edge-residual, connectivity and contradictory-loop gates are unchanged. The 120-camera route diagnostic must pass before accepting the extension.

Source `0cb74bcf6687e9684eed1ffff2ea125954966102` passed the sparse 120-camera analytic graph test (maximum numerical position error 9.66e-8 m), the 36-photo image session, and frozen rendered replay. The five-room development workflow **failed** two repeated-room/floor ambiguity checks despite correct nominal localization. Reports are retained in `docs/evidence/sparse-0cb74bc/`. The next fix solves PnP in a centroid frame and treats spatially distributed appearance matches in two separated competing views as ambiguity even when the competing PnP solve is ill-conditioned. This strengthens abstention and does not lower geometric acceptance thresholds.

Coverage now streams one depth/confidence pair at a time. Movie cache admission verifies SHA-256, dimensions, frame rate, timing and actual frame decoding. The native test is upgraded to ten seconds at 1080p30 with verified completed-shot reuse; the same workload is available from the phone's synthetic diagnostics button. These latest changes await native validation.

A larger analytic localization stress sweep is defined as 50 fixed development configurations and 20 protected configurations drawn only after candidate compilation. It requests 1,000 nominal queries plus 1,400 unrelated-image queries and 2,000 repeated-room/floor challenges. Actual executed denominators, abstentions and failures are reported; incomplete shards cannot pass. Scoring retains 90% nominal availability, p95 translation error ≤10 mm, worst accepted error ≤25 mm and zero critical false accepts. Its varied textured corners are not the runbook's full-house topology/sensor suite, and passing this sweep alone cannot mark the runbook complete. Protected seeds are preserved separately for reproducibility and excluded from candidate access and ordinary diagnostic reports.

Traced service routes now remember each source feature's revision and registration. Replaced geometry, moved registrations, stale source artifacts and cyclic or missing dependencies make annotations ineligible for scene/reveal/export selection. Camera optimization invalidates all earlier segment geometry, including raw capture meshes without image links. This preserves annotations as records without presenting their old placement as current. Native validation of this checkpoint is pending.

Source `e88cb0ac578870494e92c092208b539dab5a212b`, run `39032819859`, passed the analytic production-core diagnostics, six-view and joint replay, 36-photo session, and five-configuration development matrix including repeated-room/floor appearance ambiguity. Maximum accepted query position error in the longer session was 10.960 mm. Evidence is retained under `docs/evidence/visual-e88cb/`. This fixes the previously retained clone-ambiguity failures without weakening the geometric acceptance criteria; broader stress and full-house qualification remain separate gates.

GLB export now preserves an explicit level → room → dated-stage → feature hierarchy, source geometry dependencies, and sampled automatic tour camera animations. Each cut is a separate clip; no path is interpolated between unrelated rooms. Cameras are restricted to rooms present in the exported coordinate frame. The exporter estimates and rejects geometry above a 300 MB output-buffer budget before allocation, and the phone offers room/stage selection. Independent validation checks hierarchy reachability, metadata identities, timing, positions, quaternion orientation and the official glTF validator; this checkpoint awaits its native artifact run.

Saved measurements now retain the picked surface identities, source stage labels, feature revisions and registration snapshots. The phone distinguishes current approximate measurements from historical or unlinked measurements after reconstruction changes, instead of relying on the unrelated project revision counter. Exported metadata retains that evidence.

Automatic movies now offer current-layer, rough-in/finished comparison, and service-system presets with an inspectable shot list. Each clip carries its actual stage/layer selection and caption; no morph between independently captured frames is implied. Frame counts allocate an exact requested timeline, and bounded five-second chunks preserve the original path phase when split or resumed. Native validation is pending.

Source `ae915fe2348d9b7e048280d4be3b08921d9a4b39`, run `39032859612`, compiled and passed 69/70 native checks, including sparse camera optimization and tile budgeting. The upgraded 1080p film failed the final media validation, so process/UI gates did not run and the candidate was not accepted. The next source explicitly closes every encoder session at the frame-count boundary, declares 30 fps, and reports exact duration/dimension/rate/decode failures. The duration gate is tightened to 1/600 second; no tolerance is relaxed. Reports are in `docs/evidence/native-ae915/`.

Live AR mesh ingestion now preserves ARKit's per-face wall/floor/ceiling and other labels as unreviewed suggestions, partitions triangles without losing faces, and keeps stable source-anchor identities. This makes the ceiling switch apply to classified real captures; hidden service identities still require evidence and review. Unsupported classifications remain explicitly unknown. Source: Apple ARMeshGeometry.classification documentation (https://developer.apple.com/documentation/arkit/armeshgeometry/classification), checked October 17, 2026. Native hardware classification remains a field check.

The first two broader stress shards exposed a real accuracy gap: approximately 97% nominal availability and no observed critical false accepts, but p95 position errors of 14–15 mm exceed the unchanged 10 mm target. This is not accepted as a pass. Query localization previously checked multiple source-view poses and then returned only the best single-view pose. The next candidate instead combines spatially consistent repeated features from separated source views, retaining one correspondence per query feature and rerunning the same robust PnP/consensus gates. Versioned fingerprints invalidate prior maps and camera solutions for this algorithm change. The frozen original sweep continues to completion, and the new candidate requires independent re-evaluation.

The phone now includes a field-check recording flow with fixture/session conditions, separate calibration and independent-validation sets, measurement/source snapshots, device/build and original-image identities, measured truth uncertainty, abstentions and rejection challenges. Records survive metadata/archive round trips and export as local JSON for the later repair/calibration loop. They do not apply a global scale fudge factor or automatically enable a precision claim; pooled owner-entered checks are explicitly not a qualified device profile.

Frozen analytic stress source `e88cb0ac`, run `39032819863`, completed all 70 cases: 977/1,000 nominal queries accepted, p95 14.364 mm, worst 21.486 mm, zero reported critical false accepts. The suite **failed** its 10 mm p95 target. Its report counted 3,400 requested critical challenges; only 1,954 clone checks plus 1,400 unrelated checks were actually executed, because 23 nominal queries abstained before cloning. The next evaluator corrects that denominator to actual executed clones without changing acceptance thresholds. Evidence is in `docs/evidence/stress-e88cb/`.

Multi-view query source `ff93135f`, run `39033849141`, passed the small development suite: the longer-session maximum accepted error improved from 10.960 to 9.231 mm, the six-view joint case from 6.963 to 4.660 mm, and all 15 queries in the five-configuration matrix were admitted with clone checks intact. This is promising development evidence, not a replacement for rerunning the larger stress target. Reports are in `docs/evidence/multiview-ff931/`.

A four-room/two-level analytic layout replay now generates construction framing, cavity services, wall/door openings and stair geometry in one shared texture field. Each candidate receives only noisy local captures and placeholder design dimensions; complete geometry and query truth stay evaluator-side. The candidate builds distinct room maps and receives an explicit owner-style room selection, with wrong adjacent-room and wrong-floor queries scored separately. This is a development integration diagnostic with partial corner coverage; it does not claim complete coverage, finished-stage qualification or validated stair navigation. Runtime competing-map checks also include unregistered sessions in the same room, which cannot safely be assumed to share a coordinate frame.

## October 17 checkpoint — current evidence and unfinished work

Native integration source `1ec81a32ca`, run 39036086112, passed 77 native checks, both UI workflows, three real process-kill recovery modes, 50 portable cases and independent GLB/USDZ/archive/offline-viewer validation. Its 1080p30 movie was encoded, fully decoded and regenerated from verified cached shots. This evidence predates subsequent changes and does not qualify the latest source automatically.

Localization source `c1c6c37b`, run 39037534348, accepts 12/12 rough queries in each of two four-room layouts, with maximum errors 8.161 mm and 11.053 mm respectively. The second still fails the 10 mm gate. Finished-stage queries remain 0/8 accepted; 20/20 paired-stage rejection challenges hide alignment. Broader 70-configuration qualification remains failed at source 875d7, and the full protected-house/topology suite is unfinished.

Current repairs include capture processing leases and bounded world-map finalization, interrupted snapshot publication, cancellable offline IFC, rotated/cropped PDF normalization, classified geometry identity/ceiling transfer, optimized landmark handoff into localization, and integrated local capture processing with per-stage reports. These changes require fresh native/evaluator results. No final implementation build has been uploaded to TestFlight. Actual-device acquisition, memory/thermal/iCloud behavior and field precision remain unqualified.
