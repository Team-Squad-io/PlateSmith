# PlateSmith changelog

Each release lists what players will notice. CurseForge shows this file as the release notes.

## 1.3.0

### New

- **Four new ways to mark elites, rares and bosses.** The Elite / rare mark's **Style** (Studio › Enemies ›
  Elite / rare mark) now offers, besides Blizzard icons, Words and Letters:
  - **Classic dragon**: the classic client's gold dragon (silver for rares and rare elites) wrapped round the
    level, which moves to the health bar's right end; a world boss shows its skull in the level's place inside
    the gold dragon.
  - **Before the name**: the small winged icon (a skull for a boss) right before the name, at the name's text
    height, with the level before it; on a normal mob the level closes up to the name.
  - **Level suffix**: no icon; the level reads **60+** (gold), **60R** (silver), **60R+** (silver with a gold +),
    and a boss's **??** turns red.
  - **Bar frame**: no icon; a thin gold (elite) or silver (rare) frame round the health bar, silver round gold for
    a rare elite, and a 2 px dark red frame with a black line inside for a boss. Your target's gold edge, the
    tank warning and Threat colours on the bar's edge stay the outermost line, outside the frame.
  Each style says what it does in the menu. Classic dragon and Before the name place the mark and the level
  themselves: your own placement of those parts is kept and comes back when you pick another style (Placement
  says why it is unavailable meanwhile). Where the game keeps the classification private, no mark shows; a
  protected level shows on its own (in the mark's colour with Level suffix when the classification is known).
- **Icon size** for the Elite / rare mark: **Auto** (18 px beside the bar, the name's text height before the
  name), **18 px** or **Text height**.
- **Test values › Elite / rare**: one choice for the sample's classification (Normal, Elite, Rare, Rare elite,
  Boss) in place of the Elite, Rare and Boss boxes, so the preview shows each style at once.

Your profiles keep Blizzard icons and look exactly as before, and the looks still use Blizzard icons. Blueprints
using a new style or Icon size are `!PSB4!`.

- **Shape the soft target glow.** Plate settings › Target highlight (with Soft glow behind) has new rows, per
  plate type and design:
  - **Glow wrap**: **Fit to parts** follows your plate's parts as they show and hide, as before, and **Glow
    parts** picks which: Name, Health bar, Power bar and Cast bar (all by default), so the glow can light just
    the name or just the bar. **Fixed size** is a box of your size centred on the health bar instead (140 x 40 to
    start: picking it clears Same width and height).
  - **Glow width** and **Glow height** (Glow width replaces Glow size): with Fit to parts, the room the glow
    adds around the parts, left and right and up and down, the same on both sides; with Fixed size, the glow's
    whole size. **Same width and height** (on) sets both with Glow width, as Glow size did; untick it to give
    Height its own slider. **Glow offset X** and **Y** still move the glow's centre.
  Your glows look exactly as before. Blueprints using any of these are `!PSB4!`. Studio's preview wraps the
  name's text as your plates do, not the wider box you grab it by, so a glow round just the name ends at the name.
- **Clicking**: Settings › Behaviour & display › Clicking sets whether **Friendly players**, **Friendly NPCs** and
  **Enemies** (and **Your own plate**, where the game has a switch for it) are **Clickable** or **Click through**,
  separately from how they look. Studio's Players and Friendly NPCs tabs have the same choice as **Clicks** in Plate
  settings › Friendly plates, next to Show as. Each covers every plate of its kind, not one plate.
  - Friendly players: Click through turns on the game's "friendly players: names only" option outside dungeons &
    raids while PlateSmith draws them, which leaves their plates nothing to click; PlateSmith still draws its own
    look, names only or full plates.
  - Friendly NPCs and enemies: Click through shrinks the game's click area for them to nothing (or uses the game's
    click-through switch, on clients that have one). The game has one click setting for every friendly plate, so
    Friendly NPCs' Click through makes friendly players click through too: the Players row then reads **Click
    through (shared with NPCs)** and is locked until NPCs are clickable again. Friendly NPCs' choice applies outside
    dungeons & raids; enemies' everywhere.
  Clickable is the default everywhere, so nothing changes until you pick Click through. PlateSmith records the game's
  value first, waits for combat to end before changing it, and puts it back when you choose Clickable, turn
  PlateSmith off, switch profile or log out; Blueprints leave it out.
