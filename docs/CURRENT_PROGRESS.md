# House Xray: current progress

Updated 19 October 2026 UTC (18 October in New York). The full plan is **in progress**. Precision use and final release acceptance remain disabled.

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

Latest complete integration: **226.1**, source `ad8e0c5c8baf214967ccacea80a6195d7df66e8c`, run `39175973721`: **178/178 native checks and 19/19 interface workflows pass**, together with 19 reader phases, 52 command contracts, 36 validation reports, three process recoveries and 50 portable checks. Both artifact hashes are independently verified and all ten required screenshots reviewed in [the retained report](evidence/native-ad8-summary.json). The failed 225.1 integration is retained separately.

Saved-viewpoint recovery, usable map-marker preservation, a bounded delayed/imperfect operator coverage loop, streamed-detail hysteresis and plain-language lost-view help are integrated in the prepared continuation, authorized for publication and awaiting native validation. Expected counts: 182 native checks and all 19 interface workflows, with existing execution bounds and acceptance thresholds retained. These changes do not complete whole-house or physical qualification.

## Publication authorization

The owner approved publishing the prepared source and synthetic test evidence to the public `jverdi/house-memory-proof` repository and committing directly to `main` in this thread on 18 October 2026 at 22:42 New York time. The earlier automatic publication block is resolved by that explicit instruction. The continuation is published as `0c1da56aaab46bb5157ef6580425fe310741bb77`, with validation run `39191319328` (227.1) in progress. The owner subsequently requested a new TestFlight snapshot in this thread; its dedicated release run retains the complete simulator gate before upload.

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

The room map now has a prepared follow-up for checked wall/ceiling areas, known gaps, unchecked areas and stale definitions. It retains bounded transient summaries and keeps stages and unaligned visits separate. It is combined with a prepared distant-room collision handoff repair for 185 native checks and all 19 interface workflows. The photo-point workflow now checks actual wall analysis appearing on the map and invalidation after an edit. [Candidate details](evidence/room-map-coverage-candidate.md). The requested TestFlight snapshot is build **228.1**, source `f7123ca2ee6c556620b3f01cc3d6d88bc20d0597`, run `39191585115`, and excludes this follow-up. Its 182 native checks, 19 reader phases, 52 command contracts and process recovery pass. The native artifact hash is independently verified in [the release checkpoint](evidence/native-f712-summary.json). All 19 interface workflows and complete integration must pass before upload.

## Next steps

1. Validate the published continuation and requested TestFlight snapshot with 182 native checks and all 19 interface workflows, then verify Apple processing and owner access.
2. Continue reconstructed whole-house navigation and software qualification with bounded diagnostics.
3. Continue independent software work. Keep the exhausted accuracy-repair budget separate from implementation that can proceed.
4. Use the [owner-device protocol](DEVICE_ACCEPTANCE.md) for checks that need the actual phone. Only run feature-specific checks on a build containing those features.

Detailed state: [task ledger](../tasks/qualification.json), [implementation audit](IMPLEMENTATION.md), [runbook](architecture-runbook.md), and [TestFlight delivery evidence](evidence/testflight-216-1-summary.json).

The [streamed room-jump repair](evidence/streamed-room-jump-candidate.md) prevents a distant destination from being checked against the previous room’s collision window. It pauses walking during the handoff, preserves the latest requested room and keeps missing floor support explicit. Native validation and screenshots 48–49 remain pending. Superseded 227.1 is retained as [cancelled, without a native/interface pass](evidence/native-0c1-cancelled-summary.json).

Current combined validation is **230.1**, source `dc505889f484a0bc61baafda1c20b5c550c51ffe`, run `39192940987`. Debug compilation passes; Release/native/interface results remain pending. Superseded [229.1](evidence/native-665-cancelled-summary.json) remains cancelled with no native/interface acceptance. The owner reported installing an initial build on 17 October 2026 at 04:20 UTC; that historical statement does not establish installation or device qualification of the current snapshot.
