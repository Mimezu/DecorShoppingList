local _, Addon = ...

local Safe = Addon.Safe
local Merchant = {
    overlays = {},
    highlightedCount = 0,
}

local function Field(tableValue, key)
    if not Safe.IsTable(tableValue) then
        return nil
    end
    local value = tableValue[key]
    return Safe.IsReadable(value) and value or nil
end

local function IsCallable(value)
    return Safe.IsReadable(value) and type(value) == "function"
end

local function CallMethod(object, methodName, ...)
    local method = Field(object, methodName)
    if not IsCallable(method) then
        return false
    end
    return pcall(method, object, ...)
end

local function HideOverlay(overlay)
    if Safe.IsTable(overlay) then
        CallMethod(overlay, "Hide")
    end
end

function Merchant:_HideAll()
    for _, overlay in pairs(self.overlays) do
        HideOverlay(overlay)
    end
    self.highlightedCount = 0
end

function Merchant:_CreateOverlay(button)
    if not Safe.IsTable(button) or not IsCallable(CreateFrame) then
        return nil
    end

    local ok, overlay = pcall(CreateFrame, "Frame", nil, button)
    if not ok or not Safe.IsTable(overlay) then
        return nil
    end
    CallMethod(overlay, "SetAllPoints", button)
    CallMethod(overlay, "EnableMouse", false)

    local buttonLevel = 0
    local levelOK, level = CallMethod(button, "GetFrameLevel")
    if levelOK then
        buttonLevel = Safe.AsNonNegativeInteger(level, 0, 10000)
    end
    CallMethod(overlay, "SetFrameLevel", buttonLevel + 8)

    local fillOK, fill = CallMethod(overlay, "CreateTexture", nil, "ARTWORK", nil, 5)
    if fillOK and Safe.IsTable(fill) then
        CallMethod(fill, "SetAllPoints", button)
        CallMethod(fill, "SetColorTexture", 1.0, 0.56, 0.08, 0.16)
        overlay.fill = fill
    end

    local glowOK, glow = CallMethod(overlay, "CreateTexture", nil, "OVERLAY", nil, 5)
    if glowOK and Safe.IsTable(glow) then
        CallMethod(glow, "SetTexture", "Interface\\Buttons\\UI-ActionButton-Border")
        CallMethod(glow, "SetPoint", "TOPLEFT", button, "TOPLEFT", -11, 11)
        CallMethod(glow, "SetPoint", "BOTTOMRIGHT", button, "BOTTOMRIGHT", 11, -11)
        CallMethod(glow, "SetVertexColor", 1.0, 0.68, 0.10, 0.9)
        CallMethod(glow, "SetBlendMode", "ADD")
        overlay.glow = glow
    end

    local borders = {}
    for index = 1, 4 do
        local textureOK, texture = CallMethod(overlay, "CreateTexture", nil, "OVERLAY", nil, 6)
        if textureOK and Safe.IsTable(texture) then
            CallMethod(texture, "SetColorTexture", 1.0, 0.72, 0.12, 1.0)
            borders[index] = texture
        end
    end
    if borders[1] then
        CallMethod(borders[1], "SetPoint", "TOPLEFT", button, "TOPLEFT", -3, 3)
        CallMethod(borders[1], "SetPoint", "TOPRIGHT", button, "TOPRIGHT", 3, 3)
        CallMethod(borders[1], "SetHeight", 3)
    end
    if borders[2] then
        CallMethod(borders[2], "SetPoint", "BOTTOMLEFT", button, "BOTTOMLEFT", -3, -3)
        CallMethod(borders[2], "SetPoint", "BOTTOMRIGHT", button, "BOTTOMRIGHT", 3, -3)
        CallMethod(borders[2], "SetHeight", 3)
    end
    if borders[3] then
        CallMethod(borders[3], "SetPoint", "TOPLEFT", button, "TOPLEFT", -3, 3)
        CallMethod(borders[3], "SetPoint", "BOTTOMLEFT", button, "BOTTOMLEFT", -3, -3)
        CallMethod(borders[3], "SetWidth", 3)
    end
    if borders[4] then
        CallMethod(borders[4], "SetPoint", "TOPRIGHT", button, "TOPRIGHT", 3, 3)
        CallMethod(borders[4], "SetPoint", "BOTTOMRIGHT", button, "BOTTOMRIGHT", 3, -3)
        CallMethod(borders[4], "SetWidth", 3)
    end

    local badgeOK, badge = pcall(CreateFrame, "Frame", nil, overlay)
    if badgeOK and Safe.IsTable(badge) then
        CallMethod(badge, "SetSize", 18, 18)
        CallMethod(badge, "SetPoint", "TOPRIGHT", button, "TOPRIGHT", 6, 6)
        CallMethod(badge, "SetFrameLevel", buttonLevel + 9)
        CallMethod(badge, "EnableMouse", false)

        local backgroundOK, background = CallMethod(badge, "CreateTexture", nil, "BACKGROUND")
        if backgroundOK and Safe.IsTable(background) then
            CallMethod(background, "SetAllPoints", badge)
            CallMethod(background, "SetColorTexture", 0.12, 0.07, 0.02, 0.98)
        end
        local ringOK, ring = CallMethod(badge, "CreateTexture", nil, "BORDER")
        if ringOK and Safe.IsTable(ring) then
            CallMethod(ring, "SetAllPoints", badge)
            CallMethod(ring, "SetTexture", "Interface\\Buttons\\UI-Quickslot2")
            CallMethod(ring, "SetVertexColor", 1.0, 0.72, 0.18, 1.0)
        end
        local textOK, count = CallMethod(badge, "CreateFontString", nil, "OVERLAY", "GameFontNormalSmall")
        if textOK and Safe.IsTable(count) then
            CallMethod(count, "SetPoint", "CENTER", badge, "CENTER", 0, 0)
            CallMethod(count, "SetTextColor", 1.0, 0.88, 0.48, 1.0)
            badge.count = count
        end
        overlay.badge = badge
    end

    self.overlays[button] = overlay
    return overlay
