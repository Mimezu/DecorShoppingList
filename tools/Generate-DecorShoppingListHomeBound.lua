-- Generates Decor Shopping List's standalone vendor provider from a permitted
-- Home Bound data snapshot. Run with Lua 5.1 or LuaJIT from the Retail root:
--
--   luajit tools/Generate-DecorShoppingListHomeBound.lua \
--     Interface/AddOns/HomeBound/db.lua \
--     Interface/AddOns/DecorShoppingList/Sources/HomeBoundVendors.lua \
--     1.55

local inputPath, outputPath, sourceVersion = ...
assert(type(inputPath) == "string" and inputPath ~= "", "Home Bound db.lua path is required")
assert(type(outputPath) == "string" and outputPath ~= "", "output path is required")
assert(type(sourceVersion) == "string" and sourceVersion:match("^%d+%.%d+"), "source version is required")

local function loadDatabase(faction)
    local previousUnitFactionGroup = _G.UnitFactionGroup
    _G.UnitFactionGroup = function()
        return faction
    end

    -- db.lua normally loads after Home Bound's localization file. The importer
    -- does not consume localized drop text, but placeholder strings let the
    -- whole data chunk initialize without loading addon runtime code.
    local namespace = setmetatable({}, {
        __index = function(_, key)
            if type(key) == "string" and key:match("^L_") then
                return key
            end
        end,
    })
    local chunk, loadError = loadfile(inputPath)
    if not chunk then
        _G.UnitFactionGroup = previousUnitFactionGroup
        error(loadError)
    end

    local ok, runError = pcall(chunk, "HomeBound", namespace)
    _G.UnitFactionGroup = previousUnitFactionGroup
    if not ok then
        error(runError)
    end
    return namespace
end

local function isPositiveInteger(value)
    return type(value) == "number" and value > 0 and value % 1 == 0
end

local function isCoordinate(value)
    return type(value) == "number" and value >= 0 and value <= 100
end

local function explicitFaction(icon)
    if type(icon) ~= "string" then
        return nil
    end
    icon = icon:lower()
    if icon:find("alliance", 1, true) then
        return "Alliance"
    end
    if icon:find("horde", 1, true) then
        return "Horde"
    end
    return nil
end

local function mapFaction(mapID)
    -- Midnight faction neighborhoods. Home Bound exposes many paired vendors
    -- in both faction database loads without faction icons, so load presence
    -- alone cannot classify them. The maps themselves are faction-exclusive.
    if mapID == 2351 then return "Horde" end
    if mapID == 2352 then return "Alliance" end
    return nil
end

local function sourceKey(npcID, mapID, x, y, title)
    return table.concat({ npcID, mapID, string.format("%.6f", x), string.format("%.6f", y), title }, "\31")
end

local databases = {
    Alliance = loadDatabase("Alliance"),
    Horde = loadDatabase("Horde"),
}
local locationsByNPC = {}

for runFaction, database in pairs(databases) do
    for _, group in ipairs(database.vendors or {}) do
        for _, vendor in ipairs(group.npcs or {}) do
            local npcID = vendor.id
            local mapID = vendor.mapIDWaypoint or vendor.mapID
            local title = vendor.title
            if isPositiveInteger(npcID) and isPositiveInteger(mapID)
                and isCoordinate(vendor.x) and isCoordinate(vendor.y)
                and type(title) == "string" and title ~= "" then
                local bucket = locationsByNPC[npcID]
                if not bucket then
                    bucket = {}
                    locationsByNPC[npcID] = bucket
                end
                local key = sourceKey(npcID, mapID, vendor.x, vendor.y, title)
                local location = bucket[key]
                if not location then
                    location = {
                        npcID = npcID,
                        mapID = mapID,
                        x = vendor.x / 100,
                        y = vendor.y / 100,
                        label = title,
                        npcName = title,
                        explicitFaction = explicitFaction(vendor.icon),
                        seen = {},
                    }
                    bucket[key] = location
                end
                location.seen[runFaction] = true
            end
        end
    end
end

