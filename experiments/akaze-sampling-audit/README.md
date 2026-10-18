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
