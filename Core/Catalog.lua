local _, Addon = ...

local Safe = Addon.Safe
local Catalog = {}

local function DecorEntryType()
    local enum = Safe.IsTable(Enum) and Enum.HousingCatalogEntryType
    return Safe.IsTable(enum) and Safe.AsNonNegativeInteger(enum.Decor, 1, 100) or 1
end

local function ContentTypeToEntryType(contentType)
    contentType = Safe.AsNonNegativeInteger(contentType, nil, 100)
    local enums = Safe.IsTable(Enum) and Enum or nil
    local blueprintTypes = enums and enums.HousingBlueprintContentType
    local catalogTypes = enums and enums.HousingCatalogEntryType
    if Safe.IsTable(blueprintTypes) and Safe.IsTable(catalogTypes) then
        local decor = Safe.AsNonNegativeInteger(blueprintTypes.Decor, nil, 100)
        local room = Safe.AsNonNegativeInteger(blueprintTypes.Room, nil, 100)
        if decor and contentType == decor then
            return Safe.AsNonNegativeInteger(catalogTypes.Decor, DecorEntryType(), 100)
        end
        if room and contentType == room then
            return Safe.AsNonNegativeInteger(catalogTypes.Room, nil, 100)
        end
    end
    return DecorEntryType()
end

local function Field(tableValue, key)
    if not Safe.IsTable(tableValue) or not Safe.IsReadable(key) then
        return nil
    end
    local value = tableValue[key]
    return Safe.IsReadable(value) and value or nil
end

local function Callable(tableValue, key)
    local value = Field(tableValue, key)
    return type(value) == "function" and value or nil
end

local function OwnedCount(info)
    local stored = Safe.AsNonNegativeInteger(Field(info, "totalNumStored"), nil, 999999)
    local redeemable = Safe.AsNonNegativeInteger(Field(info, "remainingRedeemable"), 0, 999999)
    local placed = Safe.AsNonNegativeInteger(Field(info, "totalNumPlaced"), nil, 999999)
    if stored ~= nil or placed ~= nil then
        return math.min(999999, (stored or 0) + redeemable + (placed or 0))
    end

    -- Early 12.x builds and some compatibility shims expose the former field
    -- names. Keep the fallback isolated so the current additive contract wins.
    local quantity = Safe.AsNonNegativeInteger(Field(info, "quantity"), 0, 999999)
    local numPlaced = Safe.AsNonNegativeInteger(Field(info, "numPlaced"), 0, 999999)
    return math.min(999999, math.max(quantity, redeemable) + numPlaced)
end

function Catalog:NormalizeInfo(info, fallbackRecordID, fallbackContentType)
    if not Safe.IsTable(info) then
        return nil
    end

    local entryID = Field(info, "entryID")
    local recordID = Safe.AsPositiveInteger(Field(entryID, "recordID"), nil, 2147483647)
        or Safe.AsPositiveInteger(Field(info, "recordID"), nil, 2147483647)
        or Safe.AsPositiveInteger(fallbackRecordID, nil, 2147483647)
    local itemID = Safe.AsPositiveInteger(Field(info, "itemID"), nil, 2147483647)
    if not recordID and not itemID then
        return nil
    end

    local entryType = Safe.AsNonNegativeInteger(Field(entryID, "entryType"), nil, 100)
        or Safe.AsNonNegativeInteger(Field(info, "entryType"), nil, 100)
        or ContentTypeToEntryType(fallbackContentType)
    local owned = OwnedCount(info)
    local name = Safe.TrimmedString(Field(info, "name"), nil, 256)
    local getItemName = Safe.IsTable(C_Item) and Callable(C_Item, "GetItemNameByID")
    if not name and itemID and getItemName then
        local ok, itemName = pcall(getItemName, itemID)
        if ok then
            name = Safe.TrimmedString(itemName, nil, 256)
        end
    end

    return {
        key = recordID and ("decor:" .. recordID) or ("item:" .. itemID),
        recordID = recordID,
        itemID = itemID,
        entryType = entryType,
        contentType = Safe.AsNonNegativeInteger(fallbackContentType, nil, 100),
        name = name or (recordID and ("Decor #" .. recordID) or ("Item #" .. itemID)),
        iconTexture = Safe.AsNonNegativeInteger(Field(info, "iconTexture"), nil, 2147483647),
        iconAtlas = Safe.TrimmedString(Field(info, "iconAtlas"), nil, 128),
        sourceText = Safe.TrimmedString(Field(info, "sourceText"), nil, 2048),
        addedFrom = "catalog",
        invalid = false,
        owned = owned,
        desired = 1,
        missing = math.max(0, 1 - owned),
    }
end

