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
renovation state cannot be emitted as observed geometry. A separately named
appearance variant adds open windows, clutter and three diffuse material
families. Split levels, complex workmanship, insulation/renovation capture
states, glazing and broader physical materials remain open.

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
thin-service metric accuracy remain open. New runs retain raw inputs and derived
spatial records only in the ephemeral CI workspace; uploaded and permanent
evidence is aggregate only. No synthetic result
enables physical precision.

## Fixed-frame metrics and frozen-candidate inventory

The evaluator now measures rotation as well as translation. For connected-house
queries it samples up to 48 oracle-visible surface pixels, retains their true
optical-axis depth outside candidate inputs, and scores both world displacement
and pixel reprojection under the accepted camera pose. No alignment or scale fit
to truth is performed. These additional metrics are diagnostic; existing gates
are unchanged. Each room is still an independent unregistered capture frame, so
these metrics do not establish cross-room registration. A local 128-pixel fixture
self-projected all 768 nominal surface samples with negligible numerical error.
Five analytic tests cover translation, rotation, origin invariance, invalid
transforms and points behind the estimated camera.

A frozen-candidate runner prepares 50 development and 20 protected distinct
layouts after the binary hash is fixed. Fourteen shards retain both stages for
every house; aggregation checks exact split/case identities, every query/error
count, finite metrics, map counts, oracle controls, source identity and unchanged
accuracy gates. Six evaluator tests reject missing/duplicate cases, changed
binaries, relabelled splits and forged passing metrics. Whole-house paired-stage
bootstrap intervals are reported. Exception text is excluded from public logs
because subprocess arguments can disclose protected seeds.

This is prepared evaluation infrastructure, not a completed 50/20 run. It has no
automatic launch workflow yet: known development failures remain open, and a
separate restricted job context is required before drawing protected plans. Its
initial nominal corner/upper-wall captures do not cover the remaining material,
sensor, continuous-path, full-coverage or navigation requirements.

## Additional window and clutter cases

`--scene-variant windows-clutter` uses the same topology with deterministic
exterior openings, solid jambs/sills/headers, interior occluders and three diffuse
material palettes. It never cuts through a service route or adds a connection at
an image crossing. Clutter reserves door approaches and the full stair bay.
Rough assemblies, service IDs and unknown graph links survive finishing. Windows
are explicitly open: the analytic renderer does not claim transparent glass,
refraction, calibrated sunlight or realistic material-dependent depth.

The default baseline is retained. A generated four-room 128-pixel archive has
all 98 entries byte-identical to source d7d0a4af8e. Eight independent variation
contracts check 50 generated layouts, volume-conserving aperture subtraction,
frame clearance, foreground occlusion and invalid-scene refusal. The complete
local simulation suite passes 49 contracts. Both baseline and varied four-room
archives independently pass original-hash, buffer and oracle-exclusion checks.
These are generator/adaptor results, not production spatial scores.

The new development workflow budgets two four-/seven-room cases at 384 pixels,
both stages, at most two 40-minute jobs with one active at a time. It runs the
unchanged production estimator and spatial gates. Inputs, geometry, query
records and oracle remain ephemeral; only allowlisted aggregate metrics and
inventory counts are published. The original baseline replay remains separate.
Exact-source native replay of the new appearance cases is pending. These cases
do not close continuous capture, full coverage, closed-loop navigation,
cross-room registration, protected diversity or physical qualification.
