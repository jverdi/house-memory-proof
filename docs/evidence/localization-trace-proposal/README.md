# Private pose-selection observer: review preparation

**Prepared only. No native observer build, localization replay, protected draw or sixth repair attempt has run.** This directory is documentation and review material; no workflow watches it. The [renewed diagnostic proposal](../../LOCALIZATION_DIAGNOSTIC_PROPOSAL.md) remains unapproved.

`observer.diff` is a concrete patch for a future isolated host checkout. It observes all three production pose-solve sites: individual source views, disjoint pooled source groups and the final multi-view consensus solve. Fixed C++ storage retains the actual selected indices, local centroid and pre/post-refinement pose. Swift records the exact correspondence arrays, source/query identities, dimensions, intrinsics and returned outcome. Every query gets a start/end record, including no-map and ambiguous abstentions. The existing private map/image exporter runs after the candidate decisions; oracle files are copied by the separate harness only after the sandboxed candidate exits.

The observer does not alter existing C++ solver lines, detector/matcher behavior, RNG initialization, refinement, admission thresholds or acceptance decisions. This is checked structurally, not yet established by a native binary comparison. The shipped source files are unchanged.

The private JSONL writer is capped at 8 MiB per record, 1 GiB per case, 8,192 solves and 512 queries. An invalid value, write failure or exhausted trace bound makes the diagnostic incomplete; it cannot become a successful report or an automatic retry. No raw trace, map, pose, identity, image or oracle file belongs in the public artifact.

## Locally verified

Run from the repository root:

```sh
python3 -m unittest discover -s docs/evidence/localization-trace-proposal -p test_preparation.py
python3 docs/evidence/localization-trace-proposal/prepare.py . /tmp/pose-observer-review.diff
```

The **12 preparation/protocol checks pass**. They cover all query outcomes, selected inliers on rejected solves, absent RANSAC selection, truncation and trailing records, denominator/order errors, invalid indices/coordinates/dimensions, duplicate JSON fields, unexpected private fields, bounded reads, unchanged source files, insertion-only C++ instrumentation, all three actual call sites and post-candidate private export. The second command writes a diff; it does not apply, build or execute it.

`trace_contract.py` returns only allowlisted aggregate counts. It verifies trace completeness; it does **not** establish localization accuracy. A separate oracle residual evaluator and serial two-job execution wrapper are still required before this phase is ready for dispatch. They must preserve the proposal's two disclosed layouts, six declared layout/stage/resolution cases, unchanged gates and total 80 runner-minute limit. Native compilation and decision-equivalence evidence are also pending and must fit within any explicitly approved diagnostic phase.

No budget has been increased. Precision, physical qualification and final-release acceptance remain disabled.
