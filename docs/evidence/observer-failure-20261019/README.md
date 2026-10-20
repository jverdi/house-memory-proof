# Observer initialization failure retained

The authorized one-job diagnostic at source `9eb7231622a5e0af90751e07e56d790f98058b36`, run 39329166282, completed with failure in 413 runner-seconds, within its 40-minute cap. Its artifact hash is independently verified. The summary's `runnerSeconds: 2100` is its declared inner deadline, not elapsed runtime.

All three disclosed cases fail while creating the private trace file, before query evaluation. The fixed marker is `initialization / create / other / 0`. The Boolean Foundation file-creation result was converted into a generic application error, so it does not retain a native filesystem error or establish why creation failed. Source inspection shows the intended path under the already allowed candidate temporary directory; no permission expansion is justified by this result.

Baseline rough-384 and finished-768 runs return zero, and baseline finished-384 retains its failing gate. Every observed candidate is rejected as incomplete. No decision equivalence, residual diagnosis, accuracy improvement or precision qualification is established. The one-job allowance is consumed, and its active workflow is retired. No retry or sixth estimator repair is authorized.
