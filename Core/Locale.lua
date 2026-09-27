local _, PS = ...

-- User-facing text is written in English as the key: L["Show quest markers"].
-- A translation file fills PS.Locales["deDE"] (etc.) with the same keys;
-- anything missing falls back to the English key, so untranslated text shows.
PS.Locales = PS.Locales or {}

local locale = type(GetLocale) == "function" and GetLocale() or "enUS"
PS.L = setmetatable({}, {
    __index = function(_, key)
        local translations = PS.Locales[locale]
        return translations and translations[key] or key
    end,
})
