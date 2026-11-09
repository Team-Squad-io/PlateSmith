# PlateSmith

Clear, lightweight nameplates for WoW Forever that you design yourself. PlateSmith draws its own enemy and
friendly plates, gives herbs, ore, chests and books plates of their own, marks quest mobs, shows your threat on
every plate and lets you shape every part in
**Blueprint Studio**, a live editor with a preview of the plate. Give dungeons, battlegrounds and cities a look
of their own, colour plates by threat, and share your whole setup with one code or a chat link. It needs no
other addon.

## What's new in 1.4.0

- **Faster plates**: Blizzard's plate is switched off under the plates PlateSmith draws, instead of only hidden
- **Images**: add your own bits to any plate: PlateSmith's pictures, a game atlas, shared media or your own files
  (Settings › My media), flipped, turned, tinted by class, reaction, threat or the bar's colour, or fitted to a part
- **Ride the bar's fill**: a part that sits at the end of the health, power or cast bar's fill and moves with it
- **Decoration sets**: **Target arrows** (shown only on your target) and a **Fill marker**, added in one step
- **Totems, styled on their own**: the Enemies and Friendly NPCs tabs have a **Type** beside Design; with **Totems**
  open, what you change is for totems only, and **Display** shows a totem as its plate, **just its icon**, its icon
  and name, its name only or nothing. The icon is a **Totem icon** part you move, size and pin like any other
- **Incoming heals and absorbs** on health bars (off until you turn them on), all heals or others' only
- **Range**: a part (+ Add › Text) showing whether your spells reach the unit: a dot, the distance (**<5**, **<30**,
  **30+**) or both, out of range, in range or always, in your colours; from your spellbook, on friendly plates too
  (from your heals and buffs), finer as you learn spells, and range bands for rules and text: melee, near, far, out
- **Behind you**: a part (+ Add › Icons), an arrow or the words on your target's (and, if you like, your focus's)
  plate while the game says it is behind the camera
- **Corpse plates** (off until you turn them on): a dead mob gets a small plate with its name instead of an empty enemy
  bar, near or far, and the game's loot or skinning icon once the game gives one; clicking it loots as before. Off,
  dead mobs get no plate, as the game's own plates show none
- **Out of reach**: objects, corpses and NPCs you can use can dim, grey their name or show "Too far" when the game says
  they are out of reach
- **Friendly player plates for your group only** (or your group and guild), and **NPC titles** such as
  <Flight Master> under their names
- **Threat breakdown**: a threat window's title menu shows your last pulls' threat per ability, worked out from
  Blizzard's damage meter, with rage, armor and the game's own figure
- **Threat text: Gap only** (just **+1.2k** or **-300**), and a **target edge colour**: gold, custom, class, reaction
  or threat
- **Targeted by: Count only**: one small number for how many of your group or raid target an enemy
- **Hidden auras**: hide auras such as Resurrection Sickness by spell ID or name, for the plates you pick
- **Aura stacks** on the plates' buff and debuff icons, such as Lacerate's or Sunder Armor's
- **Threat colours on tagged mobs**: a mob someone else tagged keeps its threat colour, darkened, instead of plain grey
- **Your target always has a plate**, even with friendly player plates for your group only
- **Level difficulty colours**: the level in the game's red, orange, yellow, green or grey for it against yours
- **New rule and text words**: `targeted.count`, `unit.creature` and `{creature}`, `range.band` and `{range}`,
  `unit.behind`, `pvp.sanctuary` and `pvp.you`
- **Minimap button** (left-click Studio, right-click Settings; click again to close) and **a profile for this
  character** from the Profile menu
- **What's new**: a short window on your first login after each update (Settings › Studio turns it off)
- **Activity log**: `/ps diagnose` › Activity shows what changed a setting, when, and which addon
- Fixes: no empty gap under a bear's target where an invisible combo points row held its place

## What's new in 1.3.2

- **Class colours for players**: a Class colour box on the Health bar and Name for Players and Enemy players, and
  your own class colours in Studio › Settings › **Player colours** (handy if two classes look alike to you)
- **Choose where a PvP-flagged ally's colour goes**: the health bar, the name or both
- **Threat colours, Grey when tagged and aura sources per plate type and design**: threat colours on mobs but not
  enemy players, or everyone's debuffs on enemy players and only yours on mobs
- **Update a profile to its look's latest version**: a short "what's new" note, then the import review to pick what
  to take (Save keeps it, Revert undoes it)
- **Object plates match each look's own plates**, with the Action icon just outside the box
- **Clearer rule words** (`pvp.flagged = false`, `cast.active`, `unit.elite`...; the old ones still work), rules that
  can set the class colour, a note when a rule overrides a colour, and a rule reference in Settings › Help
- Fixes: cancelling Cultivation no longer marks the herb; a one-digit level's box is as wide as a two-digit one

See [CHANGELOG.md](CHANGELOG.md) for everything that changed in each release.

## Features

### Blueprint Studio

- Type `/ps` to open it. Click a part in the preview or the parts tree, change it in the inspector, and
  drag it into place; parts snap to the plate and to each other.
- Pin parts to each other, stack them, style text, bars and boxes, and write your own text such as
  `{health} / {health.max}`.
- Rules change a part while something is true: grey when tagged, red at low health, fade non-targets.
- Test values let you preview a tagged, casting or elite mob before you meet one.
- Add your own images (PlateSmith's pictures, game atlases, shared media or your own files), parts that ride a bar's
  fill, and ready-made decoration sets such as target arrows.
- Optional parts for range (from your spellbook), Behind you, incoming heals and absorbs, and NPC titles.

### Nine looks to start from

PlateSmith, Classic, Sleek, Bold, Tank, Healer, Minimal, Compact and Blizzard. Each makes a new profile that
you can change freely.

### Objects

- Herbs, ore, chests, books, quest objects and services get plates of their own on Studio's **Objects** tab, styled
  for all objects or one type at a time.
- The game's icon shows what you can do with it, and the **Status text** shows the skill a herb or vein needs, such
  as **Mining 65**, coloured by how likely it is to raise your skill. Tauren see when **Cultivation** is ready.
- Optionally fade objects you can't use yet, and show a hover cursor and tooltip on an object's plate.
- Optional corpse plates: a dead mob's name with the game's loot or skinning icon, and a dimmed plate or "Too far"
  for things out of reach.

### Designs for each place

- **World** is the look every place starts from. Add a separate design for **Dungeons & raids**,
  **Battlegrounds & arenas** or **Cities & inns**, and your plates switch as you enter and leave.
- A design follows World except what you change in it, and a gold mark shows each change.

### Enemy players

Hostile players use your enemy plates until you customise them on their own tab, for example with larger
names or their buffs shown.

### Where plates show

Pick which plate types show in each kind of place, such as no enemy plates in cities, and whether friendly players
get plates for everyone, your group only, or your group and guild. It uses Blizzard's own switches and puts them back
when you log out.

### Target highlight and glow

Light up your target with an edge or a soft glow behind its plate, in gold, your own colour, its class or
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
- **Threat breakdown** (a threat window's title menu): your last pulls' threat per ability, worked out from
  Blizzard's damage meter, with rage, armor and the game's own figure.

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
