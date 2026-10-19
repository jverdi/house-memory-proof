# House Xray: current progress

Updated 19 October 2026. Work has resumed in a new thread. The full plan remains **in progress**; precision use and final release acceptance remain disabled.

## Restart status (supersedes older run status below)

- Requested release **231.1** completed with a movement-settings interface failure; Apple upload was skipped.
- Main **233.1**, source `8e8edb6`, completed with **187/188 native checks** and **18/19 interface workflows** passing. Small-triangle source picking and the movement-settings slider still fail. The complete artifact was downloaded and SHA-256 verified; the failure recording and accessibility description were inspected. [Retained evidence](evidence/restart-20261019/summary.json).
- The snapshot accessibility repair is published as `cac8756b627474b65d2a8b1f912a73791b3225dc` on `requested-snapshot-20261019`. **234.1**, [run 39272141287](https://github.com/jverdi/house-memory-proof/actions/runs/39272141287), has been queued for the complete release validation and conditional Apple upload. A queued run is not an available TestFlight build.
- **216.1 remains the last verified available TestFlight build.** No newer installation or delivery is claimed.
- The recovery notes and exact next work are in [RESTART_CHECKPOINT.md](RESTART_CHECKPOINT.md). The new repair has not yet passed native/UI validation. All 19 interface workflows and exact setting/persistence assertions remain; no accuracy threshold or localization budget changed.

Older sections below retain their historical checkpoints and outstanding specification work.

## What you can install

**TestFlight 216.1 is available to the owner's Personal iPhone group.** Apple processing and tester access are verified. Installation on the physical phone has not been verified. This is the requested development snapshot, not the completed app.

216.1 does **not** include the new homeowner introduction, help guides, movement settings or room map. Later validation builds are not TestFlight uploads. The owner requested a new TestFlight snapshot on 19 October 2026 UTC. A dedicated release run will validate this continuation before uploading; availability remains 216.1 until Apple processing and owner access are verified.

## What has changed since that snapshot

| Work | Current evidence |
|---|---|
| First-use introduction | Five steps, three starting goals, Skip, Back, restart and show-on-next-launch settings are implemented. Replaying help preserves house records. Simulator workflows pass at 224.1. |
| Help inside the app | Fourteen searchable, offline guides explain homeowner tasks, unfamiliar terms and what to do when capture or an overlay is unavailable. Links open the relevant app screen. Simulator workflows pass at 224.1. |
| First real capture after the sample | The new house retains its own room and stage. The capture header and opening instructions pass renewed visual review at 224.1. |
| Walking over recorded surfaces | Missing floor support is refused. Connected room/stair diagnostics and two bounded reconstructed fragments pass at 224.1. This is not whole-house navigation qualification. |
| Movement and view settings | Remembered speed, acceleration, turning, sensitivity, view width, eye height, handedness and reset are implemented. Native checks, the comfort interface workflow and screenshot review pass at 226.1. |
| Room map | Room, level, direction, saved viewpoints and recorded photo positions are implemented, with separate unaligned visits and a remembered mini-map. Dots do not establish complete capture coverage. Native and interface map checks, remembered mini-map startup and screenshot review pass at 226.1. |
| Readability follow-up | Dark lettering on bright action buttons, a separate walking-notice row and clearer capture-count wording are included in 225.1. Introduction/capture contrast and comfort screenshots are reviewed. Photo-only notice and room-map screenshots pass review at 226.1. |

Latest complete integration remains **226.1**, source `ad8e0c5c8baf214967ccacea80a6195d7df66e8c`, run `39175973721`: 178 native checks, all 19 interface workflows, 19 reader phases, 52 command contracts, 36 validation reports, three recoveries and 50 portable checks pass. Both hashes and required screenshots are verified in [the retained report](evidence/native-ad8-summary.json).

The requested **228.1** release passed compilation, all 182 native checks, readers, exports and recoveries, but **17/19 interface workflows passed and two failed**. The envelope keyboard remained open after Done; the comfort test's slider gesture undershot its requested value. Apple upload was skipped. Both failure recordings and artifact hashes are reviewed in [the failure report](evidence/native-f712-summary.json). A repair based on the requested f712 source is prepared locally on `requested-snapshot-20261019`, commit `7e9359809b25889b8dca4be3da1d6549faa57af1`, with the complete original validation gate retained.

The combined map and distant-room follow-up **230.1** passes all **185 native checks**; 17 of its 19 interface workflows passed and two failed. A separate local candidate adds bounded directional prefetch and local render coordinates, expecting 187 native checks and the same 19 interface workflows. It is not published or native-validated.

## Publication authorization

The owner approved publishing the prepared source and synthetic test evidence to the public `jverdi/house-memory-proof` repository and committing directly to `main` in this thread on 18 October 2026 at 22:42 New York time. The earlier automatic publication block is resolved by that explicit instruction. The continuation is published as `0c1da56aaab46bb5157ef6580425fe310741bb77`, with cancelled validation run `39191319328` (227.1) retained separately. The owner subsequently requested a new TestFlight snapshot in this thread; its dedicated release run retains the complete simulator gate before upload.

Local verification passes: 52 command/reader tests, 41 release/recovery tests, 12 observer-preparation checks and 50 portable geometry cases. All 19 interface workflows remain unchanged; four native regression cases are added. These host checks do not establish Swift compilation or native acceptance. [Local results](evidence/continuation-local-summary.json).

The prior thread's review-only pose observer is also preserved. It does not change shipping estimators or automatically run a localization experiment. Its residual evaluator and bounded serial wrapper are now prepared with 27 local contract/math checks passing. The workflow remains disabled outside active workflow paths; native compilation, exact baseline/observer equivalence and diagnostic execution are unverified. The exhausted localization budget has not been renewed.

## What prevents full completion

| Remaining work | What must happen |
|---|---|
| Accuracy and alignment in finished rooms | Existing accuracy, rough-to-finished availability and finished depth-edge failures must be repaired and independently rerun. The five-attempt repair budget for finished 384-pixel localization is exhausted; another experiment requires an explicitly renewed, bounded budget under runbook §22.3. |
| Whole-house software qualification | Complete reconstructed-house topology and streaming, mixed construction stages, capture guidance with a simulated operator, coverage and broad tour checks. Then run the required diverse development and protected-house evaluation with unchanged acceptance criteria. |
| Geometry, drawings and uncertainty | Complete broad registration, thin-route and variable-section qualification, calibrated uncertainty, and representative real-plan recognition/resource checks. Existing bounded examples do not close these requirements. |
| Actual iPhone behavior | Run sustained capture, rendering, memory/thermal, interruption, accessibility and homeowner comprehension checks on the installed source. CI cannot supply these observations. |
| Files, iCloud and app updates | Verify real provider transfer/fault cases, large-device workloads and a signed-app update using recoverable test projects. Simulator and frozen-archive checks are separate evidence. |
| Physical accuracy | Measure camera/depth/timing behavior, calibrate using measured references, and validate on independent construction regions and later sessions. No field result is currently claimed. |
| Final delivery and upkeep | After the applicable gates pass, sign and upload the accepted source, verify Apple processing/access, and enable the approved renewal process for that accepted source. |

The original specification and its thresholds remain unchanged. Documentary and approximate use is the retained fallback while accuracy gates are open; it does not count as completing those gates.

The [proposed next localization diagnostic](LOCALIZATION_DIAGNOSTIC_PROPOSAL.md) defines a possible renewed budget: two serial jobs of at most 40 minutes each, using the unchanged estimator and already disclosed development cases. It is a proposal only; no new experiment has run.

## Current map follow-up

The room map now has a prepared follow-up for checked wall/ceiling areas, known gaps, unchecked areas and stale definitions. It retains bounded transient summaries and keeps stages and unaligned visits separate. It is combined with a prepared distant-room collision handoff repair for 185 native checks and all 19 interface workflows. The photo-point workflow now checks actual wall analysis appearing on the map and invalidation after an edit. [Candidate details](evidence/room-map-coverage-candidate.md). The requested TestFlight snapshot is build **228.1**, source `f7123ca2ee6c556620b3f01cc3d6d88bc20d0597`, run `39191585115`, and excludes this follow-up. Its 182 native checks, 19 reader phases, 52 command contracts and process recovery pass. The native artifact hash is independently verified in [the release checkpoint](evidence/native-f712-summary.json). Its later interface stage failed two workflows, so upload was skipped; the prepared repair must pass the complete gate.

## Next steps

1. Validate the published continuation and requested TestFlight snapshot with 182 native checks and all 19 interface workflows, then verify Apple processing and owner access.
2. Continue reconstructed whole-house navigation and software qualification with bounded diagnostics.
3. Continue independent software work. Keep the exhausted accuracy-repair budget separate from implementation that can proceed.
4. Use the [owner-device protocol](DEVICE_ACCEPTANCE.md) for checks that need the actual phone. Only run feature-specific checks on a build containing those features.

Detailed state: [task ledger](../tasks/qualification.json), [implementation audit](IMPLEMENTATION.md), [runbook](architecture-runbook.md), and [TestFlight delivery evidence](evidence/testflight-216-1-summary.json).

The [streamed room-jump repair](evidence/streamed-room-jump-candidate.md) prevents a distant destination from being checked against the previous room’s collision window. It pauses walking during the handoff, preserves the latest requested room and keeps missing floor support explicit. Native validation passes in 230.1; full interface integration and screenshots 48–49 remain pending. Superseded 227.1 is retained as [cancelled, without a native/interface pass](evidence/native-0c1-cancelled-summary.json).

Current combined validation is **230.1**, source `dc505889f484a0bc61baafda1c20b5c550c51ffe`, run `39192940987`. Debug and Release compilation and all 185 native checks pass; interface validation failed in classification keyboard dismissal and the photo workflow’s mini-map expectation. Superseded [229.1](evidence/native-665-cancelled-summary.json) remains cancelled with no native/interface acceptance. The owner reported installing an initial build on 17 October 2026 at 04:20 UTC; that historical statement does not establish installation or device qualification of the current snapshot.

## Current publication block and prepared work

Automatic approval review rejected publication of the repaired snapshot tree twice. A fresh context lookup recovered the exact 02:41:41 UTC request to publish source and synthetic evidence to public `jverdi/house-memory-proof`, directly to main, and the owner's 02:42:26 UTC approval. The reviewer still rejected that recovered approval as untrusted context. No alternate publication route or signing bypass was attempted. The repair and the independent streaming changes are committed locally and remain unpublished.

The [directional prefetch candidate](evidence/directional-streaming-candidate.md) preserves nearby geometry and all residency limits. The [local render coordinate candidate](evidence/local-render-coordinates-candidate.md) keeps original Double coordinates while rebasing display geometry, picks, saved poses and map positions. Their native regression cases are prepared; no results are claimed. Both interface fixes from the release repair are also applied locally to this continuation.

## 19 October follow-up

Run 230.1 completed with 185 native checks passing and 17/19 UI workflows passing. The classification Done button left the keyboard visible. The photo workflow successfully checked the full map summary but then expected the mini-map while still in Wall mode; mini-maps intentionally appear only in Inspect mode. Prepared fixes explicitly resign the filter responder and return the UI workflow to Inspect without weakening its checked-area or invalidation assertions. Native validation of these fixes remains pending. Automatic publication rejection remains unresolved. No new TestFlight upload occurred.

## Publication resumed

The owner explicitly authorized public source, workflow and synthetic evidence publication, including main and release branches, through TestFlight delivery on 19 October 2026. The repaired snapshot is published as `543bb566a052bc41718496eb8e73fe6dc4fcdf13` on `requested-snapshot-20261019`. Validation and Apple delivery remain pending. The earlier rejection is retained above as historical evidence.

The repaired release is now validating as **231.1**, run `39226613300`, source `543bb566a052bc41718496eb8e73fe6dc4fcdf13`. The published streaming/render continuation is **232.1**, run `39226689510`, source `757860efd92f1f91afa36fd24ba87678c4543d9c`, expecting 187 native cases. Both Debug and distribution compilation passed. Apple upload is not yet verified. Five automatically triggered localization/development replays were cancelled because the UIKit classification repair did not require them; these cancellations provide no qualification result or renewed repair budget.

The next prepared [bookmark follow-up](evidence/saved-viewpoint-scope-candidate.md) captures the displayed camera in the actual room/visit and refuses poses that cannot be restored faithfully. Its 188-case native validation remains pending. Six new UI evidence parser tests pass, including replay of the retained 228.1 failure log, and all 47 local CI/release-tool tests pass. Future CI retains every UI case across runner restarts and stores original result bundles separately from exported attachments; no original evidence is removed.

231.1 passed its native and process-recovery stages and entered the 19-flow UI gate. Continuation 232.1 passed 186/187 native cases; its local-render source-picking regression failed and its hash-verified checkpoint is retained. The next 188-case candidate combines two-sided picking, stage-specific render diagnostics, the saved-viewpoint repair and strict UI result reporting. The failing continuation is superseded; its incomplete integration is not accepted.
