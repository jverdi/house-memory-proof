# House Xray: current progress

Updated 18 October 2026. The full plan is **in progress**. Precision use and final release acceptance remain disabled.

## What you can install

**TestFlight 216.1 is available to the owner's Personal iPhone group.** Apple processing and tester access are verified. Installation on the physical phone has not been verified. This is the requested development snapshot, not the completed app.

216.1 does **not** include the new homeowner introduction, help guides, movement settings or room map. Later validation builds are not TestFlight uploads. The instruction to wait for completion before another upload remains in effect.

## What has changed since that snapshot

| Work | Current evidence |
|---|---|
| First-use introduction | Five steps, three starting goals, Skip, Back, restart and show-on-next-launch settings are implemented. Replaying help preserves house records. Simulator workflows pass at 224.1. |
| Help inside the app | Fourteen searchable, offline guides explain homeowner tasks, unfamiliar terms and what to do when capture or an overlay is unavailable. Links open the relevant app screen. Simulator workflows pass at 224.1. |
| First real capture after the sample | The new house retains its own room and stage. The capture header and opening instructions pass renewed visual review at 224.1. |
| Walking over recorded surfaces | Missing floor support is refused. Connected room/stair diagnostics and two bounded reconstructed fragments pass at 224.1. This is not whole-house navigation qualification. |
| Movement and view settings | Remembered speed, acceleration, turning, sensitivity, view width, eye height, handedness and reset are implemented. Combined validation is running in 225.1. |
| Room map | Room, level, direction, saved viewpoints and recorded photo positions are implemented, with separate unaligned visits and a remembered mini-map. Dots do not establish complete capture coverage. Combined validation is running in 225.1. |
| Readability follow-up | Dark lettering on bright action buttons, a separate walking-notice row and clearer capture-count wording are included in 225.1. Screenshot review is pending. |

Latest complete integration: **224.1**, source `3883931263a2861a28cd354f190bbc3d8d71f178`, run `39169002149`: 172 native checks, 17 interface workflows, 19 reader phases, 52 command contracts, 36 validation reports, three process recoveries and 50 portable checks pass. Artifact hashes are independently verified in [the retained report](evidence/native-388-summary.json).

Current candidate: **225.1**, source `bf0a75c353953233c6a517fca7a71693cae37f1e`, run `39172396220`. Debug and release compilation have passed; native diagnostics are running. Expected totals are 178 native checks and 19 interface workflows. An active build is not a passing result.

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

## Next steps

1. Finish 225.1, inspect all nine selected screenshots and retain any failures before repairing them.
2. Publish its verified results and update this page and the task ledger.
3. Continue independent software work. Keep the exhausted accuracy-repair budget separate from implementation that can proceed.
4. Use the [owner-device protocol](DEVICE_ACCEPTANCE.md) for checks that need the actual phone. Only run feature-specific checks on a build containing those features.

Detailed state: [task ledger](../tasks/qualification.json), [implementation audit](IMPLEMENTATION.md), [runbook](architecture-runbook.md), and [TestFlight delivery evidence](evidence/testflight-216-1-summary.json).
