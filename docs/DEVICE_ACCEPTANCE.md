# Owner-device acceptance record

This is the execution protocol for runbook §§25–26. It is not a completed test report. Simulator results and Apple availability do not mark any item below passed. Record the source/build shown in Tools, phone model, iOS version, free space, battery state and test date with each exported report.

## Start with a recoverable test project

Keep the existing app installed. Export an existing house as a complete archive before an update, retain that file separately, and restore a copy as a separate project. Do not use the only copy of real construction evidence for fault tests. An unavailable provider file or a failed restore stays a failed check even if the original local project still works.

After installing the new TestFlight build, open Tools → Run synthetic self-tests, then Export diagnostics. The report must identify the physical phone and the installed source; the simulator report is a separate result. Retain failures and the original report. A green self-test does not qualify the live camera or physical precision.

## Homeowner guidance and accessibility (R19)

On a build that includes R19, open Help & getting started → Help settings → Restart introduction. Complete it once, relaunch, and confirm it stays dismissed. Skip it once, enable Show introduction next time, fully close/relaunch, and confirm it returns. Verify that the same houses, photos and notes remain intact. This guide reset must not behave like a project reset.

If you first explored the sample, create your own house and confirm Capture shows that house's room and stage. Switching houses must not carry over the previous house's room selections.

With networking off, use the guide for one real homeowner task: identify the correct house, room and date; record or import a photograph; find it again; and save a complete backup. Use the unfamiliar-word search and the unavailable-camera/overlay alternatives. Record any step whose wording or named control is unclear; successful navigation alone does not establish that the instructions are understandable.

With the iPhone's larger accessibility text, landscape orientation and VoiceOver, read the introduction and a long guide. Confirm headings and actions are understandable, selection state is spoken, content scrolls, and Back, Skip, Done and the next action remain reachable. Retain screenshots or a recording of failures. Simulator screenshots do not substitute for this owner-device check.

## Movement comfort and room map

Run these checks only on a build that includes Movement & view and, for the map checks, Room map. TestFlight 216.1 does not contain these additions. Use the sample or a separate test house first.

- Open Explore → Layers → Movement & view. Start with slow movement and turning. Change the view width and eye height, then let go of the movement control. Confirm movement stops immediately and the view feels usable. Eye height must not allow passage through a low ceiling or across a missing floor.
- Enable Left-handed layout and rotate the phone. Confirm movement and looking controls remain reachable. Leave and reopen the app, then verify your choices are remembered. Reset movement and view should restore the defaults while keeping all house records and saved viewpoints.
- Interrupt a drag by switching apps, and disconnect a controller while moving if you use one. Reopen Explore and confirm no movement continues on its own. Record which interruptions actually occurred. Try Reset view to this room; if no checked walking location exists, the app should explain why Free fly is enabled.
- In Layers → Room map, turn on Show mini-map in the 3D view. Save a viewpoint through Jump, return to it from the map, and select rooms on different levels. Check the room, level and arrow against the displayed view, including Orbit overview and landscape. Dots indicate recorded photo positions; they must not be mistaken for proof that the whole area was captured. Unaligned visits must remain separate.
- Reopen the app and confirm the mini-map preference persists. Turn it off and confirm it disappears. With larger text and VoiceOver, check that room names, level, direction, selected settings and actions remain understandable. Record any controls or scene details obscured by the map. A room scope should explain how to return to All spaces.

Keep a screenshot or recording of any confusing or failed step, along with the build and phone details. Passing these usability checks does not establish whole-house geometry, complete coverage or physical accuracy.

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


## Viewer performance report (continuation candidate; not in 234.1)

Once a build containing `ViewerDiagnostics.swift` has passed integration and is installed, open the declared project and scope in Explore. In Layers choose **Start performance recording**, close the sheet, then follow the sustained walkthrough workload above. Stop recording in Layers before changing scope. Leaving Explore, backgrounding, or changing scene/layers ends the report; a force-quit retains an incomplete checkpoint. Export it from Tools → **Export viewer performance**. Retain the source/build identity with the fixture, duration and starting thermal condition.

The report measures completed-render callback intervals and sampled memory/thermal state, not display-presented FPS. Use the independent `tooling/check_viewer_runtime.py` reader to expose stalls and resource samples. Preserve overflow/unknown values and interrupted sessions. The report alone does not close the sustained-frame-rate, accessibility or actual-device qualification gates.
