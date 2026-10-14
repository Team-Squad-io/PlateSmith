# PlateSmith module API

PlateSmith keeps its runtime core small and exposes a versioned module registry for built-in and third-party
features. A module that is not part of PlateSmith lives in its own addon. This file is the reference for authors of
those addons; it ships with PlateSmith (`Docs/MODULES.md` in the download) beside a working example
(`Examples/PlateSmith_ExampleModule`).

## Contracts and versions

Each part of the API has its own version, so one can grow without breaking another. A definition may name the
range it was tested with; registration fails cleanly, with a reason, outside it.

| Contract | Value | Covers | Range fields |
| --- | --- | --- | --- |
| `PlateSmith.API_VERSION` | 1 | Modules, helpers, Blueprint fields, editor parts | `apiMin`, `apiMax` (or `requiredAPI`) |
| `PlateSmith.QUEST_PROVIDER_API_VERSION` | 1 | Quest providers | `apiMin`, `apiMax` |
| `PlateSmith.STYLE_API_VERSION` | 1 | Text tokens, facts, formatters | `styleApiMin`, `styleApiMax` |
| `PlateSmith.STUDIO_API_VERSION` | 1 | Studio settings pages and their kit | `studioApiMin`, `studioApiMax` |

Adding a call, a field or a choice does not change a version; removing one or changing what it means does, and the
older version keeps working for at least one minor release after the new one ships.

## Your first module in ten minutes

1. Make a folder beside `PlateSmith` in `Interface/AddOns`, for example `PlateSmith_KickWatch`, with a TOC:

   ```text
   ## Interface: 120100, 16001
   ## Title: PlateSmith: KickWatch
   ## Dependencies: PlateSmith
   ## SavedVariables: PlateSmithKickWatchDB

   KickWatch.lua
   ```

   `## Dependencies: PlateSmith` makes PlateSmith load first. `## Group: PlateSmith` nests the addon under
   PlateSmith in clients that group addons.

2. In `KickWatch.lua`, register the module and what it adds:

   ```lua
   local PS = PlateSmith
   local module = { version = 1, apiMin = 1, apiMax = 1 }

   function module:OnInitialize()
       -- A fact for rules and custom text: [if kickwatch.ready]...
       PS:RegisterFact("kickwatch.ready", {
           type = "boolean", label = "Kick ready", sample = true,
           read = function(unit) return module.ready end,
       })
   end

   function module:OnEnable()
       -- Start listening here; a cooldown that ends with no plate event asks PlateSmith to read the fact again:
       -- PS:InvalidateFact("kickwatch.ready")
   end

   local ok, reason = PS:RegisterModule("kickwatch", module)
   if not ok then PS:ReportError("KickWatch", reason) end
   ```

3. Reload. `/ps diagnose` lists the module and its state; Studio's custom text `?` lists `kickwatch.ready`, and a
   rule `when kickwatch.ready` works at once.

`Examples/PlateSmith_ExampleModule` is the same shape with a token, a formatter, a Blueprint field and a preview
part.

## Calling style

Every public call takes `PlateSmith:Call(...)` and `PlateSmith.Call(...)` alike, with the same answer. A colon call
passes PlateSmith first, which no argument of the API can be. The examples here use the colon.

## IDs

One grammar for every ID: **lowercase letters and digits, words joined by dots, at most 64 characters**. A module's
own ID may be one word (`kickwatch`) or more (`platesmith.questiedb`); everything a module registers (a token, a
fact, a formatter, a Blueprint field, a preview part) is `<module>.<name>`, two words or more, best with the
module's ID as its first word: `kickwatch.ready`, `kickwatch.colour`. `PlateSmith:IsModuleId(id[, words])` checks
one (`words`: the fewest words, 1 or 2).

Tokens, facts and formatters may not start with one of PlateSmith's own first words (`health`, `threat`, `level`...)
and an ID can be registered once. IDs registered before 1.3.0 in older forms still work: module IDs with capitals,
`_` or `-`, and Blueprint fields and preview parts with `_`.

## Lifecycle

