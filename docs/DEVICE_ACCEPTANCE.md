# Owner-device acceptance record

This is the execution protocol for runbook §§25–26. It is not a completed test report. Simulator results and Apple availability do not mark any item below passed. Record the source/build shown in Tools, phone model, iOS version, free space, battery state and test date with each exported report.

## Start with a recoverable test project

Keep the existing app installed. Export an existing house as a complete archive before an update, retain that file separately, and restore a copy as a separate project. Do not use the only copy of real construction evidence for fault tests. An unavailable provider file or a failed restore stays a failed check even if the original local project still works.

After installing the new TestFlight build, open Tools → Run synthetic self-tests, then Export diagnostics. The report must identify the physical phone and the installed source; the simulator report is a separate result. Retain failures and the original report. A green self-test does not qualify the live camera or physical precision.

## Thirty-minute visit

Use several short capture segments in a disposable real project. Record the start/end times and what happened at each interruption. The report records ten-second resource samples; it does not record a video of the interaction.

| Part | Action | Evidence to retain |
|---|---|---|
| 0–10 minutes | Capture accessible construction from translated, overlapping viewpoints; include low and high surfaces. Stop, review originals and start a new segment. | Original photos/depth, room/stage/session identities, coverage before/after, any visible warnings |
| 10–20 minutes | Continue capture; exercise portrait/landscape changes, app backgrounding and screen lock. Reopen and start a new segment after interruption. | Whether capture stopped honestly, finalized photo counts, timestamps, missing/limited tracking and any unmatched image/depth behavior |
| 20–30 minutes | Continue with another segment; force-quit once after visible finalized photos, reopen and verify they occur exactly once. End capture normally. | Incomplete report from force-quit, recovered originals, final report and screenshot of any failure |
| After capture | Tools → Export capture performance, Export diagnostics, Export metadata JSON and Export complete house archive. | Unmodified reports and complete source archive; keep incomplete sessions alongside completed ones |

The agent evaluates acquisition-only camera/render callback rates, save latency/backlog/failures, memory, thermal state, battery and disk readings from the report. SceneKit callbacks are **not displayed FPS or GPU time**. This report does not establish sustained walkthrough rendering or movie performance. Phone interruptions and low-storage behavior need their own observed cases; an interruption that did not occur is untested, not passed. Do not fill the phone with irreplaceable data to manufacture low storage.

## Local workflow, resource and update checks

Turn off networking for the local workflow. In the synthetic/test project, inspect source photos, reconstruct a bounded segment, switch room/stage/ceiling/service layers, walk and use explicit room/floor jumps, and exercise accessible step controls. Preserve screen recordings showing wall/floor refusal, unknown connections, omissions and restoration after interrupted interaction. Record scene size and resource warnings; a small scene does not qualify the largest supported workload.

Create the required 60-second 1080p30 movie with its metadata sidecar. Interrupt one render, reopen and resume with the same inputs; retain the output and report. Independently decode and count the final frames (1,800), and verify the complete timeline, captions and source identity. Test reconstruction cancellation/continuation separately from movie rendering; a foreground success does not prove background GPU execution.

Export GLB, USDZ, PLY/OBJ, semantic CSV and a complete archive. Restore the archive as a new project and compare original hashes, geometry, labels, dates, measurements and source dependencies. Reopen after a day. For a signed-version update, retain a pre-update archive and the post-update outputs; the frozen CI archive from build 161.1 alone is not an actual signed-app migration test.

## Files/iCloud checks

Use a dedicated snapshot folder and disposable project. Record each case separately: complete upload/readback, partial arrival, offline local use, unavailable destination, quota refusal, revoked folder permission, and account change when that transition is deliberately performed. Keep the source project and a separate complete archive. No silent original deletion, activation of an incomplete snapshot, or false remote-completion claim is acceptable. Unknown provider status stays unknown. Restore a selected revision into a separate project and compare source hashes after the provider actually makes all required files available.

## Physical precision is a separate gate

Tools → Field checks and calibration evidence guides the measured exposed/covered fixture. Independently measure the references and checkpoints, including their uncertainty; retain their identities and source records. Record calibration and validation under separate purposes, regions and later sessions. Do not refit registration to the validation checkpoints. Include repeated-looking rooms, wrong floor/wall side, moved or missing references and tracking loss.

Export field evidence with the original observation archive. Evaluate by device/OS/camera mode and declared conditions, retaining abstentions and every failed challenge. The runbook's accuracy, availability, rejection and uncertainty gates remain unchanged. A successful owner visit does not itself enable a precision profile or automatic renewal.

## Return evidence

Share the unmodified exported JSON reports, movie/sidecar, relevant screenshots or screen recording, and the test archive through the existing project conversation. State which rows actually ran and which remain unavailable. The agent can analyze those files and repair reproducible defects; it cannot infer actions or sensor behavior on an inaccessible phone.
