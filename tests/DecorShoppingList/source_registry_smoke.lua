-- Run from the Retail workspace root with a Lua 5.1-compatible runtime.

local addonRoot = ""
local addonName = "DecorShoppingList"
local Addon = {}

local function LoadAddonFile(relativePath)
    local chunk, errorMessage = loadfile(addonRoot .. relativePath)
    assert(chunk, errorMessage)
    chunk(addonName, Addon)
end

local playerFaction = "Alliance"
function UnitFactionGroup()
    return playerFaction
end

LoadAddonFile("Bootstrap.lua")
LoadAddonFile("Core/SafeValue.lua")
LoadAddonFile("Sources/Registry.lua")
LoadAddonFile("Sources/Vendors.lua")
LoadAddonFile("Sources/HomeBoundVendors.lua")

local Registry = assert(Addon:GetModule("SourceRegistry"))
local imported = assert(Registry:GetProvider("decor-shopping-list-homebound-vendors"))
assert(imported.version == "1.55", "Home Bound snapshot version was not retained")
assert(imported.provenance.name == "Home Bound vendor data", "provider attribution is missing")
assert(imported.provenance.license == "Used with permission", "provider permission is missing")
assert(#imported.records == 1497, "unexpected Home Bound record count")

local mythrindirRecord
for _, record in ipairs(imported.records) do
    for _, source in ipairs(record.sources) do
        if source.npcID == 216284 then
            mythrindirRecord = record
            assert(source.mapID == 2239, "Mythrin'dir map was not imported")
            assert(source.x == 0.54 and source.y == 0.608, "Home Bound percentages were not normalized")
            break
        end
    end
    if mythrindirRecord then break end
end
assert(mythrindirRecord, "known Home Bound vendor source was not imported")
local mappedItemIDs = Registry:GetItemIDsForDecorID(mythrindirRecord.decorID)
assert(#mappedItemIDs > 0 and mappedItemIDs[1] == mythrindirRecord.itemID,
    "provider decor-to-item crosswalk was not indexed")

local allianceNeighborhoodSources = Registry:GetSourcesForDecorID(23553)
assert(#allianceNeighborhoodSources == 1
    and allianceNeighborhoodSources[1].label == "Devin Slatesmith"
    and allianceNeighborhoodSources[1].faction == "Alliance",
    "Alliance routing did not reject Merki's Horde neighborhood source")

playerFaction = "Horde"
local hordeNeighborhoodSources = Registry:GetSourcesForDecorID(23553)
assert(#hordeNeighborhoodSources == 1
    and hordeNeighborhoodSources[1].label == "Merki"
    and hordeNeighborhoodSources[1].faction == "Horde",
    "Horde routing did not reject Devin Slatesmith's Alliance neighborhood source")
playerFaction = "Alliance"

local ok, errorMessage = Registry:RegisterProvider({
    id = "faction-filter-test",
    version = "1.0.0",
    schemaVersion = Registry.SCHEMA_VERSION,
    records = {
        {
            decorID = 999001,
            itemID = 999002,
            sources = {
                { type = "vendor", label = "Alliance Vendor", npcID = 1, mapID = 1, x = 0.1, y = 0.2, faction = "Alliance" },
                { type = "vendor", label = "Horde Vendor", npcID = 2, mapID = 1, x = 0.3, y = 0.4, faction = "Horde" },
                { type = "vendor", label = "Neutral Vendor", npcID = 3, mapID = 1, x = 0.5, y = 0.6 },
            },
        },
    },
})
assert(ok, errorMessage)

local allianceSources = Registry:GetSourcesForItem({ decorID = 999001, itemID = 999002 })
assert(#allianceSources == 2, "Alliance filtering or decor/item deduplication failed")
assert(allianceSources[1].label == "Alliance Vendor" and allianceSources[2].label == "Neutral Vendor",
    "Alliance source order is incorrect")

playerFaction = "Horde"
local hordeSources = Registry:GetSourcesForDecorID(999001)
assert(#hordeSources == 2, "Horde filtering failed")
assert(hordeSources[1].label == "Horde Vendor" and hordeSources[2].label == "Neutral Vendor",
    "Horde source order is incorrect")

hordeSources[1].label = "Mutated"
assert(Registry:GetSourcesForDecorID(999001)[1].label == "Horde Vendor", "source query leaked an internal table")

print("Decor Shopping List source registry smoke tests passed")
