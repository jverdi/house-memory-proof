# House Xray: current progress

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
| Finished localization | Existing accuracy, rough-to-finished availability and finished depth-edge failures remain. The five-attempt finished-384 repair budget is exhausted; another experiment needs an explicitly renewed bounded budget under runbook §22.3. No experiment or protected draw was run during this continuation. |
| Full software qualification | Diverse reconstructed whole-house navigation, registration, services, coverage and tours, followed by the specified development/protected evaluation. A small passing fixture is not whole-house acceptance. |
| Actual iPhone | Sustained capture/render/export, memory and thermal behavior, interruptions, accessibility and homeowner task comprehension on identified installed source. |
| Files/iCloud and updates | Real provider partial arrival, offline/quota/conflict/account transitions, large-device workloads and recoverable signed-version update. |
| Physical accuracy | Measured sensor timing/adapters, identifiable calibration and independent construction-region/later-session truth. Precision remains disabled. |

Public source, workflow and synthetic-evidence publication to `jverdi/house-memory-proof`, including direct main and release branches through the requested TestFlight delivery, is authorized. Earlier publication blocks are historical, not current restrictions.

The latest complete integration is **241.1 / 777520e23f** with 193 native checks and all 20 UI workflows; its application source is integrated on main. The earlier 239.1 room/performance integration remains retained separately. Requested snapshot **234.1 / cac8756b62** separately passes 182 native checks and all 19 UI workflows. The earlier **226.1 / ad8e0c5c8b** complete integration remains retained separately. Release 231.1 and main 233.1 failures are retained in [restart evidence](evidence/restart-20261019/summary.json); 233.1 passed 187/188 native and 18/19 UI checks. A later candidate does not erase those failures.

The current machine-readable checkpoint is the [continuation ledger](../tasks/continuation-20261019.json). Historical status/qualification documents retain their previous checkpoints; no account-specific history is republished in this update. See the [baseline qualification ledger](../tasks/qualification.json), [package audit](IMPLEMENTATION.md), [approved runbook](architecture-runbook.md) and [preserved earlier progress](history/current-progress-before-20261019-continuation.md).