```lua
local module, reason = PlateSmith:RegisterModule(id, {
    version = 1,              -- your module's own version; /ps diagnose lists it ("unknown" without one)
    apiMin = 1, apiMax = 1,   -- the PlateSmith API range you tested
    OnInitialize = function(self) end, -- create reusable state; do not start polling here
    OnEnable = function(self) end,     -- register the events you need
    OnDisable = function(self) end,    -- unregister them and hide what you own
    OnQuestLogChanged = function(self, event) end, -- optional (Quest providers, below)
})
```

| Call | Returns |
| --- | --- |
| `PlateSmith:RegisterModule(id, definition)` | the definition, or `nil, reason` |
| `PlateSmith:GetModule(id)` | the definition, or `nil` |
| `PlateSmith:IterateModules()` | an iterator of `id, definition` |

Callbacks are protected: one module's error is reported once and cannot stop PlateSmith or another module from
loading. A module registered after PlateSmith has initialized is initialized and enabled at once. Registration order
is not an API guarantee: resolve another optional capability during initialization and fail cleanly or disable only
that feature.

## Helpers

| Call | What it does |
| --- | --- |
| `PlateSmith:ReportError(scope, message)` | Reports through the player's error handler (BugSack when installed), naming PlateSmith's build. Returns the text. |
| `PlateSmith:Locale(id[, translations])` | Your module's strings: `L["Warn below"]` is the text in the client's language when you gave one, else the English key. `translations` is `{ deDE = { ["Warn below"] = "..." }, ... }`; calling again adds to them. |
| `PlateSmith:IsReadable(value)` | Whether a value from the game can be compared and calculated with (not protected). |
| `PlateSmith:ReadNumber(value)` | The value if it is a readable number, else `nil`. |
| `PlateSmith:ReadText(value)` | The value if it is a readable, non-empty string, else `nil`. |
| `PlateSmith:InvalidateFact(id[, unit])` | Asks PlateSmith to read your token or fact again on the next render: on every visible plate, or on `unit`'s plate. For a change no plate event follows (a cooldown ending). `"quest"` re-reads quest relevance after a quest provider's answers changed. `true`, or `false, reason`. |
| `PlateSmith.Ticker.Register(id, interval, callback)` | PlateSmith's one periodic update; see Runtime rules. |

`InvalidateFact` only marks plates; they render at most once a frame, and only plates whose custom text, parts or
rules read a module's token.

## Settings and profiles

`PlateSmith.GetSettings()` returns the working copy of the character's active profile. It keeps its identity across
reset, revert and profile switches, so a module may hold the reference. **Writing to it directly does not light up
Save:** only PlateSmith's own setters mark the profile changed, so a raw write is kept only if the player happens to
save for another reason, and it is not carried by Blueprints. A module's own choices that belong to the profile are
declared with its Studio settings (below) and written with `PlateSmith:SetModuleOption`; anything else goes in its
own SavedVariables. `PlateSmith.Profiles.Subscribe(callback)` runs after a save, revert, switch, or (batched to five
times a second) any settings edit.

`PlateSmith:RegisterModuleSettings(id, title, panel)` (API 1, **deprecated**) places a hand-built canvas page under
PlateSmith in Game Options, with a legacy Interface Options fallback. It cannot be searched beyond its title, is
closed in combat and has no Save. Use `RegisterStudioSettings` instead.

## Studio settings

`PlateSmith:RegisterStudioSettings(id, definition)` (`STUDIO_API_VERSION` 1) gives a module a page in
**Blueprint Studio › Settings › Modules**, built from Studio's own rows: folding sections, the same rows and `?` help
as Studio's pages, two columns when wide, Settings search, and usable in combat (no secure frames). Game Options ›
AddOns › PlateSmith gets a short page for the module with an **Open in Studio** button, unless `gameOptions = false`.
`id` is the module's own ID: register the module first.

