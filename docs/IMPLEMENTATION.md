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
| P2 Simulation | Analytic camera/depth/pose generation; frozen Cycles fixture; OS-isolated oracle; 70-configuration stress; four-room/two-level layout replay | AKAZE candidate passes all 70 analytic configurations: 1,000/1,000 valid views, 4.570 mm p95, no false accepts in 3,400 challenges. Earlier failures remain retained; both natural-feature finished-stage fixtures still accept 0/8. Full protected house/sensor/topology diversity remains incomplete |
| P3 Reconstruction | AR mesh capture; 2 cm point/TSDF fusion; reference constraints; sparse Ceres graph up to 120 cameras; joint image/depth optimization; overlapping photo tracks; textures | Whole-house registration/scaling qualification, thin-service geometry and physical uncertainty |
| P4 Capture | Posed photographs/depth/confidence/intrinsics; one pending frame; durable capture rows and foreground-resumed processing jobs; quality/thermal/disk guidance; classified mesh partitions; printable coded and legacy references | Real adapter timing/orientation, sustained capture and comprehensive interruption/resource checks |
| P5 Localization/stages | Two-source-view PnP consensus and multi-view refinement; competing-map abstention; world-map/reference paths; three-board handoff; coded corners and independently checked multi-board pose; oriented reveal volumes and stale-input hiding | Broader coded-source diversity, finished-stage/general wrong-room qualification and field precision profile (coded development replays pass) |
| P6 Walkthrough | Touch/controller, orbit/free fly, picking, bookmarks, room jumps, stage/ceiling controls, recorded-camera corridors/slopes, canonical tile streaming | Full stair/portal topology scenarios; native observed-floor stairs, full-body clearance and intact nearby surfaces pass at ffab99e3; iPhone frame time/memory and accessibility/landscape matrix |
| P7 Tours | Deterministic checked capture paths and explicit cuts; before/after and service presets; shot preview; exact-frame planning; hashed resumable chunks; H.264 sharing | Direct GPU caption/color/orientation and 1080p30 encode/full-decode/cache reuse pass at ffab99e3; full interruption matrix and owner-device sustained workload remain. 4K remains optional and unavailable |
| P8 Labels/plans/import | Trades/routes/endpoints/confirmed connections/OCR; source revision propagation; PDF/image scale and independently checked alignment; offline IFC/PLY | Broader drawing-revision and IFC fixtures; optional model suggestions not included |
| P9 Exports/recovery | GLB level/room/stage hierarchy and tour-camera clips; textured USDZ; texture-inclusive export admission and checksums; PLY/OBJ; evidence JSON; ZIP64 restore; offline WebGL viewer | Latest-source regression after passing 58591 official/independent readers; large-file/cross-version matrix and all semantic handoff cases |
| P10 iCloud/resources | Local operation; optional coordinated incremental Files/iCloud-folder snapshots; deduplicated assets; hash checks; restore as separate project; cancellation checkpoints | Real provider partial arrivals/quota/account transitions, actual device resource/lifecycle qualification |
| P11 Qualification | Portable/core/native tests, independent readers, UI flows, real process-kill recovery, retained failures and versioned evidence | Full runbook synthetic/lifecycle suite and final exact-source integrated pass; no production gate passed |
| P12 Field | Phone field-check recording, calibration/validation separation, source snapshots, independent truth/uncertainty, abstentions, local JSON export | Physical acquisition correctness, identifiable calibration and independent measured validation; precision remains disabled |
| P13 Sustained use | Mobile recovery guidance, source checkpoints, proof delivery, prepared renewal/expiry workflows | Enable renewal only after accepted release; final signed manifest, refresh cycle and completed handoff |

## Important implementation boundaries

1. Reconstruction combines captured depth/AR meshes with source-linked photograph tracks. Arbitrary unposed historical photographs remain documentary; they do not acquire invented spatial coordinates.
2. Coded references use pinned AprilTag 36h11 detection and measured print size; legacy targets use ARKit image tracking. New coded board poses come from detected pixels, and multiple views/boards must agree. Neither path is surveyed or physically qualified. Moving/resizing a board invalidates associations. A fitted residual is not a physical accuracy certificate.
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

## October 17 — pixel-derived coded capture checkpoint

Source `e68835e1` replaces ARKit anchor poses in the coded path with direct square-pose estimation from detected corners and measured border size. Ambiguous planar solutions are refused. Captured views must agree, and one conflicting later view excludes the board rather than being discarded in favor of earlier agreement. The native image fixture estimates its source-board poses from images, exercises moved/duplicate/missing/wrong-region cases and records actual source/query errors. Those new image results are pending, not accepted. Source `13cfe782` additionally carries the real reference inventory into lightweight capture admission and verifies durable coded rows after reopening.

