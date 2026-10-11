# Changelog

## 0.2.0-beta.2

- Split the client into explicit services for project storage, camera, timeline, routes, actors, recording, collaboration and lifecycle.
- Split the browser editor into feature modules with explicit shared state and dependencies; retained the existing layout and controls.
- Reduced client.lua and web/app.js to startup orchestration. Services are initialized before event handlers.
- Updated addon integrations, manifest packaging and recursive source checks for the new layout.
- Preserved project formats, translations and the 100-animation catalog. Native movement still requires in-game regression testing.

## 0.2.0-beta.1

- Removed Free edition callback and interface gates; retained configurable workload and security budgets.
- Restored routes, camera shots and presets, motion recording, grouping, accessories, attachments, vehicle interactions and invitation-based shared filming.
- Expanded the animation catalog from 40 to 100 entries, with English/French labels and placement guidance.
- Preserved the community formatting/configuration contributions and added reproducible formatting tools.
- Separated the animation catalog, NUI request transport and server payload validation into dedicated files.
- Added automated Lua, browser and request-transport checks, plus manifest-based archive verification.
- Added English installation, upgrade and contribution documentation.
- Beta: real FiveM movement, shared playback timing and performance still require server testing.

## 0.1.0-beta.2

- Added complete English and French interface localization.
- Added localized animation names, descriptions, tutorial, tooltips and errors.
- Added standalone installation and configuration documentation in English.
- Preserved the free-edition limits and isolated project storage.
- Public beta for GTA V Legacy / FiveM. FiveM Enhanced has not been validated.
