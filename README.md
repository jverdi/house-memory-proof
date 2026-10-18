# House Xray

Personal, local-first native iPhone construction record. SwiftUI + ARKit + SceneKit/Metal, SQLite, a portable C++ depth-fusion core, and an offline bundled IFC parser. No application server, account system, billing, or runtime reconstruction service.

**The source now contains a substantial experimental application. It does not yet satisfy the production/precision gates in the [architecture runbook](docs/architecture-runbook.md).** The requested current-state snapshot **216.1** is available in internal TestFlight, with Apple processing and owner access verified. Later implementation commits remain validation-only.

## Implemented paths

- Local house/room/stage records, immutable hashed originals, transactional revisions and recovery copies.
- ARKit photographs, camera calibration/poses, raw LiDAR depth/confidence, mesh checkpoints, saved maps and image-reference associations.
- Existing-photo import as explicitly unposed documentary evidence.
- First-person touch/controller navigation, free flight, room jumps, bookmarks, object picking, layer/ceiling switches and ghost views.
- Approximate point measurements, route tracing, trade/endpoint labels, explicit service links, source/session photographs and on-device OCR.
- PDF/image scale calibration, independent source preservation, offline bounded IFC and ASCII PLY import.
- Bounded local depth fusion, visibility-tested photo textures, photo-support coverage checks and an in-app simulated camera dataset.
- Automatic offscreen MP4 tours with five-second checkpoints; GLB, textured USDZ, PLY, OBJ, metadata JSON and [semantic CSV](docs/SEMANTIC_CSV.md) output.
- Streaming ZIP64 complete archives, independent offline photo index and restore into a fresh project identity.

These paths have different validation maturity. See [implementation and acceptance status](docs/IMPLEMENTATION.md), not just the feature list, before relying on them.

## Development and verification

Native source targets iOS 26+. Runtime hardware checks determine whether ARKit, scene depth and mesh capture are available. Imports, browsing and exports do not require LiDAR.

`python3 tooling/hm test` builds the portable C++ core and runs 50 analytic noisy-depth cases. Those cases are **not** 50 distinct houses or field/localization qualification.

The [command reference](docs/COMMANDS.md) covers production native tour planning,
independent archive inspection, named test suites and read-only release health,
including their runtime requirements and remaining scope.

The managed macOS workflow compiles the app, launches the iPhone simulator, runs native self-tests and XCUITest navigation, and validates output with Khronos glTF Validator, OpenUSD, trimesh and Python's independent ZIP/CSV readers. CI artifacts distinguish simulator results from physical-device results. Exact evidence and limitations are recorded in the implementation ledger.

`python3 tooling/project.py` and `python3 tooling/ui-project.py` maintain the checked-in Xcode source/test references. `tooling/prepare-ifc.sh` downloads pinned web-ifc 0.0.72 during builds; the resulting parser runs entirely offline inside the app. See [third-party notices](docs/THIRD_PARTY.md).

## Delivery

The repository and hosted macOS runner delivered signed **House Xray build 216.1**, source `f2a3d40cac`, to the owner's **Personal iPhone** group on October 18, 2026. Apple reports **VALID / IN_BETA_TESTING**, and owner access is verified. Open TestFlight → House Xray → Update. Physical installation remains unverified. [Delivery evidence](docs/evidence/testflight-216-1-summary.json) records the exact source and independently verified artifact hashes; it is separate from full application acceptance. The owner previously confirmed installing delivery proof 2.1.

- App ID: `6823862609`
- Bundle: `com.jverdi.housememoryproof`
- Team: `4RLZ6F3UA4`
- Internal group: `Personal iPhone`, owner only
- Secrets: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY_P8`

Intermediate uploads are disabled in `.github/workflows/ios.yml`. A successful simulator build alone does not authorize or establish a qualified release. Readiness polling is gated to release commits. No public App Store submission or renewal schedule is configured.

## Keeping evidence

New installations keep originals in the app's Files-visible Documents/HouseXray store; legacy installations retain their original Application Support store. Originals are never automatically evicted. Export a complete archive through Tools and save it using Files, including to iCloud Drive if desired. Optional coordinated folder snapshots can write to a user-selected Files/iCloud Drive folder, including daily while opening a house. iOS requires initial folder permission. Incremental snapshots share immutable originals, with restore-by-revision and no automatic merging. Real-provider lifecycle and performance qualification remain incomplete. Do not delete the app as a recovery step without an independently verified archive.

