# Streamed-detail stability candidate

Prepared after the saved-viewpoint and bounded coverage-loop continuations. Native validation is pending. Combined expected totals are 182 native checks and all 19 interface workflows, with existing reader counts and execution bounds unchanged.

Runbook §12.4 requires detail-level hysteresis. The previous planner changed its detail request on either side of a single 10 m boundary. Walking back and forth there could repeatedly remove and rebuild the same rendered geometry.

The planner now remembers its last admitted detail state: first admission retains the 10 m rule, detailed tiles remain detailed until 11 m, and coarse tiles regain detail below 9 m. The live scene streamer passes its preceding bounded plan into the next decision. Source geometry, distance ordering, resident/vertex/texture caps and collision originals are unchanged. A tile that leaves residency does not retain an unbounded history.

A native regression drives the actual scene stream through five distances, checks detail transitions and unchanged-node identity during reversals, verifies source-surface/source-point representation, and preserves the original feature. The existing 100-space/two-stage streamed-render diagnostic remains in the full integration suite.

This closes a prepared implementation gap only after native execution passes. It does not establish reconstructed whole-house topology, portal culling, directional prefetch, room-local rendering origins, sustained owner-device frame rate or thermal behavior. Those requirements remain open.