- **Objects tab: books, chests and quest objects get plates of their own.** When the game gives an object a
  nameplate (a book on the ground, Shipment of Iron, Alliance Chest), PlateSmith drew it as an enemy: a red name,
  level 0 and an empty health bar. Objects are now a plate type of their own, with a fifth Studio tab, **Objects**:
  the object's name in gold in a small tooltip-like box (a dark background with a thin grey-gold edge), plus a quest
  mark beside it when the object is part of a quest; no level, bars, auras, threat or target highlight. Edit it
  like any plate type: the name's font, size and colour rules, the box (the Backdrop part, below), where the quest
  mark sits, and designs of its own for dungeons & raids, battlegrounds & arenas and cities & inns. Every look has
  an Objects style of its own (Blizzard's is closest to the game's tooltip, Minimal's a faint box); your profiles get
  the default above. Clicking an object still opens or loots it.
  - **Backdrop** (a new part, on the Objects tab): the box, like the game's tooltip. **Fit to parts** wraps the parts you
    tick under Style › **Wraps** (the name, the Status text and the Action icon by default; the quest marker too if you
    like) while they show, so a herb's box grows to hold its Status text and shrinks back when it hides, with Padding
    round them; with nothing to show it hides. **Fixed size** is a box of your own Width and Height that you place and
    drag like any part. Style it as a text's box (Square or Blizzard's Rounded, Fill, Border colour and width). The
    parts it wraps drag and nudge freely in the preview; it follows them. Every look's Objects style uses it, and the
    name has no box of its own there. Hovering anywhere on the box shows the object's cursor and tooltip.
  - **Action icon**: right of the name, inside the box, the game's own icon for what you can do with the object, the one
    your cursor shows over it: a herb, ore, a book, a chest, a quest. When the game says you cannot yet (a herb
    your skill is too low for), it shows its own "can't" icon; the part's **Can't use** choice shows that as the
    game gives it (the default), greyed, or hidden. Move it, scale it or turn it off like any part. **Friendly NPCs**
    have the part too, off: turn it on to see the game's talk, trainer, vendor or flight icon by their names (a
    Blueprint with it changed is `!PSB4!`). Where the game gives no icon, none shows.
  - **Rules and custom text by what an object is**: `object.kind = herb` (or ore, skin, loot, quest, inspect,
    interact, talk, trainer, vendor, flight, repair, mail, other), read from that icon, never from object names;
    `object.unable` (the icon says you can't yet); `interact.inrange` (within reach); `object.id = 175734` (the
    object's ID from the game, to style one object of your choice) and `unit.id` (an NPC's); `object.quest` (the
    optional PlateSmith_QuestieDB companion lists the object in a quest: a quest in your log needs it, or it starts
    or ends one). `{object.kind}`, `{object.id}` and `{unit.id}` show them in custom text. `==` now works as `=`.
    Something the game does not say is unknown, so a rule on it does not apply.
  - **Type** beside Design: **All objects**, or one type of object as the game's icon says it is: **Herbs**,
    **Ore**, **Chests & loot**, **Quest objects**, **Books & lore**, **Talk & services** (a mailbox) or **Other**.
    Pick a type and change anything (the name's colour, font and box, the Action icon's size and place, which parts
    show, or **Hide these plates** under Plate settings › This type): that type keeps those changes and follows All
    objects in everything else, in every place (on top of a dungeon or city design). Changed rows get the gold mark,
    with **Reset to All objects** on each and for the whole type. An object the game gives no icon draws as All
    objects, and one that changes (a chest emptied) follows at once. Your profiles have no type changes, so every
    object looks as before; each look sets a few (herbs green, ore stone grey, chests gold, quest objects yellow,
    and the Status text on herbs and ore; Classic and Blizzard keep the game's gold names). Blueprints carry them
    (`!PSB4!`), imported with the context designs.
  - **Status text** (a new part, off on All objects, centred under the name inside the box): what the object needs and
    whether your skill reaches it, such as **Mining 65** in the game's own gathering colours for your skill (orange: a
    skill point every time, yellow: most times, green: now and then, grey: no more, red: too low; hovering the plate
    adds your own skill and what the colour means). It comes from the
    game's own tooltip: hover one Tin Vein once and every Tin Vein's plate shows it from then on, in any profile (up to 300 objects are
    remembered for your account; never shared in Blueprints). The skill is found by your own skill names, in any
    language. Herbs and ore veins need no hovering: where the game's tooltip names no requirement (WoW Forever's shows
    only the name), the original game's levels are used, by the object's ID (a Tin Vein **Mining 65**, Liferoot
    **Herbalism 150**; from the open-source VMangos database via pfQuest, credited in the README). For anything
    else, until an object like it has been hovered, or for one that needs none of your skills, it shows nothing.
    Rules and custom text read `object.skill` (the skill it needs) and `object.cangather`.
  - **Cultivation** (the Tauren racial): if you know it, herb plates' Status text says **Cultivate ready** (green,
    beside the Herbalism part in its own colour) or **Cultivate in 23m** (the spell's own cooldown, following each
    minute while herbs are in view), and the herb you cultivated says **Cultivated** until it respawns. A herb above
    your level (its Herbalism skill / 5: a herb of 150 needs level 30) says **Cultivate at level 30** in red. A herb you can cultivate is not faded by Fade objects you can't
    use, Herbalism or not. Rules and custom text read `object.cancultivate`; Test values' **Cultivation ready** shows
    it in the preview. Nothing changes for players without it.
  - **Fade objects you can't use yet** (Studio › Settings › Objects & interacting, off unless a look turns it on): an
    object whose icon says you can't use it yet (a herb above your skill) fades to half, unless your skill reaches it
    after all (`object.cangather`) or you can cultivate it.
  - **Copy style from a look...** (the Objects tab's Plate settings): gives your profile a look's Objects style (All objects,
    its types and the fade) without changing anything else. Your Objects designs for places stay. It asks first when
    you have changed the Objects tab; like any change it needs Save, and Revert undoes it.
  - **Show the game's cursor** and **Show a tooltip** (Studio › Settings › Objects & interacting › When you point at
    an object's plate, both on): pointing at an object's name on its plate shows the game's own cursor for it, as over
    the object itself (gather, mine, read, loot, greyed when it is out of reach where the game allows it), and a small
    tooltip with its name, its type and, once one like it has been hovered in the world, what it needs. Clicking the object and turning the camera work as before. Nothing changes
    in combat. Kept by your profile, not shared in Blueprints.
  - **Test values › Object** (Herb, Ore, Book, Chest, Quest, Talk, Trainer) and **Can't use yet** show each in the
    preview with the game's icon and its Status text; choosing a Type picks its sample.
- **New profiles remember their look.** A profile made with Profile › **New from preset** or a first-run look card
  records which look it came from; the Profile menu's tooltip and `/ps diagnose` name it. Your existing profiles have
  none, and it is never shared in Blueprints (an import keeps yours).
- **Studio › Settings › Objects & interacting**, a new page for everything about objects that is not their look
  (the Objects tab's Plate settings keeps the design: Copy style from a look, This type, Scale, and an **Object
  settings...** button to this page). **Object plates**: **Drawn by** PlateSmith (the Objects design) or Blizzard's
  (the game's own object plate, untouched) and Fade objects you can't use yet. **When you point at an object's
  plate**: Show the game's cursor and Show a tooltip. **Interact key**: the game's own settings for the object, corpse
  or NPC your interact key picks, each **Game's setting** (the default: nothing changes) or a choice of its own:
  **Interact key target** (On or Off), **Range** (10 to 60 yards; WoW Forever appears to drop the target past about
  15 yards whatever it says), **Direction** (Straight ahead, In front, All around), **Out of reach** (Only within
  reach, or Out of reach too), **Plate on it**, **Icon over it**, **Icons on objects too** and **Icons on minor
  targets** (On or Off). Range, Direction, Out of reach and Icons on minor targets are new. They are the same
  settings addons such as Loot Sparkles use: if another addon changes one after PlateSmith, PlateSmith follows it
  rather than setting it back, and it puts the game's value back when you choose Game's setting, Revert, turn
  PlateSmith off, switch to a profile that leaves it to the game, or log out. A row shows only where the game client
  has that setting. Where objects show at all is the game's: it has no switch for object plates. Blueprints carry
  your Objects design (`!PSB4!` when it differs from the default) but never the interact key settings.
- **Rescue, a third threat window mode.** Pick **Rescue** in a threat window's menu, its mode button or Studio ›
  Settings › Modules › Threat › Threat windows › Mode. It lists your group in a fixed order (a party as a list, tanks first; a raid as
  a grid, one column per group) and colours a member orange when they pull and red, with a pulsing glow, when an
  enemy is on them; a tank holding stays calm. **Click a member to taunt their target** (Warrior: Taunt,
  right-click Mocking Blow, Shift-click Challenging Shout; Druid: Growl, Challenging Roar, in Bear Form only, and a
  row's tooltip says when Bear Form is needed; Paladin: Judgement, Shift-click Blessing of Protection on them), or use
  **Taunt my target** in its header. Its settings: Layout, Show (Everyone, Healers only, Healers and ranged, My group
  only), In raids, Clicks, what each click casts, and three optional alerts: a sound (built-in, plus
  LibSharedMedia's sounds when it is installed), a flash of the window's border when someone newly gets aggro, and
  your taunt's cooldown in the header ("Taunt 6s", "Taunt ready"). A Rescue window holds still in combat (no moving,
  resizing or hiding until it ends; a drag or resize under way when combat starts ends there; its close button looks
  unavailable then) and catches up with group changes, newly learned spells and role changes when combat ends. Opened in an older PlateSmith, a Rescue window becomes a Tank window.
- **Skin Blizzard's damage meter** (optional, off by default): Studio › Settings › Modules › Threat › Threat windows ›
  **Damage meter**. Blizzard's damage meter takes the threat windows' look, so a threat window following it and the
  meter look like one set: the frame and title, the minimise, settings and session buttons, the bars and their dark
  track, the row and header text, the scroll bar and the breakdown pop-out, in Forge, Ledger or Glass (the theme of
  the threat window following that meter window, else of your first shown one; Forge for the other themes). Rows the
  meter adds later, a second or third meter window and a theme change follow. Only the look changes: Edit Mode
  still places and sizes the meter, and its clicks, menus and numbers are Blizzard's. Turning it off puts Blizzard's
  look back at once. The setting is for every character and is not part of Blueprints.
  It sizes itself to the members it lists; with nobody to list (solo) it keeps the size the window had and says
  "Not in a group. Rescue lists your party or raid.", and switching it to another mode gives that size back.
- **Blizzard, with PlateSmith extras is a real choice.** With **Who draws the plates** set to it, Blizzard draws its
  own plates (PlateSmith never moves, resizes or restyles them) and PlateSmith adds its extras on top, attached to
  Blizzard's name and health bar. Choose them in Studio › Settings › Behaviour & display › **Extras on Blizzard's
  plates**, where a sample of Blizzard's plate shows each one:
  - **Quest markers**, left of Blizzard's name (with their progress where your Enemies' quest marker shows it).
  - **Threat**: **Text** (your threat % and lead over the name), **Edge** (a thin edge round Blizzard's health bar in
    the Threat colours for your role), **Text and edge**, or **Off**.
  - **Target glow**: the soft glow behind your target's plate, in your Target highlight's glow colour, size and pulse.
  - **Loose mark** (below), right of Blizzard's name.
  Objects (books, chests, herbs) keep PlateSmith's own plates, which have no Blizzard style. Blizzard already draws
  raid marks and elite icons, so PlateSmith adds none. Friendly plates in dungeons & raids are Blizzard's protected
  plates and get nothing. Beside another nameplate addon's plates only the quest markers and threat text show, as
  before. Your **Who draws the plates** is unchanged; a profile saved before keeps what this choice drew then (quest
  markers and threat text), and new profiles have all four. Blueprints carry the extras (`!PSB4!` away from that).
- **Loose mark.** A new part on **Enemies** plates (+ Add › Icons): a small mark beside the name while a mob is loose,
  attacking someone who is not a tank (the Tank window's LOOSE), with two quick blinks as it gets loose. Its
  **Display** sets **Show for** (Tanks, the default, or Everyone), **Icon** (the game's alert or the Tank window's LOOSE
  icon) and **Pulse**. Where the game will not say who holds a mob, no mark shows. It is off in your profiles and in
  every look but **Tank**, which shows it (TAGGED moves after it and takes its place while the mob is not loose).
  Rules and custom text can read the same as `threat.loose`; **Test values › Loose** shows it in the preview (with
  **You tank**). Blueprints using its options are `!PSB4!`.
- **For addon authors: the module API is public.** The download now carries `Docs/MODULES.md` (the versioned API
  reference, with a ten-minute first module) and `Examples/PlateSmith_ExampleModule`. Every call takes
  `PlateSmith:Call` and `PlateSmith.Call` alike; one ID grammar covers modules, tokens, facts, formatters, Blueprint
  fields and preview parts (older IDs still register); new helpers `ReportError`, `Locale`, `IsReadable`,
  `ReadNumber`, `ReadText` and `InvalidateFact` (read a module's fact again when no plate event says it changed).
  The QuestieDB companion uses only this public API. `RegisterModuleSettings` still works but is deprecated, and
  `RegisterEditorComponent` is documented as a preview part only.
- **Studio › Settings › Modules.** A group at the end of Settings' categories (the list scrolls when it is long)
  with a page per module, each with its icon: **Threat** (PlateSmith's own), **QuestieDB** with the companion, and
  any addon that adds one. Module pages look and work like Studio's own: folding sections, `?` help, Settings
  search, and they open in combat. A module's profile settings light up Save, Revert undoes them and Blueprints
  share them; settings a module keeps itself are saved at once and say so in their tooltip. A row's gold dot means
  unsaved changes; a module whose page cannot show is greyed, with the reason in its tooltip. For addon authors:
  `PlateSmith:RegisterStudioSettings` (`Docs/MODULES.md`).
- **Other addons' data in your custom parts.** With an addon that provides them, a custom bar's **Source** can be its
  value (such as a cooldown), a custom icon's **Picture** its icon, and custom text's **Source** its text, listed by
  name beside PlateSmith's own; the preview shows them from the addon's samples. **Test values** gets a box for each
  such addon's yes/no fact, to try your rules on it. For addon authors: `RegisterBarSource`, `RegisterIconSource`.

### Changed

- **The threat settings live in Studio › Settings › Modules › Threat.** Your role (**This character tanks**, now in
  one place, with whom you are treated as now), **Threat colours** (from Behaviour & display, which keeps a link),
  **Threat text & window colours**, the **Spotlight** and the **Threat windows**: the same settings and values as
  before, on one page you can open in combat. The threat windows' **Threat window settings...** opens it at Threat
  windows. Chat says once where they went.
- **Game Options › AddOns › PlateSmith › Threat** (and each module's page there, such as **QuestieDB**) is now a
  short page saying where its settings are, with an **Open in Studio** button. **QuestieDB**'s switches and status
  are in Studio › Settings › Modules › QuestieDB.

- **Refreshed looks for new profiles.** Each look's enemy plates (Profile › **New from preset** and the first-run
  look cards) now match their card and are calmer: the name in a warm white, the level in gold (before the
  name, or where the look puts it), a slim cast bar without a border and with the spell's icon inside it, and
  what shows only in a fight (the elite and quest marks, auras, combo points) smaller. Bold's threat % sits
  unboxed under the bars and its marks are back beside the bar; Tank's threat lead is small and unboxed; Healer's
  enemy plates dim only while you target another mob; Compact's cast bar takes the cast colour. Names are 10 to
  12 pt (most looks' were 14) and easy to read: Minimal's is 11 pt over a 100 x 8 bar, Compact's 11 pt inside a
  100 x 12 bar with 11 pt cast text and 10 pt threat text, Sleek's and Healer's 10 pt. Blizzard's level box is
  exactly as tall as the health bar beside it and centred on it, on every plate type, as on Blizzard's own plates,
  with the enemy level 10 pt. Combo points show only while you have some (no empty row). The friendly plates
  follow: their names are the enemy name's size where the look shows full friendly plates (Healer 10 pt) and 1 pt
  larger where it shows names only (PlateSmith, Classic, Bold and Tank 13 pt, Minimal and Compact 12, Sleek 11),
  with the level in the look's gold (Friz Quadrata, as on its enemy plates) and the guild line at least 9 pt
  (Sleek's 10); Blizzard's keep Blizzard's 12 pt. Compact shows no level on friendly names either, and its
  friendly players' PvP and relationship icons sit beside the name instead of above the bar's corners. Blizzard's
  friendly players' bars take their class colour, as on Blizzard's own plates (the name stays white, but a
  PvP-flagged ally's name is Blizzard's green beside the faction icon; the bar keeps the class colour). Each look
  has an elite, rare and boss mark of its own (below). The looks'
  smaller aura rows leave room for their countdowns, so neighbouring times ("2m", "15m") never run together: a row
  of small icons has a wider gap, and the smallest (12 px buffs) a 7 pt countdown. Only profiles
  you make from a look from now on get them: your existing profiles, including ones made from a look, keep their
  look exactly.
- **Each look's own elite mark.** A profile made from a look now marks elite, rare and boss enemies in a style that
  suits it (Studio › Elite / rare mark › Style): **Classic** the classic gold or silver dragon round the level at
  the bar's right end (its name sits a little higher, clear of the dragon); **Sleek** the level's suffix (**60+**,
  **60R**, **60R+**, **??** in red for a boss); **Bold** and **Healer** a gold or silver frame round the health bar
  (Bold's name, cast bar and raid mark sit a pixel or two further out, clear of it); **Tank** Blizzard's icon at its
  full 18 px left of the bar; **PlateSmith**, **Minimal** and **Compact** a small icon right before the name
  (Minimal now shows it, with its raid mark after the name); **Blizzard** keeps Blizzard's icons. Your existing
  profiles, including ones made from a look, keep their mark.
- **A PvP-flagged ally's colour goes on the health bar.** With PvP icon › Display on **Colour and icon** (or
  **Colour**, until now "Name colour"), a flagged ally's full plate turned both the name and the health bar green.
  Now the bar takes the colour and the name keeps its own (its social or class colour), so a group or guild member
  still reads as one. Names-only plates, and full plates whose bar has a colour of its own (a Custom colour, a
  colour rule that always applies such as the Healer look's blend, or class colours with **Colour social
  relationships** off, as on the Blizzard look), colour the name instead. This applies to your existing profiles
  too. The swatch is now **PvP colour**, Studio's preview shows the same, and the Blizzard look uses it in place of
  its extra name rule (its white name rule now skips flagged allies).
- **Tank threat colours: Other tank has it is teal.** Its pale blue was easy to mistake for **Holding**'s
  periwinkle; new installs and new profiles (and every look) now use a teal. Your existing profiles keep their
  colours, which you can change in Threat colours.
- **A text box as tall as its bar.** Style › Box behind › **Height** has a new choice, **Match its parent**: the
  box is as tall as the part the text is pinned to (the health bar beside a level, with its border), centred on
  the text, with Padding only at its sides; it never gets shorter than the text and Padding. **Fit the text**
  stays the default, so your profiles look as before. Blueprints that use it are `!PSB4!`.
- **A new rule starts as "low health turns red".** **+ Add rule** used to start with "tagged → grey", which plates
  already do on their own. It now starts as `health.percent < 35` in red (or half see-through for parts without a
  colour); change the condition and colour to whatever you need.
- **Three slash commands.** `/ps help` (and this page) lists `/ps`, `/ps diagnose` and `/ps console`; everything
  else is in Studio and Settings. The other commands still work. `/ps quest on|off` and `/ps threat on|off` are
  gone: they said "Updated" but changed nothing (use Studio › Settings › **Show on plates**).
- **Fewer rule presets.** Rules › Presets no longer offers the two **Threat colours** presets, **Cast colours by
  interrupt**, **Fade non-targets** or **Fade out of range**: Threat colours, the cast bar's **Colour by
  interrupt** and Settings › **Fading** do those jobs (and Colour by interrupt keeps working where the game hides
  the answer). Rules you already made from them stay and keep working.
- **Importing a look keeps who draws your plates.** A Blueprint import no longer changes **Who draws the plates**:
  that depends on the nameplate addons you have, not on the look (importing someone's "PlateSmith" beside Plater
  drew two sets of plates). Exports are unchanged.
- **Friendly plates in one place, per plate type.** Studio's **Plate settings** on the **Players** and
  **Friendly NPCs** tabs now start with **Friendly plates**: **Show as** (Names only, Full plates or Blizzard
  plates), which each tab now chooses on its own; on Players, a line saying whether **Hide unstyled names** is on,
  which opens it in Settings › Names; **Show in**, the same switches as Settings › Where plates show; and a button
  to the **Dungeons & raids** design, which now has **‹ Back to World design** at the top. Your profiles keep their
  one choice for both until you change one. Settings › Behaviour & display no longer has **Friendly units**; a
  button there opens the new section, and searching for it finds it. **Hide unstyled names** (no longer "outdoors"
  in its name) stays in Settings › Names, as it changes the game's own name settings for friendly players and
  their pets, guardians, minions and totems; its help now says what it hides, when, and that PlateSmith keeps it
  so even if another addon turns those names on. The
  preview's switch reads **Editing: Names only | Full plate** and follows Show as at once; its gold mark for the
  layout your plates use no longer disappears after Studio refreshes. Blizzard's own names-only box in the
  Dungeons & raids design is now **Blizzard: names only in dungeons**, so it is not mistaken for Show as.
  Blueprints carry each plate type's choice (`!PSB4!` only when Players and Friendly NPCs differ).
- **A tagged mob's health bar is grey, as on Blizzard's plates.** A new health bar option, **Grey when tagged by
  others** (Studio › Health bar), turns an enemy's bar grey while another player or group has tagged it, so you
  can see at a glance that it gives you no credit. It wins over Threat colours; a colour rule on the health bar
  still wins over it. New profiles and every look have it on, with the **TAGGED** word turned off (it stays in
  the parts tree: its eye brings it back). Your profiles keep their TAGGED word and colours; the Health bar
  inspector offers **Grey bar instead** to switch. The **Grey when tagged** rule preset is no longer offered;
  rules you made from it keep working. Where the game hides whether a mob is tagged, the bar keeps its colour.
  Studio's Test values › **Tagged** shows the grey bar.
- **Cast bar icon inside the bar.** Cast bar › **Icon** has a new choice, **Inside**: the spell's icon sits inside
  the bar's left end, as tall as the bar, with the spell's name after it, so nothing sticks out beside the bar.
  It works on names-only casts drawn inside their bar too (under a slim bar, it stays beside it). Blueprints that
  use it are `!PSB4!`.
- **Quieter placeholders in Studio.** The dashed outlines for hidden parts (a cast bar while Casting is off, a
  turned-off Target of target) are faint grey at rest, light up when you point at or select them, and never
  cross a part that shows.
- **Stacking & distance is always editable.** There is no **Manage Blizzard's plate stacking** box to tick first:
  every Blizzard setting on the page can be changed at any time. A setting you change is PlateSmith's from then
  on (marked, saved with your profile, and put back as it was when you log out, as before); the ones you leave
  alone stay the game's own and just show its current value, even when you change it in Blizzard's options while
  the page is open. The arrow beside a changed setting gives it back to the game. **Reset Blizzard's stacking to game defaults** stays, and now also gives every setting back. If you
  never ticked the old box, nothing changes: PlateSmith still sets none of these (values a profile kept while it
  was off are cleared, and **Match frame size to layout** and **Stack only in combat** are off, as they did
  nothing then). If you had it ticked, every setting you had stays applied. `/ps diagnose` says how many of
  Blizzard's settings PlateSmith sets.
- **View distance is shown but can't be changed.** The game keeps nameplates to a fixed range (about 60 yards)
  and has ignored this setting for a long time, so PlateSmith no longer writes it (not from the slider, a preset or
  Reset); the row is dimmed and says why. A value your profile kept stays saved but unused.
- **Stack plates and Show offscreen plates.** On WoW Forever, Blizzard's options stack enemy and friendly plates
  separately and can keep plates of units off the screen at its edge; Stacking & distance now has both (where the
  game has them) in place of the old note that one setting stacks both. **Stack plates** works like Blizzard's own
  Stack Nameplates: a dropdown that reads the units that stack ("Enemy Units, Friendly Units", one of them, or
  None) and opens a list where you tick **Enemy Units** and **Friendly Units** separately. Ticking one never
  changes the other, and the arrow beside the row gives both back to the game. The presets turn enemy stacking on
  there, and **Stack only in combat** stacks enemy plates. `/ps diagnose` also lists every nameplate setting the
  game has, with its value and default.
- **Developer commands are no longer in the download.** `/ps status`, `/ps perf`, `/ps testname`,
  `/ps console sample`, `/ps fetch` and `/ps playerprobe` were test tools for PlateSmith's developers; typed now,
  each answers "That's a developer command (PlateSmith_Dev)." and does nothing. Everything a player needs is still
  under `/ps`, `/ps diagnose` and `/ps console`: the threat windows' sample data is Studio › Settings ›
  Modules › Threat › Threat windows › **Show sample data**, and the live Performance tab is in `/ps diagnose`'s window. `/ps scale`, still
  unlisted, now says what it changes: the Enemies' World design's scale only.
- **Automatic switching: scenarios and delves are open world.** Settings › Profiles › Automatic switching used
  to switch to your **Dungeons** profile in a scenario or delve, while Studio's designs treat those places as open
  world, so that profile then drew its World design anyway. Both now read the place the same way: a scenario or
  delve uses your **Open world** rule (or keeps the profile you have). Your rules are unchanged and still apply in
  dungeons, raids, battlegrounds and arenas. The section also says when to use a design per place instead.
- **Clearer labels where two settings looked alike.** The Threat page's palette section is now **Threat text &
  window colours** and says the colours on health bars and names are Studio's **Threat colours**; Studio's
  **Colour-blind friendly** says it changes Studio and the preview, never the plates. **Warn when you lose a mob
  you tank** moved from Show on plates into **Threat colours**, below Apply to, where it is unavailable (and says
  why) while **Health bar edge** gives the edge the threat colours. Friendly plates' **Show as** says Blizzard's
  plates still show and that **Show in** hides them; **Quest icons** says where the QuestieDB companion's options
  are; the combo points' **Position** says Placement is off while the row sits on the bar. Nothing you saved
  changes.

### Fixed

- **Threat windows snapped together follow the damage meter together.** Docking a window to Blizzard's damage meter
  (by dropping it there or from Follow damage meter), or the meter moving, took that window along but left the
  windows snapped to it behind, overlapping or hanging off. They now move with it, each keeping its own size and
  staying on the edge it shared, as when the group is dragged. A locked window stays put, and a group with a Rescue
  window holds still in combat and follows when combat ends.
- **Threat text on another addon's plates follows the fight.** With Who draws the plates on Automatic beside another
  nameplate addon (or Blizzard, with PlateSmith extras), the threat text PlateSmith adds was written when the plate
  appeared and when your target changed, and could then stay as it was. It now updates as the fight goes, as on
  PlateSmith's own plates.
- **The PvP faction icon is full size.** A PvP-flagged friendly player's Alliance, Horde or FFA icon drew the
  game's whole icon file, in which the emblem fills only a corner, so it showed as a small dot beside the bar or
  name. It now fills its box, about as tall as the name, on full and names-only plates and in Studio's preview. This
  applies to your existing profiles too.
- **Blizzard look: a PvP-flagged ally's name in Blizzard's green.** New profiles promise a flagged ally's name in
  Blizzard's green beside the faction icon, but the Blizzard look drew it white. A profile made from the Blizzard
  look from now on colours it green (Colour and icon, its white name rule skipping flagged allies), on full and
  names-only plates, and the bar keeps the class colour. Your existing profiles keep their look: to get the green on one made from the Blizzard look,
  add a rule to Players › Name, `pvp` → colour green, below the white one (or make the profile again from the look).
  The other looks already show it.
- **Where plates show: Players works on WoW Forever.** Its switch is named differently there
  (`nameplateShowFriendlyPlayers`), so unticking Players in a place did nothing. It now uses whichever switch the
  game has.
- **Friendly player plates can be clicked again.** With the game's "friendly players: names only" option on, the
  game takes away a friendly player plate's click area, so PlateSmith's plates for friendly players (names only or
  full plates) could not be clicked to target them. Outside dungeons & raids, while PlateSmith draws friendly
  players, it now keeps that game option off (you see PlateSmith's plates either way; **Clicking** › Friendly players
  › Click through turns it on instead, above). Your own setting comes back
  when you show friendly players as Blizzard's plates, turn PlateSmith off or log out; in dungeons & raids,
  **Dungeon friendly names only** still decides. If you or another addon turn it on meanwhile, PlateSmith gives that
  back later and turns it off again. If the game closes without a logout (a crash), your own setting comes back at
  the next login instead of staying off, as long as you had logged out normally once since PlateSmith first changed it.
- **Settings given back during combat are not forgotten.** Giving a **Stacking & distance** setting or one of the
  interact key settings (Objects & interacting) back to the game during combat, then setting it again before combat ended (switching
  profiles, Revert, turning PlateSmith off and on), could record PlateSmith's own value as yours, so logging out left
  PlateSmith's value instead of your own. Your value now waits with its record until combat ends.
- **No blocked-action warning from Escape in combat.** With Blizzard's Options open over Studio (or a PlateSmith
  menu, the first-run setup or the Blueprint window's preview open), pressing a key in combat could raise "PlateSmith
  has been blocked from an action only available to the Blizzard UI". PlateSmith no longer tries to keep a key in
  combat. Opening Blizzard's Options also no longer moves other addons' windows in the list Escape closes.
- **Friendly NPCs say when the game hides their plates.** With the game's own switch for friendly NPC plates off,
  the green names over NPCs are the game's floating names, which cannot be clicked. Studio › Friendly NPCs › Plate
  settings › Friendly plates now says so, with a button to **Where plates show**, which says where to turn them on.
- **Stacking & distance follows changes made outside PlateSmith.** A setting PlateSmith doesn't set (Target scale,
  say) now shows the value you choose in Blizzard's options or another addon, and the open page updates by
  itself; PlateSmith never writes it. A setting it does set stays PlateSmith's, and chat says once that it was
  put back: the value you chose outside becomes the one PlateSmith gives back when you log out or click the
  row's arrow, instead of the older one it first found. Before, logging out could undo your newer choice. On
  another character (the game keeps settings like Target scale per character) PlateSmith no longer puts back a
  value it recorded on the last one. Values the game holds outside PlateSmith's slider ranges show as they are
  (WoW Forever's -100000 yd for Farthest opacity from read 0 yd), and the preview's other plates no longer go
  invisible where Non-target opacity is -1 ("not used").
- **Styled text keeps its colour.** A part with its own font or outline (Style › Font, as several looks give the
  name and guild line) could lose its colour and draw white: on your plates the guild line and the grey TAGGED
  word, and in Studio's preview a friendly name (green, or its class colour) and guild line. Setting the font took
  the font's own white with it; the text now keeps its colour. This applies to your existing profiles too.
- **Switching profile by dual spec works on WoW Forever.** Settings › Profiles › Automatic switching said "This
  client has no specializations to switch by". It now offers **Primary talents** and **Secondary talents**, even
  before you learn dual spec, so you can set them up ahead.
- **Plates appear faster right after logging in.** After a login, a `/reload` or a loading screen, names could
  wait several seconds (up to 8 in a busy city) before PlateSmith drew them, while the game ran slowly. For the
  first seconds PlateSmith now spends more of those slow frames drawing them, so the first wave shows within a
  second; spare plates are made straight away afterwards (extra ones for a crowd in cities and instances). Once
  the game runs normally the usual limits that stop hitches in cities apply again. `/ps diagnose` shows the wait
  (`addQueue.loginBurst`).
- **Less memory in quiet zones and when changing profiles.** In a quiet zone PlateSmith kept spare plates for a
  crowd that was not there and made garbage for the game to clean up (about 2 MB a minute with no plate in
  view). It now makes the extra spare
  plates only in cities and instances, or when a crowd arrives (in the open world it makes the usual number); its
  every-frame plate updates rest while no plate is in view and nothing waits to be drawn, instead of running every
  frame with nothing to do; it no longer reads the quest log for quest marks while no plate is showing (with the
  QuestieDB companion, every quest's objectives on every quest log change); and a mob coming back into view, or
  the mouse passing over one, no longer reads its tooltip and quests again until your quest log changes. Plates,
  quest marks and spares look and behave as before. `/ps diagnose` now shows PlateSmith's memory before and after
  a full clean-up (`performance.memory.retained`: what it keeps and what was waiting to be cleaned up), an
  estimate of what its plates hold (`performance.spares`), and which part of the plates' every-frame work made
  garbage (`performance.memory.frameSteps`). Making a profile from a preset (Profile › New from preset) made about
  5 MB of garbage each time with Studio open; it now makes about half, as it loads and draws the new look once
  instead of the defaults first and Studio redraws once instead of up to three times. Switching profiles makes
  about half what it did, deleting one almost none, and making, loading and deleting profiles again and again no
  longer adds to what PlateSmith keeps. Editing in Blueprint Studio made the most garbage of all: every change
  redrew all of Studio, about 0.7 MB each time, including Settings pages and parts' rows you could not see. A
  change now makes a small fraction of that (about a twentieth), as Studio keeps what did not change and refreshes
  a Settings page or a part's rows when you open them; picking a part, changing the plate type tab and Revert (now
  one redraw, not two) make far less too. Your profiles, Studio and the plates look and behave as before. `/ps
  diagnose` names these actions too (`performance.memory.actions`: New from preset, switch, Save, Revert, Delete,
  Studio's redraw and opening).
- **Less memory churn.** PlateSmith made less garbage for the game to clean up: plates no longer make new
  tables when a cast bar or aura row comes and goes in combat (about 1.2 MB a minute with a dozen casters), and
  quest marks read each kind of quest mob's tooltip and each quest's objectives once per refresh instead of
  once per plate. `/ps diagnose` lists what allocates most (`performance.memory`).
- **Blizzard's name over a PlateSmith plate.** When the game gave a nameplate to a new unit before telling
  PlateSmith the old one had gone, the late notice could take the new unit's plate down and leave Blizzard's
  own large name showing until the unit left view. `/ps diagnose` now counts the nameplates PlateSmith draws
  against the game's, and any showing Blizzard's plate (`context.ownership`).
- **Big Blizzard names over friendly players in cities.** With **Hide unstyled names** on, the game's large
  floating names could still show over friendly players in a crowd: the game makes at most 40 nameplates, and
  writes its own name over everyone past them when its friendly player names are on. PlateSmith turned those
  names off only at login and loading screens, so anything that turned them back on later (another addon's
  city preset, such as Hyperframe's, or the game's Names options) won until the next loading screen. They now
  stay off while the option is on, outside dungeons & raids; what turned them on gets its choice back when you
  turn the option off or log out. Players past the 40 then show no name. The option's help says what it does.
- **`/ps diagnose` ownership counts.** `context.ownership` showed none of the game's nameplates as drawn by
  PlateSmith (`owned` and `shouldDraw` 0) while it drew them all, because the game hides which unit a nameplate
  belongs to; it now matches each nameplate to the plate PlateSmith drew on it. It also shows whether Hide
  unstyled names is being kept (`worldNames.watch`).
- **`/ps diagnose` "script ran too long".** With Keep history on and several saved captures, opening the report
  could stop with this error; the saved captures are now counted once instead of on every refresh.
- **`/ps diagnose` full report scrolls.** The Report tab (Show full report) opened with the whole report
  selected and the keyboard in it, and the mouse wheel could not move it far. It now opens at the top with
  nothing selected and the keyboard free; the wheel scrolls it from anywhere over the text, as does the scroll
  bar. **Select all** selects it for Ctrl+C. The Summary still opens selected, and **Copy full report** still
  selects the one-line code.
- **Closing Blizzard's Options keeps PlateSmith open.** Closing the game's Options (its Close button, the x or
  Escape) also closed Blueprint Studio and any other PlateSmith window. They now stay as they were. While the
  Options window is open, Escape closes the PlateSmith window over it first, then Options. Studio's search and
  Profile › **Switch automatically...**, which open a setting in Blizzard's Options, step Studio aside without
  asking about unsaved changes and bring it back when you close Options.
- **Threat rules without Colour by threat.** On mobs whose threat the game hides (in dungeons and raids), a
  colour rule on threat (`threat.holding`, `tanking`, `threat.other`, `threat.offtank`, and rules from the old
  **Threat colours (tank)** and **(DPS/healer)** presets) did not apply; with Colour by threat on, Threat colours painted the bar
  instead, so the rule only seemed to need that box. The game now picks the rule's colour from its hidden answers,
  as it does for Threat colours, with the box on or off, and a rule's colour still wins over Threat colours.
  `threat.losing` and `threat.pulling` stay unknown there.
- **Threat colours for a raid tank.** In a raid, a mob that was targeting you while the game hid its threat
  could read as held by someone else (a tank saw **Another tank has it**), because your raid slot was not
  recognised as you. It now is; when the game will not say who you are, nothing is guessed.
- **Target highlight Off means off.** With Plate settings › Target highlight › **Off**, your target's health bar
  no longer gets PlateSmith's gold edge either (a threat-coloured edge still shows). Profiles you already have
  keep the gold edge they had with Off; Target highlight then says so and offers **No gold edge**.
- **Tank warning follows the profile's role.** "Warn when you lose a mob you tank" now uses the same role as Threat
  colours. Only an older profile or Blueprint that always colours as DPS (Threat colours shows "This profile always
  colours as: DPS & healer") notices: it no longer gets the tank's red edge. **Follow my role** puts it back.
- **No empty boxes.** A text part with **Show a box** (the Tank look's threat lead before 1.3.0, a boxed threat
  text or level) drew a small hollow square beside the health bar while it had nothing to say, such as out of
  combat. The box now shows only while its text does.
- **Neutral mobs are in the Tank window.** A yellow mob you can attack (a Snapjaw, a quest mob) was left out of
  the Tank window until it was in combat, while red ones were listed idle. It is now listed the same way: IDLE
  until the fight, below the mobs you are fighting. Critters and pets are still left out, and so are friendly
  units and objects. Targeting it, the Threat meter measures it, and in combat its plate colours by threat and
  shows threat text as a red mob's does.
- **Studio's preview colours as the plates do.** The preview worked out rules and colours with its own copy of
  the plates' logic, and they had drifted: an enemy's bar and name were a different red, a friendly NPC's bar a
  different blue, your own sample ignored the group colour you set, and a rule whose condition is only spaces
  applied on the plates but not in the preview. **Test values** and **Preview as if every condition is true** now
  use the plates' own rule evaluator and base colours, so for the same facts the preview shows what a plate shows.
  The friendly player sample is you, in your group and PvP-flagged, so its PvP colour goes on the bar or the name
  as on a plate, and rules on `pvp` and `ingroup` hold for it. A part a rule hides still shows faintly in the
  preview, so you can select it.

## 1.2.0

A big feature update: a design for each kind of place, an Enemy players tab, Where plates show, a soft target
glow, combo point styles, threat colours without rules and Blueprint chat links. Your profiles carry over and
look the same as before; the Enemies' old **Dungeon** layout is now their **Dungeons & raids** design, unchanged.

Going back to 1.1.1 keeps your designs, Enemy players, Where plates show and threat colour settings for when you
update again, but 1.1.1 draws every place with your World look. A few new looks are lost for good there: the soft
glow becomes the gold edge, the new combo point and text box styles and the Blizzard modern bar texture go back
to 1.1.1's, and Studio's colour-blind **Off** goes back to following your plates.

Blueprints that use nothing new start `!PSB3!` and still import into 1.1.1; ones that use a 1.2.0 feature start
`!PSB4!` and need 1.2.0.

### New

- **A design for each kind of place.** Studio's **Design:** menu, under the plate tabs, starts at **World**; **+ Add
  separate design** gives a plate type its own look for **Dungeons & raids** (Enemies), **Battlegrounds & arenas**
  or **Cities & inns** (Cities & inns can start **Light**: no buffs, debuffs or casts under names). Plates switch
  design as you enter and leave each place.
- **Designs follow World.** A design keeps World's look except what you change in it. A gold diamond marks each
  setting and part a design changes; point at it for World's value or **Reset to World**. The chip beside the
  menu says what the design follows (**Follows World · 3 changes**). Your old Dungeon layout arrives as a **Full
  copy**; its chip offers **Follow World where they match...**.
- **Enemy players.** Studio has a fourth tab. Hostile players use your Enemies plates until you press **Customise
  for enemy players**; from then on they follow the Enemies everywhere except what you change on that tab. Where
  the game hides whether a unit is a player, its plate is drawn as an NPC.
- **Where plates show.** Studio › Settings › Behaviour & display › **Where plates show** has a box for each plate
  type in each kind of place: untick Enemies in Cities & inns and enemy plates hide in town. It uses Blizzard's
  own show/hide switches (so in dungeons it covers Blizzard's friendly plates too), waits for combat to end, and
  puts the switches back when you log out. Blueprints leave it out.
- **Soft glow behind.** Your target can have a soft cyan cloud of light behind its plate: Studio › **Plate
  settings** › Target highlight › **Highlight** › **Soft glow behind**. It wraps the health bar and any name,
  power bar or cast bar within 12 px of it, is as wide as a long name, and on names-only plates sits behind the
  name line and guild. Choose its colour (custom, class, reaction or **Threat**: your threat colour on that target
  in combat), size, opacity, offset and **Pulse slowly**.
- **A target highlight for each plate type.** Enemies, Players, Friendly NPCs and Enemy players (and each of
  their designs) can each have their own highlight; **Copy to all plate types** shares one. Until you change one,
  every type keeps the look you have now.
- **Combo point styles.** The Combo points part's **Style** has a **Shape** (blocks, round coins, squares,
  diamonds, bar segments or Blizzard's art), a **Position** (where placed, on the health bar's bottom edge, or
  above or below the bar), **Class colour**, a **Glow**, **Fit to bar width** and **Show row** (Always, In combat
  or with points, Only with points). Existing profiles keep their blocks.
- **Combo points on new profiles.** Gold round coins sit under your target's cast bar and move up under the health
  bar while nothing is cast; each look preset has its own style. Studio's Test values have a Combo points slider.
- **Colour by threat.** Studio › Settings › Behaviour & display › **Threat colours** colours an engaged enemy's
  health bar and name (and, if you like, its edge) by who holds it, in tank colours (Holding, Losing it, Other
  tank has it, Someone else has it) or DPS and healer colours (Safe, Pulling, Aggro), with no rules needed. It is
  on for new profiles and off for existing ones; a colour rule on a part still wins.
- **Blueprint chat links.** Export's **Link in chat** puts `[PlateSmith: <profile> #<id>]` in your chat box.
  Other PlateSmith 1.2.0 players click it to open their Import with your Blueprint filled in; nothing applies by
  itself. A link lasts an hour while you're online, and links pause while the game restricts addon messages
  (instance combat, encounters, keystones, PvP matches). `/ps fetch <Name-Realm> <id>` asks for one by hand.
- **Review a Blueprint before importing.** Import has **Paste** and **Review** tabs. Review shows the sections
  beside a small Studio stage with each design the import would change and what changes; **Yours now** compares
  with your plates. Nothing changes until **Import selected** (then Save).
- **Blueprints from newer versions import.** Settings a later PlateSmith adds are skipped instead of refusing the
  whole Blueprint, and chat names them.
- **First-run setup.** On a new install, Studio first asks how you play this character (**Tank**, **Healer**,
  **DPS** or **Hybrid**), which sets This character tanks and turns Colour by threat on, then offers the nine
  looks with a sketch of each. Skip or Escape at either step; it shows once.
- **A Blizzard look.** **New from preset** has **Blizzard**: Blizzard's modern plates, drawn by PlateSmith so you
  can change anything. It brings two choices for any design: the **Blizzard modern** bar texture and a **Rounded**
  box behind text.
- **Studio extras.** View › **Sample name** shows the preview's name in Chinese, Korean or Russian, and View ›
  **Model** puts you, your target or a creature behind the preview plate. `/ps testname <text>` shows text as your
  target's name. Names-only casts can show their text **Inside the bar** (Settings › Behaviour & display › Names ›
  **Name cast text**).

### Changed

- **Plate settings.** The parts tree's top row is now **Plate settings**. Its **Target highlight** section holds
  what was Settings › Behaviour & display › Target: "Selected target" is now **Highlight**, with **Off**, **Gold
  edge** (steady or pulsing) and **Soft glow behind**. Your choice is kept.
- **PvP-flagged allies in Blizzard's green.** New profiles show a flagged ally's name in Blizzard's green as well
  as the faction icon. Studio › Players › **PvP icon** has a **Name colour** and a **Blizzard green** button;
  existing profiles keep their colour.
- **Export is share-code only**, with **Link in chat**. Import still reads Blueprint JSON.
- **Studio's Layout switch is gone.** The Design menu replaces it; Blizzard's dungeon names are Players' and
  Friendly NPCs' **Dungeons & raids (Blizzard)** design.
- **Smoother sliders.** Dragging a Studio slider no longer redraws every plate at each step: your plates catch up
  a few times a second and in full when you let go, while the preview follows at once.
- **More room for the preview.** One row holds the design, its chip, the eye and **View**; **Plain dark
  background** is in View and **Test values** sits on the preview's foot, in plain words (**Tagged**, **You
  tank**...).
- **Placeholders for hidden parts.** Studio's faint placeholders for hidden parts (a cast bar while Casting is
  off, a hidden combo row) are now dashed outlines behind the plate instead of overlapping it.
- **Clearer names.** **Who draws the plates** (Automatic, PlateSmith, or Blizzard, with PlateSmith extras),
  Placement's **Stick to**, **+ Add › Custom part**, and the **Dungeon** look is now **Compact**.
- **One tank choice.** Threat colours use **This character tanks** (Settings › Threat). The two threat rule
  presets moved under Rules › Presets › **Advanced**.
- **Studio's colour-blind friendly** follows your plates' colour-blind palette unless you pick On or Off.

### Fixed

- **A druid in Cat Form is no longer coloured as a tank.** With This character tanks on Adaptive, Cat Form, caster
  form, Moonkin and Tree of Life now always count as not tanking, even with a specialization the game calls a tank,
  and they replace an earlier Bear Form at once: in a group that lists you as DPS you get the DPS & healer colours.
  Bear Form still makes you the tank even when the group finder lists you as DPS or Healer, and a group Tank role
  still counts first; warriors and paladins still go by Defensive Stance and Righteous Fury. **Always** and **Never**
  still win over everything.
- **See whom threat colours colour you as.** Studio's Threat colours and Settings › Threat › Your role now say
  "Colouring as: Tank (Bear Form)", "DPS (Cat Form)", "DPS (group role)" and so on, with a small legend of what each of that role's
  colours means (tank: holding, losing it, another tank has it, someone else has it; DPS & healer: safe, pulling,
  aggro). A threat window's title tooltip says the same, and each row's tooltip adds the legend. `/ps diagnose`
  reports the role's reason and the same line.

- **Adaptive tank role in group-finder groups.** A bear tank given a DPS or Healer role by the group finder saw
  the mobs it held as LOOSE. What you're doing now (bear form, a tanking stance, Righteous Fury) now counts before
  that role, and shifting in or out of bear in combat changes it at once; a group **Tank** role still counts first.
- **Threat colours on every plate.** A mob you held but weren't targeting could lose its threat colour while its
  text showed 100%. Plates now read the game's own threat state for each mob, as the threat text does.
- **Enemy buffs in combat.** When the game hides an enemy's buffs from addons, the Buffs row now shows them through
  the game's own aura display, as Debuffs already did.
- **Aura countdowns** count like the game's own aura timers (28, not 29) and switch to minutes at 60 seconds.
- **Combo points after Cat Form.** Combo points stay on your target when a druid leaves cat form; only the filled
  points show out of cat form.
- **Combo points on the bar's edge** no longer hide under the cast bar.
- **Studio's scroll bars** follow the pointer when dragged on every game build, and a click on the track moves a
  page.
- **Busy cities.** New plates are built over two frames, spare plates are made ahead in quiet moments, and
  entering a city restyles only the plates whose design changes, so flying into a capital hitches far less.
  Blizzard's own plate no longer flashes up first with a large name.
- **Studio in busy places.** Studio's first open after logging in could stop with "script ran too long"; it now
  builds less up front.
- **Lua errors on target changes** when the game hides a plate's size from addons.
- **Chinese, Korean and Russian names** show properly with a chosen font.
- **Hostile players who aren't PvP-flagged** get PlateSmith plates when the game hides whether they're friendly.
- **Smaller fixes:** the preview's grid, outlines and snap guides are sharp at any zoom; Targeted by's Initials
  can be turned back on; the names-only cast icon sits level with its bar; Where plates show's headers no longer
  break inside a word; and a failed Blueprint import can no longer put colours or links into chat.

## 1.1.1

Your profiles and Blueprints carry over and look the same as before.

### New

- **Display: one place for every text's look.** Every part that draws text has a **Display**
  section in Blueprint Studio: first what it shows, then always **Font**, **Font size**, **Font
  style** and **Shadow**. **Style** now holds only looks (the box behind text, bar textures, pips
  and badges).
  - **Font size** is in points. Left on **Auto**, a text keeps today's size; move the slider to set
    your own, tick Auto to go back.
  - Cast bar text, quest progress, the combo count, Targeted by initials and buff/debuff countdowns
    now take a font, size and style too.
- **Bigger, tidier countdowns on buffs and debuffs.** Select Buffs or Debuffs and change
  **Display › Font size**. Countdowns now sit centred on the icon so "15m" and "2m" line up;
  **Text position** offers Bottom centre, Centre, Top centre or the old corner. Studio's preview
  shows sample countdowns.
- **Hide permanent auras.** A buff or debuff row's **Display › Permanent** hides auras without a time
  limit (passives, Devotion Aura, Find Herbs), so the row shows what will run out. Off by default.
  In dungeons, where the game keeps aura times private, every aura still shows.
- **Dungeon friendlies in Studio.** In dungeons Blizzard draws friendly plates itself. Studio's
  **Dungeon** layout now shows just that: on Players and Friendly NPCs, one part, **Name (drawn by
  Blizzard)**, with everything the game allows (change Blizzard's names, where, names only, class
  colours, font, size and style) and a preview of the name.
  - The **Settings › Dungeon friendlies** page is gone. Its options are in that Studio view,
    **Readable Blizzard names outdoors** is in Behaviour & display › Names, and **Test editable
    overlay** is in Settings › Experimental. Search finds each in its new place.
  - The overlay test never drew (the game blocks it), so it is turned off once on updating; a chat
    line says so if it was on. Turn it back on under Experimental to try it.

### Fixed

- **Studio opening invisible** after a reload, mostly in dungeons or combat. Studio now builds each
  part and Settings page when you first open it, so it opens quickly; if it ever fails, it closes
  and says to /reload.
- **Dungeon friendly names at different sizes**, or resetting in combat. Blizzard name size now
  applies to every name, straight after each plate appears, and keeps the game's own font flags.
- **Countdowns in dungeons** keep your font, size and position on new auras.
- **Error floods:** "Box behind" text in Orgrimmar and dungeons ("attempt to perform arithmetic on
  local 'width'"), and "blocked by secret aspects" from aura countdowns in dungeons.
- `/ps diagnose` no longer lists a known, harmless lookup the game refuses as a problem.

## 1.1.0

A feature update. Profiles from 1.0.3 carry over; nothing needs setting up again.

### New

**Blueprint Studio**
- **Quick layout**: select the tree's **Plate** row and pick what goes at the Top, Bottom, Left,
  Right or Centre of the health bar (or the name on names-only plates). Picks are ordinary
  placement, so everything stays editable.
- **Search settings**: find any setting by name, help text or page, with results shown right in the
  page so you can change them there. Matches on Blizzard's Settings pages and Studio parts are
  listed under **Elsewhere**.
- **Text size**: one slider (80% to 150%) scales every PlateSmith text on every plate type.
- Each rule has an **on/off box**, so you can turn a rule off without deleting it.
- The footer shows PlateSmith's own CPU time per frame; click it for the Performance view.

**Plates**
- **Combo points** on your target's plate (rogue, or druid in cat form), on by default for enemy
  plates. Style the pips in Studio; custom text can show `{combo}`.
- **Quest progress** beside the quest mark, such as **3/8** or **38%** (select the Quest marker:
  **Progress**). Custom text: `{quest.progress}`, `{quest.percent}`.
- **Fade non-targets** and **Fade out of range** (Settings › Behaviour & display › Fading), each with
  its own opacity. Both are ordinary rules you can adjust per part, and Rules presets too. New rule
  conditions: `hastarget`, `inrange`.
- **Colour by interrupt** (Cast bar): one colour when you can interrupt and your interrupt is ready,
  one when it is on cooldown or you have none, one when the cast cannot be interrupted. Also as the
  `interruptReady` condition and a rule preset.
- **Draw casts above other plates** (Cast bar, off by default) so a casting plate is not hidden behind
  its neighbours.
- **Casts on names-only plates** (Settings › Behaviour & display › Names, off by default): a slim
  cast bar under a friendly name, so you see "Opening", "Mounting" or Hearthstone. There is an enemy
  option too, for enemy layouts with no health or cast bar.
- **Targeted by** badges (+ Add › Icons, off by default): a small class-coloured badge for each party
  member targeting an enemy (in a raid, its tanks). Hidden where the game will not say.
- The focus's plate can be drawn on top, like your target's.
- Opt-in **Blizzard name size** for friendly names in dungeons (Settings › Dungeon friendlies): one
  size, outline and font for the names Blizzard draws on its own plates, which addons cannot style.
  It changes Blizzard's shared nameplate fonts; turning it off restores them exactly.

**Stacking & distance** (new Settings page)
- PlateSmith can manage Blizzard's plate stacking: overlap or stack, spacing, movement speed, screen
  edges, keeping your target on screen, view distance, scale and fade with distance. Tight, Normal
  and Loose presets, a live preview, and optional combat-only stacking. Off until you turn it on;
  turning it off puts every setting back.
- Plates can be sized to what your layout draws, so stacked plates sit evenly apart.
- **Reset Blizzard's stacking to game defaults**, and **Restore Blizzard nameplate settings** for the
  friendly-name settings PlateSmith changes.

**Profiles**
- **Automatic switching** (Settings › PlateSmith › Profiles): pick a profile per character for the
  open world, dungeons, raids, battlegrounds and arenas, and per specialization where your client
  has them. It waits for combat to end and for unsaved changes, and says in chat why it switched.

**Threat**
- Threat text on plates reads **100%  +145**: your threat % and the signed gap the threat windows
  show. Where the game keeps the numbers private only the % shows. **Threat text** in the Threat part
  also offers **% only** or **Detailed**; custom text gains `{threat.leadpercent}`.
- The last gap read through your target, hover, focus or a boss stays on the plate marked **~**.
  **Keep last gap for** (5 s to until the mob is gone), **Stale gap** (dim, fade with age or grey)
  and **Show gap age** ("~+145  3s") set how.
- Boss units are used for threat in encounters, so a boss's plate can get its full gap even when it
  is not your target.
- Threat windows: **Detach from group** in the right-click menu; **Shift**-drag skips snapping; the
  window or meter you are about to snap to glows; **Target first** keeps your target as the Tank
  window's first row.
- A new **Experimental** page in Settings: soft-target and target-of-target threat reads, a solo
  hover gap, and an outside-group holder row. All off by default; these test what the game allows,
  and `/ps diagnose` reports whether each one worked.

**Performance**
- `/ps perf` opens a live **Performance** view: the client profiler's figures for PlateSmith, plate
  adds by phase, the busiest events and every ticker entry, with **Reset peaks**.
- `/ps diagnose` warns when the slow `taintLog` or `scriptProfile` client settings are on.

### Changed

- **Smoother plates**: new plates appear with much less of a hitch (camera turns in cities, pull
  starts, dungeons). Plates build only the parts their layout uses, a few are prepared ahead out of
  combat, setup is spread over frames, and target changes touch only the two plates involved.
- Threat windows redraw only what changed, and the Performance tab costs little to keep open.
- Larger text on **new** profiles (14 pt names, 11 pt custom text). Existing profiles keep their
  sizes.
- Settings pages are tidier: help moved into tooltips (point at a setting or its **?**), check boxes
  line up like Blizzard's Settings, and sections are evenly spaced.
- **Show on plates** ticks now match Studio's eyes, and the tank's red health-bar edge has its own
  box, **Warn when you lose a mob you tank**.
- Threat windows snap from a little further away (12 px).
- Tank window: **Possible attackers** and **LIKELY** say plainly that attackers are inferred; what
  the game hides shows as unknown (**?**) rather than 0.

### Fixed

- **Threat in dungeons**:
  - Mobs you hold no longer show **LOOSE**.
  - Mob names show instead of "nameplate5".
  - **LOSING** shows when someone is about to pull a mob you hold.
  - Fleeing, feared or stunned mobs keep their holder.
  - Critters and neutral mobs outside the fight no longer fill the Tank window.
- The threat gap no longer vanishes the moment you change target.
- A group member's unnamed pet shows as "<owner>'s pet" instead of "Unknown".
- Quest marks: a mob that still drops an item you need shows the loot bag once its kill objective is
  done, and quest progress shows in dungeons through your target or mouseover.
- Friendly names in dungeons no longer show at two sizes at once.
- Updating from 1.0.3 with threat details off keeps threat parts hidden and turns threat-reading
  rules off (a chat line says which profiles; tick the rule's box to turn it back on).
- The other-addon notice's **Disable and reload** works again and offers a **Reload now** button.
- If PlateSmith's saved file is lost while it manages Blizzard settings, turning the option off now
  restores Blizzard's defaults.
- Settings: section lines no longer vanish when scrolled to the end, section titles survive switching
  pages, and every page opens at its top.
- Rules using tanking, elite, rare, boss, hostile or neutral no longer apply when the game hides
  that information.

## 1.0.3

### Fixed

- Without QuestieDB installed, the optional PlateSmith QuestieDB companion no longer reports "failure to
  load: missing"; it now stays quietly off until QuestieDB is there.

### New

- When another nameplate addon is running, PlateSmith says so once per session in a small window
  (never in combat or during a loading screen). It explains that PlateSmith is running as a light
  overlay (quest markers and threat) on that addon's plates, and offers **Keep overlay**,
  **Disable <addon> and reload** (asks first), and **Don't show again** for that set of addons.
  With two or more nameplate addons running it warns that they overlap each other.
- PlateSmith now also recognises NeatPlates, Platynator, nPlates, and ElvUI or Tukui while their
  nameplates are on, and draws only its overlay on their plates in `mode auto`.
- `/ps diagnose` flags two or more nameplate addons running at once as a problem, and notes when
  PlateSmith is running as an overlay on another addon's plates. It also lists PlateSmith's modules
  and the add-ons they rely on, so it says why QuestieDB markers are off (disabled or not installed).
- Your target's plate now draws on top where plates overlap, so its name and bars are never hidden
  under a neighbour's.
- Blueprint Studio's Settings pages are laid out like the rest of PlateSmith's settings: folding
  sections in two columns when Studio is wide enough (one when it is narrow), each row a label, its
  control and its help underneath. Section folds are remembered.
- **Behaviour & display** is grouped into Plates, Names, Target, Text, Quests and **Show on plates**.
  The font field is as wide as the column and shows a long font name in full on hover.
- **Show on plates** (quest markers, tagged indicator, threat details, elite and rare marks) and the
  tree's eyes stay in step: unticking one shows its part's eye off, and showing the part by its eye
  ticks it again. While a switch is off, that part's inspector says so, with a **Turn on** link,
  and its controls are dimmed until it is back on.
- **Aura defaults**, **Relationships**, **Studio** and **Help** use the same sections; Help's text
  wraps to its column.
## 1.0.2

### Changed

- The AddOns list shows PlateSmith as "PlateSmith Nameplates", in the Unit Frames category.
- `/ps diagnose` matches the Settings pages: proper tabs, the title and history buttons on one line,
  and even spacing. **Details** now shows the report in folding sections (Context, Profile,
  Performance, Target, Auras, Threat, Threat windows, Quest, Restrictions, Other) as name and value
  rows, with problem values in red at the top of their section and counted on a folded section's
  header. Ticker entries and events show as small tables sorted by cost. The fold state is saved.
- Resizing a threat window now moves the windows stacked below it (and below its row) down or up
  with its bottom edge, and the windows snapped to its right (and its column's right) with its right
  edge, so they stay attached. They stop at the screen edge. Hold Shift as you start to resize one
  window alone, without moving the others.
- A threat window's title has a tooltip: drag to move it with the windows snapped to it, Shift to
  move it alone (it still snaps), right-click for its menu.
- Blueprint Studio's **+ Add rule** and **+ stop** buttons, when unavailable, now look disabled
  like Studio's other buttons instead of being dimmed twice.

### Fixed

- The threat window resize grip no longer shows its tooltip while you resize (or just after); it
  shows only when you hover over the grip.

### Performance

- Threat tracking does less work in groups and raids: a group change is handled once instead of
  once per event, changing target re-reads only the old and new target, and stance or aura changes
  no longer re-check your role when it is fixed (Always, Never, or assigned by the group).
- With the threat setting off and no threat window shown, threat tracking now sleeps and catches up
  when it is needed again. Out of combat with nothing changing it checks four times less often.
- Threat windows redraw only when something they show changed.
- Save and Revert bars that are not on screen no longer update on every edit, and the unsaved-changes
  check runs once per update instead of once per bar.
- The QuestieDB companion rebuilds its quest markers only when your quests or objectives actually
  changed, and remembers each plate's creature so it is not worked out again on every check.
- Protected-value checks, which run for nearly everything PlateSmith reads, are cheaper.
- In raids and groups, health, power, cast, name and aura updates for group members and other units
  without a nameplate are ignored straight away instead of reaching the plates.
- Nameplates redraw only what an update changes: a health change redraws only the parts that show
  health (text, bars, templates and rules that use it), and nothing at all on plates that show none.
  In instances where health is protected, the regular health check no longer redraws every plate.
- A delayed or pushed-back cast only moves its cast bar; a hidden power bar no longer reads power;
  a mob changing target redraws its plate only when you show its target's name or use it.
- Threat text on plates is rewritten only when the threat reading changes.
- Aura rows check your target only on your target's plate; an aura read the game refuses in combat
  is not retried on every update (it is tried again after combat); Blizzard's aura fallback is only
  moved or rescaled when it needs to be.
- Withheld raid markers: a group member's retarget checks only that member's target, and focus and
  mouseover changes look up markers at most four times a second.
- The target halo and spotlight animation runs only while one is showing; the native-plate
  backstop runs every 2 seconds; whether you are in a dungeon or raid is checked once per zone.

## 1.0.1

### Changed

- The threat window resize grip has a tooltip explaining snapping and Shift.
- `/ps diagnose` opens on a short summary; Copy full report gives one PS1 code line. For a bug
  report, paste the summary and that line. The full readable report is still under **Show full
  report**, and every flagged value under **Details**.

### Fixed

- Switching profiles in Blueprint Studio no longer shows an error.
- A profile's fonts now apply when you switch to it: plate names no longer keep the look of the
  profile or preset you used before (such as Bold's Morpheus or Classic's thin text).
- Blueprint Studio now follows a profile switch made anywhere (Settings, a slash command, New from
  preset), so its preview always shows the profile your plates use.
- Threat windows snapped side by side now line up at the top and share one height, and a window
  snapped above or below another takes its width. Resizing one from its corner resizes the others
  in its row (height) or column (width), and its edges now snap to neighbours and the screen edge
  while you drag, with the highlight showing. Hold Shift to resize one window freely.
- `/ps diagnose`: every tab's scroll bar now follows the text (its thumb shows how much is visible
  and can be dragged), hides when the text fits, and the view ends at the last line instead of
  scrolling on into empty space.
- `/ps diagnose` summary: only errors from this session are listed as problems (older ones stay in
  History with their build and time, and each History row has its own dismiss button); error text
  drops the addon path and is cut cleanly; Studio is named only when it edits another profile; and
  the top event reads like "plate added ×12, 170.8 ms total (peak 25.4 ms)". **Clear history** now
  sits next to **Keep history**.

## 1.0.0

PlateSmith's first full release. Design your own nameplates in **Blueprint Studio**, see who has
threat at a glance, and share your setup with a single code. Everything from the alpha builds is
here, rebuilt and reviewed for release.

### Blueprint Studio

Type `/ps` to open it. Pick a plate type (Enemies, Players or Friendly NPCs), click a part, and
change it. Changes show on the preview straight away and reach your plates when you press **Save**.

- **Every part is yours to place.** Drag parts on the preview (they snap to the plate and to each
  other; hold Shift to place freely), nudge them with the arrows, resize them with the handles,
  and rearrange them in the tree. Rename, duplicate, reset, delete or add back any part.
- **Anchor to and Pin.** A part moves with the part it is anchored to. Pin it to an edge and it
  follows that part's size: the level stays beside the name however long the name is. Turn a
  part off and whatever is pinned to it takes its place.
- **Stacks.** Parts in a stack close up when one has nothing to show, so an idle cast bar leaves
  no gap.
- **Custom parts.** Up to 24 per plate type: health, power and threat numbers, your own text
  with tokens and conditions (`{health} / {health.max}`, `[if health.percent < 35]LOW[end]`),
  or a bar, box or icon.
- **Style** any text or bar: font, outline, shadow, a box behind text, bar texture, background
  and border. Save a look as a preset and use it on other parts.
- **Rules** change a part when something is true: set its colour, blend it by health, fade it or
  hide it. Ready-made presets cover health colours, execute range, grey when tagged, and threat
  colours for tanks and for DPS and healers.
- **Test values** let you preview a rule or custom text as it would look on a low-health,
  elite, casting or tanked mob.
- **Preset profiles** get you started: PlateSmith, Classic, Sleek, Bold, Tank, Healer, Minimal
  and Dungeon, each with a look of its own. Each makes a new profile you can edit, and never
  changes the ones you have.
- A clear inspector for every part, with sections you can fold away, and Colour-blind friendly
  and High contrast options.

### Nameplates

- New default layouts for every plate type, based on Blizzard's plates and the most popular
  nameplate addons, and tested so nothing overlaps.
- **Cast bar** with the spell's icon, its name and the time left, counting down for channels too.
- **Aura rows** you can shape: how many icons, per line, size, spacing and direction, with a
  cooldown swipe and optional time left.
- **Friendly plates** as names only or a full plate, each with its own layout. Dungeons have their
  own positions too.
- **Target of target** name, quest icons (PlateSmith's or Questie's, never both), a loot bag on
  mobs that drop a quest item (with the QuestieDB companion), elite and rare marks as icons,
  words or letters, raid marks and TAGGED.
- The power bar only shows on units that have power.
- The target is highlighted with a fitted outline and chevrons.

### Threat

- **Threat on your plates**: your threat %, the gap to the next player (+125 means you are
  safely ahead), and raw threat, coloured by state: you hold it, you are losing it, you are about
  to pull it, or someone else has it. Works on every mob you are fighting, not only your target.
- **Threat windows**: up to five meter-style windows, each a **Threat meter** (your group's
  threat on your target) or a **Tank** list (every enemy and who holds it). Eight themes. They
  snap together, move as a group, and resize; a highlight shows where one will join.
- **Follow Blizzard's damage meter**: drag a window onto any side of it (or pick a side in the
  menu) and it stays attached. Windows line up one after another, and stay put when the meter is
  hidden.
- **Sample data** for the threat windows (Settings, the window menu, or `/ps console sample`):
  a made-up group and enemy list in your theme, for screenshots out of combat. Turns off in combat.
- Click a row to spotlight that mob's plate: a glow round its health bar, an arrow over its
  name, chevrons or a box, and the other plates dim.
- **Your tank role** per character: Adaptive (group role, then bear form, stances and similar,
  then your spec), Always or Never.

### Profiles and sharing

- Named profiles, one per character, with **Save** and **Revert**. Create, duplicate, rename and
  delete them from Studio or Settings.
- **Blueprints**: export a whole profile as a `!PSB3!` share code and import someone else's.
  Import checks everything first and lets you choose which parts to replace. Alpha `!PSB2!` codes
  still import.

### Settings

- Settings > AddOns > PlateSmith holds **Threat** (your role, colours, threat windows and the
  spotlight, in sections you can fold) and **Profiles**. Everything else lives in Studio.
- `/ps` opens Studio, `/ps config` opens Settings, `/ps console` shows or hides the threat
  windows, and `/ps diagnose` opens a report you can copy into a bug report.

### Performance

- Each plate redraws at most once a frame, and health, power, auras and threat only update the
  parts that use them. Busy pulls cost a fraction of what the alpha did.
- Cities and crowds stay smooth: friendly plates update only when something about the player
  changes (name, level, faction, PvP flag, group, guild or friends), aura rows read a unit's
  auras at most once a frame and nothing while a row is hidden, and a burst of new plates
  (logging in, zoning, a crowd coming round a corner) is spread over a few frames.
- Aura countdowns are drawn by the game's own cooldown frames, so they cost nothing to run.
- `/ps diagnose` shows each timer's cost over the last 30 seconds and the five costliest game
  events, for bug reports.

### Coming from the alpha

- Names-only friendly layouts now start with the aura rows hidden, like the game's own.
  Turn them on in Blueprint Studio if you want them.
- Your saved profiles carry over. Your layouts stay as you left them; to try the new defaults,
  make a new profile or pick a preset profile.
- Colour by health is now a rule. Existing health colours are converted automatically.
- When several rules hold, the last one in the list wins (it used to be the first).
- The small lead bar under the threat text is gone; the threat text is coloured instead.
- The `/ps targetprobe` test command is gone.

### Known limits

- The game hides some values in combat and in instances (some health, threat, aura and cast
  details). PlateSmith never guesses: a hidden value simply isn't shown, and a rule that depends
  on it doesn't apply.
- While the game hides aura details, the debuff row is drawn by the game's own aura frame, which
  PlateSmith can only place, not restyle.
- Clicking a threat window row spotlights a plate but can't target the mob: the game doesn't let
  addons do that.
- Aura rows show everyone's or only your auras; they can't filter by spell or by dispel type.
- English only for now.
### Optional

- Questie (quest icons), the PlateSmith QuestieDB companion (quest item drops), and
  LibSharedMedia (extra fonts and textures).

## 0.1.0-alpha.2 (2026-09-25)

- Internal restructure: the addon's files are split into Core, Nameplates, Studio, Diagnostics
  and Threat folders. No changes players will notice.
