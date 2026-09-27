local _, PS = ...

-- Plain-data table helpers for settings (no metatables, no cycles).
local Table = {}
PS.Table = Table

function Table.DeepCopy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, child in pairs(value) do copy[key] = Table.DeepCopy(child) end
    return copy
end

function Table.DeepEqual(left, right)
    if type(left) ~= "table" or type(right) ~= "table" then return left == right end
    for key, child in pairs(left) do
        if not Table.DeepEqual(child, right[key]) then return false end
    end
    for key in pairs(right) do
        if left[key] == nil then return false end
    end
    return true
end

-- Makes target hold exactly source's contents, so references to target stay valid.
function Table.Replace(target, source)
    for key in pairs(target) do target[key] = nil end
    for key, child in pairs(source) do target[key] = child end
    return target
end

-- Dotted paths where two plain tables differ, at most `limit` of them, sorted.
function Table.Differences(left, right, limit)
    local paths = {}
    limit = limit or 20
    local function Walk(a, b, prefix)
        if #paths >= limit then return end
        if type(a) ~= "table" or type(b) ~= "table" then
            if a ~= b then paths[#paths + 1] = prefix end
            return
        end
        local keys = {}
        for key in pairs(a) do keys[#keys + 1] = key end
        for key in pairs(b) do
            if a[key] == nil then keys[#keys + 1] = key end
        end
        table.sort(keys, function(x, y) return tostring(x) < tostring(y) end)
        for _, key in ipairs(keys) do
            Walk(a[key], b[key], prefix == "" and tostring(key) or prefix .. "." .. tostring(key))
        end
    end
    Walk(left, right, "")
    return paths
end