The earlier multi-board analytic core at `4a3074d` passed 50 pose cases with maximum position error 0.762468 mm, including moved/duplicate refusals and a large world-origin translation. This is known-geometry numerical evidence only; the complete visual workflow still failed its natural-image house cases. Exact provenance is retained under `docs/evidence/reference-pose-4a307`. The detector/package workflow at `1e6e495` also passed its stronger ordered-corner assertion. Current native integration, the reconstruction-stall repair and source-board image tests remain unverified until their exact-source reports finish. No implementation TestFlight upload has occurred.

## October 17 — integrated native recovery verified

Source `4a3074d`, run 39040257844, passed **89 native checks, two UI workflows, three real SIGKILL recovery modes, 50 portable cases, four GLB validators, three USDZ readers, ZIP64 and offline-viewer checks**. The formerly stalled integrated processing reaches all six stages, and interruption preserves the stored originals. Queue restart/owner pause/commit-gap deduplication and rotated/cropped PDF raster invariance pass. Native elapsed time was 175.4 seconds; the 1080p30 encode/decode/cache-reuse test took 70.5 seconds. Evidence is retained under `docs/evidence/native-4a307` with selective-download member hashes. No whole-ZIP digest verification is claimed.

The textured 100-space/five-level workload contains one million source triangles, 39.3 MB metadata, 512 resident tiles, 24 resident textures / 56.6 MB decoded bytes and full-source local collision. Offscreen 640×360 p95 snapshot/readback was 13.06 ms; this is not sustained iPhone frame rate. Peak process resident memory was 1.51 GB over the run, and physical device/resource qualification remains open. Visual inspection accepted the synthetic tour frame but found that triangle subsampling makes capacity walls appear perforated. The next display candidate keeps complete nearby surfaces and uses explicitly identified source-point previews when a full distant surface is outside budget. The repaired capacity check requires every source face of each visited room to remain present. This visual defect was not detected by the previous nonblank-frame assertion.

### Full-height walking and scene preparation lifecycle

Walking now checks a conservative upright body envelope (20 cm horizontal radius, 1.55 m below the eye and 22 cm above) against full original collision bounds. It still requires the captured camera corridor and does not infer an unseen floor or portal. Native regressions cover low obstacles, overhead beams, narrow doorways and the body leaving the locally checked region. Large-scene preparation now cancels on close/background or replacement and restarts on foreground without allowing obsolete publication. Native validation is pending. The separate e688 host run passed 25 analytic single-board pose cases; unchanged natural-image house/finished-stage failures remain release blockers.

### Isolated coded-reference image replay

The host candidate now runs the same coded detection, source-pose estimation, conflict quarantine and map/query adapter as capture. A new independent ray/plane fixture supplies four regions across two level identities, 16 rough/finished nominal queries and 20 moved/missing/duplicate/wrong-region challenges; measured marker sizes and noisy source-camera priors are inputs, while all marker/world truth and query labels stay evaluator-only behind the existing OS sandbox. Five renderer contracts pass locally, including scale/orientation, foreground occlusion and cardinal rotation invariance. This is a new development candidate awaiting compiled image replay; it does not replace the unchanged natural-feature failures or satisfy protected house/sensor qualification. Capture now preserves the message when a conflicting marker is excluded instead of overwriting it with generic photo guidance.

### Native 58591: isolated coded-image fixture failure

The source completed 90 native checks in 127.7 seconds; 89 passed. The sole failure was decoding all six boards in the first new coded-source image. Both UI workflows, all three actual process-kill recovery cases, 50 portable cases and the independent export readers passed. Exact reports are retained under docs/evidence/native-58591. A separate Linux build of the pinned, Git-blob-verified AprilTag source passed its production selftest and decoded all six boards in both independent raw ray renders of that layout. The native fixture now writes explicit row-major ray/plane samples, removing Core Graphics path-coordinate ambiguity. The following diagnostic naming collision is repaired, and the coded fixture has its own repository so it cannot contaminate unrelated store-order tests. Native verification remains required; no pose or accuracy gate was relaxed.

### Durable source references and capture guidance

