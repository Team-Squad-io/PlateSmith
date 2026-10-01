# PlateSmith changelog

Each release lists what players will notice. CurseForge shows this file as the release notes.

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
