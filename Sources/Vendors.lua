local _, Addon = ...

local Registry = Addon:GetModule("SourceRegistry")
if not Registry then
    return
end

-- This provider remains available for independently maintained records. The
-- permissioned Home Bound snapshot is generated into HomeBoundVendors.lua so
-- its attribution and update lifecycle remain explicit. A record may contain
-- both IDs when they are known:
--
-- {
--     decorID = 123,
--     itemID = 456,
--     sources = {
--         {
--             type = "vendor",
--             label = "Vendor name",
--             npcID = 789,
--             mapID = 1,
--             x = 0.50,
--             y = 0.50,
--             zoneName = "Zone name",
--         },
--     },
-- },
local provider = {
    id = "decor-shopping-list-vendors",
    version = "0.1.0",
    schemaVersion = Registry.SCHEMA_VERSION,
    provenance = {
        name = "Decor Shopping List verified vendor data",
        notes = "Independently maintained Decor Shopping List records.",
    },
    records = {},
}

Registry:RegisterProvider(provider)