Coded maps now re-measure a bounded best source from saved raw corners and camera metadata, then check every supporting source view. They no longer require the aggregate reference checkpoint to survive a crash or reuse an old metric pose after a print-width edit. Native regressions cover missing aggregate state and inconsistent edited print scale. During capture a worker periodically reports how many seen references have separated, agreeing source views and whether their centres span depth; this is explicitly a capture check, not an accuracy qualification. Native validation remains pending. A pinned Linux detector build and 52-image source/query decode diagnostic are retained under docs/evidence/coded-detector-linux; pose accuracy is not scored by that diagnostic.

The first isolated coded run at 78ed6bc was rejected before localization because its depth-free observations omitted required zero depth dimensions. The fixture now supplies depthWidth/depthHeight=0; no pose result is claimed for that failed run. Coded replay now runs before the longer natural-feature suite and uploads a small early checkpoint; its outcome remains a mandatory final gate. Pull-request path filtering prevents unrelated UI/test-only changes from restarting host evaluation, while changes to the compiled candidate replace obsolete host runs.

### Pixel replay results and multi-view board fitting

Native source bdc740 passed all 90 diagnostics, including four pixel-only coded queries with maximum accepted position error 2.552 mm, moved/duplicate/missing/wrong-region rejection, full-body collision, intact nearby capacity walls, and 1080p movie decode/cache checks. Its early checkpoint is retained under docs/evidence/native-bdc; later UI/export phases are not inferred from that artifact.

The isolated a4f4 host replay built all four six-board maps and rejected all 20 negative cases, but accepted only 14/16 nominal views (87.5%) and reached 10.836 mm p95, failing both unchanged gates. Its exact checkpoint is retained under docs/evidence/coded-a4. The next candidate fits each rigid measured board across up to 64 translated source views with Ceres, retains fixed camera priors, and checks every remaining source frame. It does not estimate camera drift, discard moved-board evidence, or establish physical accuracy. Analytic regressions require recovery from a perturbed initializer and rejection of a contradictory final view, absent translation and wrong print width. Integrated pixel replay remains required.

### Reference handoff and observed-floor navigation repairs

Cross-session registration now rebuilds coded poses from current raw corner evidence and measured widths. Its dependency hash includes the source cameras, intrinsics and detected corners; changed evidence invalidates the link. Legacy image references retain their existing path. Native coverage adds a second translated capture without any aggregate pose checkpoint and verifies that changing a source corner removes its saved registration. The reference screen computes placement summaries on the cancellable worker instead of fitting boards in SwiftUI body evaluation.

Walking now derives support from exact floor-labelled triangles and preserves capture height while checking an upright body. A separate floor BVH avoids filling holes from triangle bounds. Footprint support, maximum step rise, headroom, original-mesh collision and local-index coverage all gate movement; recorded-camera corridor selection remains required. New native scenarios cover lower phone height, observed stairs in both directions, an oversized step, a missing floor patch and a low beam. These are pending regression evidence, not a full navigation-topology qualification.

### Multi-view coded replay passed its development gate

Source 04fa7c33 accepts 16/16 nominal pixel-only queries across all four coded regions (8/8 rough and 8/8 finished), rejects all 20 negative challenges and reduces worst/p95 accepted position error to 4.395 mm. All 24 boards are reconstructed from source pixels and noisy camera priors; query labels and ground truth remain OS-denied. The unchanged gates pass for this development fixture. Evidence is retained under docs/evidence/coded-04fa with verified whole-artifact SHA-256. This does not qualify protected diversity, camera drift, physical print accuracy, natural-feature fallback, complete-house topology or end-to-end service placement.

The complete bdc740 native workflow also passed two UI tests, all three SIGKILL recovery modes, 50 portable cases and independent GLB/USDZ/archive/offline-viewer readers. Inspection confirms continuous nearby capacity surfaces and unclipped two-line movie provenance. Detailed reports and member hashes are retained under docs/evidence/native-bdc-final; the whole 78 MB artifact was not downloaded or SHA-verified.

### Direct GPU movie target candidate

Movie export now renders the shared SceneKit scene through its explicit Metal command-buffer API into BGRA IOSurface pixel buffers owned by the encoder pool. It removes per-frame SceneKit snapshots, UIImage allocation and CPU scene copies. A small caption texture is generated once per shot and composited by the shared GPU overlay; exact frame timestamps and resumable chunk checks remain unchanged. The pool is capped at eight buffers, only one command is submitted at a time, and GPU completion retains its resources even if the 15-second caller deadline expires. Renderer cache identity changes to prevent reuse of older frames.

