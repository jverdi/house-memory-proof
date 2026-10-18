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
source ec315c98d6 passed the native regression and saved-source UI flow. Its full integration remains failed because of the separate service-edit UI case. Older already-imported objects are not
silently relocated. Far-origin rebasing, explicit georeference records and
broader malformed-GUID/unsupported-geometry qualification remain open; the
existing large-coordinate refusal continues to preserve the original.

## Reversible project coordinates and documentary CRS candidate

The next candidate retains a typed source coordinate record on the original
Drawing. Near-source coordinates are unchanged. If the first transformed point
exceeds 10 km on an axis, the converter chooses a fixed 100 m grid origin and
subtracts it before handing geometry to native code. Adding the retained Z-up
metre origin recovers the project coordinates. Absolute source coordinates are
bounded to 1e9 m; the existing 100 km local geometry limit remains. Widely
separated geometry outside that range refuses the entire conversion while the
original survives. This is numeric rebasing, not registration or surveying.

Pinned web-ifc 0.0.72 still handles source units and nested placements. The
converter records the source schema/length-unit label and up to 16
IfcMapConversion records, including source numeric fields, projected-CRS labels
and map-unit labels; scaled factors are retained when supplied by the reader.
Those records are documentary: no CRS rotation, scale, projection or house
alignment is applied. Missing fields remain absent rather than invented. Full
IFC4x3 scaled-conversion interoperability, conversion-based units, malformed GUIDs
and unsupported representation census remain unqualified.

The typed origin/CRS record participates in the derived-source fingerprint.
Archive/JSON retain it; GLB carries one record per selected source in root extras,
and semantic CSV carries it in each source feature's provenance. GLB nodes also
record the source segment, export frame and any applied local-to-house
registration, so readers can invert that transform before adding the origin.
The independent reader covers both a local source and an explicitly rotated/
translated export. GLB admission
counts worst-case escaped metadata and simultaneous encoding copies. The saved
source page preserves the read-only record when notes are saved. Schema 3 reads
versions 1/2 in memory and causes older readers to refuse new saves, preventing
silent loss of the reversible origin. Originals are never rewritten by opening.
The signed old/new-app handoff is still an external qualification item.

Local JS contracts cover near/far coordinates, reversibility, range refusal,
units, CRS/scaled-field retention, no inferred alignment and metadata budgets.
The independent package reader covers malformed origins/CRS and schema refusal;
28 command/reader contracts pass locally. Native tests are prepared for real
IFC4 millimetre far-origin conversion, real CRS parsing, archive restoration,
source invalidation and GLB/CSV handoff. A separate Python reader decodes the
actual Swift GLB vertices and adds the retained origin to recover known project
bounds; pinned Khronos validation also includes this GLB. The small IFC export fixture stays private in CI; only aggregate reader reports
are retained. Native validation of this candidate is pending (140 checks expected); no physical claim is made.

Primary API basis: pinned `ThatOpen/engine_web-ifc` tag `0.72`,
`src/ts/web-ifc-api.ts` (`GetLineIDsWithType`, `GetLine`, `GetModelSchema`) and
`src/cpp/web-ifc/geometry/IfcGeometryProcessor.cpp` (placed geometry transforms).
IFC field definitions: buildingSMART IFC4.3 `IfcMapConversion` and
`IfcMapConversionScaled`. No newer web-ifc API is assumed.