```lua
local L = PlateSmith:Locale("kickwatch")
local ok, reason = PlateSmith:RegisterStudioSettings("kickwatch", {
    studioApiMin = 1, studioApiMax = 1,
    title = L["KickWatch"], icon = 132219, summary = L["Your interrupt on enemy plates."],
    -- Profile settings, declared once: PlateSmith validates, saves (Save/Revert) and shares them in Blueprints.
    settings = {
        warnBelow = { type = "range", min = 0, max = 5, step = 0.5, default = 2 },
        colour = { type = "enum", values = { "green", "blue", "gold" }, default = "green" },
        mine = { type = "boolean", default = true, scope = "character" }, -- this character's, saved at once
    },
    build = function(page, kit)
        local cooldown = kit.Section(page, L["Cooldown"], { summary = function() return kit.Value("warnBelow") .. " s" end })
        kit.Check(cooldown, { label = L["Watch my interrupt"], bind = kit.Own(PlateSmithKickWatchDB, "enabled") })
        kit.Slider(cooldown, { label = L["Warn below"], bind = kit.Profile("warnBelow"), min = 0, max = 5, step = 0.5,
            format = "%.1f s" })
        kit.Choice(cooldown, { label = L["Colour"], bind = kit.Profile("colour"), choices = {
            { value = "green", label = L["Green"] }, { value = "blue", label = L["Blue"] }, { value = "gold", label = L["Gold"] } } })
        kit.Help(cooldown, L["Use {kickwatch.cd} in custom text and kickwatch.ready in rules."])
    end,
    OnSettingsChanged = function(key, value) end, -- after any write to a bound or declared setting, from any surface
    OnShow = function() end,                       -- each time the page shows
})
```

| Field | Meaning |
| --- | --- |
| `title` (required) | The Modules row and the page's title, at most 40 characters. |
| `build(page, kit)` (required) | Builds the page the first time it shows (or Settings search indexes it). |
| `icon`, `summary` | The row's icon (texture path or file ID) and the line under the page's title. |
| `settings` | Declared settings (below). |
| `OnSettingsChanged(key, value)`, `OnShow()` | Optional callbacks, contained like every other. |
| `gameOptions` | `false`: no page in Game Options. |
| `studioApiMin`, `studioApiMax` | The range you tested. Outside it registration fails and the row says "needs a newer PlateSmith" or "needs an update". |

Returns `true`, or `false, reason`.

**Declared settings.** `{ type, default, scope }`, `scope` being `"profile"` (the default) or `"character"`. Types:
`boolean`; `range` (`min`, `max`, optional `step`); `enum` (`values`, text or numbers); `colour` (`{ r, g, b }`, 0 to
1); `text` (optional `maxLength`, at most 200; no control characters or `|`). Keys are letters, digits and `_`.
`PlateSmith:GetModuleOption(id, key)` reads one (its default while it is unset or invalid);
`PlateSmith:SetModuleOption(id, key, value)` writes one, valid by its declaration (a range is clamped to its step),
and returns `true`, or `false, reason`.

| Scope | Stored in | Saved | In Blueprints |
| --- | --- | --- | --- |
| `kit.Profile(key)`, a `profile` setting | the profile, `modules["<id>"]` | with Save; Revert undoes it | yes, `modules["settings:<id>"]`, only what differs from the defaults, validated by the declaration (no module code runs) |
| `kit.Character(key)`, a `character` setting | `PlateSmithCharacterDB.modules["<id>"]` | at once | no |
| `kit.Own(table, key)` | your own SavedVariables table | at once | only through `RegisterBlueprintField` |
| `kit.Custom{ get, set }` | wherever your functions say | your choice | no |

A default is stored as nothing, so going back to it is no change. Data of a module that is not installed stays in the
profile untouched. An imported Blueprint's settings section replaces the module's profile settings (absent: its
defaults); a known key with a bad value refuses the import, an unknown one is skipped. Rows bound with `Own` or
`Character` say in their tooltip that they are saved at once.

**The kit** (version 1). Every row takes one spec table; Studio adds the widget, its refresh, tooltip and search
entry. `label` and `help` are text; `help` becomes the row's tooltip. `shown = function` hides the row while it says
false. `bind` is one of the four bindings.