function Catalog:ResolveRecord(recordID, contentType)
    recordID = Safe.AsPositiveInteger(recordID, nil, 2147483647)
    if not recordID then
        return nil, "invalid-record"
    end
    local getInfo = Safe.IsTable(C_HousingCatalog) and Callable(C_HousingCatalog, "GetCatalogEntryInfoByRecordID")
    if not getInfo then
        return nil, "catalog-unavailable"
    end

    local entryType = ContentTypeToEntryType(contentType)
    local info
    local ok, result = pcall(getInfo, entryType, recordID)
    if ok and Safe.IsTable(result) then
        info = result
    end

    if not info then
        return {
            key = "decor:" .. recordID,
            recordID = recordID,
            entryType = entryType,
            contentType = Safe.AsNonNegativeInteger(contentType, nil, 100),
            name = "Decor #" .. recordID,
            desired = 1,
            owned = 0,
            missing = 1,
        }, "catalog-entry-unavailable"
    end
    return self:NormalizeInfo(info, recordID, contentType)
end

function Catalog:ResolveEntryID(entryID)
    local getInfo = Safe.IsTable(C_HousingCatalog) and Callable(C_HousingCatalog, "GetCatalogEntryInfo")
    if not Safe.IsTable(entryID) or not getInfo then
        return nil, "invalid-entry"
    end
    local recordID = Safe.AsPositiveInteger(Field(entryID, "recordID"), nil, 2147483647)
    if not recordID then
        return nil, "invalid-entry"
    end
    local cleanEntryID = {
        recordID = recordID,
        entryType = Safe.AsNonNegativeInteger(Field(entryID, "entryType"), DecorEntryType(), 100),
        entrySubtype = Safe.AsNonNegativeInteger(Field(entryID, "entrySubtype"), nil, 100),
        subtypeIdentifier = Safe.AsNonNegativeInteger(Field(entryID, "subtypeIdentifier"), 0, 2147483647),
    }
    local ok, info = pcall(getInfo, cleanEntryID)
    if not ok or not Safe.IsTable(info) then
        return nil, "catalog-entry-unavailable"
    end
    return self:NormalizeInfo(info, recordID)
end

function Catalog:ResolveItem(item)
    if not Safe.IsReadable(item) or (type(item) ~= "number" and type(item) ~= "string") then
        return nil, "invalid-item"
    end
    local getInfo = Safe.IsTable(C_HousingCatalog) and Callable(C_HousingCatalog, "GetCatalogEntryInfoByItem")
    if not getInfo then
        return nil, "catalog-unavailable"
    end
    local ok, info = pcall(getInfo, item)
    if not ok or not Safe.IsTable(info) then
        return nil, "catalog-entry-unavailable"
    end
    return self:NormalizeInfo(info)
end

function Catalog:ResolveCatalogEntry(entryOrInfo)
    if not Safe.IsTable(entryOrInfo) then
        return nil, "invalid-entry"
    end
    if Safe.IsTable(Field(entryOrInfo, "entryID"))
        or Field(entryOrInfo, "name") ~= nil
        or Field(entryOrInfo, "itemID") ~= nil then
        return self:NormalizeInfo(entryOrInfo)
    end
    return self:ResolveEntryID(entryOrInfo)
end

function Catalog:RefreshListOwnership(list)
    if not Safe.IsTable(list) or not Safe.IsTable(list.items) then
        return 0, {}
    end

    local changed = 0
    local completed = {}
    local visited = 0
    local function RefreshItem(item)
        if visited >= 5000 or not Safe.IsTable(item) then
            return
        end
        visited = visited + 1
        if Safe.AsBoolean(item.invalid, false) then
            return
        end
        local recordID = Safe.AsPositiveInteger(item.recordID, nil, 2147483647)
        if not recordID then
            return
        end
        local resolved, errorCode = self:ResolveRecord(recordID, item.contentType)
        local owned = not errorCode and resolved and Safe.AsNonNegativeInteger(resolved.owned, nil, 999999) or nil
        local desired = Safe.AsPositiveInteger(item.desired, nil, 9999)
        if owned == nil or not desired then
            return
        end
        local missing = math.max(0, desired - owned)
        if item.owned ~= owned or item.missing ~= missing then
            local previousMissing = Safe.AsNonNegativeInteger(item.missing, desired, 999999)
            item.owned = owned
            item.missing = missing
            changed = changed + 1
            if previousMissing > 0 and missing == 0 then
                completed[#completed + 1] = item
            end
        end
    end

    if Safe.IsTable(list.order) then
        for _, key in ipairs(list.order) do
            key = Safe.AsString(key, nil)
            if key then
                RefreshItem(list.items[key])
            end
            if visited >= 5000 then
                break
            end
        end
    else
        for _, item in pairs(list.items) do
            RefreshItem(item)
            if visited >= 5000 then
                break
            end
        end
    end
    return changed, completed
end

Addon:RegisterModule("Catalog", Catalog)
