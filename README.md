# Vanta Director Free

A free, standalone cinematic scene editor for **FiveM GTA V Legacy**. Build short scenes with a camera timeline, characters, vehicles, objects, curated animations, lighting and weather controls. The editor can hide its interface for a clean take; use OBS or another recorder to capture the footage.

[**Download the latest installer**](https://github.com/SraxDev/vanta-director-free/releases/download/v0.1.0-beta.2/VANTA_Director_Free_0.1.0-beta.2_EN_Install.zip) · [All releases](https://github.com/SraxDev/vanta-director-free/releases) · [Vanta Discord](https://discord.gg/BUdg2bx6H)

## Interface preview

[![Vanta Director interface preview from the trailer](https://img.youtube.com/vi/vkyVUIya6Mg/maxresdefault.jpg)](https://www.youtube.com/watch?v=vkyVUIya6Mg&t=15s)

Click the image to watch the trailer from the interface walkthrough at 00:15.

## Features

- Keyframed camera positions and a timeline for arranging the scene.
- Place and stage peds, vehicles and objects, with simple movement and appearance controls.
- Curated animation library with search, previews, favourites and recent items.
- Scene weather, time, vehicle cues, object visibility, save/load and JSON import/export.
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

## Free edition limits

| Limit | Free edition |
|---|---:|
| Projects per player | 3 |
| Scene duration | 60 seconds |
| Subjects per scene | 6 |
| Camera positions | 30 |
| Actions per subject | 20 |
| Curated animations | 40 |

Multi-point routes, automatic cameras, camera sequences, motion recording, attached accessories, grouped duplication, vehicle entry/exit and shared filming are part of the full edition. Free rejects projects that use unsupported features; keep the original export and open it in the edition that supports those features.

## Compatibility and data

This release targets **FiveM Legacy**. FiveM/GTA V Enhanced has not been validated. Director is framework-independent. Project data is stored in this resource `data/` directory, separately from the full edition. The release archive includes only an empty data placeholder; do not publish server or player project files.

Use `/director_free_status` for diagnostics. The archive includes the complete editable Lua/NUI resource source and English installation guide. In-game rendering, animation placement, save/reconnect behavior and performance should be verified on the target server.

## License

Vanta Director Free is licensed under the GNU General Public License, version 3 or any later version (**GPL-3.0-or-later**). You may use, modify and redistribute it, including commercially, under the license terms. If you distribute modified versions, provide the corresponding source under the same license. See [`LICENSE`](LICENSE) and [`SOURCES.md`](SOURCES.md) for the license and third-party references.

## Community

Suggestions and bug reports are welcome in the [Vanta Discord](https://discord.gg/BUdg2bx6H). For a useful bug report, include your FiveM game build, framework (if any), steps to reproduce and relevant resource logs. Remove player identifiers and other private information before sharing logs.
