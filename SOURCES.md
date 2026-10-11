# Third-party sources and scope

Vanta Director Free is a standalone cinematic scene editor for FiveM. The Vanta-authored resource is distributed under GNU GPL v3.0 or any later version; see `LICENSE`.

The curated `animations.json` catalog contains selected GTA animation dictionary/clip identifiers and original Vanta labels and placement notes. The animation identifiers were cross-referenced with the pinned GTA data dump and with DPEmotes' animation reference list. No DPEmotes runtime or emote-engine code is included. DPEmotes is licensed under GPL-3.0; its license and attribution remain with its authors. The Vanta animation catalog is distributed under the same GPL-3.0-or-later terms.

The `catalog/` directory contains model and asset identifiers for in-game browsing. Its source reference is the pinned, generated GTA data dump listed below. No GTA V game assets are included; Rockstar Games/Take-Two retain their rights to the game and its assets.

- [DurtyFree GTA V extracted data dumps](https://github.com/DurtyFree/gta-v-data-dumps/tree/b65684e00f689fdec405c5f1055322c802d3c895), commit `b65684e00f689fdec405c5f1055322c802d3c895`.
- [DPEmotes animation list](https://github.com/andristum/dpemotes/blob/ea9ad9c282ae90a21e1df08de21598c87d34a75d/Client/AnimationList.lua), commit `ea9ad9c282ae90a21e1df08de21598c87d34a75d`; see its [GPL-3.0 license](https://github.com/andristum/dpemotes/blob/ea9ad9c282ae90a21e1df08de21598c87d34a75d/LICENSE).
- [FiveM NUI callbacks](https://docs.fivem.net/docs/scripting-manual/nui-development/nui-callbacks/) and [fullscreen NUI](https://docs.fivem.net/docs/scripting-manual/nui-development/full-screen-nui/).

Selected animations do not automatically create props. Some poses require a wall, seat or appropriate placement; follow the hints shown in the animation library.
