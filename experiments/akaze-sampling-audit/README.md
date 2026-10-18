# Fixed analysis-sampling experiment

The original finished 384-pixel localization cases still fail the 10 mm p95
gate. Separate higher-resolution captures improve the result; the bounded
native-resolution corner refinement did not. This experiment asks whether
AKAZE's scale-space sampling contributes error that a fixed analysis resize can
reduce. Interpolation adds no scene evidence and cannot qualify a physical
sensor or replace the retained 384-pixel operating condition.

This is the fifth predeclared repair iteration for this failure class, following
pooled-query, geometric-median fusion, strict-PnP and native-resolution AKAZE
coordinate experiments. It is one candidate, not a parameter sweep. Two fixed
development layouts each retain rough-384, finished-384 and finished-768 cases.
All availability, accuracy, source-pose and critical-rejection gates remain.
The cap is two 40-minute managed jobs, one active at a time. Missing results fail
completion; no retries or tuning are implied by this experiment.

The patch runs only in an isolated CI checkout before host compilation. Original
image bytes remain untouched. Analysis scales by 2x, capped at the existing 1280
pixel maximum, with cubic interpolation only when enlarging; the existing
integer pixel-centre adapter returns camera coordinates. All other detector,
descriptor and geometric logic stays unchanged. Reports retain the exact source,
patch and compiled binary digest. Raw captures, poses, maps, query records and
oracle remain ephemeral; only allowlisted aggregate outcomes are published.

Adoption requires every declared case to pass, then a separate shipping/native
and broader regression run. A failure leaves the shipping detector unchanged.
On exhaustion, retain the reproducer and all attempts; keep approximate/
documentary operation and precision disabled, and continue independent work.
This fallback does not pass the release localization gate or narrow the spec.

## Retained outcome

Run 39100358085 at source `82f4d081d17c8aadb5a49eba2dcc3d0a1f6cac36`
completed both declared layouts. Both aggregate artifacts were independently
SHA-256 verified; exact results are in
`docs/evidence/akaze-sampling-82f4-summary.json`.

| Layout | Rough 384 | Finished 384 | Finished 768 |
|---|---|---|---|
| 905771 | 12/12, 2.265 mm p95 | 20/20, 6.822 mm p95 | 0/20 accepted |
| 683431 | 12/12, 5.860 mm p95 | 20/20, 14.182 mm p95 | 0/20 accepted |

All 96 critical queries abstained. That does not compensate for the accuracy
failure or loss of 768-pixel availability. The candidate is **not adopted** and
this five-iteration repair budget is exhausted. Pooled-query, geometric-median,
strict-PnP and native-coordinate experiments remain retained as earlier failures;
none of their thresholds or original failures is overwritten by this result.

The result supports further investigation of feature scale-space/descriptor
stability and map/query feature-coordinate consistency, but does not identify a
proven cause or authorize another parameter sweep. Source-camera error stayed
below 5 mm in these six cases; that alone does not establish point or live-pose
accuracy. Pixel-accurate feature/depth calibration and independent photometric
checks are remaining hypotheses, not implemented repairs. The current fallback
is approximate/documentary use with precision disabled and the localization
release gate still failed. Independent implementation work continues.
