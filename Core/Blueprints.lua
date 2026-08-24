local _, Addon = ...

local Safe = Addon.Safe
local Blueprints = {
    pendingDraft = nil,
    pendingRequestCode = nil,
}

local EVENTS = {
    "HOUSING_BLUEPRINT_CONTENTS_RECEIVED",
    "HOUSING_BLUEPRINT_CONTENTS_FAILURE",
}

local function Callable(tableValue, key)
    if not Safe.IsTable(tableValue) then
        return nil
    end
    local value = tableValue[key]
    if not Safe.IsReadable(value) or type(value) ~= "function" then
        return nil
    end
    return value
end

local function NormalizeShareCode(value)
    local shareCode = Safe.TrimmedString(value, nil, 4096)
    if not shareCode then
        return nil
    end
    local update = Safe.IsTable(C_HousingBlueprint)
        and Callable(C_HousingBlueprint, "UpdateBlueprintStringFromInput")
    if update then
        local ok, normalized = pcall(update, shareCode)
        normalized = ok and Safe.TrimmedString(normalized, nil, 4096) or nil
        if normalized then
            shareCode = normalized
        end
    end
    return shareCode
end

local function IsDecorContentType(contentType)
    contentType = Safe.AsNonNegativeInteger(contentType, nil, 100)
    local enums = Safe.IsTable(Enum) and Enum.HousingBlueprintContentType
    local decor = Safe.IsTable(enums) and Safe.AsNonNegativeInteger(enums.Decor, nil, 100)
    return decor and contentType == decor or false
end

local function DefaultDraftName()
    if type(date) == "function" then
        local ok, label = pcall(date, "%Y-%m-%d")
        label = ok and Safe.TrimmedString(label, nil, 32) or nil
        if label then
            return "Blueprint " .. label
        end
    end
    return "Blueprint Shopping List"
end

local function Now()
    if type(GetServerTime) == "function" then
        local ok, result = pcall(GetServerTime)
        if ok then
            return Safe.AsNonNegativeInteger(result, 0)
        end
    end
    return 0
end

