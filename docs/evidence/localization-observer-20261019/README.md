# Retained observer execution failure

Authorized run [39313356060](https://github.com/jverdi/house-memory-proof/actions/runs/39313356060), source `b816d75d0ce3a23408512a2f92deacb3971feb2d`, executed exactly two serial jobs. Their combined elapsed runner time was **725 seconds (12 minutes 5 seconds)**, below the 80-minute total ceiling. Both returned failure. Both aggregate ZIP SHA-256 values were independently verified; the original summaries are retained unchanged.

Both unmodified baseline and instrumented observer compiled. All six declared observed cases returned exit 1 and incomplete reports before decision equivalence and residual evaluation. The retained summaries identify only `RuntimeError`; they do not retain the underlying native error. Baseline wrapper exits were 0 for rough-384 and finished-768, and 1 for finished-384, on each layout. Those exit codes alone do not provide the denominators or measurements needed to claim qualification. The diagnostic did not establish an estimator defect.

No case was retried, replaced or removed; no protected layout was drawn, and no detector/estimator/threshold changed. The two-job allowance is consumed despite unused wall-time headroom. The active one-shot workflow is retired. Precision and final acceptance remain disabled.

A separate unexecuted proposal adds fixed phase/operation/error codes to the private observer's failure path. Its public output allowlist excludes messages, paths, image identities, poses and oracle values. See [the concrete one-job / 40-minute follow-up proposal](../../LOCALIZATION_OBSERVER_FAILURE_PROPOSAL.md). This prepared follow-up has 31 passing local checks but no renewed execution authorization.