end

function Merchant:_GetNeededItems()
    local store = Addon:GetModule("Store")
    if not Safe.IsTable(store) then
        return {}
    end
    local getActiveList = Field(store, "GetActiveList")
    if not IsCallable(getActiveList) then
        return {}
    end
    local ok, list = pcall(getActiveList, store)
    if not ok or not Safe.IsTable(list) then
        return {}
    end
    if Safe.IsTable(self.neededCache) and self.neededCache.list == list then
        return self.neededCache.items
    end

    local needed = {}
    local registry = Addon:GetModule("SourceRegistry")
    local getItemIDs = Safe.IsTable(registry) and Field(registry, "GetItemIDsForDecorID") or nil
    local order = Field(list, "order")
    local items = Field(list, "items")
    if not Safe.IsTable(order) or not Safe.IsTable(items) then
        return needed
    end
    local examined = 0
    for _, key in ipairs(order) do
        examined = examined + 1
        if examined > 5000 then break end
        if Safe.IsReadable(key) then
            local item = Field(items, key)
            local itemID = Safe.IsTable(item) and Safe.AsPositiveInteger(Field(item, "itemID"), nil, 2147483647) or nil
            local recordID = Safe.IsTable(item) and Safe.AsPositiveInteger(Field(item, "recordID"), nil, 2147483647) or nil
            local missing = Safe.IsTable(item) and Safe.AsNonNegativeInteger(Field(item, "missing"), nil, 9999) or nil
            if itemID and missing and missing > 0 then
                needed[itemID] = math.max(needed[itemID] or 0, missing)
            elseif recordID and missing and missing > 0 and IsCallable(getItemIDs) then
                local mappingOK, itemIDs = pcall(getItemIDs, registry, recordID)
                if mappingOK and Safe.IsTable(itemIDs) then
                    local resolvedCount = 0
                    for _, resolvedItemID in ipairs(itemIDs) do
                        resolvedCount = resolvedCount + 1
                        if resolvedCount > 32 then break end
                        resolvedItemID = Safe.AsPositiveInteger(resolvedItemID, nil, 2147483647)
                        if resolvedItemID then
                            needed[resolvedItemID] = math.max(needed[resolvedItemID] or 0, missing)
                        end
                    end
                end
            end
        end
    end
    self.neededCache = { list = list, items = needed }
    return needed
