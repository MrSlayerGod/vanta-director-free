# Director Free 0.3.0 validation

## Automated checks

Run `npm run format:check`, `npm run check`, `npm test`, `npm run test:ui` and `npm run package` from the development checkout. The installation package does not require Node.js.

The tests exercise the scene schema, malformed payloads, recovery isolation and ACL, stale draft deletion, restoring a new project, action retiming/ripple/reordering, gait-speed limits, recorded-take protection, deterministic camera drift, relative preset placement, subject remapping, save acknowledgement races and undo/redo. Browser checks cover drag offset, duration resize, Escape cancellation, pointer zoom, modal focus, template requests, viewer restrictions, FR/EN text and 1920×1080 / 1280×720 layouts.

Lua tests mock GTA natives. Browser tests mock NUI/server responses. They cannot establish native animation quality, collision clearance, game-frame smoothness or multiplayer timing.

## Required in-game acceptance

Use a copy of a real 0.2.0 project and keep the complete resource backup.

1. Open/close with F6 and Escape; verify camera, mouse, HUD and player controls recover. Repeat after restarting the resource.
2. Move and resize a pedestrian route, vehicle move, animation and camera shot. Confirm the cursor does not jump. Test Snap, Alt bypass, Ctrl-wheel zoom, Fit and Escape during a drag. Scroll the timeline vertically on a 720p display.
3. Edit action timings, enable ripple, reorder two steps and join them. Undo/redo. Invalid durations and seat conflicts must leave the previous scene intact. Test vehicle entry, stopping, exit and subsequent movement.
4. Save a camera preset and an actor's action sequence. Open another project, apply them to a compatible subject and map every referenced vehicle/ped. Check terrain, framing, animation transitions, save/reconnect and undo/redo. Check that a recorded take uses export/trim rather than an unsupported preset resize.
5. Aim at a flat, clear location; create and preview each starter scene. Confirm it is a new project and previous saved projects remain available.
6. Preview a shot with Steady/Subtle breathing/Gentle handheld, seek to the same time repeatedly, and duplicate it. Confirm motion is subtle, no paused drift accumulates, and the duplicate retains its curve/transition.
7. Disable regular Autosave, edit a project, finish manipulation and wait at least 30 seconds for **draft protected**. Close/reopen Director and restore through Projects. Confirm a separate project is created and the saved original is unchanged. Check explicit save, draft discard and reconnect/restart. Unacknowledged edits are not guaranteed recoverable.
8. With two clients, test shared host/viewer playback and leave/disconnect. Viewers must not retime, apply presets or restore scenes through the UI. Remove ACE access and confirm new server save/recovery requests are denied.

## Performance checks

Compare the previous resource backup and this build on the same server, game build, location, graphics settings and scene. Use `resmon 1` and the FiveM profiler for idle, editor, catalog browsing, route manipulation and playback. Include a representative complex scene (for example ten peds, five vehicles and 100 camera keys), plus a recovery write. Record CPU time, frame pacing, NUI long tasks and project file size. No in-game performance gain is claimed by the automated checks.

Do not publish the update as game-validated until these observations have been recorded.
