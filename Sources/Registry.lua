local _, Addon = ...

local Safe = Addon.Safe
local Registry = {
    SCHEMA_VERSION = 1,
    MAX_PROVIDER_RECORDS = 20000,
    MAX_SOURCES_PER_RECORD = 32,
}

local providers = {}
local providerOrder = {}
local sourcesByDecorID = {}
local sourcesByItemID = {}
local itemIDsByDecorID = {}

local function Field(tableValue, key)
    if not Safe.IsTable(tableValue) then
        return nil
    end
    local value = tableValue[key]
    return Safe.IsReadable(value) and value or nil
end

local function IsReadableString(value)
    return Safe.TrimmedString(value, nil, 2048) ~= nil
end

local function IsPositiveInteger(value)
    value = Safe.AsNumber(value, nil)
    return value ~= nil and value > 0 and value % 1 == 0
end

local function CopyProvenance(provenance)
    local provenanceName = Safe.TrimmedString(provenance, nil, 256)
    if provenanceName then
        return { name = provenanceName }
    end

    if not Safe.IsTable(provenance) then
        return nil
    end

    local copy = {}
    for _, key in ipairs({ "name", "url", "license", "notes" }) do
        local value = Safe.TrimmedString(Field(provenance, key), nil, 2048)
        if value then
            copy[key] = value
        end
    end
    return next(copy) and copy or nil
end

local function CopySource(source, provider)
    if not Safe.IsTable(source) then
        return nil
    end

    local sourceType = Safe.TrimmedString(Field(source, "type"), nil, 64)
    if not sourceType then
        return nil
    end

    local provenance = CopyProvenance(Field(source, "provenance"))
        or CopyProvenance(provider.provenance)
    local copy = {
        type = sourceType,
        provenance = provenance,
        provider = {
            id = provider.id,
            version = provider.version,
            provenance = CopyProvenance(provider.provenance),
        },
    }

    for _, key in ipairs({ "label", "zoneName", "npcName", "notes", "requirements" }) do
        local value = Safe.TrimmedString(Field(source, key), nil, 2048)
        if value then
            copy[key] = value
        end
    end

    local faction = Safe.TrimmedString(Field(source, "faction"), nil, 16)
    if faction == "Alliance" or faction == "Horde" then
        copy.faction = faction
    end

    for _, key in ipairs({ "mapID", "npcID", "questID", "achievementID", "priority" }) do
        local value = Field(source, key)
        if IsPositiveInteger(value) then
            copy[key] = value
        end
    end

    local x = Safe.AsNumber(Field(source, "x"), nil)
    if x then
        copy.x = x
    end
    local y = Safe.AsNumber(Field(source, "y"), nil)
    if y then
        copy.y = y
    end

    return copy
end

local function GetPlayerFaction()
    if not Safe.IsReadable(UnitFactionGroup) or type(UnitFactionGroup) ~= "function" then
        return nil
    end
    local ok, faction = Safe.Call(UnitFactionGroup, "player")
    if not ok then
        return nil
    end
    faction = Safe.TrimmedString(faction, nil, 16)
    return (faction == "Alliance" or faction == "Horde") and faction or nil
end

local function SourceIdentity(source)
    local provider = Field(source, "provider")
    return table.concat({
        Safe.TrimmedString(Field(provider, "id"), "", 128),
        Safe.TrimmedString(Field(source, "type"), "", 64),
        tostring(Safe.AsNumber(Field(source, "npcID"), 0)),
        tostring(Safe.AsNumber(Field(source, "mapID"), 0)),
        tostring(Safe.AsNumber(Field(source, "x"), -1)),
        tostring(Safe.AsNumber(Field(source, "y"), -1)),
        Safe.TrimmedString(Field(source, "faction"), "", 16),
        Safe.TrimmedString(Field(source, "label"), "", 2048),
    }, "\31")
end

local function CopyIndexedSource(source)
    if not Safe.IsTable(source) then
        return nil
    end

    local sourceProvider = Field(source, "provider")
    if not Safe.IsTable(sourceProvider) then
        return nil
    end

    local provider = {
        id = Safe.TrimmedString(Field(sourceProvider, "id"), nil, 128),
        version = Safe.TrimmedString(Field(sourceProvider, "version"), nil, 64),
        provenance = CopyProvenance(Field(sourceProvider, "provenance")),
    }
    if not provider.id or not provider.version then
        return nil
    end
    return CopySource(source, provider)