local function MergeItem(itemsByKey, order, item, desired, missing)
    local key = Safe.AsString(item and item.key, nil)
    if not key then
        return
    end
    local current = itemsByKey[key]
    if current then
        current.desired = math.min(9999, current.desired + desired)
        current.missing = math.min(9999, current.missing + missing)
        current.owned = math.max(0, current.desired - current.missing)
        return
    end
    item.desired = desired
    item.missing = missing
    item.owned = math.max(0, desired - missing)
    itemsByKey[key] = item
    order[#order + 1] = key
end

local function ArrayLength(value, maximum)
    if not Safe.IsTable(value) then
        return 0
    end
    local ok, length = pcall(function()
        return #value
    end)
    length = ok and Safe.AsNonNegativeInteger(length, 0, maximum) or 0
    return length
end

local function FrameIsShown(frame)
    if not Safe.IsTable(frame) then
        return false
    end
    local isShown = frame.IsShown
    if not Safe.IsReadable(isShown) or type(isShown) ~= "function" then
        return false
    end
    local ok, shown = pcall(isShown, frame)
    return ok and Safe.AsBoolean(shown, false) == true
end

local function FrameBlueprintMatch(frame, responseCode)
    if not Safe.IsTable(frame) then
        return false, false
    end
    local foundMethod = false

    local isShowingBlueprint = frame.IsShowingBlueprint
    if Safe.IsReadable(isShowingBlueprint) and type(isShowingBlueprint) == "function" then
        foundMethod = true
        local ok, matches = pcall(isShowingBlueprint, frame, responseCode)
        if ok and Safe.AsBoolean(matches, false) then
            return true, true
        end
    end

    local isShowingForTarget = frame.IsShowingBlueprintForTarget
    if Safe.IsReadable(isShowingForTarget) and type(isShowingForTarget) == "function" then
        foundMethod = true
        local getTargetGUID = frame.GetTargetGUID
        if Safe.IsReadable(getTargetGUID) and type(getTargetGUID) == "function" then
            local guidOK, targetGUID = pcall(getTargetGUID, frame)
            if guidOK and Safe.IsReadable(targetGUID) then
                local ok, matches = pcall(isShowingForTarget, frame, responseCode, targetGUID)
                if ok and Safe.AsBoolean(matches, false) then
                    return true, true
                end
            end
        end
    end
    return foundMethod, false
end

local function NativeBlueprintRequestIsVisible(responseCode)
    local importFrame = _G.HousingBlueprintImportFrame
    if Safe.IsTable(importFrame) then
        local validationContent = importFrame.ValidationContent
        if FrameIsShown(validationContent) then
            local validationHasMatch, validationMatches = FrameBlueprintMatch(validationContent, responseCode)
            local importHasMatch, importMatches = FrameBlueprintMatch(importFrame, responseCode)
            if validationHasMatch or importHasMatch then
                return validationMatches or importMatches
            end
            return false
        end
    end
    local contentList = _G.HousingBlueprintContentListFrame
    if not FrameIsShown(contentList) then
        return false
    end
    local hasMatch, matches = FrameBlueprintMatch(contentList, responseCode)
    return hasMatch and matches
end

function Blueprints:GetEvents()
    return EVENTS
end

function Blueprints:GetPendingDraft()
    return self.pendingDraft
end

function Blueprints:RequestContents(shareCode)
    shareCode = NormalizeShareCode(shareCode)
    if not shareCode then
        return false, "invalid-share-code"
    end
    local requestContents = Safe.IsTable(C_HousingBlueprint) and Callable(C_HousingBlueprint, "RequestBlueprintContents")
    if not requestContents then
        return false, "blueprint-api-unavailable"
    end
    if self.pendingRequestCode then
        return false, "request-pending"
    end

    local validateCode = Callable(C_HousingBlueprint, "IsShareCodeValid")
    if validateCode then
        local ok, valid = pcall(validateCode, shareCode)
        valid = ok and Safe.AsBoolean(valid, false) or false
        if not valid then
            return false, "invalid-share-code"
        end
    end

    local ok = pcall(requestContents, shareCode)
    if not ok then
        return false, "request-failed"
    end
    self.pendingRequestCode = shareCode
    self.requestSerial = (self.requestSerial or 0) + 1
    local serial = self.requestSerial
    local timerAPI = Safe.IsTable(C_Timer) and C_Timer or nil
    local after = timerAPI and timerAPI.After or nil
    if Safe.IsReadable(after) and type(after) == "function" then
        pcall(after, 20, function()
            if self.requestSerial == serial and self.pendingRequestCode == shareCode then
                self.pendingRequestCode = nil
            end
        end)
    end
    return true
end

function Blueprints:Normalize(contentInfo)
    if not Safe.IsTable(contentInfo) then
        return nil, "unreadable-content"
    end
    local groups = contentInfo.contentGroups
    if not Safe.IsTable(groups) then
        return nil, "missing-content-groups"
    end

    local catalog = Addon:GetModule("Catalog")
    local itemsByKey, order = {}, {}
    local totalMissing = 0
    local groupCount = ArrayLength(groups, 100)
    for groupIndex = 1, groupCount do
        local group = groups[groupIndex]
        if Safe.IsTable(group) then
            local contentType = Safe.AsNonNegativeInteger(group.contentType, nil, 100)
            local entries = group.entries
            if IsDecorContentType(contentType) and Safe.IsTable(entries) then
                local entryCount = ArrayLength(entries, 5000)
                for entryIndex = 1, entryCount do
                    local raw = entries[entryIndex]
                    if Safe.IsTable(raw) then
                        local recordID = Safe.AsPositiveInteger(raw.recordID, nil, 2147483647)
                        local total = Safe.AsPositiveInteger(raw.total, nil, 9999)
                        local missing = Safe.AsPositiveInteger(raw.numMissing, nil, 9999)
                        local invalid = Safe.AsBoolean(raw.invalid, false)
                        local blueprintName = Safe.TrimmedString(raw.name, nil, 256)
                        if invalid and total then
                            missing = total
                        end
                        if recordID and missing then
                            total = math.max(total or missing, missing)
                            local item = catalog and catalog:ResolveRecord(recordID, contentType) or nil
                            if not item then
                                item = {
                                    key = "decor:" .. recordID,
                                    recordID = recordID,
                                    contentType = contentType,
                                    name = "Decor #" .. recordID,
                                    owned = math.max(0, total - missing),
                                }
                            end
                            if blueprintName then
                                item.name = blueprintName
                            end
                            item.addedFrom = "blueprint"
                            item.invalid = invalid
                            MergeItem(itemsByKey, order, item, total, missing)
                            totalMissing = math.min(999999, totalMissing + missing)
                        end
                    end
                end
            end
        end
    end

    local items = {}
    for _, key in ipairs(order) do
        items[#items + 1] = itemsByKey[key]
    end

    return {
        name = DefaultDraftName(),
        shareCode = NormalizeShareCode(contentInfo.shareCode) or self.pendingRequestCode,
        createdAt = Now(),
        items = items,
        totalEntries = #items,
        totalMissing = totalMissing,
    }
end

function Blueprints:OnEvent(event, ...)
    event = Safe.AsString(event, nil)
    if event == "HOUSING_BLUEPRINT_CONTENTS_RECEIVED" then
        local contentInfo = ...
        if not Safe.IsTable(contentInfo) then
            return false
        end
        local responseCode = NormalizeShareCode(contentInfo.shareCode)
        if self.pendingRequestCode then
            if not responseCode or responseCode ~= self.pendingRequestCode then
                -- Another consumer superseded Retail's single request slot.
                -- Release ours, but never consume or display its response.
                self.pendingRequestCode = nil
                return false
            end
        elseif not NativeBlueprintRequestIsVisible(responseCode) then
            return false
        end
        if self.pendingRequestCode then
            self.pendingRequestCode = nil
        end
        local draft = self:Normalize(contentInfo)
        if not draft then
            return false
        end
        self.pendingDraft = draft
        local ui = Addon:GetModule("UI")
        if ui and type(ui.ShowBlueprintDraft) == "function" then
            pcall(ui.ShowBlueprintDraft, ui, draft)
        end
        return true
    elseif event == "HOUSING_BLUEPRINT_CONTENTS_FAILURE" then
        if self.pendingRequestCode then
            -- Failure payload shapes have varied; do not permanently lock all
            -- later requests when the event omits or redacts its share code.
            self.pendingRequestCode = nil
        end
        return false
    end
end

function Blueprints:CreateListFromPending(name)
    local draft = self.pendingDraft
    if not Safe.IsTable(draft) or not Safe.IsTable(draft.items) then
        return nil, "no-blueprint-draft"
    end
    local store = Addon:GetModule("Store")
    if not store then
        return nil, "store-unavailable"
    end
    local list, errorCode = store:CreateListWithItems(name or draft.name, {
        kind = "blueprint",
        shareCode = Safe.TrimmedString(draft.shareCode, nil, 4096),
    }, draft.items)
    if not list then
        return nil, errorCode
    end
    self.pendingDraft = nil
    return list
end

Addon:RegisterModule("Blueprints", Blueprints)
