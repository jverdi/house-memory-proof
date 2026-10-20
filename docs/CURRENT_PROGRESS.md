# House Xray: current progress

## Current priority checkpoint — 20 October UTC / 19 October New York

Storage repair source **8770dd80e23b050ad2e140bd00842481c01ac190**, [build 247.1 / run 39357781944](https://github.com/jverdi/house-memory-proof/actions/runs/39357781944), is compiling under its single 70-minute integration budget. Four new native tests bring the required count to 198. A separate read-only before/after archive comparison tool passes five local contracts; [actual-device evidence procedure](evidence/storage-recovery-tools/README.md). Item 5 remains open; no new localization experiment has been started.

Owner priority is **5 → 1 → 2 → 3**: storage/update recovery, localization, whole-house reconstruction/navigation, then representative qualification. Storage access-boundary repair is prepared with four new native tests and one declared integration job of at most 70 minutes. [Scope and remaining actual-provider/device gates](evidence/storage-access-candidate.md). Real iCloud behavior and an actual signed-app update are not marked passed.

**246.1 / 389ac9ccde** now passes complete simulator integration: 194 native checks, 21 reader phases, 63 command contracts, all 20 UI workflows with zero runner exit, three process recoveries, 50 portable cases and 38 validation reports. Native and full evidence artifact hashes are verified. [Current validated checkpoint](evidence/native-389/summary.json). This supersedes the older queued/failed current-state descriptions below; the original failures remain retained. No new TestFlight upload occurred.

The one-job localization failure probe has completed with a failed result, not a qualification pass. Its allowance is consumed; aggregate review is pending while storage remains the priority. No rerun has been started.

Updated 19 October 2026. Work has resumed in a new thread. The approved runbook remains **in progress**. Precision, accepted-release and automatic-renewal gates remain closed.

## TestFlight delivery

**234.1 has completed Apple processing and is enabled for internal TestFlight testing.** The exact-build check reports `VALID`, internal `IN_BETA_TESTING` and non-expiration. [Public delivery evidence](evidence/testflight-234-1-summary.json) retains build status only; account-specific access evidence is excluded. Installation and physical qualification remain unverified. The earlier 216.1 delivery remains retained.

Requested snapshot **234.1**, source `cac8756b627474b65d2a8b1f912a73791b3225dc`, [run 39272141287](https://github.com/jverdi/house-memory-proof/actions/runs/39272141287), passes Debug/Release compilation, **182/182 native checks**, **19 independent reader/command phases** and **52 command contracts**. Its native artifact SHA-256 was independently verified. The complete **19-workflow interface gate passes**, as do three process recoveries, 50 portable cases and 36 export-validation reports. Required keyboard/comfort/map visual follow-ups have been inspected. Distribution signing and the Xcode upload command now pass; Apple processing and internal testing state now pass the exact-build check. The inspected IPA hash is retained, but the hash of the uploaded bytes is not independently verified. [Retained checkpoint](evidence/native-cac/summary.json).

This requested snapshot includes homeowner introduction/help, viewer comfort and room-map work. It does not include the subsequent picking, room-priority or viewer-performance continuation. The full simulator gate passed before upload; no release criterion was removed.

## Work completed or under validation

| Work | Exact state |
|---|---|
| Snapshot accessibility repair | Native slider percentages are retained; current physical units move to the accessible label. Standard slider adjustment still requires exact endpoint/persistence/reset assertions. Switch interaction targets its actual control. 234.1 passes native and all 19 UI workflows. |
| Small displayed-surface picking | Source `1fee4cc117fc61baa5c8f8a6b8d531b56d68c5db`, **235.1**, [run 39273286562](https://github.com/jverdi/house-memory-proof/actions/runs/39273286562). Production double-precision segment/triangle picking operates only on resident displayed surfaces, preserves original coordinates and the unchanged 2 µm diagnostic tolerance. 591 portable analytic cases and address/undefined-behavior sanitizers pass; Debug/Release compile passes; **189/189 native checks pass**, including the original large-coordinate regression; all 19 UI cases pass, but the runner exceeds its 2100-second execution budget during shutdown. The overall interface gate remains failed (exit 124), and the required new screenshots are not yet reviewed. [Verified checkpoint](evidence/native-1fee/summary.json). |
| Checked room priorities | A separate continuation branch derives bounded adjacency from registered, same-stage viewpoints with original floor/clearance checks and a recorded-camera corridor. Current room, checked neighbors and same-floor shell geometry receive display priority after the immediate neighborhood. Existing live walking checks remain mandatory. The combined source passes 192/192 native checks, including all new room-link cases; all 19 interface workflows and full export/recovery integration pass at 239.1. [Candidate](evidence/room-streaming-candidate.md). |
| Viewer performance evidence | User-started local cadence/memory/thermal reports checkpoint incomplete sessions and finalize on leaving Explore, inactivity or scene changes. Five independent reader tests pass. Combined source passes 192 native checks, 20 reader phases and 57 command contracts; all 19 UI workflows, three process recoveries and 37 export reports pass. Required map/comfort screenshots have been inspected. [Native checkpoint](evidence/native-883/summary.json). This does not measure presented FPS or qualify a phone. [Candidate](evidence/viewer-runtime-candidate.md). |

The room/performance continuation **239.1**, source `8831db8767338f2b485293a6dbaf1e9ff6188c11`, [run 39276168643](https://github.com/jverdi/house-memory-proof/actions/runs/39276168643), passes complete integration and its exact application source is now on `main`; the measured-taper follow-up now also passes complete integration. Predecessors 236.1 and 237.1 were superseded while queued; 238.1 was cancelled during setup. None supplied a native or UI acceptance result. No active TestFlight validation is cancelled by this work.

Existing portable geometry (50), command (52) and CI/release (47) tests passed with the picking repair. The viewer continuation expands the command/reader suite to **57/57 passing tests**. LeakSanitizer itself was unavailable because the host blocks its process inspection; address and undefined-behavior checks passed with leak detection disabled. These host results do not substitute for native or device results.

The combined candidate **241.1**, source `777520e23ffc6930ce4118be2626c1634f0a045a`, [run 39281579722](https://github.com/jverdi/house-memory-proof/actions/runs/39281579722), adds checked straight round/rectangular tapers with both measured endpoint sizes. It retains 240.1’s application implementation, with adjusted CI execution headroom. All 60 command/reader contracts pass. Its 193 native checks, 20 reader phases and 60 command contracts pass in a SHA-verified checkpoint; all 20 interface workflows, including save/relaunch of endpoint dimensions, also pass. Three process recoveries, 50 portable cases and 37 export reports pass; required screenshots are reviewed. The combined application source is integrated on main. [Native evidence](evidence/native-777/summary.json). The superseded 240.1 also passed 193 native checks before cancellation; it did not complete independent readers or UI. Constant-size geometry is checked for exact compatibility; this does not qualify arbitrary curved transitions or physical geometry. [Candidate](evidence/measured-taper-candidate.md).

The combined follow-up increases only execution headroom to 2400 seconds for the 20-case UI process, 42 minutes for its step and 70 minutes for the simulator job. 235.1’s 1992.629-second case run plus build and shutdown exceeded the old 2100-second bound. Every declared case and a zero runner exit remain required; native limits and accuracy thresholds are unchanged. The original timeout remains retained.

## Remaining work, in execution order

1. Requested 234.1 signing, upload, Apple processing and internal testing state are verified. Account-specific access evidence is excluded from public reports; installation/device results remain separate.
2. Both the room/performance and tapered-section continuations are validated and integrated. Latest complete integration is 241.1 / `777520e23ffc6930ce4118be2626c1634f0a045a`: 193 native checks and all 20 UI workflows. Exact-source results and screenshot review are retained.
3. Continue reconstructed whole-house topology/streaming, mixed-stage/closed-loop coverage, broad tours, thin/variable-section services, registration and representative drawing qualification. Current bounded analytic cases do not close these software requirements.
4. Complete the owner-device, real provider and signed-update matrix using [DEVICE_ACCEPTANCE.md](DEVICE_ACCEPTANCE.md). New instrumentation must only be tested on a build that contains it.
5. Finish physical acquisition/calibration/independent validation and the unresolved localization acceptance gates before final acceptance or renewal.

## Gates that cannot be marked complete here

| Gate | Evidence still required |
|---|---|
| Finished localization | Existing accuracy, rough-to-finished availability and finished depth-edge failures remain. The five-attempt finished-384 repair budget is exhausted; another experiment needs an explicitly renewed bounded budget under runbook §22.3. The separately authorized two-job diagnostic has now finished with six incomplete observed cases; its allowance is consumed and the workflow retired. The distinct one-job / 40-minute failure-diagnosis follow-up is now authorized and running; no retry is authorized. No sixth estimator variant is authorized. Integration-triggered unchanged-estimator replay jobs were cancelled and supply no qualification result; the cancellation record is in the continuation ledger. |
| Full software qualification | Diverse reconstructed whole-house navigation, registration, services, coverage and tours, followed by the specified development/protected evaluation. A small passing fixture is not whole-house acceptance. |
| Actual iPhone | Sustained capture/render/export, memory and thermal behavior, interruptions, accessibility and homeowner task comprehension on identified installed source. |
| Files/iCloud and updates | Real provider partial arrival, offline/quota/conflict/account transitions, large-device workloads and recoverable signed-version update. |
| Physical accuracy | Measured sensor timing/adapters, identifiable calibration and independent construction-region/later-session truth. Precision remains disabled. |

Public source, workflow and synthetic-evidence publication to `jverdi/house-memory-proof`, including direct main and release branches through the requested TestFlight delivery, is authorized. Earlier publication blocks are historical, not current restrictions.

The latest complete integration is **241.1 / 777520e23f** with 193 native checks and all 20 UI workflows; its application source is integrated on main. The earlier 239.1 room/performance integration remains retained separately. Requested snapshot **234.1 / cac8756b62** separately passes 182 native checks and all 19 UI workflows. The earlier **226.1 / ad8e0c5c8b** complete integration remains retained separately. Release 231.1 and main 233.1 failures are retained in [restart evidence](evidence/restart-20261019/summary.json); 233.1 passed 187/188 native and 18/19 UI checks. A later candidate does not erase those failures.

The current machine-readable checkpoint is the [continuation ledger](../tasks/continuation-20261019.json). Historical status/qualification documents retain their previous checkpoints; no account-specific history is republished in this update. See the [baseline qualification ledger](../tasks/qualification.json), [package audit](IMPLEMENTATION.md), [approved runbook](architecture-runbook.md) and [preserved earlier progress](history/current-progress-before-20261019-continuation.md).

Integration commit `5404e776b6c032ee16282bb8889b025dccfc7104` contains the same application/CLI/CI source validated at 241.1; a file-level comparison is empty across those paths. The ordinary main build may repeat that validation. Five unrelated localization replay triggers were cancelled, including the native vision job during compilation before query generation or evaluation. No new localization result is claimed.

## Registered reconstruction/navigation follow-up

A three-fragment native check is prepared for registered room-boundary traversal, missing-floor refusal and disconnected upper-floor jumps. All 63 command/reader and 47 CI contracts pass locally; native integration at source `5242e7c320dbfb24a39c86ec1eebac7b558143e4` found the graph-completion reporting failure retained below. A corrective source is prepared. Registration and floor classification are explicitly supplied. This expands the existing isolated-fragment coverage without claiming whole-house acceptance. [Candidate and declared validation budget](evidence/reconstructed-rooms-candidate.md). The separately authorized localization observer finished at [39313356060](https://github.com/jverdi/house-memory-proof/actions/runs/39313356060), serially within its two-job / 80-minute cap, with incomplete diagnostic results.

## Authorized localization diagnostic outcome

The two-job diagnostic completed serially in **12m05s**, with both artifact hashes verified. Both native binaries compiled, but all six observed cases were incomplete before equivalence/residual evaluation. The native error category was not retained, so no estimator defect or accuracy improvement is established. The original failures remain; the allowance is consumed and the one-shot workflow is retired. [Results](evidence/localization-observer-20261019/README.md). A separately prepared controlled-failure probe has 31 local checks passing and is now executing under its authorized [one-job / 40-minute proposal](LOCALIZATION_OBSERVER_FAILURE_PROPOSAL.md).

## Registered-room native failure and correction

Build **244.1 / 5242e7c320** compiles both configurations and completes **194 native checks in 271.777 seconds: 193 pass, one fails**. Actual seam movement, floor refusal and upper-floor jumps pass; the graph incorrectly flags completed work as limited when duplicate evidence remains after its only link is found. The source correction skips resolved pairs before checking the expensive-candidate budget, with a deterministic one-candidate regression and unchanged checks for genuinely unfinished multi-pair work. [Original failed checkpoint](evidence/native-524/summary.json). One corrective integration job is declared under the existing 70-minute cap; native and complete integration acceptance remain pending.

The correction is committed as **ed5aaa7e13881348e927a45a553845934c0e7b41**. Corrective build **245.1**, [run 39317003340](https://github.com/jverdi/house-memory-proof/actions/runs/39317003340), completed with 194/194 native checks and all 21 independent reader phases passing. The room-graph correction is natively validated, but the full integration gate failed: 19/20 UI workflows passed; the viewer-speed adjustment stopped at 0.3 m/s instead of the required 0.2 m/s. [SHA-verified evidence](evidence/native-ed5/summary.json). The latest complete integration remains 241.1.

## Slider endpoint follow-up and active diagnostic

The UI harness retains the normalized adjustment and adds at most one thumb-to-edge gesture if it stops short. Exact endpoint, relaunch persistence and reset assertions remain unchanged; no application setting or tolerance is changed. The retained 245.1 accessibility snapshots all report 0.3 m/s. All 63 command and 47 CI contracts pass locally. One follow-up integration job is declared, maximum 70 minutes; native UI execution remains pending.

The separately authorized failure-code probe is running as [39329166282](https://github.com/jverdi/house-memory-proof/actions/runs/39329166282), source `9eb7231622a5e0af90751e07e56d790f98058b36`: one job, 40 minutes maximum, original disclosed seed 905771, no reruns or estimator/threshold changes. It does not upload a new TestFlight build.

The endpoint correction is committed as `389ac9ccde749623f51d3b84397b25f9db742de9`; [build 246.1 / run 39329413198](https://github.com/jverdi/house-memory-proof/actions/runs/39329413198) is queued. The retained 245.1 screen recording was also visually reviewed and confirms the displayed 0.3 m/s value; this is not just an accessibility-label discrepancy. No production UI or numeric tolerance was changed.

## Evidence review completed 20 October

246.1 comfort, left-handed landscape layout, map checked-area/invalidation and saved-taper screenshots are reviewed against the hash-verified simulator artifact. The complete passing result and visual findings are retained in [native-389](evidence/native-389/summary.json). The current storage continuation remains separate and unchanged.

The authorized one-job observer probe completed in 413 runner-seconds with all three cases incomplete at `initialization / create`, before query evaluation. Its generic application error does not establish the underlying filesystem cause. The artifact hash is verified, the allowance is consumed and the active workflow is retired; no retry or estimator change is authorized. [Retained outcome](evidence/observer-failure-20261019/README.md).
