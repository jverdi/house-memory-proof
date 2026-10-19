# Saved viewpoint scope and displayed pose

Status: prepared; native compilation and execution pending.

Save viewpoint now records the displayed SceneKit camera, including the orbit camera, in canonical coordinates. In registered geometry it finds the containing room and level instead of assigning the first project room. It refuses an overview outside room bounds or outside the selected room with an actionable message. Unaligned visits retain their segment and room without testing local positions against unrelated design coordinates. No stored viewpoint or source geometry is rewritten.

The native regression covers a second-floor room in all-spaces scope, distinct orbit position and angles, restoring that view, outside-room refusal, selected-room refusal and an unaligned visit. It raises the continuation to 188 native cases; all 19 interface workflows remain required. This is separate from the requested 231.1 TestFlight snapshot and does not establish whole-house or actual-device qualification.

Views with roll or pitch beyond the walking camera’s existing limits are explicitly refused instead of saving a pose that restoration would silently change. Both refusal cases are included in the native regression.
