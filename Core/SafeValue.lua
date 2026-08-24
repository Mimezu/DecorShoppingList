local _, Addon = ...

local Safe = {}
Addon.Safe = Safe

local function IsSecret(value)
    if type(issecretvalue) ~= "function" then
        return false
    end

    local ok, secret = pcall(issecretvalue, value)
    return not ok or secret == true
end

function Safe.IsReadable(value)
    if IsSecret(value) then
        return false
    end

    if type(canaccessvalue) == "function" then
        local ok, accessible = pcall(canaccessvalue, value)
        if not ok or accessible ~= true then
            return false
        end
    end

    return true
end

function Safe.IsTable(value)
    return Safe.IsReadable(value) and type(value) == "table"
end

function Safe.AsString(value, fallback)
    if not Safe.IsReadable(value) or type(value) ~= "string" then
        return fallback
    end
    return value
end

function Safe.AsNumber(value, fallback)
    if not Safe.IsReadable(value) or type(value) ~= "number" then
        return fallback
    end
    if value ~= value or value == math.huge or value == -math.huge then
        return fallback
    end
    return value
end

function Safe.AsBoolean(value, fallback)
    if not Safe.IsReadable(value) or type(value) ~= "boolean" then
        return fallback
    end
    return value
end

function Safe.AsPositiveInteger(value, fallback, maximum)
    value = Safe.AsNumber(value, nil)
    if not value or value < 1 then
        return fallback
    end
    value = math.floor(value)
    if maximum and value > maximum then
        value = maximum
    end
    return value
end

function Safe.AsNonNegativeInteger(value, fallback, maximum)
    value = Safe.AsNumber(value, nil)
    if not value or value < 0 then
        return fallback
    end
    value = math.floor(value)
    if maximum and value > maximum then
        value = maximum
    end
    return value
end

function Safe.TrimmedString(value, fallback, maximumLength)
    value = Safe.AsString(value, nil)
    if not value then
        return fallback
    end
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    if value == "" then
        return fallback
    end
    if maximumLength and #value > maximumLength then
        value = value:sub(1, maximumLength)
    end
    return value
end

function Safe.Call(func, ...)
    if not Safe.IsReadable(func) or type(func) ~= "function" then
        return false
    end
    return pcall(func, ...)
end

Addon:RegisterModule("SafeValue", Safe)