A native asymmetric color/depth target checks row direction, BGRA channel order, occlusion and caption presence in the actual buffer; the existing ten-second 1080p30 encode/full-decode/cache suite remains mandatory. Validation is pending. Apple API contracts were checked on October 17: SCNRenderer render(atTime:viewport:commandBuffer:passDescriptor:), SCNSceneRenderer.overlaySKScene, CVMetalTextureCacheCreateTextureFromImage and kCVMetalTextureUsage. These APIs remain isolated compatibility adapters; the app does not claim to implement the full standalone shader renderer described in runbook section 3.3.

Host evaluation now runs on relevant pushes to main and agent branches. Pull-request path filters compare the entire PR and were still restarting unchanged localization work after UI-only commits; the per-push filter corrects that behavior. The native workflow validates direct main commits; PR #1 was merged at the owner’s request and further PRs are not used. The final acceptance requires the exact release source and all applicable checks, regardless of incremental filters.

### Direct-main validation checkpoint

PR #1 merged as 2c9ab2a2. This source passed 91/92 native checks, including raw-corner stage handoff and observed-floor stairs/headroom/gap cases, plus both UI flows and process-kill recovery. The two-view coded image fixture rejects its third nominal query after multi-view board fitting. A separate local SciPy diagnostic using the exact pinned detector reproduces a 2.693-pixel held-out-board discrepancy against the unchanged 2-pixel gate; the pose is hidden. This remains a failing acceptance case. Native diagnostics now retain every nominal query's rejection gate and held-out residual, then continue the negative challenges without changing the required 4/4 acceptance or 10 mm accuracy limits.

The first direct-GPU movie commit 8404e288 did not compile because its new Swift file was missing from the checked-in Xcode sources phase. Regenerating the deterministic source references fixes that integration omission; actual GPU validation remains pending.


### October 17 continuation: retained failures and bounded pixel refinement

Source `eace3b6425` and caption candidate `05fcfdfcf8` compiled and completed 93 native diagnostics with 91 passes. Both preserve the same coded query rejection (2.693 held-out pixels against the unchanged 2-pixel bound), and neither SceneKit overlay nor an explicit SpriteKit renderer produced caption pixels in the encoder target. The 1080p30 encode/full-decode/cache check passed, but missing provenance is a real rendering failure. The `05fcfdf` checkpoint artifact SHA-256 was independently verified (`e2c71601bef163ff335c014c9dfcf1588d7c36d6100ebea9eb7de9b18f504422`); reports are retained under `docs/evidence/continuation-20261017/`.

The next candidate draws the caption with a direct alpha-blended Metal quad and invalidates cached shots. A separate reference repair refines an already decoded tag homography using its known internal black/white transitions as well as the external border. It uses only image pixels and the decoded code, caps the patch at 262,144 floats and the optimizer at 20 iterations, limits corner displacement to two pixels, and retains the prior detector result if photometric support is insufficient. All map/query pose and held-out gates remain unchanged. Stored raw corners are not rewritten.

The exact C detector adapter passed 24 independent projective raster/blur/noise cases on Linux (maximum corner error 0.4035 pixels), alongside the existing rotation/duplicate/malformed-input checks. A SciPy diagnostic reproduces the original native rejection and suggests the refined pixels resolve it; that diagnostic is not the production Ceres pose engine and is not recorded as native acceptance. Native and isolated four-region replay remain required. The earlier natural-feature house/finished-wall and 70-case stress failures remain unwaived; no implementation TestFlight upload is authorized by these small diagnostics alone.


### Pixel-centre convention correction

The pinned AprilTag decoder reports edge-origin coordinates (first pixel centre 0.5); AR camera intrinsics and the independent ray renderer use integer pixel centres. Saved normalized detections retain their original convention. The geometry adapter now subtracts half a pixel only at source measurement, multi-view fitting, consistency checking and query localization. Coded registration fingerprints include the algorithm version so existing transforms are recomputed. A native regression archives exact projected marker corners and requires recovery of the original metric board pose. This correction requires fresh native and isolated replay results.

Before this coordinate correction, source `b022d8fa` passed the isolated four-region coded replay: 16/16 nominal queries, zero false accepts among 20 negative challenges, worst/p95 3.873 mm. Artifact 12108253343 from run 39054429618 was downloaded and SHA-256 verified (`341fa97741e51e95af076e61304e51819c99b2c3c67879309ff01ea27fcab683`). This remains a development fixture, not field qualification.


### Natural-feature support experiment rejected

