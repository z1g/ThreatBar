# ThreatBar

ElvUI-style **player-only** threat data bar for **WoW Forever**. One bar, your threat on the current target — not the group list.

EllesmereUI already ships the full threat meter (`EllesmereUIForeverEssentials`). Keep that. This is the extra strip you used to park on the cast bar so you never have to find yourself in a top-10 list.

Forever does not give addons `COMBAT_LOG_EVENT`. The bar reads `UnitDetailedThreatSituation("player", "target")` and colours with `GetThreatStatusColor`. EllesmereUI skins the chrome through `EllesmereUI.RegisterSkin` (Blizzard Skins+ → Window Skins → Third-Party Addons → ThreatBar).

## Install

Copy the `ThreatBar` folder into `_forever_/Interface/AddOns/` (or the Nextcloud-synced `Interface/AddOns` folder). **Quit the client fully** — a new `.toc` does not load on `/reload`. Enable it on the character addon list.

Source of truth: `~/Projects/threatbar`.

## Place it on the cast bar

1. `/threatbar test` — fills at 80% for 10 seconds so you can see it out of combat.
2. Drag the bar onto your cast bar. Drag the bottom-right grip to match width/height.
3. `/threatbar lock`

Unlocked, the bar stays on screen even with no threat so you can move it.

## Commands

- `/threatbar` or `/tbar` — show/hide
- `/threatbar lock` — lock/unlock move and resize
- `/threatbar test` — 80% preview for 10 seconds
- `/threatbar text` — percent text on/off
- `/threatbar combat` — hide out of combat (default on)
- `/threatbar reset` — default size and position

## Honesty

This is **your** threat on **your current target** only. It does not list the raid. Use EllesmereUI’s threat meter (or Details Tiny Threat) when you want the whole table.