| Call | Row |
| --- | --- |
| `kit.Section(page, title[, { summary, key }])` | A folding section; `summary()` shows at its title while folded. Returns the section rows go in. |
| `kit.SubHeader(section, text)`, `kit.Help(section, text)` | A sub-heading; a paragraph. |
| `kit.Note(section, text or function)` | A line under the row above (a function is read on each refresh). |
| `kit.Check(section, { label, bind })` | A tick box. |
| `kit.Slider(section, { label, bind, min, max, step, format })` | A slider; `format` is a format string or `function(value)`. |
| `kit.Choice(section, { label, bind, choices })` | A dropdown; `choices` is `{ { value, label }, ... }` or a function returning it (read when it opens). |
| `kit.Swatch(section, { label, bind })` | A colour (`{ r, g, b }`). |
| `kit.Segmented(section, { label, bind, choices })` | A row of exclusive choices. |
| `kit.Button(section, { text, onClick, width, available })`, `kit.Buttons(section, { label, buttons })` | Buttons; `available()` dims one that cannot apply now. |
| `kit.Text(section, { label, text })` | A read-only value; `text` may be a function, read on each refresh. |
| `kit.Value(key)` | A profile setting's value now. |
| `kit.Refresh()`, `kit.IsShown()` | Read the rows again (after your own state changed); whether the page shows. |
| `kit.Has(name)` | Whether this PlateSmith's kit has a call, for a newer one you can do without. |

Adding a row type, field or binding does not change `STUDIO_API_VERSION`; check with `kit.Has`. Unknown spec fields
are ignored; a missing required one fails the build with a reason.

**Failure and limits.** `build` runs once a session per page, timed (`/ps diagnose` lists one over 20 ms), with at
most 80 rows. If it errors, the page shows a card in its place ("could not be shown") and the error is reported once;
the rest of Studio is unaffected. Each callback (`get`, `set`, `choices`, `summary`, `shown`, `onClick`, `text`) runs
under `pcall`: an error reads as nothing and is reported once, and after five errors the page turns off for the
session (its card shows, search offers none of it). A page's rows refresh only while it shows. `/ps diagnose` reports
each page as `modules[].studio`: `ok`, `error: ...`, `disabled` or `api-missing`. Nothing in this API runs per plate:
keep `get`, `summary` and `text` cheap and allocation-free.

PlateSmith's own **Threat** page is built with this API (`Settings/ThreatPage.lua`), with its settings kept where they
always were in the profile; `PlateSmith_QuestieDB` and `Examples/PlateSmith_ExampleModule` are third-party examples.

## Quest providers

The quest-provider contract is `PlateSmith.QUEST_PROVIDER_API_VERSION == 1`. Providers supplement, but never
override, native quest relevance:

```lua
PlateSmith:RegisterQuestProvider("exampleauthor.database", {
    apiMin = 1,
    apiMax = 1,
    GetUnitRelevance = function(self, unit)
        -- Keep this bounded and allocation-free. Return only readable values.
        return false
    end,
})
```

`GetUnitRelevance` may return `true, kind, detail`. `kind` is a stable styling identifier and `detail` is a short
diagnostic string. It may also return the objective it matched as `true, kind, detail, questID, objectiveIndex` (the
index into `C_QuestLog.GetQuestObjectives`); PlateSmith then shows that objective's progress by the quest mark and in
`{quest.progress}`, read from the quest log. A provider that returns three values is unchanged. PlateSmith's native
unit signal always wins on whether a unit is marked. When it says a unit is related but PlateSmith cannot tell which
objective is outstanding, a provider's `questiedb-item-drop` kind picks the loot bag and its objective the progress.
Providers must precompute indexes from events rather than reading a database for every visible plate. When their
answers change, call `PlateSmith:InvalidateFact("quest")`. The optional `PlateSmith_QuestieDB` companion is the
reference implementation.

