# Storage and update recovery: current priority

The owner requested this order on 19 October: storage/update recovery (5), then localization (1) and whole-house navigation (2), then broader qualification (3). This work does not mark real provider or signed-update checks complete.

## Concrete access-boundary repair

The prior account lease accepted a selected iCloud folder when both saved and current account identities were absent. After obtaining a lease, it relied on notification delivery/generation changes rather than checking the current identity again. Save checked its lease after some immutable objects had already been published; restore checked only after the operation returned.

The candidate refuses a missing iCloud identity, latches an observed account mismatch until folder reselection, and rechecks identity before publication, inside file coordination, immediately before the final move, and at bounded save/restore boundaries. Local-folder use remains possible without iCloud. Partial objects are cleaned up on failure; existing local projects and originals are not overwritten. A fully published revision before an interruption may remain valid and retryable; no remote durability claim follows from local readback.

Four new native checks cover isolated account identity/defaults, injected publication-boundary errors, account loss between chunk/metadata/manifest publication, and every guarded restore boundary for both legacy and chunked snapshots. The quota/permission cases are injected errors, not actual iCloud-account or full-disk tests. No actual account sign-out or quota manipulation is performed.

All 63 command and 47 CI/release contracts pass locally. Declare **one integration job, maximum 70 minutes**, with 198 native checks, 21 independent reader phases and all 20 UI workflows required. Swift compilation and the four new native tests remain pending until the exact-source result is collected. No numeric, recovery or precision gate is relaxed.

## Real checks still required

- On a disposable project and a dedicated user-selected Files/iCloud folder: real upload/readback, delayed or partial arrival, offline local use, quota refusal, permission loss, conflict branches, and a deliberately coordinated account transition.
- A clean destination restore must verify originals, metadata and project isolation. Cached readback alone is not independent remote recovery.
- For signed-app update: retain an archive and diagnostics before updating the existing installation, update without deleting it, then compare the same project's original hashes and metadata and restore the archive separately. CI's archived old-format fixture is not proof of this operation.

These require the owner's physical installation/account and returned reports under `docs/DEVICE_ACCEPTANCE.md`. There is no connected iPhone filesystem or Files-provider control in this workspace. The existing available TestFlight snapshot remains 234.1; 246.1 is a successful simulator validation, not a delivered update. Do not claim this priority complete or enable precision/automatic renewal from simulated checks.
