## Vanta Director Free 0.2.0-beta.2

This update removes paid-edition feature gates and makes the source easier to maintain. It includes 100 animations, multi-point routes, live movement recording, camera presets and sequences, actor grouping, accessories and invitation-based shared filming.

### Install

Download **VANTA_Director_Free_0.2.0-beta.2_EN_Install.zip**, extract it and copy the `vanta_director_free` folder to your server resources. Follow the English **INSTALL.md** guide for ACE permissions and configuration.

### Upgrade

Back up the entire resource, especially `config.lua` and `data/`. Preserve your projects and merge configuration changes. After replacing files, run these commands in the **server console**:

```text
stop vanta_director_free
refresh
start vanta_director_free
```

Reconnect if your client still uses the old resource pack. The new module layout requires refreshed resource metadata.

### Source and checks

Client and browser code are separated into feature modules with explicit shared state and startup order. Formatting, Lua tests, mocked browser tests and archive checks passed. The maintainer also confirmed that their in-game tests worked. This remains a beta: game-native behavior and performance depend on the target server.

FiveM **Legacy** is the supported target. Enhanced has not been validated. There are no paid feature locks; configurable workload and security budgets remain in the server configuration.

GPL-3.0-or-later. See CHANGELOG.md and CONTRIBUTING.md for details.