A provider may also have `GetObjectRelevance(self, objectID)` (1.3.0): `true` when it lists the game object (its ID
from the game, a readable number) in a quest (an objective, starter or finisher), `false` when it knows the object is
in none, `nil` for no answer. It feeds the `object.quest` fact for rules and custom text; with no provider answering,
`object.quest` is unknown. It is called when a rule or custom part reads `object.quest`, and again for object plates
after each quest log change, so keep it to a cached lookup. Module facts cannot use the `object.` namespace
(PlateSmith's), so this optional method is the route for quest data about objects.

`OnQuestLogChanged` is coalesced: bursts of `QUEST_LOG_UPDATE` and `QUEST_WATCH_LIST_CHANGED` produce at most one call
every 0.25 seconds. While no plate is up the call waits, as nothing reads a quest cache then: it comes in the frame
the first plate is added, before that frame is drawn. A module that shows quest figures elsewhere (a settings page)
reads the quest log itself when that shows.

## Blueprint fields

`PlateSmith:RegisterBlueprintField("module.field", { export, parse, apply })` adds a namespaced entry under the
Blueprint's `modules` object. `export` returns any JSON value (string, number, boolean, or a table of those);
`parse` receives the decoded value and must return the validated data or `nil, reason`. Data for a module that is
not installed on the importing client is skipped. PlateSmith skips (and names) fields of its own it does not know,
from a newer version, but hands a module's value to its `parse` as it is: a module that wants the same forward
compatibility ignores its own unknown keys there rather than refusing them. Imports are all-or-nothing for
PlateSmith's own settings: if any `apply` returns `false` or errors, every change already made to the working copy
is restored. A successful import still waits for Save like any other edit. State a module keeps elsewhere is not
rolled back, so `apply` should not fail after a successful `parse`. Returns `true`, or `false, reason`.

## Preview parts

`PlateSmith:RegisterEditorComponent(key, definition)` adds a part to **Blueprint Studio's preview and tree only**:
nothing draws it on a real plate. Use it to show where a module's own frames go, not as a plate part. One a player
deleted comes back from **+ Add > Other**. It is movable by default; `movable = false` keeps it selectable without
drag, nudge or coordinate controls. It does not grant modules permission to alter protected live nameplate frames.
`definition` needs `label`, numeric `x`, `y`, `width` and `height`, and may have `create(component)` and
`refresh(component, profile)`. Returns `true`, or `false, reason`.

## Diagnostics

`/platesmith diagnose` reports are plain tables, and the Summary tab reads them generically. Report states with the
standard words so they are flagged without UI changes: `error`, `failed`, `blocked`, `api-missing`, `missing`,
`invalid…` for problems; `secret`, `protected`, `unavailable`, `withheld`, `no-entry`, `restricted` for restricted
data. Values such as `readable`, `none`, and `protected/displayable` are normal and are not flagged.

## Runtime rules

- Treat combat-restricted and secret values as unreadable (`PlateSmith:IsReadable`). Never use them in arithmetic,
  comparisons, table keys, or sorting.
- Prefer events and dirty flags. If polling is unavoidable, register it on the shared ticker
  (`PlateSmith.Ticker.Register(id, interval, callback)`), disable it while the feature is hidden, and use a bounded
  interval.
- Reuse frames, rows, and scratch tables. Do not create UI objects or short-lived tables during every update.
- Iterate visible nameplate unit tokens only. Do not scan the combat log to reconstruct data already provided by
  unit APIs.
- Do not hook or replace another nameplate addon's private objects. Register an explicit provider adapter when one is
  necessary.
- Keep optional libraries optional. A missing media or provider addon must not prevent PlateSmith from loading.
- Use only what this file documents. Other members of `PlateSmith` (`Options`, `Secret`, `Chat`, `UI`...) are
  internal and change without notice.

## Dependency policy

PlateSmith currently embeds no framework. Blizzard Settings and frame APIs cover the core UI; the Blueprint format is
small and deterministic enough to serialize directly. Full Ace3 and compression libraries are not justified for the
current runtime cost and maintenance surface.

PlateSmith reads an already-loaded `LibSharedMedia-3.0` through `PlateSmith.Media` for fonts and bar textures and
always keeps native defaults. Compression should only be considered if real Blueprint payloads become large enough to
measure a problem.

## Style API: tokens, facts and formatters

The style calls are under `PlateSmith.STYLE_API_VERSION == 1`. They add names that value templates and part rules
(`docs/TEMPLATES.md`) can use:

```lua
local PS = PlateSmith
if type(PS.RegisterTextToken) == "function" then
    -- {exampleauthor.stagger} in a template; also usable in conditions (a number is true when not 0).
    local ok, reason = PS:RegisterTextToken("exampleauthor.stagger", {
        styleApiMin = 1, styleApiMax = 1,
        kind = "number",                  -- number | percent | signed | text ("string") | flag
        label = "Stagger",                -- shown in Studio's ? help
        sample = 12400,                   -- Studio's preview value (preview = ... also accepted)
        read = function(unit, read)       -- may return a protected value: it is only shown
            return GetStagger(unit)
        end,
    })
    -- A condition fact: [if exampleauthor.ready] and rules' "when exampleauthor.ready".
    PS:RegisterFact("exampleauthor.ready", {
        type = "boolean",                 -- boolean (a flag) | number
        read = function(unit) return IsInterruptReady() end,
        sample = true,
    })
    -- {level:exampleauthor.roman}: readable values only.
    PS:RegisterFormatter("exampleauthor.roman", {
        label = "Roman numerals",
        format = function(value) return ToRoman(value) end,
    })
end
```

| Call | Returns |
| --- | --- |
| `PlateSmith:RegisterTextToken(id, definition)` | `true`, or `false, reason` |
| `PlateSmith:RegisterFact(id, definition)` | `true`, or `false, reason` |
| `PlateSmith:RegisterFormatter(id, function or definition)` | `true`, or `false, reason` |
| `PlateSmith.Template.ListTokens()` | every token: `{ id, kind, builtin, label, sample, aliases, state }`, sorted by id |
| `PlateSmith.Template.ListFormatters()` | registered formatters: `{ id, label, state }` |

- **IDs** follow the grammar above. Formatter IDs cannot be built-in modifier names. Nothing is stored when any part
  of a definition is invalid.
- **Readers** are called as `read(unit, read)` under `pcall`, each at most once per plate per render. They get only
  the unit token and a `read(token)` function for other tokens of the same plate, valid only while the reader runs. A
  reader that reads itself gets `nil`. A readable value of the wrong type for its kind reads as missing; a protected
  value is passed straight to the client to be shown. In a condition a protected or missing value is unknown, which
  carries through `not`, `and` and `or`; only a true condition holds (`TEMPLATES.md`, "Protected values").
- **Flags** (`kind = "flag"`, or a boolean fact) work only in conditions, like the built-in flags.
- **Formatters** run only on readable values. A protected value skips the formatter and uses the token's default
  format. A result is cut to 64 characters and `|` is escaped, so it cannot open a texture, link or colour code. A
  formatter that fails or returns something other than text falls back to the default format.
- **Errors** are contained: a reader or formatter that errors is reported once through PlateSmith's error report,
  reads `nil` for that call (the rest of the text still renders), and is switched off for the session after five
  errors. `ListTokens`/`ListFormatters` show `state = "error"` or `"disabled"`.
- Registration may happen at any time. A template or rule that names an ID before it is registered does not compile
  (Studio says so) and shows once it is.
- Tokens are read when PlateSmith renders the plate's text or rules (on its own unit, threat and target events, and
  whenever anything on the plate changes). For a change with no plate event, call `PlateSmith:InvalidateFact(id)`.

