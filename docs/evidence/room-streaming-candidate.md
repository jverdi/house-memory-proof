# Checked room streaming candidate — 2026-10-19

Status: source prepared; native compilation and runtime assertions pending. This is independent of the requested 234.1 TestFlight snapshot.

The display planner retains the immediate four-metre neighbourhood, then prioritizes the current room, checked adjacent rooms, other rooms on the same declared floor, and other rooms. Within a room priority, shell geometry precedes services. Existing 400,000-vertex, 512-resident and 24-texture limits remain unchanged. Original geometry and live walking admission are unchanged.

A derived room graph considers registered, spatially eligible viewpoints in the selected stage/frame. Each short candidate requires complete stage-specific original-geometry clearance, supported floor footprints, bidirectional walking checks and a sampled recorded-camera corridor. Its links retain the source observation IDs and stage. No inferred link is physical doorway evidence. Missing evidence produces missing links. Separate unregistered visits never acquire cross-room links.

Metadata and candidate work are bounded: at most 2,000 sampled anchors, 4,096 generated pairs, 256 checked candidates and a one-second cooperative time budget. A limited graph remains conservative and only influences display priority. Initial scene streaming becomes usable before background graph construction finishes; stale results are discarded.

New native assertions cover six analytic room/stair transitions, an obstructed door, hidden display trades, missing camera corridor, missing/planned floors, separate frames, mixed stages without finished floor support, candidate exhaustion, two unobserved stacked rooms, and room/residency ordering under a tight budget. These are analytic development fixtures, not reconstructed whole-house or physical-device qualification. Expected combined native suite: 191 checks; interface suite: 19 workflows. Results remain pending.
