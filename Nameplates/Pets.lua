-- Pets (Type › Pets on the Enemies and Friendly NPCs): hunter pets and warlock summons, as read by Secret.IsMinion.
-- Like Totems, a pet uses its tab's type layer only while that layer has changes.
local _, PS = ...
local Secret = assert(PS.Secret, "PlateSmith Secret missing")

local Pets = {}
PS.Pets = Pets

Pets.TYPE = "pet"
function Pets.TypeFor(db, data)
    if not PS.Designs.Record(db, data.profileKey, Pets.TYPE) then return nil end
    return Secret.IsMinion(data.unit) and Pets.TYPE or nil
end
