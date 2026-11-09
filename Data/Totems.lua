-- Hand-curated (no generator): the original game's shaman totems, by their English name without the rank numeral and
-- without " Totem" ("Mana Spring" for "Mana Spring Totem II"), each to its rank 1 spell ID. The game gives addons no icon
-- for a totem's unit; Nameplates/Totems.lua asks the client for this spell's icon (its spell texture API) instead. A
-- name not here (another language's, or a creature's own totem) gets no icon from this table, never a guessed one:
-- Totems.GenericIcon's plain totem icon.
--
-- Source: the spell IDs of the classic client's shaman totem spells (rank 1), checked by hand; each spell's own data,
-- its icon included, is read from the client at runtime.
local _, PS = ...

PS.TotemSpells = {
    ["Disease Cleansing"] = 8170,
    ["Earthbind"] = 2484,
    ["Fire Nova"] = 1535,
    ["Fire Resistance"] = 8184,
    ["Flametongue"] = 8227,
    ["Frost Resistance"] = 8181,
    ["Grace of Air"] = 8835,
    ["Grounding"] = 8177,
    ["Healing Stream"] = 5394,
    ["Magma"] = 8190,
    ["Mana Spring"] = 5675,
    ["Mana Tide"] = 16190,
    ["Nature Resistance"] = 10595,
    ["Poison Cleansing"] = 8166,
    ["Searing"] = 3599,
    ["Sentry"] = 6495,
    ["Stoneclaw"] = 5730,
    ["Stoneskin"] = 8071,
    ["Strength of Earth"] = 8075,
    ["Tranquil Air"] = 25908,
    ["Tremor"] = 8143,
    ["Windfury"] = 8512,
    ["Windwall"] = 15107,
}
