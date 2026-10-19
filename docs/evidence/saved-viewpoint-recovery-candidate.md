# Saved-viewpoint recovery candidate

Prepared against 226.1 source `ad8e0c5c8baf214967ccacea80a6195d7df66e8c`; native validation is pending.

Runbook §12.3 requires a corrupt camera bookmark to return to a safe view. The archive reader rejects nonfinite bookmark values, but it permits finite Double coordinates larger than SceneKit's Float range. Returning to such a bookmark in Free fly previously bypassed walking validation and could put infinity into the camera. A single oversized marker also caused the entire room map to refuse preparation.

The controller now checks the supported coordinate range, finite orientation, room scope and coordinate-frame identity before conversion. Rejected bookmarks clear movement and use the existing room reset/floor-and-route check; unavailable walking remains explicit Free fly. Valid yaw is reduced before Float conversion, pitch stays within the existing look bounds, and returning to a bookmark exits Orbit so the selected camera is actually displayed. No saved record is rewritten.

The map omits unusable markers, counts and explains them, and preserves valid room/viewpoint content. Unsupported room or photo-position bounds still refuse the map. The existing 100-marker display cap remains.

Two native regression cases exercise extreme finite coordinates, nonfinite runtime inputs, unknown room/frame, stopped movement, Orbit exit, bounded angles, unsupported-stage fallback, valid marker preservation and record immutability. The finite oversized bookmark fixture also passes the existing archive-domain validator, reproducing the real admission boundary. Expected total: 180 native checks and all 19 interface workflows, with existing reader counts and execution bounds unchanged. This is a prepared repair, not physical or whole-house qualification.
