## Vanta Director Free 0.3.0

Create and adjust scenes faster while keeping the existing editor layout. This release improves the timeline and action inspector, adds reusable personal presets and starter scenes, and protects acknowledged unsaved work with a separate recovery draft.

### What's new

- Timeline dragging preserves your grab position. Resize supported action clips, snap to nearby edges or keys, hold Alt to bypass snapping, and zoom around the pointer with Ctrl + wheel. Escape cancels a drag.
- Edit action start times and durations, optionally move following steps, and join or reorder steps from the current inspector. Changes support undo/redo and validate movement and vehicle-seat dependencies.
- Save personal camera paths and actor action presets, then apply them with relative placement and explicit subject mapping. Recorded takes continue to use the existing export and trim tools.
- Start from three editable scenes: slow camera reveal, conversation and vehicle follow. The English quickstart video is linked in the library.
- Add subtle breathing or gentle handheld motion per camera shot. Duplicating shots retains their curve, transition and handheld settings.
- Recover the latest acknowledged unsaved scene from a separate server draft slot per account. Restoration creates a new project without replacing your saved original.
- Improved save confirmation and loading of server-normalized scenes. Includes English/French interface text and regression coverage.

The existing 100 animations, routes, recordings and shared filming remain available. There are no paid-edition feature locks; configurable workload and security budgets remain.

### Install

Download **VANTA_Director_Free_0.3.0_EN_Install.zip**, extract it and copy the `vanta_director_free` folder to your server resources. Follow the English **INSTALL.md** guide for ACE permissions and configuration. Node.js is not required on your FiveM server.

### Upgrade

Back up the entire resource, especially `config.lua` and `data/`. Preserve your projects and merge configuration changes. After replacing files, run these commands in the **server console**:

```text
stop vanta_director_free
refresh
start vanta_director_free
```

Reconnect if your client still uses the old resource pack. Project format version 4 and library format version 2 are retained. See **INSTALL.md** for optional new settings and rollback instructions.

### Validation and compatibility

Formatting, Lua/JavaScript checks, Lua regression tests, mocked browser tests and archive verification passed locally. GitHub Actions repeats the release checks before publishing this archive. Automated tests mock GTA natives and server responses: native movement, multiplayer playback timing and in-game performance have not been established by these checks. **VALIDATION.md** contains the in-game acceptance checklist.

FiveM **GTA V Legacy** is the supported target. Enhanced has not been validated. This is a normal release, not a GitHub prerelease.

GPL-3.0-or-later. See CHANGELOG.md and CONTRIBUTING.md for details.
