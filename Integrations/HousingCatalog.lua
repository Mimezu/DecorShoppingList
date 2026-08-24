local _, Addon = ...

local Safe = Addon.Safe
local L = Addon.L

local CatalogIntegration = {
    initialized = false,
}

local MENU_TAG = "MENU_HOUSING_CATALOG_ENTRY"
local MAX_MENU_LIST_NAME_LENGTH = 48

local function IsCallable(value)
    return Safe.IsReadable(value) and type(value) == "function"
end

local function GetDecorEntryType()
    if not Safe.IsTable(Enum) or not Safe.IsTable(Enum.HousingCatalogEntryType) then
        return nil
    end

    return Safe.AsNumber(Enum.HousingCatalogEntryType.Decor, nil)
end

local function GetMenuItem(owner)
    if not Safe.IsTable(owner) then
        return nil
    end

    -- Blizzard does not create MENU_HOUSING_CATALOG_ENTRY for bundle children,
    -- but retain this guard in case that host behavior changes.
    local bundleItemInfo = owner.bundleItemInfo
    if not Safe.IsReadable(bundleItemInfo) or bundleItemInfo ~= nil then
        return nil
    end

    local entryInfo = owner.entryInfo
    local entryVariantID = owner.entryVariantID
    if not Safe.IsTable(entryInfo) or not Safe.IsTable(entryVariantID) then
        return nil
    end

    local decorEntryType = GetDecorEntryType()
    local variantEntryType = Safe.AsNumber(entryVariantID.entryType, nil)
    local infoEntryType = Safe.AsNumber(entryInfo.entryType, nil)
    if not decorEntryType or variantEntryType ~= decorEntryType or infoEntryType ~= decorEntryType then
        return nil
    end

    local variantRecordID = Safe.AsPositiveInteger(entryVariantID.recordID, nil, 2147483647)
    local infoRecordID = Safe.AsPositiveInteger(entryInfo.recordID, nil, 2147483647)
    if not variantRecordID or variantRecordID ~= infoRecordID then
        return nil
    end

    local rawItemID = entryInfo.itemID
    if not Safe.IsReadable(rawItemID) then
        return nil
    end
    local itemID = Safe.AsPositiveInteger(rawItemID, nil, 2147483647)
    if rawItemID ~= nil and not itemID then
        return nil
    end

    local name = Safe.TrimmedString(entryInfo.name, nil, 256)
    if not name then
        return nil
    end

    local rawIconTexture = entryInfo.iconTexture
    local rawIconAtlas = entryInfo.iconAtlas
    local rawSourceText = entryInfo.sourceText
    if not Safe.IsReadable(rawIconTexture)
        or not Safe.IsReadable(rawIconAtlas)
        or not Safe.IsReadable(rawSourceText)
    then
        return nil
    end

    local iconTexture = Safe.AsNonNegativeInteger(rawIconTexture, nil, 2147483647)
    local iconAtlas = Safe.TrimmedString(rawIconAtlas, nil, 128)
    local sourceText = Safe.TrimmedString(rawSourceText, nil, 2048)

    return {
        recordID = variantRecordID,
        itemID = itemID,
        entryType = variantEntryType,
        name = name,
        iconTexture = iconTexture,
        iconAtlas = iconAtlas,
        sourceText = sourceText,
        addedFrom = "catalog",
    }
end

local function GetActiveList()
    local store = Addon:GetModule("Store")
    if not Safe.IsTable(store)
        or not IsCallable(store.GetActiveList)
        or not IsCallable(store.AddItem)
    then
        return nil
    end

    local list = store:GetActiveList()
    if not Safe.IsTable(list) then
        return store
    end

    local listID = Safe.AsString(list.id, nil)
    local listName = Safe.TrimmedString(list.name, nil, MAX_MENU_LIST_NAME_LENGTH)
    if not listID or not listName then
        return store
    end

    return store, listID, listName
end

local function SetDisabledTooltip(buttonDescription)
    if not Safe.IsTable(buttonDescription) or not IsCallable(buttonDescription.SetTooltip) then
        return
    end

    buttonDescription:SetTooltip(function(tooltip)
        if IsCallable(GameTooltip_SetTitle) then
            GameTooltip_SetTitle(tooltip, L.NO_ACTIVE_LIST)
        end
    end)
end

local function AddCatalogMenuSection(owner, rootDescription)
    if not Safe.IsTable(rootDescription) then
        return
    end

    local createDivider = rootDescription.CreateDivider
    local createTitle = rootDescription.CreateTitle
    local createButton = rootDescription.CreateButton
    if not IsCallable(createDivider) or not IsCallable(createTitle) or not IsCallable(createButton) then
        return
    end

    -- Capture a plain-data snapshot. Catalog entry frames are pooled and can be
    -- recycled after this menu is constructed.
    local item = GetMenuItem(owner)
    if not item then
        return
    end

    rootDescription:CreateDivider()
    rootDescription:CreateTitle(L.ADDON_TITLE)

    local store, listID, listName = GetActiveList()
    if not store or not listID then
        local description = rootDescription:CreateButton(L.ADD_TO_ACTIVE_LIST, function() end)
        if Safe.IsTable(description) and IsCallable(description.SetEnabled) then
            description:SetEnabled(false)
            SetDisabledTooltip(description)
        end
        return
    end

    local buttonText = string.format("%s (%s)", L.ADD_TO_ACTIVE_LIST, listName)
    rootDescription:CreateButton(buttonText, function()
        local savedItem, wasAdded = store:AddItem(listID, item, 1, "ensure")
        if not savedItem then
            return
        end

        if IsCallable(Addon.Print) then
            local messageFormat = wasAdded and L.ADDED_TO_LIST or L.ALREADY_ON_LIST
            Addon:Print(string.format(messageFormat, item.name, listName))
        end
    end)
end

function CatalogIntegration:Initialize()
    if self.initialized then
        return true
    end

    if not Safe.IsTable(Menu) or not IsCallable(Menu.ModifyMenu) then
        return false
    end

    local registered = pcall(Menu.ModifyMenu, MENU_TAG, AddCatalogMenuSection)
    if not registered then
        return false
    end

    self.initialized = true
    return true
end

Addon:RegisterModule("CatalogIntegration", CatalogIntegration)