Isolated source `db5d1f6c`, run 39054565418 compared 15/21/25-pixel ORB patches on the four unchanged house fixtures. All three variants failed overall. The 15-pixel variant lost all rough-view availability; 21 and 25 pixels still accepted at most one of eight finished views and exceeded accuracy limits in other configurations. No production feature parameters were changed. Whole artifact hashes and per-scenario results are retained under `docs/evidence/feature-support-db5d1/`.

A separate diagnostic now evaluates the pinned OpenCV AKAZE detector with its standard threshold, a 256-bit binary descriptor and the existing feature-count, matching and pose gates. It uses AKAZE's own scale-space localization, with no ORB-specific corner refinement. The production extractor stays unchanged unless a candidate clears the independent acceptance suites; the experiment alone cannot qualify a release. API contract: https://docs.opencv.org/4.13.0/d8/d30/classcv_1_1AKAZE.html.


### Coordinate replay and hosted simulator startup

Source `37c54858` passed the corrected pixel-centre coded replay with 16/16 nominal queries, zero false accepts among 20 negative cases, and worst/p95 3.908 mm. Its checkpoint SHA-256 is `835e50ad2fc05a56ec9299f34e0846b58f83e5340ff224ae3436d8a353f602a3`. The following sampler guard rejects nonfinite/out-of-range trial coordinates before C integer conversion; the 24 independent pixel cases retain the identical maximum error, and invalid-coordinate checks pass with undefined/float-cast sanitizers.

Native source `b022d8fa` compiled but **did not launch the app**. Hosted simulator migration exceeded its 180-second startup budget; its cleanup also encountered a protected process-group signal error. No native test outcome is inferred. The whole failed-run artifact was SHA-256 verified and the failure provenance retained. Startup now has a bounded 300-second allowance, independent of the unchanged 300-second app diagnostic limit. The timeout wrapper tolerates a child-exit race and restricted group signalling, attempts only its own direct child as fallback, and still returns failure 124. Exit propagation, actual timeout termination and mocked denied-group cleanup passed locally. Fresh native results are still required.


### Nonlinear feature experiment: rough geometry improved, finished matching still fails

Isolated AKAZE source `7ba4169d`, run 39055131621, passed both rough house layouts at 12/12 nominal availability each, with worst/p95 errors 4.682 and 5.867 mm. Rough queries in the paired and staggered fixtures also passed at 12/12, worst 3.697 and 4.853 mm. All 56 negative challenges were rejected. Both finished-stage variants still accepted 0/8 and therefore failed overall. Production ORB remains unchanged. Exact reports and the isolated diff are retained under `docs/evidence/akaze-7ba416/`, with whole-artifact SHA-256 verified. The same experimental change is now submitted to the existing 70-case stress evaluator without changing its inputs, thresholds or oracle exclusion. No broad pass is inferred from these development cases.


### Native marker repair passed; caption texture decoding failed

Source `ee0c4a1749`, run 39055306722, completed 93 native checks with 91 passes. All four coded-image queries now pass, including the former held-out rejection, with worst accepted position error 1.596 mm. The archive pixel-centre regression also passes. Two movie checks fail with `Image decoding failed` during caption texture loading, before the target can be rendered; this is not accepted as a rendering pass. The checkpoint SHA-256 was verified (`d1b6153b9926f960b0e9e87177c4f3de15572db38e358f714f0839263c1bbfd7`).

The next movie candidate normalizes each once-per-shot caption into explicit premultiplied RGBA8 storage and uploads those bytes directly into a shared Metal texture. It removes generic image decoding from this path and changes the shot cache identity. Scene rendering stays in the encoder pixel buffer, with no per-frame CPU scene copy. Native color/orientation/caption and 1080p encode/full-decode/cache checks remain mandatory.


### Native rendering and marker repairs verified

Source `ffab99e3b9`, run 39056203326, passed **all 93 native checks** in 153.9 seconds. The direct Metal target preserves BGRA color order, orientation, depth and caption pixels; visual inspection confirms upright two-line text. The ten-second 1920×1080/30fps movie passes full decode and verified chunk reuse in 47.4 seconds. The marker/image/archived-coordinate checks remain green. Exact reports and the inspected target are retained under `docs/evidence/native-ffab/`; checkpoint SHA-256 was verified. Later UI/recovery/export steps of this run are not inferred from the early checkpoint.

The preceding `ee0c4a17` workflow separately passed both UI flows, actual process-termination recovery and independent export readers; its two movie failures remain recorded. All runtime precision profiles and TestFlight implementation uploads remain disabled.


### Seventy-configuration analytic stress passed; tested extractor adopted

