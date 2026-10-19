# Restart checkpoint — 19 October 2026

Work resumed in a new thread after the previous conversation stalled. The public repository was cloned at main `8e8edb6`; the requested release is based on `543bb56`. Earlier scratch checkouts are older and have not been substituted for either published source.

Both previously pending runs completed with failures. Release 231.1 passes native checks but fails the movement-settings switch workflow. Main 233.1 passes 187/188 native checks and 18/19 interface workflows; tiny source-triangle picking and the turning-speed slider remain failing. Apple upload was skipped in both runs. TestFlight availability remains last verified at 216.1.

The 233.1 full artifact was downloaded and its SHA-256 matched GitHub. Its complete case-level UI summary, native report, and provenance are retained in `docs/evidence/restart-20261019/`. The comfort failure recording and accessibility description were inspected: the slider stayed at 90 °/s after the coordinate gesture.

The release repair keeps the native slider accessibility value and places the current physical units in its accessibility label. XCTest uses the standard normalized slider adjustment and still requires the exact endpoint in those physical units. Switch interaction targets the trailing control when the accessibility row has no child switch. All 19 workflows and their state/persistence/reset assertions remain. This candidate still requires native/UI validation; a prepared fix is not a passing result.

Next: validate and deliver the owner-requested snapshot; repair and validate main's tiny-triangle picking separately; continue the remaining runbook. The exhausted localization budget, actual-iPhone checks, real Files/iCloud tests and independent field accuracy remain open. No new localization experiment or acceptance-threshold change is part of this restart.
