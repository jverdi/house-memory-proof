# Connected house simulation contracts

The new development generator builds connected room unions across one to three
levels. Cells can merge into real open-plan polygons; internal walls disappear.
Doors connect only adjacent rooms through cut wall openings. Stair flights have
individual treads, upper-floor and ceiling openings, and top landings. The
geometry checks verify connectivity, polygon area, non-overlap, portal clearance,
tread continuity and headroom. Fifty deterministic development seeds produce
fifty distinct topology signatures after removing materials, dimensions and IDs.
This checks generator diversity; it does not qualify the application on fifty
houses or establish a protected holdout result.

Physical assembly and service IDs survive rough and finished stages. Finishes
have 12.5 mm thickness on each side of framing. Source assemblies stay in place;
added finish surfaces occlude cavity services. Electrical, plumbing and thin
low-voltage routes remain separate even when they cross in the image. A planned
renovation state cannot be emitted as observed geometry. Split levels, complex
workmanship, windows, clutter and broader material families remain to be added.

The separate sensor adapter applies reproducible depth noise, temporal
correlation, scale/bias, edge mixing, thin-object dropout, exposure, compression,
Gaussian blur, calibration error, pose drift/jumps, clock offsets, dropped frames
and tracking breaks. It never substitutes background depth for a missing thin
object. Gaussian blur is not described as rolling shutter. Parameters are
analytic challenges, not measured iPhone behavior. Source arrays stay immutable;
configuration, event ledgers and visibility IDs remain evaluator-only.

The capture adapter observes selected corners and tilted upper-wall views. The
ray renderer can emit a separate visibility pass without changing its ordinary
RGB/depth contract. Ground-truth layouts, routes, cameras, topology signatures,
noise parameters and query labels do not enter the `.hxray` candidate archive.
The generated observations use the versioned capture-provenance contract with explicit unavailable EXIF, camera pixel format, motion and clock-calibration fields. The independent archive check verifies every hash, buffer length, reference and receipt relationship.
The existing macOS OS sandbox denies the evaluator oracle to the compiled
production map/query implementation.

Each localization replay receives observed maps for one stage. The same physical
layout is replayed separately in rough and finished states. It does not assume a
known registration between two independent stage sessions. Cross-stage handoff
and whole-house registration remain separate acceptance work. The evaluator
requires all expected maps, >=90% nominal availability, <=10 mm p95, <=25 mm
worst accepted error, zero critical false accepts and the existing source-pose
gate. Existing four-map fixtures retain their original denominator and gates.

The first CI matrix covers three development layouts (four, seven and eleven
rooms on one, two and three floors) in both stages at 384 pixels. It is a new
qualification attempt, not a passed release gate. Wider 50-development / 20-
protected candidate evaluation, sensor-profile sweeps, continuous doorway/stair
capture, closed-loop guidance, coverage scoring, reconstructed navigation and
thin-service metric accuracy remain open. Detailed inputs and results belong in
bounded CI artifacts; permanent evidence is aggregate only. No synthetic result
enables physical precision.