end

function Merchant:InvalidateNeeded()
    self.neededCache = nil
end

local function GetMerchantItemIDSafe(index)
    if IsCallable(GetMerchantItemID) then
        local ok, itemID = pcall(GetMerchantItemID, index)
        itemID = ok and Safe.AsPositiveInteger(itemID, nil, 2147483647) or nil
        if itemID then return itemID end
    end

    if not IsCallable(GetMerchantItemLink) then
        return nil
    end
    local ok, link = pcall(GetMerchantItemLink, index)
    link = ok and Safe.AsString(link, nil) or nil
    local itemAPI = Safe.IsTable(C_Item) and C_Item or nil
    local getInstant = itemAPI and Field(itemAPI, "GetItemInfoInstant") or nil
    if not link or not IsCallable(getInstant) then
        return nil
    end
    local infoOK, itemID = pcall(getInstant, link)
    return infoOK and Safe.AsPositiveInteger(itemID, nil, 2147483647) or nil
end

function Merchant:Refresh(reason)
    if Safe.AsString(reason, nil) then
        self:InvalidateNeeded()
    end
    self:_HideAll()

    local frame = Safe.IsReadable(MerchantFrame) and MerchantFrame or nil
    if not Safe.IsTable(frame) then
        return 0
    end
    local shownOK, shown = CallMethod(frame, "IsShown")
    if not shownOK or Safe.AsBoolean(shown, false) ~= true then
        return 0
    end
    local selectedTab = Safe.AsPositiveInteger(Field(frame, "selectedTab"), 1, 10)
    if selectedTab ~= 1 then
        return 0
    end

    local needed = self:_GetNeededItems()
    if not next(needed) then
        return 0
    end

    local page = Safe.AsPositiveInteger(Field(frame, "page"), 1, 10000)
    local perPage = Safe.AsPositiveInteger(MERCHANT_ITEMS_PER_PAGE, 12, 60)
    for position = 1, perPage do
        local button = _G["MerchantItem" .. position .. "ItemButton"]
        if Safe.IsTable(button) then
            local buttonShownOK, buttonShown = CallMethod(button, "IsShown")
            local merchantIndex = ((page - 1) * perPage) + position
            local itemID = buttonShownOK and Safe.AsBoolean(buttonShown, false)
                and GetMerchantItemIDSafe(merchantIndex) or nil
            local missing = itemID and needed[itemID] or nil
            if missing then
                local overlay = self.overlays[button] or self:_CreateOverlay(button)
                if overlay then
                    local badge = Field(overlay, "badge")
                    local count = Field(badge, "count")
                    if Safe.IsTable(count) then
                        CallMethod(count, "SetFormattedText", "%d", missing)
                    end
                    CallMethod(overlay, "Show")
                    self.highlightedCount = self.highlightedCount + 1
                end
            end
        end
    end
    return self.highlightedCount
end

function Merchant:OnEvent(event)
    event = Safe.AsString(event, nil)
    if event == "MERCHANT_CLOSED" then
        self:_HideAll()
        return
    end
    if event == "MERCHANT_SHOW" then
        self:_InstallUpdateHook()
    end
    if event == "MERCHANT_SHOW" or event == "MERCHANT_UPDATE" then
        self:Refresh()
    end
end

function Merchant:_InstallUpdateHook()
    if self.updateHooked or not IsCallable(hooksecurefunc) or not IsCallable(MerchantFrame_Update) then
        return self.updateHooked == true
    end
    local ok = pcall(hooksecurefunc, "MerchantFrame_Update", function()
        Merchant:Refresh()
    end)
    if ok then
        self.updateHooked = true
    end
    return self.updateHooked == true
end

function Merchant:Initialize()
    local eventFrame = Addon.eventFrame
    if Safe.IsTable(eventFrame) then
        for _, event in ipairs({ "MERCHANT_SHOW", "MERCHANT_UPDATE", "MERCHANT_CLOSED" }) do
            CallMethod(eventFrame, "RegisterEvent", event)
        end
    end
    self:_InstallUpdateHook()
    return true
end

Addon:RegisterModule("MerchantIntegration", Merchant)
