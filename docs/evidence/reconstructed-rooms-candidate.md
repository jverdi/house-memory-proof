# Registered reconstruction/navigation continuation

Runbook §12.2–12.3 / P6.2 continuation, prepared 19 October 2026.

The previous native reconstruction/navigation check covers two isolated floor fragments. This candidate adds three separately generated nine-view RGB-D captures, each passed through production surface reconstruction without generator meshes. Two fragments overlap across a registered lower-floor room boundary; the third lies on a disconnected upper floor. Known translations and explicit floor classification are supplied to isolate downstream navigation. This is not registration estimation or whole-house qualification.

The actual walking controller must traverse the lower-floor seam sixteen steps in both directions without changing source geometry. The derived room graph must contain exactly the lower-floor connection. Three movement attempts must be refused after the second fragment's floor classification is removed. An explicit upper-floor jump must land on its reconstructed support without inventing an inter-floor graph link.

The private package preserves original observations, reconstructed local triangles and supplied registration. Its SHA-256 binds the public report. A separate Python reader checks intermediate nine-point body footprints against the actual triangles transformed into their registered frames, validates source/room/stage links and denominators, and rejects missing support, altered transforms, cross-room source links, incorrect floors, incomplete traces and unsupported qualification claims. Only the synthetic movement trace and aggregate results enter public evidence; the source package stays in the ephemeral CI job.

Local results: **63 command/reader contracts and 47 CI/release contracts pass**. Native execution is pending. One ordinary native integration job is declared under the existing **70-minute** job cap, with all existing native/interface/resource/accuracy limits unchanged. Expected inventory is 194 native checks, 21 independent reader phases, 63 command contracts and the existing 20 UI workflows. This validation is independent of the separately authorized two-job localization diagnostic; it does not run a new localization estimator or protected layout.

No whole-house diversity, sustained device performance, automatic semantic classification, estimated registration, protected evaluation or physical accuracy acceptance is claimed.

## Retained 244.1 result and corrective validation

Source `5242e7c320dbfb24a39c86ec1eebac7b558143e4`, run 39313991922, compiles Debug and Release and completes all 194 native checks in 271.777 seconds. **193 pass; the new registered-fragment check fails.** Its SHA-verified report shows all 16 movement steps, all three missing-floor refusals, the separate upper-floor jump and source preservation passing, with exactly the expected room link. The failure is `graphLimited=true`. Independent readers were skipped because the native aggregate failed. [Original checkpoint](native-524/summary.json).

The graph checks its work limit before skipping already-resolved room/stage pairs. Once the only needed link is found, duplicate camera pairs can therefore falsely flag the graph as incomplete. The correction skips those redundant pairs first. A deterministic one-candidate regression requires a single connected pair with repeated observations to finish, while the existing multi-pair one-candidate case must still report incomplete work. All clearance, observed-corridor, candidate-count and time checks remain required before checking any unresolved pair.

Declare **one corrective native integration job, at most 70 minutes**, for this first repair of the room-graph completion-reporting failure class. The original failed source is retained and is not rerun unchanged. The diagnostic geometry, expected 194 checks, 21 reader phases, 63 command contracts, 20 UI workflows and all execution/accuracy limits remain unchanged. Corrective native validation is pending.
