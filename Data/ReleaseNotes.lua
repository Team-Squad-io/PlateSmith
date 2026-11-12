-- Hand-curated (no generator): each release's highlights for players, shown once by the What's new window on the first
-- login after PlateSmith updates (Studio/WhatsNew.lua). Keyed by the release ("1.4.0", never a build's "+stamp"): a
-- subtitle (optional) and its sections, each a heading and its items (one short line each, at most 80 characters), in Studio's
-- names for things. A release without an entry shows no window.
--
-- Source: the release's New and Changed sections in CHANGELOG.md, shortened by hand.
local _, PS = ...
local L = PS.L

PS.ReleaseNotes = {
    ["1.4.1"] = {
        sections = {
            {
                title = L["New"],
                items = {
                    L["Class icon for players: Studio › + Add › Icons › Class icon."],
                    L["Threat breakdown: Group replay tab, the group's threat through a pull."],
                },
            },
            {
                title = L["Changed"],
                items = {
                    L["Threat breakdown lists your last ten pulls; click one to view it."],
                    L["Threat breakdown shows a bar per ability, with the working on hover."],
                    L["Group replay lists each aggro change; click one to jump to it."],
                    L["Threat breakdown counts Cat Form threat (x0.71)."],
                },
            },
            {
                title = L["Fixed"],
                items = {
                    L["Enemy cast bars show the time left in combat."],
                    L["Objects that appear in combat show their name once the fight ends."],
                    L["What's new no longer blocks clicks to the game."],
                    L["Target spotlight reaches the name when the game hides it."],
                },
            },
        },
    },
    ["1.4.0"] = {
        subtitle = L["Here is what this update brings. Everything below is in Blueprint Studio."],
        sections = {
            {
                title = L["On your plates"],
                items = {
                    L["Incoming heals and absorbs on health bars."],
                    L["Totems with a look of their own: Type › Totems, even just an icon."],
                    L["Images on any plate: PlateSmith's pictures, game atlases or your own."],
                    L["Your target's edge by class, reaction, threat or a colour you pick."],
                    L["Corpse plates for looting."],
                    L["Range, Behind you and Decoration sets in + Add."],
                },
            },
            {
                title = L["In Studio"],
                items = {
                    L["Search that goes straight to the setting you typed."],
                    L["A tidier Settings list, with Profiles, Hidden auras and My media."],
                    L["Hidden auras: hide Resurrection Sickness and the like."],
                    L["Friendly players for everyone, your group, or group and guild."],
                    L["+ Word in rules, and Range and Creature test values."],
                    L["A minimap button: left-click Studio, right-click Settings."],
                },
            },
            {
                title = L["When something looks wrong"],
                items = {
                    L["Threat breakdown: your own threat on each pull."],
                    L["/ps diagnose › Activity: what changed a setting, and which addon."],
                    L["Clicks pass through the empty edges round Studio."],
                },
            },
        },
    },
}
