local _, Addon = ...

local UI = {}
Addon:RegisterModule("UI", UI)

local Safe = Addon.Safe

local ROW_HEIGHT = 56
local LIST_ROW_HEIGHT = 34
local MOUSE_WHEEL_ROWS = 3
local SOURCE_FILTERS = { "all", "vendor", "craft", "drop", "quest", "unknown" }
local SOURCE_LABELS = {
    all = "All sources",
    vendor = "Vendors",
    craft = "Crafting",
    drop = "Loot",
    quest = "Quest / Rep",
    unknown = "Unknown",
}
local SOURCE_ALIASES = {
    crafting = "craft",
    crafted = "craft",
    loot = "drop",
    reputation = "quest",
    catalog = "unknown",
}
local TEST_PREVIEW_MODES = {
    default = true,
    dense = true,
    empty = true,
    readonly = true,
}
local TEST_DECOR = {
    { "Silvermoon Curio Shelves", "vendor", "Vendor · Silvermoon City", "Interface\\Icons\\INV_Misc_Book_09" },
    { "Small Elegant End Table", "craft", "Crafting · Woodworking", "Interface\\Icons\\INV_Misc_Bag_10" },
    { "Sprouting Lamppost", "quest", "Quest · Hallowfall", "Interface\\Icons\\INV_Misc_Lantern_01" },
    { "Rectangular Elven Floor Rug", "drop", "Loot · Azj-Kahet", "Interface\\Icons\\INV_Fabric_Linen_01" },
    { "Sturdy Wooden Trellis", "vendor", "Vendor · Dornogal", "Interface\\Icons\\INV_Misc_Herb_19" },
    { "Sunlit Glass Mirror", "unknown", "Source not mapped", "Interface\\Icons\\INV_Misc_Gem_Pearl_05" },
    { "Reinforced Wooden Chest", "craft", "Crafting · Blacksmithing", "Interface\\Icons\\INV_Misc_Chest_03" },
    { "Small Purple Suramar Cushion", "quest", "Reputation · Suramar", "Interface\\Icons\\INV_Misc_Bag_10_Blue" },
}
local TEST_LIST_NAMES = {
    "Silvermoon Lounge", "Garden Entrance", "Guest Room", "Workshop",
    "Library", "Kitchen", "Courtyard", "Greenhouse", "Study",
    "Dining Hall", "Bedroom", "Balcony", "Gallery", "Cellar",
    "Festival Set", "Spare Ideas",
}