end

local function AddIndexedSource(index, id, source)
    local bucket = index[id]
    if not bucket then
        bucket = {}
        index[id] = bucket
    end
    bucket[#bucket + 1] = source
end

local function IndexRecord(record, provider)
    if not Safe.IsTable(record) then
        return
    end

    local sources = Field(record, "sources")
    if not Safe.IsTable(sources) then
        return
    end

    local decorValue = Field(record, "decorID") or Field(record, "recordID")
    local itemValue = Field(record, "itemID")
    local decorID = IsPositiveInteger(decorValue) and decorValue or nil
    local itemID = IsPositiveInteger(itemValue) and itemValue or nil
    if not decorID and not itemID then
        return
    end

    if decorID and itemID then
        local itemIDs = itemIDsByDecorID[decorID]
        if not itemIDs then
            itemIDs = {}
            itemIDsByDecorID[decorID] = itemIDs
        end
        itemIDs[itemID] = true
    end

    for _, source in ipairs(sources) do
        local copy = CopySource(source, provider)
        if copy then
            if decorID then
                AddIndexedSource(sourcesByDecorID, decorID, copy)
            end
            if itemID then
                AddIndexedSource(sourcesByItemID, itemID, copy)
            end
        end
    end
end

local function SnapshotRecords(records, provider)
    local snapshot = {}
    if not Safe.IsTable(records) then
        return snapshot
    end

    local recordsExamined = 0
    for _, record in ipairs(records) do
        recordsExamined = recordsExamined + 1
        if recordsExamined > Registry.MAX_PROVIDER_RECORDS then
            break
        end

        if Safe.IsTable(record) then
            local decorValue = Field(record, "decorID") or Field(record, "recordID")
            local itemValue = Field(record, "itemID")
            local decorID = IsPositiveInteger(decorValue) and decorValue or nil
            local itemID = IsPositiveInteger(itemValue) and itemValue or nil
            local recordSources = Field(record, "sources")

            if (decorID or itemID) and Safe.IsTable(recordSources) then
                local sources = {}
                local sourcesExamined = 0
                for _, source in ipairs(recordSources) do
                    sourcesExamined = sourcesExamined + 1
                    if sourcesExamined > Registry.MAX_SOURCES_PER_RECORD then
                        break
                    end
                    local sourceCopy = CopySource(source, provider)
                    if sourceCopy then
                        sources[#sources + 1] = sourceCopy
                    end
                end

                if #sources > 0 then
                    snapshot[#snapshot + 1] = {
                        decorID = decorID,
                        itemID = itemID,
                        sources = sources,
                    }
                end
            end
        end
    end

    return snapshot
end

local function RebuildIndexes()
    sourcesByDecorID = {}
    sourcesByItemID = {}
    itemIDsByDecorID = {}

    for _, providerID in ipairs(providerOrder) do
        local provider = providers[providerID]
        for _, record in ipairs(provider.records) do
            IndexRecord(record, provider)
        end
    end
end

local function GetReadableID(item, primary, alternate)
    if not Safe.IsTable(item) then
        return nil
    end

    local value = Field(item, primary)
    if not IsPositiveInteger(value) and alternate then
        value = Field(item, alternate)
    end
    return IsPositiveInteger(value) and value or nil
end

local function AppendUnique(output, seen, bucket, playerFaction)
    if not bucket then
        return
    end

    for _, source in ipairs(bucket) do
        local copy = CopyIndexedSource(source)
        if copy and (not copy.faction or not playerFaction or copy.faction == playerFaction) then
            local identity = SourceIdentity(copy)
            if not seen[identity] then
                seen[identity] = true
                output[#output + 1] = copy
            end
        end
    end
end

function Registry:RegisterProvider(provider)
    if not Safe.IsTable(provider) then
        return false, "Invalid source provider."
    end

    local providerID = Safe.TrimmedString(Field(provider, "id"), nil, 128)
    local version = Safe.TrimmedString(Field(provider, "version"), nil, 64)
    local schemaVersion = Safe.AsPositiveInteger(Field(provider, "schemaVersion"), nil, 100)
    local records = Field(provider, "records")
    if not providerID or not version or schemaVersion ~= self.SCHEMA_VERSION
        or not Safe.IsTable(records) then
        return false, "Invalid source provider."
    end

    if providers[providerID] then
        return false, "A source provider with this ID is already registered."
    end

    local stored = {
        id = providerID,
        version = version,
        schemaVersion = schemaVersion,
        provenance = CopyProvenance(Field(provider, "provenance")),
    }
    -- Own a bounded schema snapshot. Holding the provider's original records
    -- table would let a later mutation silently alter a future index rebuild.
    stored.records = SnapshotRecords(records, stored)

    providers[stored.id] = stored
    providerOrder[#providerOrder + 1] = stored.id
    RebuildIndexes()
    return true
end

function Registry:GetProvider(providerID)
    if not IsReadableString(providerID) then
        return nil
    end
    local provider = providers[providerID]
    if not provider then
        return nil
    end

    -- Do not expose the internal snapshot by reference.
    local copy = {
        id = provider.id,
        version = provider.version,
        schemaVersion = provider.schemaVersion,
        provenance = CopyProvenance(provider.provenance),
    }
    copy.records = SnapshotRecords(provider.records, copy)
    return copy
end

function Registry:GetSourcesForItem(item)
    if not Safe.IsTable(item) then
        return {}
    end

    local decorID = GetReadableID(item, "decorID", "recordID")
    local itemID = GetReadableID(item, "itemID")
    local output, seen = {}, {}
    local playerFaction = GetPlayerFaction()

    -- Decor-specific records win when both IDs are available.
    AppendUnique(output, seen, decorID and sourcesByDecorID[decorID], playerFaction)
    AppendUnique(output, seen, itemID and sourcesByItemID[itemID], playerFaction)
    return output
end

function Registry:GetSourcesForDecorID(decorID)
    decorID = IsPositiveInteger(decorID) and decorID or nil
    local output = {}
    AppendUnique(output, {}, decorID and sourcesByDecorID[decorID], GetPlayerFaction())
    return output
end

function Registry:GetSourcesForItemID(itemID)
    itemID = IsPositiveInteger(itemID) and itemID or nil
    local output = {}
    AppendUnique(output, {}, itemID and sourcesByItemID[itemID], GetPlayerFaction())
    return output
end

function Registry:GetItemIDsForDecorID(decorID)
    decorID = IsPositiveInteger(decorID) and decorID or nil
    local indexed = decorID and itemIDsByDecorID[decorID] or nil
    local output = {}
    if indexed then
        for itemID in pairs(indexed) do
            output[#output + 1] = itemID
        end
        table.sort(output)
    end
    return output
end

function Registry:GetSources(item)
    return self:GetSourcesForItem(item)
end

function Registry:Initialize()
    -- Providers are indexed as their files load. This no-op keeps the module's
    -- lifecycle consistent with the rest of the addon and external callers.
end

function Registry:GetDisplaySource(item)
    local sources = self:GetSourcesForItem(item)
    local source = sources[1]
    if source then
        return Field(source, "label") or Field(source, "zoneName") or Field(source, "type"), source
    end

    -- Blizzard catalog sourceText is deliberately display-only. It must never
    -- be parsed into coordinates, NPC IDs, or an acquisition classification.
    local sourceText = Safe.IsTable(item) and Safe.TrimmedString(Field(item, "sourceText"), nil, 2048)
    if sourceText then
        return sourceText, {
            type = "catalog",
            label = sourceText,
            actionable = false,
            isCatalogFallback = true,
        }
    end

    return "Source not yet mapped", nil
end

function Registry:IsCoordinateSource(source)
    if not Safe.IsTable(source) then
        return false
    end
    local mapID = Field(source, "mapID")
    local x = Safe.AsNumber(Field(source, "x"), nil)
    local y = Safe.AsNumber(Field(source, "y"), nil)
    return IsPositiveInteger(mapID)
        and x ~= nil and x >= 0 and x <= 1
        and y ~= nil and y >= 0 and y <= 1
end

Addon:RegisterModule("SourceRegistry", Registry)
