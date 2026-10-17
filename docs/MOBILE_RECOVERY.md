# Mobile use and recovery

The app is local. Deleting it can remove the only copy of construction evidence. Keep complete archives in Files or iCloud Drive and verify a restore before depending on a backup.

- **New project:** House → create a house. Add rooms with design dimensions; these are not measured dimensions.
- **Construction stages:** Tools → Construction stages sets explicit rough/finished/other categories and capture dates. Names do not determine category once it is explicitly set.
- **Capture:** select room/stage, keep the phone cool, light every cavity and move sideways with overlap. Stop before switching spaces. Inspect original photographs and coverage afterward.
- **Explore:** use the joystick to move and drag the scene to look. Layers controls systems, stages and ceilings. Jump changes room/floor without pretending an unseen stair connection exists. Free fly bypasses the constrained walk path.
- **Existing photos:** Evidence → Import existing photographs. These retain originals and notes without invented geometry.
- **Refinement:** Tools → Reconstruct saved depth → refine local camera poses. Joint camera/point refinement adds independent image checks; if it refuses the data, existing estimates stay in place. Rebuild surfaces and visual references after changing camera estimates. Camera refinement is bounded to 120 session keyframes, with at most twelve image observations per retained point.
- **Small photo-visible features:** Evidence → Locate a point from three photos. Select three distinct translated views and the same physical point. The third photo checks the first two; the result retains all source selections and remains approximate.
- **Trace and label:** Explore → Trace route; select an object to review its system, endpoint and associated photos. Tools → Service endpoint connections records only explicit links.
- **Wall/ceiling reveal:** Explore → Wall, select three corners on one surface, define the cavity direction/depth and finish offset, then save. Capture → reveal requires a current boundary. Wrong-side, stale, conflicting or lost alignment hides the overlay. These are approximate display volumes, not surveyed wall assemblies.
- **Coverage:** Tools → Capture coverage includes a wall/ceiling heat map. Gray is unknown, red is blocked, orange needs better views, and mint has three sampled views. This evaluates the entered back plane; it cannot certify that every wire or pipe was observed.
- **Drawing overlays:** PDF/image sources retain their originals. Calibrate the selected page, then use three fitting controls and a separate check in house coordinates. Rotated PDF pages are normalized locally for the overlay texture. Design remains separate from observed construction.
- **Spreadsheet handoff:** Tools → Export semantic CSV. This includes all project records, including hidden features and separate capture frames. Read the coordinate-frame column before combining points; registration remains explicit. Use metadata JSON for detailed provenance and the complete archive for originals.
- **Backup:** Tools → Export complete house archive → Save to Files. Original images, raw depth, references, annotations and geometry remain in the archive. The archive is a ZIP64 file with an `.hxray` extension; unzip a copy for its independent HTML photo index, self-contained offline WebGL 3D viewer and JSON. The offline viewer supports touch controls and layer changes, but has no collision or measurement qualification.
- **Restore:** Tools → Import archive, IFC or point cloud. A house archive creates a separate restored project. It does not replace your current project. Restore checks manifest hashes before publishing the project.
- **Optional folder snapshots:** Tools → Automatic folder snapshots → Choose snapshot folder. The iOS folder permission must be granted on the phone. Incremental revisions share immutable assets; List saved revisions restores one into a separate project. No assets are pruned. Daily-on-open snapshots run only while the app is active; a local copy is not proof that a cloud provider has finished uploading.
- **Bad edit:** Tools → Restore previous local revision. Twenty prior metadata/geometry revisions are retained; original content-addressed files are never automatically pruned.
- **Interrupted capture:** finalized photos remain saved; mesh state checkpoints periodically. Start a new session after interruption rather than assuming its frame stayed valid.
- **Interrupted triangle reconstruction:** repeat reconstruction with unchanged capture inputs. Completed ten-frame checkpoints are reused; corrupt or mismatched checkpoints restart from originals. Point-cloud fusion still restarts.
- **Originals without launching the app:** new installations keep their store under Files → On My iPhone → House Xray → HouseXray. Copy the whole folder for emergency recovery; do not edit its live database or hashed assets. Deleting the app also deletes this folder. An older beta store is preserved in its original private location and still needs an exported archive. Files visibility does not create an independent backup.
- **Interrupted movie:** export again using the same project revision and layers. Completed five-second chunks are reused. Keep the app foregrounded and cool.
- **Bad alignment:** treat the overlay as approximate, return to source photos, and invalidate any moved reference. A familiar-looking room is not evidence of precision.
- **Development issue:** tell the agent what screen/action failed and the build/source shown in Tools. Use Export diagnostics for the local self-test report. No remote agent can silently inspect your phone or its local data.

The installed proof build 2.1 does not contain these application screens; they describe the implementation currently under qualification.

A weekly renewal check is implemented but disabled until acceptance. Once enabled, it uses Apple’s reported expiration date and rebuilds only the pinned `personal-beta` tag when fewer than 21 days remain. Signing/account failures still require agent repair; this is not a guarantee that Apple or GitHub remains available.