The frozen AKAZE candidate at `bf7e1b99`, run 39055638533, passes the unchanged full stress gate: **70 configurations, 1,000/1,000 nominal queries, zero false accepts among 3,400 executed unrelated/room-clone/floor-clone challenges, p95 4.570 mm and worst 6.990 mm**. Both the 50 development and 20 independently drawn protected configurations pass; oracle access remains denied throughout. Full reports, candidate diff, replay records and verified whole-artifact hashes are retained under `docs/evidence/akaze-stress-bf7e1/`. This is analytic textured-corner qualification, not complete-house, sensor or field qualification.

Production now uses the exact tested AKAZE/256-bit descriptor extraction with the same feature-count, mutual matching, source-consensus and geometric acceptance limits. The visual fingerprint moves to `visual-v11-akaze-mldb256`, invalidating old descriptor maps, camera solutions and dependent derived geometry through the existing dependency checks; saved source photographs remain the rebuild input. Experimental workflows become manual-only and check out their frozen baselines so later reruns cannot silently apply an old patch to the new extractor.

Fresh native and standard host integration checks are required after adoption. The two natural-feature finished-stage fixtures still reject all eight nominal finished views each. Their failure is retained, and the successful coded-reference workflow does not erase it. No TestFlight release or physical precision profile is enabled.


### Full movie workflow and frozen rendered reference

The full `ffab99e3` workflow passed both UI flows, all three SIGKILL recovery modes, 50 portable cases, independent GLB/USDZ/ZIP64 readers and the offline viewer. Its complete artifact was downloaded and SHA-256 verified (`72db6af2d934d9640423c167f0b954139d55b93392aa1462d48711cc8b08b080`). Inspection of the decoded 1080p movie frame confirms readable, upright, unclipped title and provenance lines. Retained validation reports extend `docs/evidence/native-ffab/`.

After adopting AKAZE, source `ffa44947`, run 39057607285, passes the frozen Blender/Cycles replay: 3/3 nominal views, one unrelated query rejected, maximum position error 8.100 mm. The fixture uses the verified original bytes rather than regenerated pixels. Reports and verified artifact provenance are retained under `docs/evidence/rendered-ffa449/`. This small rendered reference remains separate from the broader analytic and complete-house gates. Native adoption checks are still pending.


### Adopted extractor: complete native and host verification

Source `ffa44947`, run 39057607330, completed successfully with **93/93 native checks, both UI flows, all three process-kill recovery modes and the independent export-reader workflow**. The native count and empty failure list are confirmed by the job log. The local executor disconnected before the new artifact could be retrieved, so its GitHub-reported hashes are recorded without claiming independent byte verification. The earlier full movie-repair artifact at `ffab99e3` remains independently verified and visually inspected. Current native evidence is retained under `docs/evidence/native-ffa449/`.

The standard host workflow at `ffa44947`, run 39057607243, reproduces the two rough-house passes exactly. Basic, joint, 36-photo and all five additional-room replays pass; coded regions remain 16/16 with all 20 negative challenges rejected. Both natural-feature finished-stage variants still accept 0/8, while their rough queries and negative challenges pass. The whole host artifact was downloaded and SHA-256 verified before the workspace outage; a compact result summary is retained under `docs/evidence/host-ffa449/`.

The isolated image-scale experiment at workflow `ab9116ae`, run 39058172269, passed both rough fixtures but failed the paired and staggered fixtures: 16/20 and 19/20 total nominal accepts respectively, with maximum accepted error 5.326 mm and 15.687 mm. No false accepts were reported. It is **not adopted**; production remains the stress-qualified AKAZE candidate. Log-derived results and clearly labelled unverified artifact hashes are retained under `docs/evidence/resolution-ab911/`.

Remaining work includes finished-wall natural-feature support, full-house/sensor/topology and thin-service qualification, physical-device resources and acquisition checks, independent field validation and the final release handoff. No implementation TestFlight build was uploaded and no precision profile was enabled. Further image-level diagnosis was interrupted by the unavailable execution workspace.


### Camera pixel centres across image resizing

Saved photographs are analysed as bounded thumbnails, but natural-feature coordinates previously scaled directly into original-camera intrinsics. Integer pixel centres instead require the half-pixel resize transform. The adapter now restores centres after its internal downsize, and saved-image mapping, photograph triangulation and replay queries explicitly restore thumbnail centres into original camera dimensions. Images analysed at their original dimensions retain the same coordinate arithmetic. Descriptor extraction and acceptance gates are unchanged; the visual fingerprint advances to invalidate derived results computed with the old convention.

