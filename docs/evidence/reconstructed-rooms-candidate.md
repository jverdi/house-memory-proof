# Registered reconstruction/navigation continuation

Runbook §12.2–12.3 / P6.2 continuation, prepared 19 October 2026.

The previous native reconstruction/navigation check covers two isolated floor fragments. This candidate adds three separately generated nine-view RGB-D captures, each passed through production surface reconstruction without generator meshes. Two fragments overlap across a registered lower-floor room boundary; the third lies on a disconnected upper floor. Known translations and explicit floor classification are supplied to isolate downstream navigation. This is not registration estimation or whole-house qualification.

The actual walking controller must traverse the lower-floor seam sixteen steps in both directions without changing source geometry. The derived room graph must contain exactly the lower-floor connection. Three movement attempts must be refused after the second fragment's floor classification is removed. An explicit upper-floor jump must land on its reconstructed support without inventing an inter-floor graph link.

The private package preserves original observations, reconstructed local triangles and supplied registration. Its SHA-256 binds the public report. A separate Python reader checks intermediate nine-point body footprints against the actual triangles transformed into their registered frames, validates source/room/stage links and denominators, and rejects missing support, altered transforms, cross-room source links, incorrect floors, incomplete traces and unsupported qualification claims. Only the synthetic movement trace and aggregate results enter public evidence; the source package stays in the ephemeral CI job.

Local results: **63 command/reader contracts and 47 CI/release contracts pass**. Native execution is pending. One ordinary native integration job is declared under the existing **70-minute** job cap, with all existing native/interface/resource/accuracy limits unchanged. Expected inventory is 194 native checks, 21 independent reader phases, 63 command contracts and the existing 20 UI workflows. This validation is independent of the separately authorized two-job localization diagnostic; it does not run a new localization estimator or protected layout.

No whole-house diversity, sustained device performance, automatic semantic classification, estimated registration, protected evaluation or physical accuracy acceptance is claimed.
