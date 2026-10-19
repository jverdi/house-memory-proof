# Local render coordinates with canonical source positions

Status: prepared, native compilation and runtime acceptance pending.

Scene geometry now retains a Double-precision source anchor and stores Float vertices relative to that anchor. The interactive camera retains a nearby render origin; a jump or movement more than 256 metres from that origin rebases resident nodes and selection markers in one zero-duration SceneKit transaction. Newly streamed tiles use the current render origin. Canonical source records, navigation and collision queries, measurements, map positions, boundary viewpoints, bookmarks and exports retain their original coordinate frame.

Room jumps leave orbit mode before moving to the requested view. The source anchor and stable feature identity survive display reduction and tile replacement. This is a renderer change; it does not improve captured measurement accuracy or enable precision use.

The new native regression uses two floor-supported rooms around positive and negative 50-kilometre coordinates within the existing source limits. It checks one-millimetre vertex separation in the actual SceneKit buffer, ray-hit identity and canonical hit position, walking, precise bookmark restoration, a distant orbit-to-room jump, selection-marker restoration, newly streamed tile placement and unchanged source records. The complete next candidate, including directional prefetch, expects 187 native checks and all 19 interface workflows under the unchanged limits.

Full reconstructed-house topology, verified portals, complete room/floor prioritization and sustained iPhone rendering remain open. TestFlight 228.1 is pinned to its earlier source and excludes this follow-up.

232.1 compiled in Debug and Release and passed 186/187 native cases, failing this local-render regression. Its [failed checkpoint](native-757-failed-summary.json) is retained. The next candidate explicitly uses two-sided picking to match two-sided source materials, tests both ray directions at the same two-micrometre coordinate tolerance, and emits per-stage failure messages. Apple documents back-face culling as enabled by default: https://developer.apple.com/documentation/scenekit/scnhittestoption/backfaceculling . This is a repair hypothesis pending native rerun, not an accepted rendering result.
