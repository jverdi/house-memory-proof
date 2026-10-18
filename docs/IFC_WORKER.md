# Bounded local IFC worker

Native source 67cc61c3d6 timed out during the existing IFC2x3 cancellation/reuse scenario. It completed 128 native checks: 127 passed and one failed; the first IFC failure prevented three later checks in that block. The new photograph annotation and provenance checks passed. This failure is retained, not counted as a full integration pass.

The converter uses a nonpersistent WKWebView outside the visible view hierarchy. Apple documents inactiveSchedulingPolicy as the policy for views not in a window; the default suspend policy can stop asynchronous work after page loading. WebKit's explanation of SDK-linked behavior is consistent with this worker's intermittent timeout, but the timed-out run did not record an internal phase, so suspension is a supported hypothesis rather than a proven trace.

The next candidate sets the public policy to none for this single bounded local operation, retains the 60-second deadline, ignores obsolete view requests, and handles failures after provisional navigation. It records only allowlisted lifecycle phase names (created, initializing, source, parsing, geometry, complete/cancelled/failed). Failure output identifies the last phase without including IFC content or resource paths. Completion and cancellation destroy the worker; this creates no background entitlement or promise of execution while the app is suspended. Existing cancellation/reuse, units, placements and malformed-geometry tests remain mandatory.

Primary references:
- https://developer.apple.com/documentation/webkit/wkpreferences/inactiveschedulingpolicy-swift.property
- https://developer.apple.com/documentation/webkit/wkpreferences/inactiveschedulingpolicy-swift.enum/none
- https://bugs.webkit.org/show_bug.cgi?id=283794 (WebKit maintainer explanation, comments 4–5)

Source 0e191bca22, build 197.1, passed the IFC2x3 cancellation/reuse path and every expected phase, IFC4 millimetre/nested/rotated placements, bounded coordinate refusal and recovery. Its complete integration passed 133 native checks, six UI flows and 22 independent readers. The original timeout remains recorded; IFC time/geometry admission limits are unchanged. See `docs/evidence/native-0e19-summary.json`.


## Source dependency and placement continuation

The next candidate associates every converted IFC object with its saved source
Drawing, a converter/version/asset fingerprint and a separate unregistered
planned segment. Room association does not establish house alignment. Import
publication compares the source/stage snapshots and refuses changed or missing
inputs and repeated feature identities. A source replacement invalidates derived
geometry. The original is saved before conversion and remains after refusal;
archive restoration preserves the source, local geometry and frame. A saved IFC
can be reopened from its Drawing page after selecting a room association; the
result states that house alignment is unknown and identifies its stage.

This fixes the earlier Tools importer, which retained the IFC file but did not
link its objects to that file and left their coordinates in the global house
frame. A native source/frame/stale-publication/archive regression and a saved-source
interface workflow are prepared (137 native checks and nine UI flows expected);
exact-source validation is pending. Older already-imported objects are not
silently relocated. Far-origin rebasing, explicit georeference records and
broader malformed-GUID/unsupported-geometry qualification remain open; the
existing large-coordinate refusal continues to preserve the original.