local records = {}
local allianceDatabase = databases.Alliance
for npcID, itemIDs in pairs(allianceDatabase.vendorItems or {}) do
    local locationBucket = locationsByNPC[npcID]
    if locationBucket then
        for _, itemID in ipairs(itemIDs) do
            local decor = allianceDatabase.decorItem and allianceDatabase.decorItem[itemID]
            local decorID = type(decor) == "table" and decor.decorID or nil
            if isPositiveInteger(itemID) and isPositiveInteger(decorID) then
                local recordKey = decorID .. ":" .. itemID
                local record = records[recordKey]
                if not record then
                    record = { decorID = decorID, itemID = itemID, sources = {}, sourceKeys = {} }
                    records[recordKey] = record
                end
                for key, location in pairs(locationBucket) do
                    if not record.sourceKeys[key] then
                        record.sourceKeys[key] = true
                        local faction = location.explicitFaction or mapFaction(location.mapID)
                        if not faction and not (location.seen.Alliance and location.seen.Horde) then
                            faction = location.seen.Alliance and "Alliance" or "Horde"
                        end
                        record.sources[#record.sources + 1] = {
                            type = "vendor",
                            label = location.label,
                            npcName = location.npcName,
                            npcID = location.npcID,
                            mapID = location.mapID,
                            x = location.x,
                            y = location.y,
                            faction = faction,
                        }
                    end
                end
            end
        end
    end
end

local ordered = {}
for _, record in pairs(records) do
    table.sort(record.sources, function(left, right)
        if left.npcID ~= right.npcID then return left.npcID < right.npcID end
        if left.mapID ~= right.mapID then return left.mapID < right.mapID end
        if left.x ~= right.x then return left.x < right.x end
        if left.y ~= right.y then return left.y < right.y end
        return (left.faction or "") < (right.faction or "")
    end)
    assert(#record.sources <= 32, "record exceeds provider source limit: " .. record.decorID)
    ordered[#ordered + 1] = record
end
table.sort(ordered, function(left, right)
    if left.decorID ~= right.decorID then return left.decorID < right.decorID end
    return left.itemID < right.itemID
end)

local function quote(value)
    return string.format("%q", value)
end

local output = assert(io.open(outputPath, "wb"))
local function write(line)
    output:write(line, "\n")
end

write("-- Generated by tools/Generate-DecorShoppingListHomeBound.lua. Do not edit by hand.")
write("-- Source: Home Bound " .. sourceVersion .. " by Bettiold; imported with permission.")
write("")
write("local _, Addon = ...")
write("")
write("local Registry = Addon:GetModule(\"SourceRegistry\")")
write("if not Registry then")
write("    return")
write("end")
write("")
write("local provider = {")
write("    id = \"decor-shopping-list-homebound-vendors\",")
write("    version = " .. quote(sourceVersion) .. ",")
write("    schemaVersion = Registry.SCHEMA_VERSION,")
write("    provenance = {")
write("        name = \"Home Bound vendor data\",")
write("        license = \"Used with permission\",")
write("        notes = \"Imported from Home Bound " .. sourceVersion .. " by Bettiold with permission.\",")
write("    },")
write("    records = {")
for _, record in ipairs(ordered) do
    write(string.format("        { decorID = %d, itemID = %d, sources = {", record.decorID, record.itemID))
    for _, source in ipairs(record.sources) do
        local faction = source.faction and (", faction = " .. quote(source.faction)) or ""
        write(string.format(
            "            { type = \"vendor\", label = %s, npcName = %s, npcID = %d, mapID = %d, x = %.6f, y = %.6f%s },",
            quote(source.label), quote(source.npcName), source.npcID, source.mapID, source.x, source.y, faction
        ))
    end
    write("        } },")
end
write("    },")
write("}")
write("")
write("Registry:RegisterProvider(provider)")
output:close()

local sourceCount = 0
for _, record in ipairs(ordered) do
    sourceCount = sourceCount + #record.sources
end
io.write(string.format("Generated %d vendor decor records with %d coordinate sources from Home Bound %s.\n", #ordered, sourceCount, sourceVersion))
