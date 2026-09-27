# PlateSmith

Design your own nameplates for WoW Forever, see threat at a glance, and share your setup with one
code. PlateSmith shows what matters (names, quests, auras and threat) without turning every mob
into a dashboard.

## Features

- **Blueprint Studio** (`/ps`): a live preview of the plate, a tree of every part and an inspector
  for whatever you click. Drag parts to place them, pin them to each other, stack them, style
  them, and add rules that recolour, blend, fade or hide a part when something is true.
- **Preset profiles** to start from: PlateSmith, Classic, Sleek, Bold, Tank, Healer, Minimal and
  Dungeon. Each creates a new profile you can edit.
- **Nameplates** for enemies, friendly players and friendly NPCs, in the world and in dungeons:
  cast bar with icon, spell and time left; buff and debuff rows you can shape; level, elite and
  rare marks, raid marks, TAGGED, guild, target of target and quest icons.
- **Threat** on every plate (your threat %, the gap to the next player, raw threat), coloured by
  state, and up to five **threat windows** (a threat meter or a tank list) that can attach to any
  side of Blizzard's damage meter.
- **Profiles and Blueprints**: named profiles with Save and Revert, and share codes (`!PSB3!`) to
  export and import a whole setup.

`PlateSmith_QuestieDB` is an optional companion included with the release. With QuestieDB
installed, it adds quest-objective and quest-item drop markers. PlateSmith works without it.

## Getting started

Install PlateSmith through CurseForge. For a manual install, extract a packaged release into
`Interface/AddOns` so you have `PlateSmith/PlateSmith.toc`; to use the companion, put
`PlateSmith_QuestieDB` beside it and install QuestieDB.

In game:

| Command | What it does |
|---|---|
| `/ps` | Open Blueprint Studio |
| `/ps config` | Open Settings (Threat and Profiles) |
| `/ps console` | Show or hide the threat windows |
| `/ps diagnose` | Open a report to copy into a bug report |

## Known limits

- The game hides some values in combat and in instances. PlateSmith never guesses: a hidden value
  isn't shown, and a rule that depends on it doesn't apply.
- While aura details are hidden, the debuff row is the game's own aura frame, placed by
  PlateSmith but not restyled.
- Clicking a threat window row spotlights the plate; addons can't target mobs from a click.
- English only for now.

## Reporting a problem

Run `/ps diagnose`, copy the report, and post it with a screenshot and what you were doing. See
[CHANGELOG.md](CHANGELOG.md) for what changed in each release.

## Permissions

Copyright 2026 TeamSquadIO. All rights reserved. You may install and use official PlateSmith releases in World of Warcraft. Reusing PlateSmith's original code or artwork, republishing the addon, or distributing modified versions requires prior written permission. No open-source licence is granted. GitHub may allow a fork, but that is not permission to publish a derivative addon.

World of Warcraft is a trademark of Blizzard Entertainment. PlateSmith is an independent addon and is not affiliated with Blizzard.
