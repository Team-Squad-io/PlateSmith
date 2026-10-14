# PlateSmith

Clear, lightweight nameplates for WoW Forever that you design yourself. PlateSmith draws its own enemy and
friendly plates, gives herbs, ore, chests and books plates of their own, marks quest mobs, shows your threat on
every plate and lets you shape every part in
**Blueprint Studio**, a live editor with a preview of the plate. Give dungeons, battlegrounds and cities a look
of their own, colour plates by threat, and share your whole setup with one code or a chat link. It needs no
other addon.

## What's new in 1.3.0

- **Objects**: herbs, ore, chests, books and quest objects get plates of their own, with the game's icon for what you
  can do and the skill a herb or vein needs, in the game's skill-up colours for yours
- **Refreshed looks**: each look's plates match its card, with friendly plates and an elite mark of its own
- **Rescue**, a third threat window mode: your group at a glance, and a click taunts an enemy off them
- **Skin Blizzard's damage meter** (optional) to match the threat windows
- Four new elite, rare and boss marks, and the **Loose mark** for a mob attacking someone who is not a tank
- **Blizzard, with PlateSmith extras**: keep Blizzard's plates and add quest markers, threat and the target glow
- **Clicking**: make friendly players, friendly NPCs or enemies click through
- All threat settings on one page, Studio › Settings › Modules › Threat

See [CHANGELOG.md](CHANGELOG.md) for everything that changed in each release.

## Features

### Blueprint Studio

- Type `/ps` to open it. Click a part in the preview or the parts tree, change it in the inspector, and
  drag it into place; parts snap to the plate and to each other.
- Pin parts to each other, stack them, style text, bars and boxes, and write your own text such as
  `{health} / {health.max}`.
- Rules change a part while something is true: grey when tagged, red at low health, fade non-targets.
- Test values let you preview a tagged, casting or elite mob before you meet one.

### Nine looks to start from

PlateSmith, Classic, Sleek, Bold, Tank, Healer, Minimal, Compact and Blizzard. Each makes a new profile that
you can change freely.

### Objects

- Herbs, ore, chests, books, quest objects and services get plates of their own on Studio's **Objects** tab, styled
  for all objects or one type at a time.
- The game's icon shows what you can do with it, and the **Status text** shows the skill a herb or vein needs, such
  as **Mining 65**, coloured by how likely it is to raise your skill. Tauren see when **Cultivation** is ready.
- Optionally fade objects you can't use yet, and show a hover cursor and tooltip on an object's plate.

### Designs for each place

- **World** is the look every place starts from. Add a separate design for **Dungeons & raids**,
  **Battlegrounds & arenas** or **Cities & inns**, and your plates switch as you enter and leave.
- A design follows World except what you change in it, and a gold mark shows each change.

### Enemy players

Hostile players use your enemy plates until you customise them on their own tab, for example with larger
names or their buffs shown.

### Where plates show

Pick which plate types show in each kind of place, such as no enemy plates in cities. It uses Blizzard's own
switches and puts them back when you log out.

### Target highlight and glow

Light up your target with a gold edge or a soft glow behind its plate, in your own colour, its class or
reaction colour, or your threat colour on it. Each plate type can have its own.

### Combo points

Your combo points on your target's plate, in the shape, size and colour you choose, as wide as the health
bar if you like, and shown always, in combat or only when you have points.

### Threat

- Your threat on every plate: your threat percent and the gap to the next player.
- Colour by threat colours health bars and names for tanks (holding, losing it) or for DPS and healers
  (safe, pulling, aggro).
- Up to five threat windows: a threat meter for your target, a tank list of every enemy in view, or **Rescue**,
  your group at a glance with a click to taunt. They can follow Blizzard's damage meter, which PlateSmith can skin
  to match.

### Quests

- Quest markers on mobs you still need for a quest, with optional progress such as 3/8.
- If you use Questie, choose whether its quest icons or PlateSmith's show.
- The optional **PlateSmith_QuestieDB** companion, included in the download, also marks mobs that can drop a
  quest item when QuestieDB is installed.

### Blueprints

- Export your whole setup as a share code, or **Link in chat** for other PlateSmith players to click.
- Import shows what will change, design by design, and you pick the sections to bring in.

### Clicking

Choose whether friendly players, friendly NPCs and enemies can be clicked through, separately from how they look.

### Profiles

- Named profiles with Save and Revert, so you can try things without losing your setup.
- Switch profiles automatically for dungeons, raids, battlegrounds or each specialization.

## Install

Install PlateSmith through CurseForge. For a manual install, extract a packaged release into your WoW Forever
`Interface/AddOns` folder so you have `PlateSmith/PlateSmith.toc`, then restart the game or `/reload`. To use
the optional quest companion, put `PlateSmith_QuestieDB` beside it and install QuestieDB.

## Getting started

1. Log in with PlateSmith enabled.
2. Type `/ps`. On a new install a short setup asks how you play this character, then lets you pick a look.
3. Click a part, change it, and press **Save**. Your plates show changes at once, but only Save keeps them.

## Commands

| Command | What it does |
| --- | --- |
| `/ps` | Open Blueprint Studio |
| `/ps diagnose` | Open the diagnostics report |
| `/ps console` | Show or hide the threat windows |

Everything else is in Studio and its Settings.

## Compatibility

- Made for WoW Forever. The game keeps some values private in combat and in instances. PlateSmith still shows
  them where the game allows, but never guesses: a rule that depends on one does not apply.
- QuestieDB, Questie and LibSharedMedia are used when installed, and are never required.
- Another nameplate addon (KuiNameplates, Plater, Threat Plates, ElvUI's nameplates and others): PlateSmith
  says so once a session and, by default, runs as a light overlay (quest markers and threat) on its plates.
  It offers to disable the other addon (for ElvUI, turn its nameplates off), or use `/ps mode own`.
- Blizzard protects friendly plates in dungeons and raids; there PlateSmith offers what the game allows.
- English only for now.

## Reporting a problem

Target the mob, type `/ps diagnose`, and copy the summary and the report code into your report with a
screenshot and what you were doing.

## Permissions

Copyright 2026 TeamSquadIO. All rights reserved. You may install and use official PlateSmith releases in World
of Warcraft. Reusing PlateSmith's original code or artwork, republishing the addon, or distributing modified
versions requires prior written permission. No open-source licence is granted. GitHub may allow a fork, but that
is not permission to publish a derivative addon.

World of Warcraft is a trademark of Blizzard Entertainment. PlateSmith is an independent addon and is not
affiliated with Blizzard.