New C++ diagnostics compare identical analysis pixels through internal versus external resizing, including odd input dimensions. A native image test measures a rendered Gaussian through the actual ImageIO thumbnail path and compares its recovered centre to the original raster. These changes await host and native validation. The separate bounded subpixel-refinement experiment remains isolated and is not part of production.


### Camera-coordinate correction verified; finished-wall experiment rejected

Source `ca5a28fe`, run 39062386754, passed the complete iPhone simulator workflow: **94/94 native checks, both UI flows, all three SIGKILL recovery modes, 50 portable cases and independent GLB/USDZ/ZIP64/offline-viewer validation**. The added ImageIO regression checks a 2048×1536 image reduced to 1280×960: restored centres stay within 0.15 original pixel on each axis, while the old zero-origin scaling exceeds 0.2 pixel. The C++ checks independently compare identical analysed pixels through internal and external resizing, including rounded dimensions. Both checkpoint and full artifact SHA-256 were verified; reports are retained under `docs/evidence/native-ca5a/`.

The standard host suite reproduces the prior fixture outputs: basic, joint, long-session, additional-room, rough-house and coded-reference gates pass, with the same numeric errors; both natural-feature finished variants remain 0/8. Its overall failure remains visible in `docs/evidence/host-ca5a/`. The unchanged frozen Blender/Cycles bytes also pass 3/3 nominal views and reject the unrelated view, with maximum error 8.100 mm (`docs/evidence/rendered-ca5a/`). These results do not establish physical-device accuracy or finish-stage readiness.

The isolated bounded subpixel experiment at `66def558`, run 39062207327, does not fix finished-wall matching: paired 16/20 and staggered 19/20 total accepts, with maximum errors 5.329 mm and 15.587 mm. The paired failures still lack six-cell coverage; the staggered finished views all match but exceed the metric accuracy gate. The candidate is not adopted, and all gates remain unchanged. Full verified reports and the candidate diff are retained under `docs/evidence/subpixel-66def/`.

The earlier `ffa44947` full native artifact and `ab9116ae` resolution artifact have now also been retrieved and SHA-256 verified, resolving the previous workspace-outage evidence limitation. Their reports and updated provenance are retained. No intermediate TestFlight upload occurred; the installed delivery proof remains build 2.1. Finished-wall natural-feature reliability, full-house/sensor/topology and thin-service qualification, real-device/provider lifecycle checks and independent field validation remain open.


### Snapshot retry, movie recovery and mesh interchange continuation

Snapshot source `974b9d09` makes the revision commit idempotent by deriving its identity from the metadata content hash. An interrupted acknowledgement can be retried without publishing a duplicate revision; an existing conflicting record is rejected without overwriting evidence. The new native fault case covers interruption after commit, retry identity/date preservation, distinct changed content with a reused revision number and corrupt-record rejection. Native verification is pending.

Movie source `666ce918` adds explicit final-assembly cancellation and cleanup, preserving verified completed shots. The fault matrix exercises interruption after a shot commit, before/after assembly and actual task cancellation before publication, followed by full-frame decode and checksum/modification-time reuse checks. Its queued standalone run was superseded by the combined `ed156b6a` run; no independent pass is claimed yet.

Source `ed156b6a` rejects malformed PLY fields instead of compacting away bad tokens and silently shifting coordinates/indices. Header/element/property order, record lengths, nonfinite values, extra records and triangulated output budgets are checked. An asymmetric registered PLY/OBJ fixture is now emitted for pinned external **trimesh 5.1.1** validation of units, Z-up coordinates, winding, feature groups, hidden-feature exclusion and registration applied exactly once. The old native PLY round-trip is accurately renamed; it was not an independent parser. The external checker passes a standalone fixture and rejects injected winding/scale/index errors locally; actual native exports await CI. The 50 portable cases pass. Reader contract: https://trimesh.org/quick_start.html.

### Landmark ablations fail the finished-wall gate

Workflow `3fc3eb18`, run 39064286652, tested two isolated ablations against the exact frozen upscaled-image experiment, preserving all four input fixtures and every matching/geometric/evaluator gate. Both complete artifacts were downloaded and SHA-256 verified; full reports and candidate diffs are retained under `docs/evidence/landmark-3fc3/`.

