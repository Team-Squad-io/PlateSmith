# PlateSmith changelog

Each release lists what players will notice. CurseForge shows this file as the release notes.

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