local function buildTestItems(count, seed)
    local items, order = {}, {}
    seed = seed or 0
    for index = 1, count do
        local spec = TEST_DECOR[((index + seed - 1) % #TEST_DECOR) + 1]
        local desired = ((index + seed) % 4) + 1
        local owned = (index + seed) % (desired + 1)
        local key = "preview:" .. seed .. ":" .. index
        local cycle = math.floor((index - 1) / #TEST_DECOR)
        local name = spec[1] .. (cycle > 0 and (" " .. (cycle + 1)) or "")
        items[key] = {
            key = key,
            name = name,
            iconTexture = spec[4],
            sourceType = spec[2],
            sourceText = spec[3],
            desired = desired,
            owned = owned,
            missing = math.max(0, desired - owned),
            previewItem = true,
        }
        order[#order + 1] = key
    end
    return items, order
end

local function buildTestList(index, itemCount)
    local items, order = buildTestItems(itemCount or 0, index * 10)
    return {
        id = "preview-list:" .. index,
        name = TEST_LIST_NAMES[index] or ("Room " .. index),
        items = items,
        order = order,
        sourceType = "manual",
    }
end

local function buildTestPreview(mode)
    local preview = { mode = mode, lists = {} }
    if mode == "readonly" then
        return preview
    end

    local listCount = mode == "dense" and #TEST_LIST_NAMES or 4
    for index = 1, listCount do
        local itemCount = 0
        if mode ~= "empty" then
            if index == 1 then
                itemCount = mode == "dense" and 36 or 8
            elseif index <= 4 then
                itemCount = math.max(1, 5 - index)
            end
        end
        preview.lists[index] = buildTestList(index, itemCount)
    end
    preview.activeList = preview.lists[1]
    return preview
end

local function isSecret(value)
    return Safe and not Safe.IsReadable(value) or false
end

local function safeString(value, fallback)
    return Safe.AsString(value, fallback or "")
end

local function safeNumber(value, fallback)
    return Safe.AsNumber(value, fallback or 0)
end

local function call(module, method, ...)
    if not Safe.IsTable(module) then
        return nil, "unavailable"
    end
    local func = module[method]
    if not Safe.IsReadable(func) or type(func) ~= "function" then
        return nil, "unavailable"
    end
    local ok, a, b, c = pcall(func, module, ...)
    if not ok then
        return nil, "failed"
    end
    return a, b, c
end

local function updateScrollThumb(scroll, totalRows, visibleRows)
    if not Safe.IsTable(scroll) then return end
    local thumb = scroll.decorShoppingListThumb
    if not Safe.IsTable(thumb) then return end
    local trackHeight = math.max(26, safeNumber(scroll:GetHeight(), 26))
    local fraction = totalRows > 0 and math.min(1, visibleRows / totalRows) or 1
    thumb:SetHeight(math.max(26, math.floor(trackHeight * fraction + 0.5)))
end

local function bindMouseWheel(frame, handler)
    if not Safe.IsTable(frame) or type(handler) ~= "function" then return end
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", handler)
end

local function trim(value)
    value = safeString(value, "")
    return value:match("^%s*(.-)%s*$") or ""
end

local function setEnabled(button, enabled, disabledReason)
    if enabled then
        button.disabledReason = nil
        button:Enable()
    else
        button.disabledReason = disabledReason
        button:Disable()
    end
end

local function setButtonTooltip(button, title, body)
    button:SetScript("OnEnter", function(owner)
        local Theme = Addon:GetModule("Theme")
        call(Theme, "SetTooltip", owner, title, owner.disabledReason or body)
    end)
    button:SetScript("OnLeave", function()
        local Theme = Addon:GetModule("Theme")
        call(Theme, "HideTooltip")
    end)
end

local function addEscapeFrame(frame, globalName)
    _G[globalName] = frame
    UISpecialFrames = UISpecialFrames or {}
    for _, name in ipairs(UISpecialFrames) do
        if name == globalName then
            return
        end
    end
    table.insert(UISpecialFrames, globalName)
end

local function addPriorityEscapeFrame(frame, globalName)
    _G[globalName] = frame
    UISpecialFrames = UISpecialFrames or {}
    for index = #UISpecialFrames, 1, -1 do
        if UISpecialFrames[index] == globalName then
            table.remove(UISpecialFrames, index)
        end
    end
    table.insert(UISpecialFrames, 1, globalName)
end

function UI:GetStore()
    return Addon:GetModule("Store")
end

function UI:GetTheme()
    return Addon:GetModule("Theme")
end

function UI:IsTestPreview()
    return Safe.IsTable(self.testPreview)
end

function UI:IsReadOnlyUnsupported()
    if self:IsTestPreview() then
        return self.testPreview.mode == "readonly"
    end
    local store = self:GetStore()
    return Safe.IsTable(store) and Safe.AsBoolean(store.readOnlyUnsupported, false)
end

function UI:IsMutationLocked()
    return self:IsTestPreview() or self:IsReadOnlyUnsupported()
end

function UI:GetMutationLockReason()
    if self:IsTestPreview() then
        return "Preview only. Use /dsl testui off to return."
    end
    return "Update the addon before editing saved lists."
end

function UI:GetActiveList()
    if self:IsTestPreview() then
        return Safe.IsTable(self.testPreview.activeList) and self.testPreview.activeList or nil
    end
    local list = call(self:GetStore(), "GetActiveList")
    return Safe and Safe.IsTable(list) and list or nil
end

function UI:ShowPrompt(title, value, acceptText, callback, options)
    local prompt = self.prompt
    if not prompt then
        return
    end
    options = options or {}
    prompt.title:SetText(safeString(title, "Shopping List"))
    prompt.description:SetText(safeString(options.description, ""))
    prompt.edit:SetText(safeString(value, ""))
    prompt.edit:SetShown(options.noInput ~= true)
    prompt.accept:SetText(safeString(acceptText, "Save"))
    prompt.callback = callback
    prompt.noInput = options.noInput == true
    prompt:Show()
    prompt:Raise()
    if not prompt.noInput then
        prompt.edit:SetFocus()
        prompt.edit:HighlightText()
    end
end

function UI:CreatePrompt(frame)
    local Theme = self:GetTheme()
    local prompt = Theme:CreateInset(frame)
    prompt:SetSize(350, 144)
    prompt:SetPoint("CENTER", frame, "CENTER", 80, 0)
    prompt:SetFrameLevel(safeNumber(frame:GetFrameLevel(), 1) + 30)
    prompt:EnableMouse(true)
    prompt:Hide()

    local blocker = CreateFrame("Frame", nil, frame)
    blocker:SetFrameLevel(safeNumber(frame:GetFrameLevel(), 1) + 20)
    blocker:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -10)
    blocker:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 10)
    blocker:EnableMouse(true)
    blocker:EnableMouseWheel(true)
    blocker:SetScript("OnMouseWheel", function() end)
    blocker:Hide()
    local shade = blocker:CreateTexture(nil, "BACKGROUND")
    shade:SetColorTexture(0, 0, 0, 0.58)
    shade:SetAllPoints()
    prompt.blocker = blocker
    prompt:HookScript("OnShow", function(promptFrame) promptFrame.blocker:Show() end)
    prompt:HookScript("OnHide", function(promptFrame)
        promptFrame.blocker:Hide()
        promptFrame.edit:ClearFocus()
        promptFrame.callback = nil
    end)

    prompt.title = prompt:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    prompt.title:SetPoint("TOPLEFT", 18, -16)
    prompt.title:SetPoint("TOPRIGHT", -18, -16)
    prompt.title:SetJustifyH("LEFT")
    prompt.title:SetTextColor(unpack(Theme.colors.title))

    prompt.description = prompt:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    prompt.description:SetPoint("TOPLEFT", prompt.title, "BOTTOMLEFT", 0, -7)
    prompt.description:SetPoint("TOPRIGHT", prompt.title, "BOTTOMRIGHT", 0, -7)
    prompt.description:SetJustifyH("LEFT")

    prompt.edit = Theme:CreateFrame("EditBox", prompt, "InputBoxTemplate")
    prompt.edit:SetSize(310, 25)
    prompt.edit:SetPoint("TOP", 0, -63)
    prompt.edit:SetAutoFocus(false)
    prompt.edit:SetMaxLetters(64)

    prompt.accept = Theme:CreateButton(prompt, "Save", 100, 24)
    prompt.accept:SetPoint("BOTTOMRIGHT", -18, 14)
    prompt.cancel = Theme:CreateButton(prompt, CANCEL or "Cancel", 100, 24)
    prompt.cancel:SetPoint("RIGHT", prompt.accept, "LEFT", -8, 0)
    prompt.cancel:SetScript("OnClick", function() prompt:Hide() end)
    prompt.accept:SetScript("OnClick", function()
        local value = prompt.noInput and true or trim(prompt.edit:GetText())
        if value == "" then
            prompt.edit:SetFocus()
            return
        end
        local callback = prompt.callback
        prompt:Hide()
        if Safe.IsReadable(callback) and type(callback) == "function" then
            callback(value)
        end
    end)
    prompt.edit:SetScript("OnEnterPressed", function() prompt.accept:Click() end)
    prompt.edit:SetScript("OnEscapePressed", function() prompt:Hide() end)
    self.prompt = prompt
    addPriorityEscapeFrame(prompt, "DecorShoppingListPromptFrame")
end

function UI:CreateListRail(frame)
    local Theme = self:GetTheme()
    local rail = Theme:CreateInset(frame)
    rail:SetPoint("TOPLEFT", 18, -66)
    rail:SetPoint("BOTTOMLEFT", 18, 52)
    rail:SetWidth(205)
    self.listRail = rail

    local title = rail:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 13, -13)
    title:SetText("SHOPPING LISTS")
    title:SetTextColor(unpack(Theme.colors.parchment))

    local newButton = Theme:CreateButton(rail, NEW or "New", 58, 22)
    newButton:SetPoint("TOPLEFT", 10, -35)
    local renameButton = Theme:CreateButton(rail, "Rename", 65, 22)
    renameButton:SetPoint("LEFT", newButton, "RIGHT", 3, 0)
    local deleteButton = Theme:CreateButton(rail, DELETE or "Delete", 61, 22)
    deleteButton:SetPoint("LEFT", renameButton, "RIGHT", 3, 0)
    self.newListButton = newButton
    self.renameListButton = renameButton
    self.deleteListButton = deleteButton
    setButtonTooltip(newButton, "New", "Create a list.")
    setButtonTooltip(renameButton, "Rename", "Rename this list.")
    setButtonTooltip(deleteButton, "Delete", "Delete this list and its decor.")

    newButton:SetScript("OnClick", function()
        if self:IsMutationLocked() then return end
        local lists = self.lists or {}
        self:ShowPrompt("New Shopping List", "Shopping List " .. (#lists + 1), CREATE or "Create", function(name)
            local list, reason = call(self:GetStore(), "CreateList", name, { kind = "manual" })
            if not Safe.IsTable(list) then
                reason = safeString(reason, "")
                if reason == "too-many-lists" then
                    Addon:Print("List limit reached. Delete a list first.")
                else
                    Addon:Print("List wasn't created. Try again.")
                end
            end
        end)
    end)

    renameButton:SetScript("OnClick", function()
        if self:IsMutationLocked() then return end
        local list = self:GetActiveList()
        if not list then return end
        local listID = list.id
        if isSecret(listID) or listID == nil then return end
        self:ShowPrompt("Rename Shopping List", safeString(list.name, "Shopping List"), SAVE or "Save", function(name)
            local target = call(self:GetStore(), "GetList", listID)
            if not Safe.IsTable(target) then
                Addon:Print("That list no longer exists.")
                self:Refresh("rename-list-missing")
                return
            end
            call(self:GetStore(), "RenameList", target.id, name)
        end)
    end)

    deleteButton:SetScript("OnClick", function()
        if self:IsMutationLocked() then return end
        local list = self:GetActiveList()
        if not list then return end
        local listID = list.id
        if isSecret(listID) or listID == nil then return end
        self:ShowPrompt("Delete this list?", "", DELETE or "Delete", function()
            local target = call(self:GetStore(), "GetList", listID)
            if not Safe.IsTable(target) then
                Addon:Print("That list no longer exists.")
                self:Refresh("delete-list-missing")
                return
            end
            call(self:GetStore(), "DeleteList", target.id)
        end, {
            noInput = true,
            description = "Deletes “" .. safeString(list.name, "Shopping List") .. "” and its decor.",
        })
    end)

    local viewport = CreateFrame("Frame", nil, rail)
    viewport:SetPoint("TOPLEFT", 8, -67)
    viewport:SetPoint("BOTTOMRIGHT", -24, 10)
    viewport:EnableMouseWheel(true)
    self.listViewport = viewport

    local scroll = Theme:CreateScrollBar(rail)
    scroll:SetPoint("TOPRIGHT", -7, -69)
    scroll:SetPoint("BOTTOMRIGHT", -7, 12)
    scroll:SetScript("OnValueChanged", function(_, value)
        if self.syncingListScroll then return end
        local offset = math.floor(safeNumber(value, 0) + 0.5)
        if offset ~= self.listOffset then
            self.listOffset = offset
            self.renderingFromListScroll = true
            self:RenderListRail()
            self.renderingFromListScroll = nil
        end
    end)
    viewport:SetScript("OnMouseWheel", function(_, delta)
        scroll:SetValue(safeNumber(scroll:GetValue(), 0) - safeNumber(delta, 0) * MOUSE_WHEEL_ROWS)
    end)
    bindMouseWheel(scroll, function(_, delta)
        scroll:SetValue(safeNumber(scroll:GetValue(), 0) - safeNumber(delta, 0) * MOUSE_WHEEL_ROWS)
    end)
    self.listScroll = scroll

    self.listRows = {}
    for index = 1, 11 do
        local row = CreateFrame("Button", nil, viewport)
        row:SetHeight(LIST_ROW_HEIGHT)
        row:SetPoint("TOPLEFT", 0, -(index - 1) * LIST_ROW_HEIGHT)
        row:SetPoint("TOPRIGHT", 0, -(index - 1) * LIST_ROW_HEIGHT)
        Theme:CreateHighlight(row)
        row.selected = Theme:CreateSelectedTexture(row)
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.name:SetPoint("TOPLEFT", 8, -6)
        row.name:SetPoint("TOPRIGHT", -8, -6)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.count = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.count:SetPoint("BOTTOMLEFT", 8, 5)
        row:SetScript("OnClick", function(button)
            if not isSecret(button.listID) and button.listID ~= nil then
                if self:IsTestPreview() then
                    for _, list in ipairs(self.testPreview.lists) do
                        if list.id == button.listID then
                            self.testPreview.activeList = list
                            self:Refresh("preview-list")
                            break
                        end
                    end
                elseif not self:IsReadOnlyUnsupported() then
                    call(self:GetStore(), "SetActiveList", button.listID)
                end
            end
        end)
        bindMouseWheel(row, function(_, delta)
            scroll:SetValue(safeNumber(scroll:GetValue(), 0) - safeNumber(delta, 0) * MOUSE_WHEEL_ROWS)
        end)
        self.listRows[index] = row
    end
end

function UI:CreateBlueprintBanner(frame)
    local Theme = self:GetTheme()
    local banner = Theme:CreateInset(frame)
    banner:SetPoint("TOPLEFT", 234, -129)
    banner:SetPoint("TOPRIGHT", -18, -129)
    banner:SetHeight(50)
    banner:Hide()
    self.blueprintBanner = banner

    local icon = banner:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
    icon:SetSize(31, 31)
    icon:SetPoint("LEFT", 10, 0)

    banner.title = banner:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    banner.title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 9, 0)
    banner.title:SetPoint("TOPRIGHT", -205, 0)
    banner.title:SetJustifyH("LEFT")
    banner.title:SetTextColor(unpack(Theme.colors.warning))
    banner.detail = banner:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    banner.detail:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 9, 1)
    banner.detail:SetPoint("BOTTOMRIGHT", -205, 1)
    banner.detail:SetJustifyH("LEFT")

    banner.save = Theme:CreateButton(banner, "Create List", 105, 24)
    banner.save:SetPoint("RIGHT", -8, 0)
    setButtonTooltip(banner.save, "Create List", "Create a list from this draft.")
    banner.dismiss = Theme:CreateButton(banner, "Later", 70, 24)
    banner.dismiss:SetPoint("RIGHT", banner.save, "LEFT", -5, 0)
    setButtonTooltip(banner.dismiss, "Later", "Keep the draft for later.")
    banner.dismiss:SetScript("OnClick", function()
        banner:Hide()
        self:UpdateContentLayout()
    end)
    banner.save:SetScript("OnClick", function()
        if self:IsMutationLocked() then return end
        local draft = self.pendingDraft
        if not draft then return end
        self:ShowPrompt("Create Blueprint List", safeString(draft.name, "Blueprint Shopping List"), CREATE or "Create", function(name)
            local created = call(Addon:GetModule("Blueprints"), "CreateListFromPending", name)
            if not Safe.IsTable(created) then
                Addon:Print("Blueprint list wasn't created. Try again.")
                return
            end
            self:ClearBlueprintDraft()
        end)
    end)
