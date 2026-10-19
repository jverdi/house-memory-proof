# Bounded directional streaming

Status: prepared for native validation; no acceptance result claimed.

The display planner now looks up to two seconds ahead along the actual movement velocity, capped at six metres. The nearest four-metre neighbourhood retains admission priority. Remaining tiles use the nearer of current distance and a penalized look-ahead distance. Stopping, reversing and large direction changes replan at the existing half-second cadence; tiny velocity changes do not churn residency. Orbit and idle looking do not fabricate movement.

The existing limits remain: 512 resident tiles, 400,000 vertex/index entries, 24 textures and 64 MiB decoded texture bytes. One tile is loaded per update, source IDs and original geometry remain unchanged, and this display hint does not change collision, navigation connectivity or measurement/export geometry.

The native regression checks tight-budget admission in both directions, protection of nearby geometry, invalid/tiny/large velocities, exact source materialization, reversal of pending loads at an unchanged camera position, stopping, source picking IDs and stable nearby SceneKit nodes. The combined next candidate with local render coordinates expects 187 native checks and the same 19 interface workflows. Native compilation and execution are pending.

This advances runbook §12.4. Verified room portals, room-local coordinates, complete reconstructed-house topology and sustained actual-phone performance remain open. It is absent from the requested TestFlight 228.1 and does not alter that release run.
