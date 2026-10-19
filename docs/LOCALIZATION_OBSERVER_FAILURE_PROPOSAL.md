# Proposed observer failure diagnosis — execution not authorized

Both jobs of authorized run 39313356060 compiled both native binaries, but all six observed cases returned incomplete candidate reports. Their verified aggregates retain `RuntimeError`, process exits and source/binary/patch hashes. It does not retain the native error category. No selected-inlier measurements or decision-equivalence result can be inferred from those artifacts. The original run remains failed/incomplete, and is not rerun.

## Concrete prepared change

The isolated observer now has a proposed, controlled stderr marker containing only a schema number, fixed phase, fixed operation kind, an allowlisted system-error domain and an integer error code. It distinguishes initialization, query work, trace serialization/bounds/write/finalization, and post-candidate private export. No error description, image, source identity, pose, path or oracle value enters this marker. The harness extracts it before truncating private stderr, validates its exact field set, and rejects duplicate or malformed markers. Unknown failure categories remain unknown.

The bounded runner also records a fixed failure stage and whether the candidate was rejected. It preserves all original exceptions, exit codes, incomplete cases and failed acceptance gates. The existing record/solve/query limits, deadline, source checks, candidate/oracle sandbox and exact output-equivalence requirement remain unchanged. There is no estimator, detector, threshold or case-selection change.

**31 local preparation, parser, mathematical and runner checks pass.** The new observer has not been compiled or executed natively. The original executed patch remains in `docs/evidence/localization-trace-proposal/observer.diff` and source `b816d75d0ce3a23408512a2f92deacb3971feb2d`; the proposed patch is separately retained as `observer-failure-codes.diff`. No original result is relabeled.

## Separate budget needed before execution

Proposed follow-up: **one managed job, at most 40 runner-minutes**, first attempt only, using the already disclosed layout **905771** and its same rough-384, finished-384 and finished-768 cases. The existing 2,100-second inner deadline includes baseline and observer builds, comparison and evaluation. No reruns, replacement cases, sweeps, protected draws, estimator changes or threshold changes are allowed. Only allowlisted aggregate summaries may be uploaded.

This phase diagnoses observer execution failure. It is not a sixth localization repair attempt and cannot authorize precision, qualification or release. A failing marker identifies a subsystem, not automatically a proven estimator defect. Any subsequent change or experiment must follow the runbook's separately declared evidence and budget requirements.

The proposed workflow remains a disabled text artifact outside `.github/workflows`. Nothing in this preparation triggers another managed job. The ongoing registered-fragment navigation integration is independent and continues under its existing declared job cap.