## Sources for custom parts

A player's custom parts (Studio's **+ Add > Custom part**) can show a module's data on real plates, through
PlateSmith's own placement, designs, rules, Blueprints and preview; the module runs no code per plate beyond its
reader. Under `STYLE_API_VERSION` 1:

```lua
-- A custom bar's fill: a number token scaled from min..max to empty..full (clamped).
PlateSmith:RegisterBarSource("kickwatch.cd", {
    label = "Kick cooldown", min = 0, max = 15,
    read = function(unit) return SecondsLeft() end, sample = 6, -- registers the token kickwatch.cd too
})
-- Or over a token registered elsewhere: { label = "...", token = "kickwatch.other", min = 0, max = 100 }.

-- A custom icon's picture: a texture (file ID or path) or nil to hide the icon.
PlateSmith:RegisterIconSource("kickwatch.icon", {
    label = "Kick ready", sample = 132219,
    read = function(unit) if KickReady() then return 132219 end end,
})

-- No plate event follows a cooldown: ask PlateSmith to read it again.
PlateSmith:InvalidateFact("kickwatch.cd")
```

- A **custom bar**'s Source and a **custom icon**'s Picture list the registered sources by label; a **custom text**'s
  Source lists modules' number and text tokens (their `{id}`). Choosing one stores the part's source as its text
  (`source = "template"`, `template = "{kickwatch.cd}"`), so profiles, designs, rules and Blueprints carry it like any
  custom part. Older PlateSmith versions hide such a bar and show such an icon as their default picture.
