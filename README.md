# Vanta Director Free

A free, standalone cinematic scene editor for **FiveM GTA V Legacy**. Build short scenes with a camera timeline, characters, vehicles, objects, curated animations, lighting and weather controls. The editor can hide its interface for a clean take; use OBS or another recorder to capture the footage.

[**Download a release**](https://github.com/SraxDev/vanta-director-free/releases) · [Installation guide](INSTALL.md) · [Documentation (EN)](https://vantadocs.netlify.app/director-free.html) · [Documentation (FR)](https://vantadocs.netlify.app/fr/director-free.html) · [Vanta Discord](https://discord.gg/BUdg2bx6H)

Current release: [**0.3.0**](https://github.com/SraxDev/vanta-director-free/releases/tag/v0.3.0). Download the **EN Install** ZIP for installation. [Watch the English quickstart tutorial](https://youtu.be/WRm5OxSCESE).

## Interface preview

[![Vanta Director interface preview from the trailer](https://img.youtube.com/vi/vkyVUIya6Mg/maxresdefault.jpg)](https://www.youtube.com/watch?v=vkyVUIya6Mg&t=15s)

Click the image to watch the trailer from the interface walkthrough at 00:15.

## Features

- Keyframed camera positions and a timeline for arranging the scene.
- Resize action clips, preserve the grab offset when dragging, snap to nearby clip edges, zoom around the pointer with Ctrl + wheel, and cancel a drag with Escape. Hold Alt to bypass snapping.
- Edit, reorder and join an actor's action steps in the existing inspector. Optionally move following steps when retiming a clip.
- Reuse personal camera and action presets between projects, with relative placement and explicit subject mapping for interactions.
- Start from three editable examples: slow camera reveal, conversation and vehicle follow.
- Add deterministic, subtle handheld motion to individual camera shots. Existing shot curves and transitions remain available.
- Place and stage peds, vehicles and objects, with simple movement and appearance controls.
- 100 curated animations with search, previews, favourites, recent items and English/French placement hints.
- Multi-point pedestrian and vehicle routes, live motion recording, recorded gestures and trimming.
- Camera presets, automatic target/follow/orbit modes and shot sequences.
- Subject grouping and duplication, accessories, attachments and vehicle entry/exit actions.
- Invitation-based shared filming: the host publishes scenes and controls synchronized playback.
- Scene weather, time, vehicle cues, object visibility, save/load and JSON import/export.
- A separate recovery draft for the latest unsaved scene on each account; restore it as a new project from Projects.
- English and French interface, help and interactive tutorial.
- Clean-take mode for recording cinematic footage with OBS.
- Standalone operation: no ESX, QBCore or inventory dependency.

## Install

1. Download the **EN Install** ZIP from the latest release and extract it.
2. Copy the `vanta_director_free` folder into your server `resources` directory. Keep that folder name.
3. Add these lines to `server.cfg`:

```cfg
add_ace group.admin vanta.director.free allow
ensure vanta_director_free
```

4. Grant the ACE permission to the group that should use Director. Access is restricted by default. See `INSTALL.md` in the archive for configuration, first-use steps, updating and troubleshooting.
5. Open the editor with **F6** or `/director_free`. Start a clean take in Director, record the footage separately in OBS, and press **F9** to stop the take.

The full edition and Free use separate commands, events and project storage. Stop the full edition while testing Free so their camera and mouse focus do not overlap.

## Configurable workload budgets

There are no paid-edition feature locks in this version. Server owners control workload budgets in `config.lua` to bound storage, memory, entities and network traffic. These are not purchase requirements. Defaults:

| Limit               |     Default |      Allowed range |
| ------------------- | ----------: | -----------------: |
| Projects per player |         100 |        1 to 100000 |
| Scene duration      | 600 seconds | 1 to 86400 seconds |
| Subjects per scene  |         100 |         1 to 10000 |
| Camera positions    |        1000 |        1 to 100000 |
| Actions per subject |         200 |        1 to 100000 |
| Camera shots        |         200 |        1 to 100000 |
| Route points        |         256 |        1 to 100000 |
| Saved locations     |         200 |        1 to 100000 |
| Recording length    | 120 seconds |  1 to 3600 seconds |
| Project file size   |       1 MiB |   16 KiB to 64 MiB |

Shared filming is enabled by default and can be disabled by the server owner. Its default session budget is eight participants. It is shared playback, not simultaneous project editing.

For development, formatting, automated checks and packaging, see [CONTRIBUTING.md](CONTRIBUTING.md). Runtime installation does not require Node.js.

## Compatibility and data

This release targets **FiveM Legacy**. FiveM/GTA V Enhanced has not been validated. Director is framework-independent. Project data is stored in this resource `data/` directory, separately from the full edition. The release archive includes only an empty data placeholder; do not publish server or player project files.

Recovery drafts are enabled by default with `Config.RecoveryEnabled`. While the editor is open and changed, Director attempts a draft every 30 seconds; playback, recording, routes and active manipulation pause the attempt. Only an acknowledged draft is protected. Each account has one recovery slot for its latest scene. The draft shares the project library's verified backup writes, and never replaces the explicitly saved project. A successful restore creates a new project. The separate optional Autosave preference still saves the regular project.

Personal presets are stored on the player's computer using resource KVP storage, not in server `data/`. `Config.MaximumPresets` defaults to 100 and `Config.PresetFileLimit` to 4 MiB for the whole personal library. Paths rotate and translate relative to the destination subject or camera; check terrain and framing after applying. Recorded takes use project JSON export instead of action presets. One-shot animations can be shortened, but cannot be extended beyond their captured duration in the timing editor.

Starter scenes are placed at the current camera aim. Choose an open, flat area and save current changes before creating an example. See [VALIDATION.md](VALIDATION.md) for the release's automated and in-game verification checklist.

Use `/director_free_status` for diagnostics. The archive includes the complete editable Lua/NUI resource source and English installation guide. In-game rendering, animation placement, save/reconnect behavior and performance should be verified on the target server.

## License

Vanta Director Free is licensed under the GNU General Public License, version 3 or any later version (**GPL-3.0-or-later**). You may use, modify and redistribute it, including commercially, under the license terms. If you distribute modified versions, provide the corresponding source under the same license. See [`LICENSE`](LICENSE) and [`SOURCES.md`](SOURCES.md) for the license and third-party references.

## Community

Suggestions and bug reports are welcome in the [Vanta Discord](https://discord.gg/BUdg2bx6H). For a useful bug report, include your FiveM game build, framework (if any), steps to reproduce and relevant resource logs. Remove player identifiers and other private information before sharing logs.