end

function UI:CreateReadOnlyBanner(frame)
    local Theme = self:GetTheme()
    local banner = Theme:CreateInset(frame)
    banner:SetPoint("TOPLEFT", 234, -129)
    banner:SetPoint("TOPRIGHT", -18, -129)
    banner:SetHeight(50)
    banner:Hide()

    local icon = banner:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew")
    icon:SetSize(34, 34)
    icon:SetPoint("LEFT", 11, 0)

    banner.title = banner:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    banner.title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -1)
    banner.title:SetPoint("TOPRIGHT", -12, -1)
    banner.title:SetJustifyH("LEFT")
    banner.title:SetText("Newer saved data detected")
    banner.title:SetTextColor(unpack(Theme.colors.warning))

    banner.detail = banner:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    banner.detail:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 10, 1)
    banner.detail:SetPoint("BOTTOMRIGHT", -12, 1)
    banner.detail:SetJustifyH("LEFT")
    banner.detail:SetText("Update the addon to continue. Your saved data is unchanged.")
    self.readOnlyBanner = banner
end

function UI:CreatePreviewBanner(frame)
    local Theme = self:GetTheme()
    local banner = Theme:CreateInset(frame)
    banner:SetPoint("TOPLEFT", 234, -129)
    banner:SetPoint("TOPRIGHT", -18, -129)
    banner:SetHeight(50)
    banner:Hide()

    local icon = banner:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Icons\\INV_Misc_Spyglass_03")
    icon:SetSize(32, 32)
    icon:SetPoint("LEFT", 11, 0)

    banner.title = banner:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    banner.title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -1)
    banner.title:SetPoint("TOPRIGHT", -12, -1)
    banner.title:SetJustifyH("LEFT")
    banner.title:SetText("Temporary layout data")
    banner.title:SetTextColor(unpack(Theme.colors.warning))

    banner.detail = banner:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    banner.detail:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 10, 1)
    banner.detail:SetPoint("BOTTOMRIGHT", -12, 1)
    banner.detail:SetJustifyH("LEFT")
    banner.detail:SetText("Temporary data only. /dsl testui off returns to your lists.")
    self.previewBanner = banner
end

