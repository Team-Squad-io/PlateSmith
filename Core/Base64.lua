local _, PS = ...

-- Standard Base64 (RFC 4648, padded) in pure Lua 5.1 arithmetic, for Blueprint share codes and
-- diagnostic report codes. Decode is strict: it returns nil for any damaged or incomplete input.
local Base64 = {}
PS.Base64 = Base64

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local DECODE = {}
for index = 1, #ALPHABET do DECODE[ALPHABET:sub(index, index)] = index - 1 end

function Base64.Encode(input)
    local output = {}
    for index = 1, #input, 3 do
        local first, second, third = input:byte(index, index + 2)
        local value = first * 65536 + (second or 0) * 256 + (third or 0)
        local a, b = math.floor(value / 262144) % 64 + 1, math.floor(value / 4096) % 64 + 1
        local c, d = math.floor(value / 64) % 64 + 1, value % 64 + 1
        output[#output + 1] = ALPHABET:sub(a, a) .. ALPHABET:sub(b, b)
            .. (second and ALPHABET:sub(c, c) or "=") .. (third and ALPHABET:sub(d, d) or "=")
    end
    return table.concat(output)
end

function Base64.Decode(input)
    if type(input) ~= "string" or #input == 0 or #input % 4 ~= 0 or input:find("[^%w%+/%=]") then return nil end
    local output = {}
    for index = 1, #input, 4 do
        local a, b = input:sub(index, index), input:sub(index + 1, index + 1)
        local c, d = input:sub(index + 2, index + 2), input:sub(index + 3, index + 3)
        local first, second = DECODE[a], DECODE[b]
        local third, fourth = c ~= "=" and DECODE[c] or nil, d ~= "=" and DECODE[d] or nil
        if first == nil or second == nil or (c ~= "=" and third == nil)
            or (d ~= "=" and fourth == nil) or (c == "=" and d ~= "=")
            or ((c == "=" or d == "=") and index + 3 ~= #input) then return nil end
        local value = first * 262144 + second * 4096 + (third or 0) * 64 + (fourth or 0)
        output[#output + 1] = string.char(math.floor(value / 65536) % 256)
        if c ~= "=" then output[#output + 1] = string.char(math.floor(value / 256) % 256) end
        if d ~= "=" then output[#output + 1] = string.char(value % 256) end
    end
    return table.concat(output)
end
