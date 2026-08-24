local _, Addon = ...

local Safe = Addon.Safe
local Store = {
    SCHEMA_VERSION = 1,
    DEFAULT_LIST_NAME = "My Decor List",
    MAX_LISTS = 200,
    MAX_ITEMS_PER_LIST = 5000,
}

local function Now()
    local value
    if type(GetServerTime) == "function" then
        local ok, result = pcall(GetServerTime)
        if ok then
            value = Safe.AsNonNegativeInteger(result, nil)
        end
    end
    return value or 0
end

local function CleanName(value, fallback)
    return Safe.TrimmedString(value, fallback, 96)
end

local function CopyPlainValue(value, depth, state)
    if not Safe.IsReadable(value) or state.count >= 500 then
        return nil
    end
    local valueType = type(value)
    if valueType == "string" then
        return Safe.AsString(value, ""):sub(1, 4096)
    elseif valueType == "number" then
        return Safe.AsNumber(value, nil)
    elseif valueType == "boolean" then
        return Safe.AsBoolean(value, nil)
    elseif valueType ~= "table" or depth >= 3 or state.seen[value] then
        return nil
    end

    state.seen[value] = true
    local copy = {}
    for rawKey, rawChild in pairs(value) do
        if state.count >= 500 then
            break
        end
        state.count = state.count + 1
        local key
        if Safe.IsReadable(rawKey) and type(rawKey) == "string" then
            key = rawKey:sub(1, 128)
        elseif Safe.IsReadable(rawKey) and type(rawKey) == "number" then
            key = Safe.AsPositiveInteger(rawKey, nil, 10000)
        end
        if key ~= nil then
            local child = CopyPlainValue(rawChild, depth + 1, state)
            if child ~= nil then
                copy[key] = child
            end
        end
    end
    state.seen[value] = nil
    return copy
end

local function CleanSettings(value)
    if not Safe.IsTable(value) then
        return {}
    end
    return CopyPlainValue(value, 0, { count = 0, seen = {} }) or {}
end

local function CleanID(value)
    local text = Safe.AsString(value, nil)
    if text and text:match("^%d+$") then
        local number = Safe.AsPositiveInteger(tonumber(text), nil, 2147483647)
        return number and tostring(number) or nil
    end
    local number = Safe.AsPositiveInteger(value, nil, 2147483647)
    return number and tostring(number) or nil
end

local function CleanItem(raw)
    if not Safe.IsTable(raw) then
        return nil
    end

    local recordID = Safe.AsPositiveInteger(raw.recordID, nil, 2147483647)
    local itemID = Safe.AsPositiveInteger(raw.itemID, nil, 2147483647)
    if not recordID and not itemID then
        return nil
    end

    local key = recordID and ("decor:" .. recordID) or ("item:" .. itemID)

    local desired = Safe.AsPositiveInteger(raw.desired, 1, 9999)
    local owned = Safe.AsNonNegativeInteger(raw.owned, 0, 999999)
    local missing = Safe.AsNonNegativeInteger(raw.missing, nil, 999999)
    if missing == nil then
        missing = math.max(0, desired - owned)
    end

    local addedFrom = Safe.TrimmedString(raw.addedFrom, "manual", 32)
    if addedFrom ~= "catalog" and addedFrom ~= "blueprint" and addedFrom ~= "manual" then
        addedFrom = "manual"
    end

    return {
        key = key,
        recordID = recordID,
        itemID = itemID,
        entryType = Safe.AsNonNegativeInteger(raw.entryType, nil, 100),
        contentType = Safe.AsNonNegativeInteger(raw.contentType, nil, 100),
        name = CleanName(raw.name, recordID and ("Decor #" .. recordID) or ("Item #" .. itemID)),
        iconTexture = Safe.AsNonNegativeInteger(raw.iconTexture, nil, 2147483647),
        iconAtlas = Safe.TrimmedString(raw.iconAtlas, nil, 128),
        sourceText = Safe.TrimmedString(raw.sourceText, nil, 2048),
        addedFrom = addedFrom,
        invalid = Safe.AsBoolean(raw.invalid, false),
        desired = desired,
        owned = owned,
        missing = math.max(0, math.min(desired, missing)),
        addedAt = Safe.AsNonNegativeInteger(raw.addedAt, Now()),
    }
