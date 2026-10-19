# Streamed room-jump collision handoff

Status: native validation passes in 230.1; full interface integration and screenshots remain pending.

The exact-source checkpoint dc505889f484a0bc61baafda1c20b5c550c51ffe passes all 185 native checks. The handoff regression confirms movement pauses during preparation, the latest destination survives rapid competing jumps, missing floors are refused, and source records are unchanged. Evidence: [native checkpoint](native-dc5-summary.json).

A room jump in a large scene previously tried to validate its destination against the previous resident collision window. This could relocate the view to the old room before the destination geometry was loaded. The controller now preserves the requested viewpoint, pauses walking while preparing its floor/clearance window, and validates against that window. A newer jump cancels and supersedes older work. Missing floor support or preparation failure retains explicit Free fly rather than inventing a walking route. Choosing Free fly explicitly cancels the pending walking intention.

A bounded asynchronous native diagnostic uses 514 analytic source features and two rooms 100 metres apart through the actual streaming controller. It checks initial admission, movement paused during handoff, destination retention, resumed walking, rapid competing jumps, cancellation, missing-floor refusal and unchanged source records. This adds one native case: the combined candidate expects 185 native checks, with the original 300-second app and 60-minute integration limits unchanged.

The existing photo-point interface workflow now continues through its saved wall boundary, runs a real coverage check, verifies its summary in the full map and mini-map, and confirms a project edit invalidates the check. Screenshots 48 and 49 capture checked and invalidated states. The total remains 19 interface workflows under the existing 2,100-second UI budget; no assertion or threshold is removed.

This is a local handoff regression, not reconstructed whole-house topology, sustained-device performance or physical qualification. TestFlight 228.1 remains pinned to its separately requested source and excludes this follow-up.
