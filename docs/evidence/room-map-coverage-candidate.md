# Checked wall areas in the room map

Status: compilation and both native regression checks pass in 230.1; interface and visual review remain pending. Evidence: [native checkpoint](native-dc5-summary.json).

The full map and mini-map summarize wall/ceiling checks actually requested through Review capture coverage. The shared transient cache retains at most 128 compact area results, without retaining depth buffers. Counts distinguish defined, checked, unchecked and stale areas, supported sampled patches and known gaps. Overlapping rectangles remain separate sampled areas; no whole-room percentage or unique covered area is inferred. Other surfaces remain unassessed.

Results are tied to project identity, revision and exact boundary inputs. Project changes, changed definitions and app restarts require fresh checks. Scene stage, room and unaligned-visit scope match the map. Report preparation runs in cancellable background work; camera animation does not re-read depth or recompute coverage.

Two native regression cases use production depth coverage for supported/blocked planes, then exercise revision/project invalidation, overlapping and unchecked regions, malformed reports, stage/room/frame separation and bounded eviction. The existing map interface workflow additionally checks the accessibility caveat. All 19 interface workflows remain required, together with 185 native checks in the combined map and room-jump candidate. Original acceptance thresholds and runtime budgets are unchanged.

The separately requested TestFlight snapshot 228.1 uses source f7123ca2ee6c556620b3f01cc3d6d88bc20d0597 and excludes this follow-up. It retains the full simulator validation gate before Apple upload. This candidate does not enable precision, establish whole-house coverage or complete physical qualification.
