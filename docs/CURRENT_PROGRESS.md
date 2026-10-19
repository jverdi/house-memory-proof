# House Xray: current progress

Updated 19 October 2026. Work has resumed in a new thread. The approved runbook remains **in progress**. Precision, accepted-release and automatic-renewal gates remain closed.

## TestFlight delivery

**216.1 is the last verified available TestFlight build.** Apple processing and owner-group access are verified; installation or physical qualification of a later build is not claimed.

Requested snapshot **234.1**, source `cac8756b627474b65d2a8b1f912a73791b3225dc`, [run 39272141287](https://github.com/jverdi/house-memory-proof/actions/runs/39272141287), passes Debug/Release compilation, **182/182 native checks**, **19 independent reader/command phases** and **52 command contracts**. Its native artifact SHA-256 was independently verified. The complete **19-workflow interface gate is running**; signing, Apple upload, processing and owner access remain pending. [Retained checkpoint](evidence/native-cac/summary.json).

This requested snapshot includes homeowner introduction/help, viewer comfort and room-map work. It does not include the subsequent picking, room-priority or viewer-performance continuation. The full simulator gate still precedes upload; no release criterion was removed.

## Work completed or under validation

| Work | Exact state |
|---|---|
| Snapshot accessibility repair | Native slider percentages are retained; current physical units move to the accessible label. Standard slider adjustment still requires exact endpoint/persistence/reset assertions. Switch interaction targets its actual control. 234.1 native passes; UI pending. |
| Small displayed-surface picking | Source `1fee4cc117fc61baa5c8f8a6b8d531b56d68c5db`, **235.1**, [run 39273286562](https://github.com/jverdi/house-memory-proof/actions/runs/39273286562). Production double-precision segment/triangle picking operates only on resident displayed surfaces, preserves original coordinates and the unchanged 2 µm diagnostic tolerance. 591 portable analytic cases and address/undefined-behavior sanitizers pass; Debug/Release compile passes; 189 native checks and 19 UI workflows pending. |
| Checked room priorities | A separate continuation branch derives bounded adjacency from registered, same-stage viewpoints with original floor/clearance checks and a recorded-camera corridor. Current room, checked neighbors and same-floor shell geometry receive display priority after the immediate neighborhood. Existing live walking checks remain mandatory. Source/negative regression cases published; native validation pending. [Candidate](evidence/room-streaming-candidate.md). |
| Viewer performance evidence | User-started local cadence/memory/thermal reports checkpoint incomplete sessions and finalize on leaving Explore, inactivity or scene changes. Five independent reader tests pass. Combined source expects 192 native checks and 19 UI workflows; native execution pending. This does not measure presented FPS or qualify a phone. [Candidate](evidence/viewer-runtime-candidate.md). |

The room/performance continuation is isolated on `room-streaming-20261019` while the requested release and main picking validation finish. Its queued predecessor 236.1 was superseded without a native or UI acceptance claim. No active TestFlight validation is cancelled by this work.

Existing portable geometry (50), command (52) and CI/release (47) tests passed with the picking repair. LeakSanitizer itself was unavailable because the host blocks its process inspection; address and undefined-behavior checks passed with leak detection disabled. These host results do not substitute for native or device results.

## Remaining work, in execution order

1. Finish the requested 234.1 interface gate, repair any reproduced failure, then verify signed upload, Apple processing and owner-group access.
2. Inspect the 235.1 picking regression and complete interface evidence. Inspect the combined 192-check room/performance continuation, repair failures and integrate the passing source into main. Preserve each exact-source result and required screenshots.
3. Continue reconstructed whole-house topology/streaming, mixed-stage/closed-loop coverage, broad tours, thin/variable-section services, registration and representative drawing qualification. Current bounded analytic cases do not close these software requirements.
4. Complete the owner-device, real provider and signed-update matrix using [DEVICE_ACCEPTANCE.md](DEVICE_ACCEPTANCE.md). New instrumentation must only be tested on a build that contains it.
5. Finish physical acquisition/calibration/independent validation and the unresolved localization acceptance gates before final acceptance or renewal.

## Gates that cannot be marked complete here

| Gate | Evidence still required |
|---|---|
| Finished localization | Existing accuracy, rough-to-finished availability and finished depth-edge failures remain. The five-attempt finished-384 repair budget is exhausted; another experiment needs an explicitly renewed bounded budget under runbook §22.3. No experiment or protected draw was run during this continuation. |
| Full software qualification | Diverse reconstructed whole-house navigation, registration, services, coverage and tours, followed by the specified development/protected evaluation. A small passing fixture is not whole-house acceptance. |
| Actual iPhone | Sustained capture/render/export, memory and thermal behavior, interruptions, accessibility and homeowner task comprehension on identified installed source. |
| Files/iCloud and updates | Real provider partial arrival, offline/quota/conflict/account transitions, large-device workloads and recoverable signed-version update. |
| Physical accuracy | Measured sensor timing/adapters, identifiable calibration and independent construction-region/later-session truth. Precision remains disabled. |

Public source, workflow and synthetic-evidence publication to `jverdi/house-memory-proof`, including direct main and release branches through the requested TestFlight delivery, is authorized. Earlier publication blocks are historical, not current restrictions.

Latest complete integrated source before this continuation remains **226.1 / ad8e0c5c8b**, with 178 native checks, all 19 UI workflows, readers/recovery/exports and visual follow-ups passing. Release 231.1 and main 233.1 failures are retained in [restart evidence](evidence/restart-20261019/summary.json); 233.1 passed 187/188 native and 18/19 UI checks. A later candidate does not erase those failures.

See the [qualification ledger](../tasks/qualification.json), [package audit](IMPLEMENTATION.md), [approved runbook](architecture-runbook.md) and [preserved earlier progress](history/current-progress-before-20261019-continuation.md).
