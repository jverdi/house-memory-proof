# Proposed next localization diagnostic

**Status: authorized phase executed; both jobs failed with incomplete diagnostic outputs. The two-job allowance is consumed.** [Retained results](evidence/localization-observer-20261019/README.md).

Runbook §22.3 limits a failure class to five repair iterations and a declared compute cap. The finished 384-pixel localization accuracy class has exhausted that budget. The renewed authorization covers only the proposed diagnostic phase below; it does not authorize a sixth estimator repair attempt.

## Retained evidence

The [five-attempt record](../experiments/akaze-sampling-audit/README.md) retains the reproducer, attempted repairs and fallback. The fifth candidate improved one finished-384 layout to 6.822 mm p95, left the other at 14.182 mm, and accepted none of the forty finished-768 queries. It was not adopted. The original failed accuracy, availability and critical-rejection gates are unchanged.

The earlier [depth audit](evidence/localization-depth-audit-summary.json) measured raw descriptor correspondences before the production PnP inlier selection. Those measurements do not identify which correspondence errors survive into the returned pose. Feature scale-space behavior, coordinate consistency and depth/pixel calibration remain hypotheses, not proven bugs.

## Concrete scope for a renewed diagnostic budget

Authorize one diagnostic phase with **at most two managed jobs, at most 40 minutes each, and only one active at a time**: a maximum of 80 runner-minutes. Use only the two already disclosed development layouts, `905771` and `683431`. Preserve their declared rough-384, finished-384 and finished-768 cases and every existing acceptance threshold. Do not draw protected layouts.

Before dispatch, prepare and review an isolated host-only instrumentation patch. It must preserve the detector, matching, PnP, refinement and admission behavior, and record the source and instrumented-binary hashes. Check its trace parser, bounds and output allowlist locally. Do not modify an automatically triggered experiment path until execution of this phase is authorized.

The instrumented candidate should retain, privately in the ephemeral job:

- The actual correspondence inputs, selected inlier indices and returned pose for each production pose solve, linked to the opaque candidate query identity.
- Image dimensions, coordinate transformations and the source/map identities needed to distinguish raw and pooled solves.
- Rejection reasons and both accepted and abstained query outcomes, without selecting only favorable results.

The candidate remains isolated from oracle files and query labels. Seal its outputs before the separate evaluator reads truth. The evaluator then reports aggregate source/query pixel residuals, depth/3D residuals and pose errors before and after the production selection, with explicit denominators. Raw images, maps, poses, correspondence traces and oracle data are not uploaded or committed.

## Decision after the phase

Publish hash-verified aggregate results and an explanation of whether the evidence identifies a specific implementation defect. A failed or incomplete job remains failed; there is no automatic rerun, parameter sweep or replacement case. Stop when the declared budget is consumed.

This proposal authorizes **diagnosis only** if approved. It does not authorize adopting a detector variant, changing thresholds, narrowing the required operating conditions, enabling precision, or shipping a final release. Any subsequent repair must have an evidence-based change and a separately declared validation budget.

Until the accuracy gates pass, retain documentary/approximate operation with precision disabled. This is a fallback, not completion of the original specification.

## Prepared review package

The [observer, residual evaluator and bounded runner](evidence/localization-trace-proposal/README.md) passed 27 local contract/math checks before activation. The original disabled template remains retained as review material. The separately activated one-shot workflow executed both jobs and is now retired. The original 80-runner-minute cap included baseline/observer compilation and comparison. Subsequent controlled-failure preparation expands the local suite to 31 checks but remains unexecuted.

## Execution outcome

Run 39313356060 completed both serial jobs in 725 combined runner-seconds. All six observed cases were incomplete before equivalence/residual evaluation; their SHA-verified summaries are retained. Both binaries compiled, but the coarse error metadata does not identify the native failure. The active one-shot workflow is retired, without rerun. [A separate unexecuted failure-diagnosis proposal](LOCALIZATION_OBSERVER_FAILURE_PROPOSAL.md) retains a concrete one-job / 40-minute budget request; it does not renew the consumed allowance.