function UI:CreateContent(frame)
    local Theme = self:GetTheme()

    self.activeName = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    self.activeName:SetPoint("TOPLEFT", 239, -70)
    self.activeName:SetPoint("TOPRIGHT", -160, -70)
    self.activeName:SetJustifyH("LEFT")
    self.activeName:SetWordWrap(false)
    self.activeName:SetTextColor(unpack(Theme.colors.title))

    self.previewBadge = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.previewBadge:SetPoint("TOPRIGHT", -27, -74)
    self.previewBadge:SetWidth(112)
    self.previewBadge:SetJustifyH("RIGHT")
    self.previewBadge:SetText("PREVIEW")
    self.previewBadge:SetTextColor(unpack(Theme.colors.warning))
    self.previewBadge:Hide()

    self.summary = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.summary:SetPoint("TOPLEFT", self.activeName, "BOTTOMLEFT", 0, -8)
    self.summary:SetPoint("TOPRIGHT", -24, -104)
    self.summary:SetJustifyH("LEFT")

    local headerRule = Theme:CreateDivider(frame)
    headerRule:SetPoint("TOPLEFT", 234, -119)
    headerRule:SetPoint("TOPRIGHT", -18, -119)

    self:CreateBlueprintBanner(frame)
    self:CreateReadOnlyBanner(frame)
    self:CreatePreviewBanner(frame)

    self.toolbar = CreateFrame("Frame", nil, frame)
    self.toolbar:SetHeight(28)
    self.search = Theme:CreateSearchBox(self.toolbar, 215)
    self.search:SetPoint("LEFT", 0, 0)
    -- Preserve SearchBoxTemplate's native OnTextChanged handler; it owns the
    -- instruction text and clear-button visibility.
    self.search:HookScript("OnTextChanged", function()
        self.searchText = safeString(self.search:GetText(), ""):lower()
        if self.suspendRender then return end
        self.itemOffset = 0
        self.filteredItemsCache = nil
        self:RenderItems()
        self:RefreshTrackAllButton()
    end)

    self.filterIndex = 1
    self.filterButton = Theme:CreateButton(self.toolbar, SOURCE_LABELS.all, 112, 24)
    self.filterButton:SetPoint("LEFT", self.search, "RIGHT", 8, 0)
    self.filterButton:SetScript("OnClick", function()
        self.filterIndex = (self.filterIndex % #SOURCE_FILTERS) + 1
        self.filterButton:SetText(SOURCE_LABELS[SOURCE_FILTERS[self.filterIndex]])
        self.itemOffset = 0
        self.filteredItemsCache = nil
        self:RenderItems()
        self:RefreshTrackAllButton()
    end)
    setButtonTooltip(self.filterButton, "Source Filter", "Show one source type.")

    self.trackAllButton = Theme:CreateButton(self.toolbar, "Track All", 94, 24)
    self.trackAllButton:SetPoint("LEFT", self.filterButton, "RIGHT", 8, 0)
    self.trackAllButton:SetScript("OnClick", function() self:StartBulkTrackingToggle() end)
    setButtonTooltip(self.trackAllButton, "Track All", "Track decor in the current filtered view. Choose again to untrack it.")

    self.clearCompleted = Theme:CreateButton(self.toolbar, "Clear obtained", 110, 24)
    self.clearCompleted:SetPoint("RIGHT", 0, 0)
    self.clearCompleted:SetScript("OnClick", function() self:ClearCompletedItems() end)
    setButtonTooltip(self.clearCompleted, "Clear obtained", "Remove decor with nothing left to collect.")

    self.itemsInset = Theme:CreateInset(frame)
    self.itemsInset:EnableMouseWheel(true)
    self.itemsInset:SetScript("OnMouseWheel", function(_, delta)
        self.itemScroll:SetValue(safeNumber(self.itemScroll:GetValue(), 0) - safeNumber(delta, 0) * MOUSE_WHEEL_ROWS)
    end)

    self.itemScroll = Theme:CreateScrollBar(self.itemsInset)
    self.itemScroll:SetPoint("TOPRIGHT", -7, -8)
    self.itemScroll:SetPoint("BOTTOMRIGHT", -7, 8)
    self.itemScroll:SetScript("OnValueChanged", function(_, value)
        if self.syncingItemScroll then return end
        local offset = math.floor(safeNumber(value, 0) + 0.5)
        if offset ~= self.itemOffset then
            self.itemOffset = offset
            self.renderingFromItemScroll = true
            self:RenderItems()
            self.renderingFromItemScroll = nil
        end
    end)
    bindMouseWheel(self.itemScroll, function(_, delta)
        self.itemScroll:SetValue(safeNumber(self.itemScroll:GetValue(), 0) - safeNumber(delta, 0) * MOUSE_WHEEL_ROWS)
    end)

    self.emptyText = self.itemsInset:CreateFontString(nil, "OVERLAY", "GameFontDisableLarge")
    self.emptyText:SetPoint("CENTER", -7, 0)
    self.emptyText:SetWidth(430)
    self.emptyText:SetJustifyH("CENTER")
    self.emptyText:SetText("No decor yet.\n\nRight-click decor in the Housing Catalog to add it.")

    self.itemRows = {}
    for index = 1, 7 do
        self.itemRows[index] = self:CreateItemRow(self.itemsInset, index)
    end
    self:UpdateContentLayout(true)
end

function UI:CreateItemRow(parent, index)
    local Theme = self:GetTheme()
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 7, -7 - ((index - 1) * ROW_HEIGHT))
    row:SetPoint("TOPRIGHT", -23, -7 - ((index - 1) * ROW_HEIGHT))
    Theme:CreateHighlight(row)

    row.stripe = Theme:CreateRowBackground(row)
    if index % 2 == 0 then row.stripe:SetAlpha(0.82) end

    row.iconBorder = Theme:CreateFrame("Frame", row, "BackdropTemplate")
    row.iconBorder:SetSize(44, 44)
    row.iconBorder:SetPoint("LEFT", 7, 0)
    if row.iconBorder.SetBackdrop then
        row.iconBorder:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10 })
        row.iconBorder:SetBackdropBorderColor(0.50, 0.34, 0.14, 1)
    end
    row.icon = row.iconBorder:CreateTexture(nil, "ARTWORK")
    row.icon:SetPoint("TOPLEFT", 4, -4)
    row.icon:SetPoint("BOTTOMRIGHT", -4, 4)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("TOPLEFT", row.iconBorder, "TOPRIGHT", 8, -2)
    row.name:SetWidth(202)
    row.name:SetHeight(18)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.name:SetTextColor(unpack(Theme.colors.text))

    row.source = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.source:SetPoint("BOTTOMLEFT", row.iconBorder, "BOTTOMRIGHT", 8, 3)
    row.source:SetWidth(202)
    row.source:SetHeight(25)
    row.source:SetJustifyH("LEFT")
    row.source:SetJustifyV("TOP")
    row.source:SetWordWrap(true)

    row.missing = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.missing:SetPoint("TOPLEFT", row.name, "TOPRIGHT", 7, 0)
    row.missing:SetWidth(66)
    row.missing:SetJustifyH("CENTER")
    row.missing:SetTextColor(unpack(Theme.colors.warning))
    row.owned = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.owned:SetPoint("TOP", row.missing, "BOTTOM", 0, -4)
    row.owned:SetWidth(66)
    row.owned:SetJustifyH("CENTER")

    row.minus = Theme:CreateIconButton(row, "−", 24)
    row.minus:SetPoint("LEFT", row.missing, "RIGHT", 4, 0)
    row.quantity = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.quantity:SetPoint("LEFT", row.minus, "RIGHT", 3, 0)
    row.quantity:SetWidth(23)
    row.quantity:SetJustifyH("CENTER")
    row.plus = Theme:CreateIconButton(row, "+", 24)
    row.plus:SetPoint("LEFT", row.quantity, "RIGHT", 3, 0)

    row.track = Theme:CreateButton(row, "Track", 64, 22)
    row.track:SetPoint("RIGHT", -32, 12)
    row.track.activeCheck = Theme:CreateTrackedButtonCheck(row.track)
    row.remove = Theme:CreateIconButton(row, "×", 25)
    row.remove:SetPoint("RIGHT", -2, 12)

    row.desiredLabel = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.desiredLabel:SetPoint("TOP", row.quantity, "BOTTOM", 0, -5)
    row.desiredLabel:SetText("desired")

    row:SetScript("OnEnter", function(button) self:ShowItemTooltip(button) end)
    row:SetScript("OnLeave", function() Theme:HideTooltip() end)
    row.minus:SetScript("OnClick", function() self:ChangeDesired(row, -1) end)
    row.plus:SetScript("OnClick", function() self:ChangeDesired(row, 1) end)
    row.remove:SetScript("OnClick", function() self:RemoveRowItem(row) end)
    row.track:SetScript("OnClick", function() self:TrackRowItem(row) end)
    row.track:SetScript("OnEnter", function(button)
        Theme:SetTooltip(
            button,
            button.tracked and "Untrack" or "Track",
            button.disabledReason or (button.tracked
                and "Stop tracking this decor."
                or "Add a waypoint or start Blizzard decor tracking.")
        )
    end)
    row.track:SetScript("OnLeave", function() Theme:HideTooltip() end)
    setButtonTooltip(row.minus, "Decrease", "Want one fewer.")
    setButtonTooltip(row.plus, "Increase", "Want one more.")
    row.remove:SetScript("OnEnter", function(button) Theme:SetTooltip(button, "Remove", button.disabledReason or "Remove this decor from the list.") end)
    row.remove:SetScript("OnLeave", function() Theme:HideTooltip() end)
    local function scrollItems(_, delta)
        self.itemScroll:SetValue(safeNumber(self.itemScroll:GetValue(), 0) - safeNumber(delta, 0) * MOUSE_WHEEL_ROWS)
    end
    for _, wheelTarget in ipairs({ row, row.minus, row.plus, row.track, row.remove }) do
        bindMouseWheel(wheelTarget, scrollItems)
    end
    return row
end

function UI:UpdateContentLayout(skipRender)
    if not self.toolbar or not self.itemsInset then return end
    local draftShown = self.blueprintBanner and Safe.AsBoolean(self.blueprintBanner:IsShown(), false)
    local readOnlyShown = self.readOnlyBanner and Safe.AsBoolean(self.readOnlyBanner:IsShown(), false)
    local previewShown = self.previewBanner and Safe.AsBoolean(self.previewBanner:IsShown(), false)
    local bannerShown = draftShown or readOnlyShown or previewShown
    self.toolbar:ClearAllPoints()
    self.toolbar:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 239, bannerShown and -190 or -137)
    self.toolbar:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -24, bannerShown and -190 or -137)
    self.itemsInset:ClearAllPoints()
    self.itemsInset:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 234, bannerShown and -224 or -171)
    self.itemsInset:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -18, 52)
    if not skipRender then self:RenderItems() end
end

