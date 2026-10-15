# Changelog

## 0.3.0

- Retained the existing editor layout and improved timeline interaction: no cursor-offset jump, duration handles for supported action clips, edge/key snapping, Alt bypass, Ctrl-wheel pointer zoom, Escape/blur cancellation and interval-based clip stacking.
- Added action timing fields, optional ripple movement of following steps, joining and reordering in the current inspector. Edits validate duration, gait speed and vehicle-seat dependencies before committing, and support undo/redo.
- Added personal camera/action presets with relative placement and subject remapping. Presets are kept on the player's computer; server saves still validate their resulting projects.
- Added three editable starter scenes at the camera aim, plus a link to the English quickstart video.
- Added subtle per-shot handheld motion, sampled from scene time with fades at shot edges. Duplicating a shot now retains its curve, transition and handheld settings.
- Added a separate server recovery slot per account, with acknowledged periodic drafts, revision-checked discard, and restoration as a new project through the existing verified library write path.
- Fixed save confirmation to compare project contents rather than JSON serialization order. Edits made while a save is pending remain unsaved.
- Fixed loading server-normalized scenes without runtime actor IDs, while preserving IDs when returning to a local shared-session backup.
- Shared the existing project schema between client preset checks and authoritative server validation; retained project format version 4 and library format version 2.
- Added FR/EN captions, regression coverage and English upgrade/validation notes. Automated checks do not establish native gameplay, shared playback timing or runtime performance; see VALIDATION.md for the in-game acceptance checklist.

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
