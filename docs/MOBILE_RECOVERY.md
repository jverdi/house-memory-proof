# Mobile use and recovery

The app is local. Deleting it can remove the only copy of construction evidence. Keep complete archives in Files or iCloud Drive and verify a restore before depending on a backup.

- **New project:** House → create a house. Add rooms with design dimensions; these are not measured dimensions.
- **Capture:** select room/stage, keep the phone cool, light every cavity and move sideways with overlap. Stop before switching spaces. Inspect original photographs and coverage afterward.
- **Explore:** use the joystick to move and drag the scene to look. Layers controls systems, stages and ceilings. Jump changes room/floor without pretending an unseen stair connection exists. Free fly bypasses the constrained walk path.
- **Existing photos:** Evidence → Import existing photographs. These retain originals and notes without invented geometry.
- **Trace and label:** Explore → Trace route; select an object to review its system, endpoint and associated photos. Tools → Service endpoint connections records only explicit links.
- **Backup:** Tools → Export complete house archive → Save to Files. Original images, raw depth, references, annotations and geometry remain in the archive. The archive is a ZIP64 file with an `.hxray` extension; unzip a copy for its independent HTML photo index and JSON.
- **Restore:** Tools → Import archive, IFC or point cloud. A house archive creates a separate restored project. It does not replace your current project. Restore checks manifest hashes before publishing the project.
- **Optional folder snapshots:** Tools → Automatic folder snapshots → Choose snapshot folder. The iOS folder permission must be granted on the phone. Daily-on-open snapshots run only while the app is active; a local copy is not proof that a cloud provider has finished uploading.
- **Bad edit:** Tools → Restore previous local revision. Twenty prior metadata/geometry revisions are retained; original content-addressed files are never automatically pruned.
- **Interrupted capture:** finalized photos remain saved; mesh state checkpoints periodically. Start a new session after interruption rather than assuming its frame stayed valid.
- **Interrupted movie:** export again using the same project revision and layers. Completed five-second chunks are reused. Keep the app foregrounded and cool.
- **Bad alignment:** treat the overlay as approximate, return to source photos, and invalidate any moved reference. A familiar-looking room is not evidence of precision.
- **Development issue:** tell the agent what screen/action failed and the build/source shown in Tools. Use Export diagnostics for the local self-test report. No remote agent can silently inspect your phone or its local data.

The installed proof build 2.1 does not contain these application screens; they describe the implementation currently under qualification.