function UI:GetListItems(list)
    if not Safe.IsTable(list) or not Safe.IsTable(list.items) then
        return {}
    end
    local items = {}
    if Safe.IsTable(list.order) then
        for _, key in ipairs(list.order) do
            if not isSecret(key) and Safe.IsTable(list.items[key]) then
                items[#items + 1] = list.items[key]
            end
        end
    else
        for _, item in pairs(list.items) do
            if Safe.IsTable(item) then items[#items + 1] = item end
        end
    end
    return items
end

function UI:GetSource(item)
    local label = safeString(item.sourceText, "Source not mapped")
    local sourceType = safeString(item.sourceType, "")
    if sourceType == "" then sourceType = safeString(item.acquisitionType, "unknown") end
    sourceType = sourceType:lower()
    if Safe.AsBoolean(item.previewItem, false) then
        sourceType = SOURCE_ALIASES[sourceType] or sourceType
        if not SOURCE_LABELS[sourceType] then sourceType = "unknown" end
        return label, sourceType, { type = sourceType, label = label }
    end
    self.sourceCache = self.sourceCache or {}
    local itemKey = safeString(item.key, "")
    local cacheKey = itemKey ~= "" and itemKey or nil
    local cached = cacheKey and self.sourceCache[cacheKey] or nil
    if Safe.IsTable(cached) then
        return cached.label, cached.sourceType, cached.source
    end
    local registry = Addon:GetModule("SourceRegistry") or Addon:GetModule("Registry")
    local registryLabel, source = call(registry, "GetDisplaySource", item)
    registryLabel = safeString(registryLabel, "")
    if registryLabel ~= "" then
        label = registryLabel
    end
    if Safe.IsTable(source) then
        sourceType = safeString(source.type, sourceType):lower()
    else
        source = nil
    end
    sourceType = SOURCE_ALIASES[sourceType] or sourceType
    if not SOURCE_LABELS[sourceType] and sourceType ~= "all" then
        sourceType = "unknown"
    end
    if cacheKey and source and not Safe.AsBoolean(source.isCatalogFallback, false) then
        self.sourceCache[cacheKey] = {
            label = label,
            sourceType = sourceType,
            source = source,
        }
    end
    return label, sourceType, source
end

function UI:GetFilteredItems(list)
    local search = self.searchText or ""
    local wantedType = SOURCE_FILTERS[self.filterIndex or 1] or "all"
    local cache = self.filteredItemsCache
    if Safe.IsTable(cache) and cache.list == list and cache.search == search
        and cache.wantedType == wantedType then
        return cache.filtered, cache.all
    end

    local allItems = self:GetListItems(list)
    if search == "" and wantedType == "all" then
        self.filteredItemsCache = {
            list = list,
            search = search,
            wantedType = wantedType,
            filtered = allItems,
            all = allItems,
        }
        return allItems, allItems
    end

    local filtered = {}
    for _, item in ipairs(allItems) do
        local name = safeString(item.name, "Unknown decor")
        local source, sourceType = self:GetSource(item)
        local matchesText = search == "" or name:lower():find(search, 1, true) or source:lower():find(search, 1, true)
        local matchesType = wantedType == "all" or wantedType == sourceType
        if matchesText and matchesType then filtered[#filtered + 1] = item end
    end
    self.filteredItemsCache = {
        list = list,
        search = search,
        wantedType = wantedType,
        filtered = filtered,
        all = allItems,
    }
    return filtered, allItems
end

function UI:GetListSummary(list)
    if not Safe.IsTable(list) then
        return { itemCount = 0, missing = 0, obtained = 0, hasObtained = false }
    end
    self.listSummaries = self.listSummaries or {}
    local cached = self.listSummaries[list]
    if Safe.IsTable(cached) then return cached end

    local items = self:GetListItems(list)
    local missing, obtained = 0, 0
    local hasObtained = false
    for _, item in ipairs(items) do
        local desired = math.max(1, safeNumber(item.desired, 1))
        local owned = math.max(0, safeNumber(item.owned, 0))
        local itemMissing = math.max(0, safeNumber(item.missing, desired - owned))
        missing = missing + itemMissing
        obtained = obtained + math.min(desired, owned)
        if itemMissing <= 0 then hasObtained = true end
    end
    cached = {
        itemCount = #items,
        missing = missing,
        obtained = obtained,
        hasObtained = hasObtained,
    }
    self.listSummaries[list] = cached
    return cached
end

function UI:RenderListRail()
    if not self.listRows then return end
    local lists = self.lists or {}
    local active = self:GetActiveList()
    local activeID = active and active.id
    local visible = #self.listRows
    local maxOffset = math.max(0, #lists - visible)
    self.listOffset = math.min(math.max(0, self.listOffset or 0), maxOffset)
    self.syncingListScroll = true
    self.listScroll:SetMinMaxValues(0, maxOffset)
    updateScrollThumb(self.listScroll, #lists, visible)
    if not self.renderingFromListScroll and safeNumber(self.listScroll:GetValue(), 0) ~= self.listOffset then
        self.listScroll:SetValue(self.listOffset)
    end
    self.syncingListScroll = false
    self.listScroll:SetShown(maxOffset > 0)

    for index, row in ipairs(self.listRows) do
        local list = lists[self.listOffset + index]
        if list then
            local listID = list.id
            row.listID = not isSecret(listID) and listID or nil
            row.name:SetText(safeString(list.name, "Shopping List"))
            local summary = self:GetListSummary(list)
            local itemCount = summary.itemCount
            local missing = summary.missing
            row.count:SetFormattedText("%d items  •  %d missing", itemCount, missing)
            local comparable = not isSecret(activeID) and not isSecret(list.id)
            row.selected:SetShown(comparable and activeID ~= nil and list.id == activeID)
            row:Show()
        else
            row.listID = nil
            row:Hide()
        end
    end
    local mutationLocked = self:IsMutationLocked()
    local lockReason = self:GetMutationLockReason()
    setEnabled(self.newListButton, not mutationLocked, lockReason)
    setEnabled(self.renameListButton, not mutationLocked and active ~= nil, mutationLocked and lockReason or "Select a list first.")
    setEnabled(self.deleteListButton, not mutationLocked and active ~= nil, mutationLocked and lockReason or "Select a list first.")
end

function UI:RenderItems()
    if not self.itemRows or not self.itemsInset then return end
    local list = self:GetActiveList()
    local items, allItems = {}, {}
    if list then
        items, allItems = self:GetFilteredItems(list)
    end
    local hasObtained = list and self:GetListSummary(list).hasObtained or false
    local readOnly = self:IsReadOnlyUnsupported()
    local mutationLocked = self:IsMutationLocked()
    setEnabled(self.clearCompleted, not self.clearingCompleted and not mutationLocked and hasObtained,
        self.clearingCompleted and "Tracking cleanup is in progress."
        or (
        mutationLocked and self:GetMutationLockReason()
        or (list and "No fully obtained decor remains on this list." or "Select a list first.")))
    local availableHeight = math.max(1, safeNumber(self.itemsInset:GetHeight(), ROW_HEIGHT + 14) - 14)
    local visible = math.min(#self.itemRows, math.max(1, math.floor(availableHeight / ROW_HEIGHT)))
    local maxOffset = math.max(0, #items - visible)
    self.itemOffset = math.min(math.max(0, self.itemOffset or 0), maxOffset)
    self.syncingItemScroll = true
    self.itemScroll:SetMinMaxValues(0, maxOffset)
    updateScrollThumb(self.itemScroll, #items, visible)
    if not self.renderingFromItemScroll and safeNumber(self.itemScroll:GetValue(), 0) ~= self.itemOffset then
        self.itemScroll:SetValue(self.itemOffset)
    end
    self.syncingItemScroll = false
    self.itemScroll:SetShown(maxOffset > 0)

    for index, row in ipairs(self.itemRows) do
        local item = index <= visible and items[self.itemOffset + index] or nil
        if item then
            self:PopulateItemRow(row, item, list)
            row:Show()
        else
            row.item = nil
            row.list = nil
            row:Hide()
        end
    end

    if readOnly then
        self.emptyText:Hide()
    elseif not list then
        self.emptyText:SetText("Select a list or choose New.")
        self.emptyText:Show()
    elseif #items == 0 and #allItems > 0 then
        self.emptyText:SetText("No matching decor.")
        self.emptyText:Show()
    elseif #allItems == 0 then
        self.emptyText:SetText("No decor yet.\n\nRight-click decor in the Housing Catalog to add it.")
        self.emptyText:Show()
    else
        self.emptyText:Hide()
    end
end

function UI:ClearCompletedItems()
    if self.clearingCompleted or self:IsMutationLocked() then return end
    local list = self:GetActiveList()
    local listID = Safe.IsTable(list) and list.id or nil
    if not list or isSecret(listID) or listID == nil then return end

    local completed = {}
    for _, item in ipairs(self:GetListItems(list)) do
        if safeNumber(item.missing, 0) <= 0 then completed[#completed + 1] = item end
    end
    if #completed == 0 then return end

    local waypoint = Addon:GetModule("Waypoint")
    self.clearingCompleted = true
    self.clearCompleted:SetText("Clearing…")
    setEnabled(self.clearCompleted, false, "Tracking cleanup is in progress.")
    local index, failures = 1, 0

    local function Finish()
        self.clearingCompleted = nil
        self.clearCompleted:SetText("Clear obtained")
        if failures > 0 then
            self:RenderItems()
            Addon:Print(string.format("%d obtained decor could not be untracked. Nothing was removed; try again.", failures))
            return
        end
        local _, reason = call(self:GetStore(), "RemoveCompletedItems", listID)
        reason = safeString(reason, "")
        if reason == "failed" then
            Addon:Print("Obtained decor wasn't cleared. Try again.")
            self:RenderItems()
        end
    end

    local function ProcessBatch()
        local last = math.min(#completed, index + 5 - 1)
        while index <= last do
            local success = Safe.AsBoolean(call(waypoint, "UntrackItem", completed[index]), false)
            if not success then failures = failures + 1 end
            index = index + 1
        end
        self:RenderItems()
        if index > #completed then
            Finish()
            return
        end
        local after = Safe.IsTable(C_Timer) and C_Timer.After or nil
        if Safe.IsReadable(after) and type(after) == "function" then
            local ok = pcall(after, 0.01, ProcessBatch)
            if ok then return end
        end
        ProcessBatch()
    end
    ProcessBatch()
end

function UI:RefreshTrackAllButton(items)
    if not self.trackAllButton then return end
    local list = self:GetActiveList()
    if not items and list then items = self:GetFilteredItems(list) end
    items = Safe.IsTable(items) and items or {}
    local anyTracked = Safe.AsBoolean(call(Addon:GetModule("Waypoint"), "HasTrackedItems", items), false)
    local hasNeeded = false
    for _, item in ipairs(items) do
        if safeNumber(item.missing, 0) > 0 then
            hasNeeded = true
            break
        end
    end
    self.bulkShouldUntrack = anyTracked
    if not self.bulkTracking then
        self.trackAllButton:SetText(anyTracked and "Untrack All" or "Track All")
    end
    local allowed = not self.bulkTracking and not self:IsTestPreview() and (anyTracked or hasNeeded)
        and Safe.IsTable(Addon:GetModule("Waypoint"))
    setEnabled(self.trackAllButton, allowed,
        self.bulkTracking and "Tracking is in progress."
        or ((#items == 0 or (not anyTracked and not hasNeeded)) and "No needed decor is shown in the current view."
        or (self:IsTestPreview() and "Preview only. Tracking is disabled." or "Tracking is unavailable.")))
end

function UI:RefreshFriendlyNPCNameplatesButton()
    local button = self.friendlyNPCNameplatesButton
    if not button then return end
    local integration = Addon:GetModule("VendorNameplateIntegration")
    local enabled = call(integration, "GetFriendlyNPCNameplatesState")
    enabled = Safe.AsBoolean(enabled, nil)
    button:SetText(enabled and "Hide NPC Plates" or "Show NPC Plates")
    if enabled then
        button:LockHighlight()
    else
        button:UnlockHighlight()
    end
    setEnabled(button, enabled ~= nil and not self:IsTestPreview(),
        self:IsTestPreview() and "Preview only. Nameplate settings are unchanged."
        or "Friendly NPC nameplate settings are unavailable.")
end

function UI:StartBulkTrackingToggle()
    if self.bulkTracking or self:IsTestPreview() then return end
    local list = self:GetActiveList()
    if not list then return end
    local filtered = self:GetFilteredItems(list)
    if #filtered == 0 then return end

    local waypoint = Addon:GetModule("Waypoint")
    if not Safe.IsTable(waypoint) then return end
    local untrack = self.bulkShouldUntrack == true
    local items = {}
    for _, item in ipairs(filtered) do
        if untrack or safeNumber(item.missing, 0) > 0 then
            items[#items + 1] = item
        end
    end
    if #items == 0 then return end
    self.bulkTracking = true
    self.bulkTrackingToken = (self.bulkTrackingToken or 0) + 1
    local token = self.bulkTrackingToken
    local index, changed, failed = 1, 0, 0
    self.trackAllButton:SetText(untrack and "Untracking…" or "Tracking…")
    setEnabled(self.trackAllButton, false, "Tracking is in progress.")

    local function Finish()
        if self.bulkTrackingToken ~= token then return end
        self.bulkTracking = nil
        self:RenderItems()
        self:RefreshTrackAllButton(items)
        if failed > 0 then
            Addon:Print(string.format("%d decor updated; %d could not be changed.", changed, failed))
        else
            Addon:Print(string.format("%d decor %s.", changed, untrack and "untracked" or "tracked"))
        end
    end

    local function ProcessBatch()
        if self.bulkTrackingToken ~= token then return end
        local last = math.min(#items, index + 5 - 1)
        while index <= last do
            local item = items[index]
            local isTracked = Safe.AsBoolean(call(waypoint, "IsItemTracked", item), false)
            local success = true
            if untrack and isTracked then
                success = Safe.AsBoolean(call(waypoint, "UntrackItem", item), false)
            elseif not untrack and not isTracked then
                success = Safe.AsBoolean(call(waypoint, "TrackItemBulk", item), false)
            end
            if success then changed = changed + 1 else failed = failed + 1 end
            index = index + 1
        end
        self:RenderItems()
        if index > #items then
            Finish()
            return
        end
        local after = Safe.IsTable(C_Timer) and C_Timer.After or nil
        if Safe.IsReadable(after) and type(after) == "function" then
            local ok = pcall(after, 0.01, ProcessBatch)
            if ok then return end
        end
        ProcessBatch()
    end
    ProcessBatch()
end

function UI:PopulateItemRow(row, item, list)
    local Theme = self:GetTheme()
    row.item = item
    row.list = list
    row.name:SetText(safeString(item.name, "Unknown decor"))
    local sourceText, _, source = self:GetSource(item)
    row.source:SetText(sourceText)

    row.icon:SetTexture(nil)
    local iconAtlas = safeString(item.iconAtlas, "")
    local iconTexture = item.iconTexture
    local atlasApplied = iconAtlas ~= "" and Theme:SetAtlasIfAvailable(row.icon, iconAtlas, false)
    if not atlasApplied and not isSecret(iconTexture)
        and (type(iconTexture) == "number" or type(iconTexture) == "string")
    then
        row.icon:SetTexture(iconTexture)
    elseif not atlasApplied then
        row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end

    local desired = math.max(1, safeNumber(item.desired, 1))
    local owned = math.max(0, safeNumber(item.owned, 0))
    local missing = math.max(0, safeNumber(item.missing, desired - owned))
    row.missing:SetFormattedText("%d missing", missing)
    row.owned:SetFormattedText("%d / %d owned", math.min(owned, desired), desired)
    row.quantity:SetFormattedText("%d", desired)
    row.missing:SetTextColor(unpack(missing > 0 and Theme.colors.warning or Theme.colors.success))
    local mutationLocked = self:IsMutationLocked()
    local lockReason = self:GetMutationLockReason()
    setEnabled(row.minus, not mutationLocked and desired > 1, mutationLocked and lockReason or "Quantity cannot be lower than one.")
    setEnabled(row.plus, not mutationLocked, lockReason)
    setEnabled(row.remove, not mutationLocked, lockReason)

    local recordID = safeNumber(item.recordID, 0)
    if recordID <= 0 then recordID = safeNumber(item.decorID, 0) end
    local waypoint = Addon:GetModule("Waypoint")
    local hasTrackingTarget = not self:IsTestPreview() and Safe.IsTable(waypoint) and (source ~= nil or recordID > 0)
    local tracked = hasTrackingTarget and Safe.AsBoolean(call(waypoint, "IsItemTracked", item), false)
    local canTrack = hasTrackingTarget and (missing > 0 or tracked)
    local reason
    if self:IsTestPreview() then
        reason = "Preview only. No waypoint will be added."
    elseif missing <= 0 and not tracked then
        reason = "Nothing remains to collect for this decor."
    elseif not canTrack then
        reason = "No waypoint or Blizzard tracking is available for this decor."
    end
    setEnabled(row.track, canTrack, reason)
    row.track.tracked = tracked
    row.track:SetText(tracked and "Untrack" or "Track")
    row.track.activeCheck:SetShown(tracked)
    if tracked then
        row.track:LockHighlight()
    else
        row.track:UnlockHighlight()
    end
end

function UI:ChangeDesired(row, delta)
    if self:IsMutationLocked() then return end
    local item, list = row.item, row.list
    if not item or not list or isSecret(item.key) or isSecret(list.id) then return end
    if item.key == nil or list.id == nil then return end
    local desired = math.max(1, safeNumber(item.desired, 1) + delta)
    call(self:GetStore(), "SetItemDesired", list.id, item.key, desired)
end

function UI:RemoveRowItem(row)
    if self:IsMutationLocked() then return end
    local item, list = row.item, row.list
    if not item or not list or isSecret(item.key) or isSecret(list.id) then return end
    if item.key == nil or list.id == nil then return end
    call(self:GetStore(), "RemoveItem", list.id, item.key)
end

function UI:TrackRowItem(row)
    if self:IsTestPreview() then return end
    local item = row.item
    if not item then return end
    local success, modeOrReason, locationName = call(Addon:GetModule("Waypoint"), "ToggleItem", item)
    success = Safe.AsBoolean(success, false)
    modeOrReason = safeString(modeOrReason, "")
    if modeOrReason == "" then modeOrReason = "No location is available." end
    if not success then
        Addon:Print("No waypoint was added. " .. modeOrReason)
    elseif modeOrReason == "untracked" or modeOrReason == "not-tracked" then
        Addon:Print("Tracking stopped.")
    elseif modeOrReason == "tomtom" then
        Addon:Print("TomTom waypoint added.")
    elseif modeOrReason == "native" then
        Addon:Print("Blizzard waypoint set for " .. safeString(locationName, "the destination")
            .. ". It replaces the previous Blizzard waypoint.")
    elseif modeOrReason == "native-map" then
        Addon:Print("Map pin set for " .. safeString(locationName, "the destination")
            .. ", but Blizzard navigation could not be started.")
    elseif modeOrReason == "housing" then
        Addon:Print("Blizzard is now tracking this decor.")
    else
        Addon:Print("Tracking started.")
    end
    if success then self:RenderItems() end
    if success then self:RefreshTrackAllButton() end
end

function UI:ShowItemTooltip(row)
    local item = row.item
    if not item then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    local itemID = item.itemID
    if not isSecret(itemID) and type(itemID) == "number" and GameTooltip.SetItemByID then
        GameTooltip:SetItemByID(itemID)
    else
        GameTooltip:SetText(safeString(item.name, "Unknown decor"), unpack(self:GetTheme().colors.title))
        GameTooltip:AddLine(safeString(item.sourceText, "Source not mapped"), 1, 1, 1, true)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Desired: " .. safeNumber(item.desired, 1), 0.92, 0.82, 0.62)
    GameTooltip:Show()
end

function UI:Refresh(reason, payload)
    if not self.initialized then return end
    local observedActiveList = self:GetActiveList()
    if self.lastActiveList ~= observedActiveList then
        self.lastActiveList = observedActiveList
        self.itemOffset = 0
        self.filteredItemsCache = nil
    end
    local changedList
    local changedItem
    if Safe.IsTable(payload) then
        changedList = Safe.IsTable(payload.list) and payload.list or payload
        changedItem = Safe.IsTable(payload.item) and payload.item or nil
    end
    if Safe.IsTable(changedItem) then
        local changedKey = safeString(changedItem.key, "")
        if changedKey ~= "" and Safe.IsTable(self.sourceCache) then
            self.sourceCache[changedKey] = nil
        end
    end
    if self.frame and reason ~= "initialize" and reason ~= "show"
        and not Safe.AsBoolean(self.frame:IsShown(), false) then
        self.refreshPending = true
        self.filteredItemsCache = nil
        self.listSummaries = self.listSummaries or {}
        if Safe.IsTable(changedList) then
            self.listSummaries[changedList] = nil
        else
            self.listSummaries = {}
        end
        return
    end
    self.refreshPending = nil
    self.filteredItemsCache = nil
    local preview = self:IsTestPreview() and self.testPreview or nil
    local lists = preview and preview.lists or call(self:GetStore(), "GetLists")
    self.lists = Safe.IsTable(lists) and lists or {}
    self.listSummaries = self.listSummaries or {}
    if Safe.IsTable(changedList) then
        self.listSummaries[changedList] = nil
    end
    local list = observedActiveList
    local readOnly = self:IsReadOnlyUnsupported()
    self.previewBadge:SetShown(preview ~= nil)
    self.previewBanner:SetShown(preview ~= nil and not readOnly)
    if preview then self.blueprintBanner:Hide() end
    if readOnly then
        self.activeName:SetText("Update required")
        self.summary:SetText(preview and "Read-only state preview." or "Saved lists are read-only.")
        self.blueprintBanner:Hide()
        self.readOnlyBanner:Show()
    elseif list then
        self.readOnlyBanner:Hide()
        self.activeName:SetText(safeString(list.name, "Shopping List"))
        local activeSummary = self:GetListSummary(list)
        self.summary:SetFormattedText("%d decor  •  %d obtained  •  |cffffb347%d still needed|r",
            activeSummary.itemCount, activeSummary.obtained, activeSummary.missing)
    else
        self.readOnlyBanner:Hide()
        self.activeName:SetText("No active shopping list")
        self.summary:SetText("Select a list or choose New.")
    end
    setEnabled(self.blueprintBanner.save, not self:IsMutationLocked(), self:GetMutationLockReason())
    if self.clearWaypointsButton then
        setEnabled(self.clearWaypointsButton, not preview and Safe.IsTable(Addon:GetModule("Waypoint")),
            preview and "Preview only. No waypoints will be changed." or "Waypoint support is unavailable.")
    end
    self:UpdateContentLayout()
    self:RenderListRail()
    self:RefreshTrackAllButton()
    self:RefreshFriendlyNPCNameplatesButton()
end

function UI:ClearBlueprintDraft()
    self.pendingDraft = nil
    if Safe.IsTable(self.testPreviewSnapshot) then
        self.testPreviewSnapshot.blueprintShown = false
    end
    if self.blueprintBanner then
        self.blueprintBanner:Hide()
        self:UpdateContentLayout()
    end
    return true
end

function UI:ShowBlueprintDraft(draft)
    if not self.initialized or not Safe.IsTable(draft) then return end
    self.pendingDraft = draft
    if self:IsTestPreview() then
        if Safe.IsTable(self.testPreviewSnapshot) then
            self.testPreviewSnapshot.blueprintShown = true
        end
        return
    end
    local missing = math.max(0, safeNumber(draft.totalMissing, 0))
    local entries = math.max(0, safeNumber(draft.totalEntries, Safe.IsTable(draft.items) and #draft.items or 0))
    self.blueprintBanner.title:SetText("Blueprint ready: " .. safeString(draft.name, "Imported Blueprint"))
    self.blueprintBanner.detail:SetFormattedText("%d decor entries  •  %d pieces missing", entries, missing)
    self.blueprintBanner:SetShown(not self:IsReadOnlyUnsupported())
    self:UpdateContentLayout(true)
    self:Show()
end

-- Developer preview data is memory-only. It deliberately bypasses Store and
-- remains active while the window is hidden; ClearTestPreview restores the
-- exact live search, filter, scroll offsets, draft visibility, and open state.
function UI:ShowTestPreview(mode)
    mode = safeString(mode, "default"):lower()
    if mode == "" then mode = "default" end
    if not TEST_PREVIEW_MODES[mode] then
        return false, "unknown-mode"
    end

    local uiWasInitialized = self.initialized == true
    local pendingDraft
    if not uiWasInitialized then
        local candidate = call(Addon:GetModule("Blueprints"), "GetPendingDraft")
        if Safe.IsTable(candidate) then pendingDraft = candidate end
    end
    if not uiWasInitialized then
        -- Seed preview first so Initialize never asks Store for live lists.
        self.testPreview = buildTestPreview(mode)
        self:Initialize()
    end
    if not self.frame then
        self.testPreview = nil
        return false, "ui-unavailable"
    end
    if self.prompt and Safe.AsBoolean(self.prompt:IsShown(), false) then
        return false, "dialog-open"
    end

    if not self.testPreviewSnapshot then
        self.testPreviewSnapshot = {
            uiWasInitialized = uiWasInitialized,
            wasShown = Safe.AsBoolean(self.frame:IsShown(), false),
            searchText = safeString(self.search:GetText(), ""),
            filterIndex = self.filterIndex,
            listOffset = self.listOffset,
            itemOffset = self.itemOffset,
            blueprintShown = uiWasInitialized and Safe.AsBoolean(self.blueprintBanner:IsShown(), false)
                or Safe.IsTable(pendingDraft),
        }
    end

    self.testPreview = buildTestPreview(mode)
    self.search:SetText("")
    self.searchText = ""
    self.filterIndex = 1
    self.filterButton:SetText(SOURCE_LABELS.all)
    self.listOffset = 0
    self.itemOffset = 0
    self:Show()
    return true, mode
end

function UI:ClearTestPreview()
    if not self:IsTestPreview() then return false, "not-active" end
    local snapshot = self.testPreviewSnapshot or {}
    self.testPreview = nil
    self.testPreviewSnapshot = nil

    self.suspendRender = true
    self.search:SetText(safeString(snapshot.searchText, ""))
    self.suspendRender = false
    self.searchText = safeString(snapshot.searchText, ""):lower()
    self.filterIndex = math.floor(math.max(1, math.min(#SOURCE_FILTERS, safeNumber(snapshot.filterIndex, 1))))
    self.filterButton:SetText(SOURCE_LABELS[SOURCE_FILTERS[self.filterIndex]])
    self.listOffset = math.max(0, safeNumber(snapshot.listOffset, 0))
    self.itemOffset = math.max(0, safeNumber(snapshot.itemOffset, 0))
    self.previewBanner:Hide()
    self.previewBadge:Hide()
    self.blueprintBanner:SetShown(Safe.AsBoolean(snapshot.blueprintShown, false) and not self:IsReadOnlyUnsupported())

    if not Safe.AsBoolean(snapshot.uiWasInitialized, true) and not Safe.AsBoolean(snapshot.wasShown, false) then
        -- The live window was never initialized or visible. Leave it hidden and
        -- defer Store access until a normal UI open.
        self.frame:Hide()
        return true
    end

    self:Refresh("test-preview-cleared")

    if Safe.AsBoolean(snapshot.wasShown, false) then
        self.frame:Show()
        self.frame:Raise()
    else
        self.frame:Hide()
    end
    return true
end

function UI:ToggleTestPreview(mode)
    if self:IsTestPreview() then
        return self:ClearTestPreview()
    end
    return self:ShowTestPreview(mode)
end

function UI:Initialize()
    if self.initialized then return end
    local Theme = self:GetTheme()
    if not Theme then return end
    self.initialized = true
    self.listOffset = 0
    self.itemOffset = 0
    self.searchText = ""

    local frame = Theme:CreateWindow(Addon.title or "Decor Shopping List", 820, 580, "DIALOG")
    Theme:SetWindowHeaderHeight(frame, 56)
    Theme:AddWindowIcon(frame, "Interface\\AddOns\\DecorShoppingList\\Assets\\DecorShoppingListIcon", 39)
    frame:SetScript("OnHide", function()
        if self.prompt and Safe.AsBoolean(self.prompt:IsShown(), false) then
            self.prompt:Hide()
        end
        local help = Addon:GetModule("Help")
        call(help, "Hide")
    end)
    frame:Hide()
    self.frame = frame
    addEscapeFrame(frame, "DecorShoppingListMainFrame")

    self:CreateListRail(frame)
    self:CreateContent(frame)
    self:CreatePrompt(frame)

    local helpButton = Theme:CreateButton(frame, "?  Help", 76, 24)
    helpButton:SetPoint("BOTTOMLEFT", 21, 18)
    helpButton:SetScript("OnClick", function()
        local help = Addon:GetModule("Help")
        call(help, "Toggle")
    end)
    local closeButton = Theme:CreateButton(frame, CLOSE or "Close", 105, 25)
    closeButton:SetPoint("BOTTOMRIGHT", -21, 18)
    closeButton:SetScript("OnClick", function() self:Hide() end)
    local clearWaypoints = Theme:CreateButton(frame, "Clear Waypoints", 118, 25)
    clearWaypoints:SetPoint("RIGHT", closeButton, "LEFT", -8, 0)
    clearWaypoints:SetScript("OnClick", function()
        if self:IsTestPreview() then return end
        local success, result = call(Addon:GetModule("Waypoint"), "Clear")
        success = Safe.AsBoolean(success, false)
        local status = Safe.IsTable(result) and safeString(result.status, "") or ""
        if status == "cleared" or (status == "" and success) then
            Addon:Print("Addon waypoints cleared. Blizzard decor tracking is unchanged.")
        elseif status == "nothing-owned" then
            Addon:Print("No addon waypoints to clear. Blizzard decor tracking is unchanged.")
        elseif status == "partial-failure" then
            Addon:Print("Some addon waypoints remain. Try again. Blizzard decor tracking is unchanged.")
        else
            Addon:Print("Waypoints weren't cleared. Try again. Blizzard decor tracking is unchanged.")
        end
        self:RenderItems()
    end)
    setButtonTooltip(clearWaypoints, "Clear Waypoints", "Remove this addon's waypoints. Restores the prior Blizzard waypoint when safe.")
    setEnabled(clearWaypoints, Safe.IsTable(Addon:GetModule("Waypoint")), "Waypoint support is unavailable.")
    self.clearWaypointsButton = clearWaypoints
    local friendlyNPCNameplates = Theme:CreateButton(frame, "Show NPC Plates", 116, 25)
    friendlyNPCNameplates:SetPoint("RIGHT", clearWaypoints, "LEFT", -8, 0)
    friendlyNPCNameplates:SetScript("OnClick", function()
        if self:IsTestPreview() then return end
        local success = Safe.AsBoolean(call(Addon:GetModule("VendorNameplateIntegration"),
            "ToggleFriendlyNPCNameplates"), false)
        if not success then
            Addon:Print("Friendly NPC nameplates could not be changed.")
        end
        self:RefreshFriendlyNPCNameplatesButton()
    end)
    setButtonTooltip(friendlyNPCNameplates, "Friendly NPC Nameplates",
        "Temporarily toggle Blizzard’s friendly NPC nameplates. Toggle again to restore the prior setting; logout and reload also restore it.")
    self.friendlyNPCNameplatesButton = friendlyNPCNameplates
    self:RefreshFriendlyNPCNameplatesButton()
    -- Building a long list while this window is hidden wastes work and makes
    -- login/catalog interactions hitch. Show() performs the first render.
    self.refreshPending = true
    self.lists = {}
    self.listSummaries = {}

    local blueprints = Addon:GetModule("Blueprints")
    local draft = call(blueprints, "GetPendingDraft")
    if Safe.IsTable(draft) then self:ShowBlueprintDraft(draft) end
end

function UI:Show()
    if not self.initialized then self:Initialize() end
    if not self.frame then return end
    self:Refresh("show")
    self.frame:Show()
    self.frame:Raise()
end

function UI:Hide()
    if self.frame then self.frame:Hide() end
end

function UI:Toggle(forceShown)
    if not self.initialized then self:Initialize() end
    if not self.frame then return end
    forceShown = Safe.AsBoolean(forceShown, nil)
    if forceShown == true then
        self:Show()
    elseif forceShown == false then
        self:Hide()
    elseif Safe.AsBoolean(self.frame:IsShown(), false) then
        self:Hide()
    else
        self:Show()
    end
end
