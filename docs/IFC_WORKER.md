# Bounded local IFC worker

Native source 67cc61c3d6 timed out during the existing IFC2x3 cancellation/reuse scenario. It completed 128 native checks: 127 passed and one failed; the first IFC failure prevented three later checks in that block. The new photograph annotation and provenance checks passed. This failure is retained, not counted as a full integration pass.

The converter uses a nonpersistent WKWebView outside the visible view hierarchy. Apple documents inactiveSchedulingPolicy as the policy for views not in a window; the default suspend policy can stop asynchronous work after page loading. WebKit's explanation of SDK-linked behavior is consistent with this worker's intermittent timeout, but the timed-out run did not record an internal phase, so suspension is a supported hypothesis rather than a proven trace.

The next candidate sets the public policy to none for this single bounded local operation, retains the 60-second deadline, ignores obsolete view requests, and handles failures after provisional navigation. It records only allowlisted lifecycle phase names (created, initializing, source, parsing, geometry, complete/cancelled/failed). Failure output identifies the last phase without including IFC content or resource paths. Completion and cancellation destroy the worker; this creates no background entitlement or promise of execution while the app is suspended. Existing cancellation/reuse, units, placements and malformed-geometry tests remain mandatory.

Primary references:
- https://developer.apple.com/documentation/webkit/wkpreferences/inactiveschedulingpolicy-swift.property
- https://developer.apple.com/documentation/webkit/wkpreferences/inactiveschedulingpolicy-swift.enum/none
- https://bugs.webkit.org/show_bug.cgi?id=283794 (WebKit maintainer explanation, comments 4–5)

Exact-source native verification is pending. The original timeout is not waived and the IFC time/geometry admission limits are unchanged.
