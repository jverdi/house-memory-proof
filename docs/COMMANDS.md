# Repository commands

Run from a checkout with `python3 tooling/hm`. Commands do not install a toolchain,
provision an Apple account, start a network server or enable field precision.

| Command | Current implementation |
|---|---|
| `doctor` | Reports local compiler/runtime/credential presence. Account and network access remain unverified until a live health read. |
| `test --suite portable` | Builds and runs the production portable C++ fusion/surface diagnostics, including 50 analytic fusion cases. This remains the default for existing CI. |
| `test --suite simulation` | Runs the renderer, sensor, topology, pose-metric, protected-run inventory and publication contracts. |
| `test --suite release` | Runs signing, upload-idempotency, readiness, renewal and release-health tests without shipping. |
| `test --suite commands` | Exercises package corruption/semantic refusal, CLI failure handling and scene staging. |
| `simulate --scenario analytic-depth --seed 42 --output DIR` | Generates analytic noisy XYZ inputs and separate evaluator truth. |
| `simulate --scenario connected-house --seed 85838 --stage rough --profile nominal --width 384 --output DIR` | Calls the existing connected-house generator. Its observations are distinct from the evaluator-only topology/pose/query records. This is development generation; it never draws protected qualification seeds. |
| `reconstruct --bundle observations.xyz --output candidate.xyz` | Runs the production portable point-fusion executable. The XYZ interface does not yet replace the native complete image/depth reconstruction pipeline. |
| `evaluate --candidate candidate.xyz --truth truth.json` | Scores analytic point fusion, with its limited scope retained. |
| `evaluate --candidate build/vision-replay --fixture DIR --output report.json` | Runs the production house replay through the existing macOS OS sandbox, stripping evaluator labels and denying oracle access. The candidate must already be compiled. |
| `tour --scene INPUT --preset before-after --simulator UDID --output DIR` | Runs the installed Debug app's production TourDirector and SceneKit storyboard renderer. INPUT is an exported `.hxray` archive, `house.json` or a directory containing `house.json` and `assets/`. |
| `export-check --package FILE.hxray --output report.json` | Independently streams every payload hash and checks manifest completeness, asset identities, schema, camera/session relationships, geometry and service endpoints, then round-trips metadata through a separate JSON implementation. It never extracts the archive. |
| `release-health --live --output report.json` | Reads Apple build/expiry and certificate inventory plus exact-main-source CI state. Requires existing Apple/GitHub credentials. No Apple/GitHub records are created. Missing access and stale evidence cannot become a passing report. |
| `release-health --input snapshot.json` | Evaluates a previously captured health snapshot, enforcing a 24-hour freshness limit. This is useful for offline inspection/testing; it does not refresh account state. |
| `release --commit FULL_SHA --ref main --dispatch` | Verifies the ref resolves to the requested source, then requests the existing validation workflow with shipping disabled. The response is a dispatch receipt, not a build or Apple-delivery claim. |
| `release --commit FULL_SHA --ref personal-beta --ship --dispatch` | Requires an accepted exact-source ledger, no remaining software/external gates and the matching pinned release tag before requesting delivery. The ordinary acceptance path cannot ship another intermediate development build. |

`release` without `--dispatch` verifies the reference and describes the request.
Actual Apple readiness is checked by the existing release workflow; a successful
upload/dispatch is never treated as completed delivery. Credentials are read from
existing environment configuration; neither token values nor private keys enter
reports. `release-health` cannot infer current agreement status, actual signing,
owner installation or physical qualification from API access.

## Tour execution and input isolation

The caller selects an already booted simulator with an already installed Debug
build (default bundle `com.example.HouseMemoryProof`). No simulator is created or
booted, and no application is installed by this command. The command ends the
existing simulator app process, stages verified scene inputs in its own random
request directory, launches `--developer-command`, and waits up to 180 seconds.
It ends that worker process before cleaning up, including on timeout.
Its input is not imported into the user's project list or capture store. The
request directory is removed afterward. Originals outside that directory are
never modified. Use a dedicated development simulator.

The output contains the complete deterministic `tour.json`, an HTML storyboard,
up to eight 640×360 native previews and a result identifying the input hash,
app source, source revision, exclusions and frame count. Every preview uses its
shot's actual layer selection and interval midpoint. Explicit cuts and omitted
regions remain in the production plan. The command does not claim to render an
MP4 or qualify sustained phone performance; the existing movie workflow handles
those separate operations.

The launch adapter exists only in Debug simulator builds. It has no socket or
unauthenticated external endpoint. Native regression covers the production plan,
preview dimensions and changed-input rejection; CI additionally launches the
adapter through `hm tour`. Only aggregate CLI validation is published by that
test; staged inputs, full tour paths and storyboard files stay temporary.

## Remaining interface scope

The generic archive reader supplements, rather than replaces, Khronos/OpenUSD,
mesh, CSV and actual restore readers. Their CI fixtures still exercise native
exports. General multi-format package checking, a complete native reconstruction
CLI adapter and network/account checks in `doctor` remain separate work. The
presence of command names is not a claim that every runbook interface or product
acceptance gate has passed.
