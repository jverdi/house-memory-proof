# Private pose-selection observer: review preparation

**The originally authorized observer has now run and failed incompletely on all six cases.** [SHA-verified results](../localization-observer-20261019/README.md). The two-job allowance is consumed, and the active workflow is retired. The original `observer.diff` remains retained. The current preparation code additionally proposes controlled failure codes in `observer-failure-codes.diff`; that follow-up has not been compiled or executed and has no renewed budget. No workflow watches this directory.

`observer.diff` is a concrete patch for a future isolated host checkout. It observes all three production pose-solve sites: individual source views, disjoint pooled source groups and the final multi-view consensus solve. Fixed C++ storage retains the actual selected indices, local centroid and pre/post-refinement pose. Swift records the exact correspondence arrays, source/query identities, dimensions, intrinsics and returned outcome. Every query gets a start/end record, including no-map and ambiguous abstentions. The existing private map/image exporter runs after the candidate decisions; oracle files are copied by the separate harness only after the sandboxed candidate exits.

The observer does not alter existing C++ solver lines, detector/matcher behavior, RNG initialization, refinement, admission thresholds or acceptance decisions. This is checked structurally, not yet established by a native binary comparison. The shipped source files are unchanged.

The private JSONL writer is capped at 8 MiB per record, 1 GiB per case, 8,192 solves and 512 queries. An invalid value, write failure or exhausted trace bound makes the diagnostic incomplete; it cannot become a successful report or an automatic retry. No raw trace, map, pose, identity, image or oracle file belongs in the public artifact.

## Locally verified

Run from the repository root:

```sh
python3 -m unittest discover -s docs/evidence/localization-trace-proposal -p 'test_*.py'
python3 docs/evidence/localization-trace-proposal/prepare.py . /tmp/pose-observer-review.diff
```

The **31 preparation, evaluator, failure-parser and runner contract checks pass**. They cover all query outcomes, selected inliers on rejected solves, absent RANSAC selection, truncation and trailing records, denominator/order errors, invalid indices/coordinates/dimensions, duplicate JSON fields, unexpected private fields, bounded reads, unchanged source files, insertion-only C++ instrumentation, all three actual call sites and post-candidate private export. The second command writes a diff; it does not apply, build or execute it.

`trace_contract.py` validates every private record and query denominator before a report can complete. `pose_residuals.py` now evaluates actual input/selected correspondences and pre/post-refinement poses against the separately supplied oracle. It reports query pixel, optical-depth and 3D ray residuals for individual, pooled and consensus solves, including solves from accepted and abstained positive queries. Source-pixel/depth/ray metrics are limited to uniquely recoverable individual-solve source identities; pooled/consensus source metrics are not guessed. Negative query solves, absent surfaces, behind-camera points and ambiguous source pixels retain explicit denominators. The trace hash is sealed immediately after the sandboxed candidate exits and checked before evaluation. No raw arrays or identities enter the aggregate output.

`run_diagnostic.py` is the prepared serial runner, with exactly rough-384, finished-384 and finished-768 cases per disclosed seed. It compiles an unmodified baseline and an isolated observer, requires exact decision/numeric-output equivalence, and retains failed original gates separately from diagnostic completeness. It has a 2,100-second inner deadline, bounded child processes, no retries, no replacement cases and no protected layouts. Native builds, replays and evaluator work must all fit the deadline. Exceeding it records an incomplete case; it does not renew the budget.

`workflow.yml.txt` retains the original disabled review template. Its separately activated one-shot workflow executed both serial jobs and is now retired. Native compilation succeeded, but all six observed cases were incomplete before equivalence/residual scoring. The later `failure-workflow.yml.txt` is a distinct disabled, unapproved one-job proposal. Local protocol/math checks do not establish native equivalence.

The originally authorized two-job allowance is consumed. No additional execution budget is approved. Precision, physical qualification and final-release acceptance remain disabled.

The earlier preparation statements above describe the originally proposed scope. Actual execution now establishes native compilation but not decision equivalence or residual completeness. See [the unexecuted controlled-failure follow-up](../../LOCALIZATION_OBSERVER_FAILURE_PROPOSAL.md); `failure-workflow.yml.txt` remains disabled outside active workflow paths. No shipping estimator source is modified by this preparation.
