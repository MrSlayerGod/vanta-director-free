# Contributing

The source is editable and licensed under GPL-3.0-or-later. Keep changes focused and explain the behavior being fixed. Preserve contributor attribution and existing project compatibility.

## Local checks

Clone the GitHub repository for development (the installer contains runtime files only). Use Node.js 22 or later:

```sh
npm ci
npm run catalog
npm run format
npm run check
npm test
npx playwright install chromium
npm run test:ui
npm run package
```

`DIRECTOR_BROWSER` can point to a local Chromium or Edge executable for UI tests. The server uses the checked-in UI assets directly; no runtime npm install is needed. `dist/`, `node_modules/` and `test-results/` are local outputs.

## Source map

- `client.lua`: startup orchestration; `client/state.lua`: per-session state.
- `client/`: client services. Camera, playback, routes, projects, entity lifecycle, input and recording have separate modules.
- `server.lua`: project validation and persistence.
- `project_validation.lua`: shared scene normalization; server calls remain authoritative. `timing.lua`, `presets.lua` and `templates.lua` contain pure editing/placement helpers.
- `client/workflow.lua`, `client/presets.lua`: validated action-chain edits, local preset storage and starter-scene requests.
- `web/editor/actionChain.js`, `web/editor/presets.js`: additions inside the existing inspector and project library. `web/editor/timeline.js` owns drag/resize/zoom; snap targets are cached for each drag.
- `access.lua`, `payload.lua`: authorization, rate control and payload shape checks.
- `collaboration_server.lua`: invitations, host authority and shared playback.
- `routes.lua`, `motion.lua`, `recording.lua`, `shots.lua`: scene movement and camera data.
- `web/app.js`: browser startup; `web/editor/`: rendering, input, saving, model browsing and animation services.
- `web/editor/state.js`: shared state and DOM references; `web/nui-bridge.js`: cancellable request transport.
- `web/route-editor.js`: route interaction and cancellation lifecycle.
- `animations.json`: editable animation source; regenerate `web/animation-catalog.js` with `npm run catalog`.
- `web/locales.js`: English/French presentation strings. Native identifiers and user project names must stay unchanged.

Each module receives the editor context explicitly. Cross-module calls use named services (`ctx.routes`, `ctx.camera`, etc.); mutable session values live in `ctx.state`. Module factories define functions first and return an event-binding function. Bootstraps bind events only after all services and state are initialized, so no handler observes a partially initialized editor.

Add runtime files to `fxmanifest.lua` and browser scripts to `web/index.html`. Do not concatenate sources at runtime or introduce hidden global aliases. Keep pure scene math in the existing shared Lua helpers, and keep native calls on the client. The larger playback and actor-inspector routines remain grouped by their behavior; avoid mixing unrelated UI or persistence work into them.

## Review expectations

Run format and source checks, then test changed behaviors. Lua tests use mocked natives, and browser tests use mocked NUI messages. Document real in-game checks separately, including any that you could not run. For movement, entity lifecycle or shared filming, test in FiveM before calling a change production-ready.

AI assistance is allowed. Contributors remain responsible for understanding, reviewing and testing their changes. Be honest about tooling when asked; do not fabricate authorship or test results.

Never commit server configuration secrets, player data or recordings. The packager uses the manifest allowlist and includes only an empty `data/.keep`.
