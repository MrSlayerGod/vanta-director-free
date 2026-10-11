# Installation and upgrade

This beta targets FiveM with GTA V Legacy. GTA V Enhanced is not validated. No ESX, QBCore, database, Node.js or build tools are needed on the game server.

## Fresh installation

1. Extract the archive and copy `vanta_director_free` into the server's `resources` folder. Keep its name.
2. Add the following to `server.cfg`:

```cfg
add_ace group.admin vanta.director.free allow
ensure vanta_director_free
```

3. Assign trusted users to the permitted ACE group through your server administration setup. Director access is restricted by default.
4. Start the resource, connect and press **F6**, or use `/director_free`. FiveM key bindings can override the defaults.
5. Place a camera, add positions, add subjects and preview the scene. Use the animation library for character actions and the route editor for paths.
6. Use clean-take mode with an external recorder such as OBS. Director does not export MP4 files. **F9** stops a clean take; **F10** finishes live motion recording and **F11** cancels it.

## Upgrade from an earlier Free build

Stop the resource and back up its complete folder, especially `config.lua` and `data/`. Replace the resource files with this release, then restore your `data/` folder. Merge your settings into the new `config.lua`; do not blindly overwrite it with the old file. Shared filming is now enabled by default. Set `Config.CollaborationEnabled = false` if you do not want it.

After replacing files, reload the manifest in the **server console**:

```text
stop vanta_director_free
refresh
start vanta_director_free
```

A plain restart can keep old resource metadata after files are added to the manifest. Reconnect if the client is still using the old resource pack.

Test loading, editing, saving and reopening a copy of an existing project before using important projects. Existing per-player preferences take priority over new defaults. For rollback, stop the resource and restore the complete backup, including its data.

Stop other Director editions during testing to avoid overlapping cameras and mouse focus. Free keeps its own event namespace and project storage. Do not rename another edition's folder to install this release.

## Configuration

`config.lua` controls permissions, keyboard defaults, workload budgets, collaboration and default preferences. There are no paid-edition feature checks. Numeric budgets remain configurable to bound memory, disk, networking and entity load. Increase them gradually and measure on your server; a large allowed value is not a performance guarantee.

English is the initial language. French is available in Settings. `Config.DiscordUrl = ""` hides the optional community link. Joining Discord is not required to use the editor.

Shared filming uses invitations: the host publishes the scene and controls playback; invited participants load it and receive synchronized playback commands. It is not simultaneous multi-user editing. Both users need Director permission. Animations with accessory hints require manual accessory placement.

## Troubleshooting and acceptance checks

- Run `/director_free_status` and inspect the server console and client F8 console for resource errors.
- For a missing interface, verify the folder name and that all `web/` files were extracted. Do not install only the Lua files.
- Test camera positions and shots, pedestrian and vehicle paths, animation previews, undo/redo, project save/reconnect and import/export.
- Test clean-take exit, resource restart and restoration of player controls. For collaboration, use two clients and test invitation, playback, leaving and host disconnection.
- Measure idle/editor/playback with FiveM's resource monitor on a representative scene before raising workload budgets.

Automated tests cover source validation, mocked Lua behavior and browser UI behavior. They do not validate native game rendering, physical motion, network timing or performance on your server.

Never share player project data, identifiers or server credentials in bug reports. Include your game build, reproduction steps and relevant sanitized logs.