end

local function CleanSource(raw)
    if not Safe.IsTable(raw) then
        return { kind = "manual" }
    end
    local kind = Safe.TrimmedString(raw.kind, "manual", 32)
    if kind ~= "blueprint" and kind ~= "catalog" and kind ~= "manual" then
        kind = "manual"
    end
    local source = { kind = kind }
    if kind == "blueprint" then
        source.shareCode = Safe.TrimmedString(raw.shareCode, nil, 4096)
    end
    return source
end

local function CleanList(raw, id)
    if not Safe.IsTable(raw) then
        return nil
    end

    local list = {
        id = id,
        name = CleanName(raw.name, "Decor List " .. id),
        source = CleanSource(Safe.IsTable(raw.source) and raw.source or {
            kind = raw.sourceType,
            shareCode = raw.sourceCode,
        }),
        sourceType = Safe.TrimmedString(raw.sourceType, nil, 32),
        sourceCode = Safe.TrimmedString(raw.sourceCode, nil, 4096),
        createdAt = Safe.AsNonNegativeInteger(raw.createdAt, Now()),
        updatedAt = Safe.AsNonNegativeInteger(raw.updatedAt, Now()),
        items = {},
        order = {},
    }
    list.sourceType = list.source.kind
    list.sourceCode = list.source.shareCode

    local rawItems = Safe.IsTable(raw.items) and raw.items or {}
    local rawOrder = Safe.IsTable(raw.order) and raw.order or {}
    local seen = {}

    for _, rawKey in ipairs(rawOrder) do
        if #list.order >= Store.MAX_ITEMS_PER_LIST then
            break
        end
        local key = Safe.AsString(rawKey, nil)
        if key and not seen[key] then
            local item = CleanItem(rawItems[key])
            if item then
                list.items[item.key] = item
                list.order[#list.order + 1] = item.key
                seen[item.key] = true
            end
        end
    end

    for rawKey, rawItem in pairs(rawItems) do
        local knownKey = Safe.AsString(rawKey, nil)
        if knownKey and not seen[knownKey] then
            local item = CleanItem(rawItem)
            if item and not seen[item.key] and #list.order < Store.MAX_ITEMS_PER_LIST then
                list.items[item.key] = item
                list.order[#list.order + 1] = item.key
                seen[item.key] = true
            end
        end
    end

    return list
end

function Store:_Notify(reason, payload)
    if type(self.changeHandler) == "function" then
        pcall(self.changeHandler, reason, payload)
    end
end

function Store:SetChangeHandler(handler)
    self.changeHandler = type(handler) == "function" and handler or nil
end

function Store:Initialize()
    if self.initialized then
        return self.db
    end

    local raw = _G.DecorShoppingListDB
    if not Safe.IsTable(raw) then
        raw = {}
    end

    local clean = {
        schemaVersion = self.SCHEMA_VERSION,
        nextListID = 1,
        activeListID = nil,
        lists = {},
        settings = CleanSettings(raw.settings),
    }

    local savedSchemaVersion = Safe.AsNonNegativeInteger(raw.schemaVersion, 0, 2147483647)
    if savedSchemaVersion > self.SCHEMA_VERSION then
        self.db = clean
        self.initialized = true
        self.readOnlyUnsupported = true
        if type(Addon.Print) == "function" then
            pcall(Addon.Print, Addon, "Saved data is from a newer addon version and was left unchanged. Update Decor Shopping List before editing lists.")
        end
        return self.db
    end

    local rawLists = Safe.IsTable(raw.lists) and raw.lists or {}
    local highestID = 0
    local count = 0
    for rawID, rawList in pairs(rawLists) do
        local id = CleanID(rawID) or (Safe.IsTable(rawList) and CleanID(rawList.id))
        local numericID = id and tonumber(id)
        if id and numericID and not clean.lists[id] and count < self.MAX_LISTS then
            local list = CleanList(rawList, id)
            if list then
                clean.lists[id] = list
                count = count + 1
                highestID = math.max(highestID, numericID)
            end
        end
    end

    clean.nextListID = math.max(highestID + 1, Safe.AsPositiveInteger(raw.nextListID, 1, 2147483647))
    local activeID = CleanID(raw.activeListID)
    if activeID and clean.lists[activeID] then
        clean.activeListID = activeID
    end

    self.db = clean
    _G.DecorShoppingListDB = clean
    self.initialized = true

    if count == 0 then
        self:CreateList(self.DEFAULT_LIST_NAME, { kind = "manual" })
    elseif not clean.activeListID then
        local lists = self:GetLists()
        clean.activeListID = lists[1] and lists[1].id or nil
    end

    return self.db
end

function Store:_UniqueName(name, excludeID)
    local base = CleanName(name, self.DEFAULT_LIST_NAME)
    local occupied = {}
    for id, list in pairs(self.db.lists) do
        if id ~= excludeID then
            occupied[list.name:lower()] = true
        end
    end
    if not occupied[base:lower()] then
        return base
    end
    for suffix = 2, self.MAX_LISTS + 1 do
        local suffixText = string.format(" (%d)", suffix)
        local candidate = base:sub(1, 96 - #suffixText) .. suffixText
        if not occupied[candidate:lower()] then
            return candidate
        end
    end
    return base
end

function Store:CreateList(name, source, sourceCode)
    self:Initialize()
    if self.readOnlyUnsupported then
        return nil, "unsupported-schema"
    end
    if #self:GetLists() >= self.MAX_LISTS then
        return nil, "too-many-lists"
    end

    local id = tostring(self.db.nextListID)
    while self.db.lists[id] do
        self.db.nextListID = self.db.nextListID + 1
        id = tostring(self.db.nextListID)
    end
    self.db.nextListID = self.db.nextListID + 1

    local sourceKind = Safe.AsString(source, nil)
    if sourceKind then
        source = { kind = sourceKind, shareCode = Safe.AsString(sourceCode, nil) }
    elseif not Safe.IsTable(source) then
        source = nil
    end
    local timestamp = Now()
    local list = {
        id = id,
        name = self:_UniqueName(name),
        source = CleanSource(source),
        createdAt = timestamp,
        updatedAt = timestamp,
        items = {},
        order = {},
    }
    list.sourceType = list.source.kind
    list.sourceCode = list.source.shareCode
    self.db.lists[id] = list
    self.db.activeListID = id
    self:_Notify("list-created", list)
    return list
end

function Store:CreateListWithItems(name, source, items)
    self:Initialize()
    if self.readOnlyUnsupported then
        return nil, "unsupported-schema"
    end
    if #self:GetLists() >= self.MAX_LISTS then
        return nil, "too-many-lists"
    end
    if not Safe.IsTable(items) then
        return nil, "invalid-items"
    end

    local preparedItems, preparedOrder = {}, {}
    local count = 0
    for _, rawItem in ipairs(items) do
        count = count + 1
        if count > self.MAX_ITEMS_PER_LIST then
            return nil, "too-many-items"
        end
        local item = CleanItem(rawItem)
        if not item then
            return nil, "invalid-item"
        end
        local desired = Safe.AsPositiveInteger(rawItem.desired, item.desired, 9999)
        item.desired = desired
        item.missing = math.max(0, desired - item.owned)
        if preparedItems[item.key] then
            return nil, "duplicate-item"
        end
        preparedItems[item.key] = item
        preparedOrder[#preparedOrder + 1] = item.key
    end

    local sourceKind = Safe.AsString(source, nil)
    if sourceKind then
        source = { kind = sourceKind }
    elseif not Safe.IsTable(source) then
        source = nil
    end
    local id = tostring(self.db.nextListID)
    while self.db.lists[id] do
        self.db.nextListID = self.db.nextListID + 1
        id = tostring(self.db.nextListID)
    end
    self.db.nextListID = self.db.nextListID + 1
    local timestamp = Now()
    local list = {
        id = id,
        name = self:_UniqueName(name),
        source = CleanSource(source),
        createdAt = timestamp,
        updatedAt = timestamp,
        items = preparedItems,
        order = preparedOrder,
    }
    list.sourceType = list.source.kind
    list.sourceCode = list.source.shareCode
    self.db.lists[id] = list
    self.db.activeListID = id
    self:_Notify("list-created", list)
    return list
end

function Store:GetList(id)
    self:Initialize()
    id = CleanID(id)
    return id and self.db.lists[id] or nil
end

function Store:GetLists()
    self:Initialize()
    local lists = {}
    for _, list in pairs(self.db.lists) do
        lists[#lists + 1] = list
    end
    table.sort(lists, function(a, b)
        if a.createdAt == b.createdAt then
            return tonumber(a.id) < tonumber(b.id)
        end
        return a.createdAt < b.createdAt
    end)
    return lists
end

function Store:GetActiveList()
    self:Initialize()
    return self.db.activeListID and self.db.lists[self.db.activeListID] or nil
end

function Store:SetActiveList(id)
    self:Initialize()
    if self.readOnlyUnsupported then
        return nil, "unsupported-schema"
    end
    local list = self:GetList(id)
    if not list then
        return nil, "list-not-found"
    end
    if self.db.activeListID ~= list.id then
        self.db.activeListID = list.id
        self:_Notify("active-list-changed", list)
    end
    return list
end

function Store:RenameList(id, name)
    self:Initialize()
    if self.readOnlyUnsupported then
        return nil, "unsupported-schema"
    end
    local list = self:GetList(id)
    if not list then
        return nil, "list-not-found"
    end
    local cleanName = CleanName(name, nil)
    if not cleanName then
        return nil, "invalid-name"
    end
    list.name = self:_UniqueName(cleanName, list.id)
    list.updatedAt = Now()
    self:_Notify("list-renamed", list)
    return list
end

function Store:DeleteList(id)
    self:Initialize()
    if self.readOnlyUnsupported then
        return false, "unsupported-schema"
    end
    local list = self:GetList(id)
    if not list then
        return false, "list-not-found"
    end
    self.db.lists[list.id] = nil
    if self.db.activeListID == list.id then
        local remaining = self:GetLists()
        self.db.activeListID = remaining[1] and remaining[1].id or nil
    end
    if not self.db.activeListID then
        self:CreateList(self.DEFAULT_LIST_NAME, { kind = "manual" })
    else
        self:_Notify("list-deleted", list)
    end
    return true
end

function Store:AddItem(listID, itemTable, desiredQuantity, mode)
    self:Initialize()
    if self.readOnlyUnsupported then
        return nil, "unsupported-schema"
    end
    local list = self:GetList(listID)
    if not list then
        return nil, "list-not-found"
    end
    local normalizedMode = Safe.AsString(mode, nil)
    if normalizedMode == nil and Safe.IsReadable(mode) and type(mode) == "nil" then
        normalizedMode = "ensure"
    end
    if normalizedMode ~= "ensure" and normalizedMode ~= "replace" then
        return nil, "invalid-mode"
    end
    mode = normalizedMode

    local suppliedOwned = Safe.IsTable(itemTable) and Safe.AsNonNegativeInteger(itemTable.owned, nil, 999999) or nil
    local suppliedMissing = Safe.IsTable(itemTable) and Safe.AsNonNegativeInteger(itemTable.missing, nil, 999999) or nil
    local suppliedAddedFrom = Safe.IsTable(itemTable) and Safe.TrimmedString(itemTable.addedFrom, nil, 32) or nil
    local suppliedName = Safe.IsTable(itemTable) and CleanName(itemTable.name, nil) or nil
    local suppliedInvalid = Safe.IsTable(itemTable) and Safe.AsBoolean(itemTable.invalid, nil) or nil
    local incoming = CleanItem(itemTable)
    if not incoming then
        return nil, "invalid-item"
    end
    local desired = Safe.AsPositiveInteger(desiredQuantity, incoming.desired, 9999)
    local existing = list.items[incoming.key]
    if existing then
        local changed = false
        local function AssignIfChanged(key, value)
            if value ~= nil and existing[key] ~= value then
                existing[key] = value
                changed = true
            end
        end
        if suppliedName then
            AssignIfChanged("name", suppliedName)
        end
        AssignIfChanged("itemID", incoming.itemID)
        AssignIfChanged("recordID", incoming.recordID)
        AssignIfChanged("entryType", incoming.entryType)
        AssignIfChanged("contentType", incoming.contentType)
        AssignIfChanged("iconTexture", incoming.iconTexture)
        AssignIfChanged("iconAtlas", incoming.iconAtlas)
        AssignIfChanged("sourceText", incoming.sourceText)
        if suppliedAddedFrom and mode == "replace" then
            AssignIfChanged("addedFrom", incoming.addedFrom)
        end
        if suppliedInvalid ~= nil then
            AssignIfChanged("invalid", suppliedInvalid)
        end
        if suppliedOwned ~= nil then
            AssignIfChanged("owned", suppliedOwned)
        end
        local previousDesired = existing.desired
        if mode == "replace" then
            existing.desired = desired
        else
            existing.desired = math.max(existing.desired, desired)
        end
        if existing.desired ~= previousDesired then changed = true end
        local previousOwned, previousMissing = existing.owned, existing.missing
        if suppliedMissing ~= nil and suppliedOwned == nil then
            existing.missing = math.min(existing.desired, suppliedMissing)
            existing.owned = math.max(0, existing.desired - existing.missing)
        else
            existing.missing = math.max(0, existing.desired - (existing.owned or 0))
        end
        if existing.owned ~= previousOwned or existing.missing ~= previousMissing then changed = true end
        if changed then
            list.updatedAt = Now()
            self:_Notify("item-updated", { list = list, item = existing })
        end
        return existing, false
    end

    if #list.order >= self.MAX_ITEMS_PER_LIST then
        return nil, "too-many-items"
    end
    incoming.desired = desired
    if suppliedMissing ~= nil and suppliedOwned == nil then
        incoming.missing = math.min(desired, suppliedMissing)
        incoming.owned = math.max(0, desired - incoming.missing)
    else
        incoming.missing = math.max(0, desired - (incoming.owned or 0))
    end
    list.items[incoming.key] = incoming
    list.order[#list.order + 1] = incoming.key
    list.updatedAt = Now()
    self:_Notify("item-added", { list = list, item = incoming })
    return incoming, true
end

function Store:RemoveItem(listID, itemKey)
    self:Initialize()
    if self.readOnlyUnsupported then
        return false, "unsupported-schema"
    end
    local list = self:GetList(listID)
    itemKey = Safe.AsString(itemKey, nil)
    if not list or not itemKey or not list.items[itemKey] then
        return false, "item-not-found"
    end
    local removed = list.items[itemKey]
    list.items[itemKey] = nil
    for index, key in ipairs(list.order) do
        if key == itemKey then
            table.remove(list.order, index)
            break
        end
    end
    list.updatedAt = Now()
    self:_Notify("item-removed", { list = list, item = removed })
    return true
end

function Store:RemoveCompletedItems(listID)
    self:Initialize()
    if self.readOnlyUnsupported then
        return 0, "unsupported-schema"
    end
    local list = self:GetList(listID)
    if not list then
        return 0, "list-not-found"
    end

    local removed = 0
    local retained = {}
    for _, key in ipairs(list.order) do
        local item = list.items[key]
        local missing = Safe.IsTable(item) and Safe.AsNonNegativeInteger(item.missing, nil, 999999) or nil
        if missing ~= nil and missing == 0 then
            list.items[key] = nil
            removed = removed + 1
        else
            retained[#retained + 1] = key
        end
    end
    if removed > 0 then
        list.order = retained
        list.updatedAt = Now()
        self:_Notify("completed-items-removed", { list = list, count = removed })
    end
    return removed
end

function Store:SetItemDesired(listID, itemKey, desiredQuantity)
    self:Initialize()
    if self.readOnlyUnsupported then
        return nil, "unsupported-schema"
    end
    local list = self:GetList(listID)
    itemKey = Safe.AsString(itemKey, nil)
    local item = list and itemKey and list.items[itemKey] or nil
    if not item then
        return nil, "item-not-found"
    end
    local desired = Safe.AsPositiveInteger(desiredQuantity, nil, 9999)
    if not desired then
        return nil, "invalid-quantity"
    end
    item.desired = desired
    item.missing = math.max(0, desired - (item.owned or 0))
    list.updatedAt = Now()
    self:_Notify("item-quantity-changed", { list = list, item = item })
    return item
end

Addon:RegisterModule("Store", Store)