| Candidate | Rough A | Rough B | Paired | Staggered | Worst staggered error |
|---|---:|---:|---:|---:|---:|
| Original depth landmarks with joint camera refinement | 12/12 | 12/12 | 16/20 | 18/20 | 14.945 mm |
| Graph cameras without joint bundle refinement | 12/12 | 12/12 | 16/20 | 18/20 | 14.891 mm |

All 56 negative challenges reject in each candidate. Neither ablation repairs the finished-wall failure; both lose one more nominal view than the original upscale candidate. Neither is adopted. A separate experiment now varies only AKAZE detection contrast at original resolution, on a frozen `ca5a28fe` baseline. Production descriptor/matching/pose parameters and precision eligibility remain unchanged. These diagnostic results do not replace the required full-house, sensor, topology, lifecycle or physical-device acceptance work.


### Snapshot commit retry verified natively

Source `974b9d09`, run 39064382551, passed **95/95 native checks** in 149.7 seconds, including the new post-commit retry/conflict case. The checkpoint artifact was downloaded and SHA-256 verified (`70245d5bba01c811d7b950b553e1a002f0410983b3ad7f5ef42a61e6f9f23f5d`); native reports are retained under `docs/evidence/native-974b/`. All three process-kill recovery modes also completed successfully. UI and independent-reader steps were still running when this checkpoint was recorded. This source predates the movie-recovery and PLY changes, whose combined native run remains pending.

Automatic approval review blocked a subsequent default-branch evidence update for lack of explicit main-branch authorization. The prepared evidence is preserved on `continuation-evidence-20261017`; no rejected ref update was retried. Previously queued validation continues. No TestFlight upload occurred.


### Review-branch movie cancellation completion

The review branch adds actual task cancellation three frames into the second shot, requiring the first verified shot to retain its checksum/modification time and the partial second shot/final export to disappear before retry. A function-wide job-state cleanup also covers cancellation during cached-clip validation and renderer setup. This is additional unverified code until the branch CI completes. Simulator-only CI accepts this explicit review branch; the TestFlight job remains disabled.


### Lower-contrast detection does not repair finished matching

The native-resolution AKAZE detector thresholds 0.0003 and 0.0001, isolated at workflow `8e443bb5`, run 39064906350, both fail the unchanged paired/staggered gates. Each accepts all 12 rough queries in every fixture and **0/8 finished queries in each paired variant**, with zero false accepts across all 56 negative challenges. Rough-layout worst errors are 3.581/6.863 mm for 0.0003 and 3.700/6.149 mm for 0.0001. The first staggered finished view contains 415/459 detected features, but individual sources supply only 3–21 matches and the first disjoint pool only nine independently repeated features. Lower detection contrast does not supply sufficient stable correspondence. No matching or geometric gate was changed and neither candidate is adopted. Full reports/diffs and independently verified artifact hashes are retained under `docs/evidence/contrast-8e443/`.


### Direct-main authorization restored; snapshot full workflow passed

On October 17 at 16:10 America/New_York, the owner explicitly instructed: “Yes, Just commit directly to main.” Prepared source/evidence commits through `9297d1b3` were fast-forwarded to main. Ongoing logical commits go directly to main; no PR review is required. TestFlight remains held for the final candidate.

Source `974b9d09` now passes its complete workflow: 95 native checks, both UI tests, all three process-kill recovery modes, 50 portable cases and independent GLB/USDZ/ZIP64/offline-viewer readers. The full artifact was downloaded and SHA-256 verified (`022ddd33963d49fbe907e88b74810e080a117834703dc21b0b82f9f5e264d695`); exact reports extend `docs/evidence/native-974b/`. The movie/PLY sources are newer and still require their own results.


### Movie cancellation and strict PLY import verified natively

Source `9297d1b3`, run 39065223663, passed **98/98 native checks** in 131.4 seconds. Actual cancellation three frames into the second shot retains the completed first shot and removes partial output; failures after shot commit and before/after final assembly preserve completed clips. A subsequent retry reuses all three verified chunks (hashes and modification times unchanged) and decodes all 150 output frames. Snapshot commit retry and the PLY malformed-field/header/record checks pass. The asymmetric native PLY/OBJ files were generated successfully; external-reader and UI results remain pending. Checkpoint SHA-256 was independently verified, with exact reports in `docs/evidence/native-9297/`. No physical-device or release qualification is inferred.

The finished-stage follow-up at workflow `5129d268` records bounded candidate 3D/2D correspondences before querying evaluator-only synthetic camera truth. It repeats the frozen image-scale candidate without altering its matching/pose gates, so residual diagnosis can distinguish image correspondence bias from fitting behavior. Production remains unchanged.