- A bar shows `(value - min) / (max - min)`, clamped; a protected value fills it only when the source is 0 to 100
  (passed straight to the bar), else the bar hides. An icon's `read` runs under `pcall` when the plate renders; it may
  return a protected texture (it is only shown); five errors turn the source off for the session.
- Studio's preview draws a bar from its token's sample through the same scaling, and an icon from its `sample`.
- A source's ID follows the token rules (above). Both calls return `true`, or `false, reason`, and store nothing on
  failure. `PlateSmith:InvalidateFact(id[, unit])` takes a source's ID as well as a token's.

**Test values.** A module's boolean fact (`RegisterFact` with `type = "boolean"`) gets a box in Studio's Test values
(up to eight modules' facts, after PlateSmith's own flags), its sample until the player ticks or unticks it, so a rule
`when kickwatch.ready` can be tried in the preview.

## Planned extension points: style API

Status: designed, not implemented, apart from the calls above (full part types of a module's own, with their own
inspector, wait for the descriptor-driven inspector). The full design, including descriptor fields and
examples, is `docs/STYLING_RULES.md` section 12 (not shipped). These calls join `PlateSmith.STYLE_API_VERSION`,
which is frozen only when the last style phase ships.

The trust boundary: an installed module is trusted code and may register functions. Blueprints, presets, rules, and
text templates are untrusted data and may only reference registered IDs; modules never receive executable Blueprint
code.

| Call | Registers |
| --- | --- |
| `PlateSmith:RegisterAsset(kind, id, spec)` | A texture or font for `statusbar`, `background`, `border`, `font`, `overlay`, `icon`, or `mask`. IDs are `namespace:name`; paths must be inside the registering addon's folder, a Blizzard `Interface\` path, or a file ID. |
| `PlateSmith:RegisterFact(id, spec)` | Implemented for `boolean` and `number` (above). Planned: `enum`, `readability`, `scope`, and optional `curve`/`boolean` routes for client-evaluated `steps()`/`gradient()`/`pick()` bindings. |
| `PlateSmith:InvalidateFact(id[, unit])` | Implemented (Helpers, above). |
| `PlateSmith:RegisterTextToken(id, spec)` | Implemented (above). Planned: `facts` dependencies that re-render the text, and a default format. |
| `PlateSmith:RegisterFormatter(id, spec)` | Implemented (above): a `{token:formatter}` modifier on readable values only. Planned: `accepts`. |
| `PlateSmith:RegisterComponentType(id, spec)` | A component made of primitive parts, with its own extra property descriptors and live/preview `create`/`apply` adapters. |
| `PlateSmith:RegisterPresetPack(id, spec)` | Read-only style presets shown under the addon's name. |

An asset remembers the addon that registered it. When a Blueprint uses it, export lists that addon (its TOC
`Title`, and `X-Curse-Project-ID` / `X-Website` if present) in `requires`, so importers are told what to install.
Add those TOC fields to a media addon to make it findable.
