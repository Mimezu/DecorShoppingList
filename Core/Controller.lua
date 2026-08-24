local addonName, Addon = ...

local Safe = Addon.Safe
local Controller = {
    initialized = false,
}

local function UI()
    return Addon:GetModule("UI")
end

local function Print(message)
    if type(message) == "string" then
        Addon:Print(message)
    end
end

local function IsCallable(value)
    return Safe.IsReadable(value) and type(value) == "function"
end

local function RegisterEvent(event)
    local frame = Addon.eventFrame
    if not Safe.IsTable(frame) then
        return false
    end
    local register = frame.RegisterEvent
    if not IsCallable(register) then
        return false
    end
    return pcall(register, frame, event)
end

function Controller:_RefreshUI(reason, payload)
    local ui = UI()
    if ui and type(ui.Refresh) == "function" then
        pcall(ui.Refresh, ui, reason, payload)
    end
    local merchant = Addon:GetModule("MerchantIntegration")
    if merchant and type(merchant.Refresh) == "function" then
        pcall(merchant.Refresh, merchant, reason, payload)
    end
end

function Controller:_RefreshActiveOwnership()
    local store = Addon:GetModule("Store")
    local catalog = Addon:GetModule("Catalog")
    local list = store and store:GetActiveList() or nil
    local changed = 0
    local completed = {}
    if catalog and list and type(catalog.RefreshListOwnership) == "function" then
        local ok, result, newlyCompleted = pcall(catalog.RefreshListOwnership, catalog, list)
        changed = ok and Safe.AsNonNegativeInteger(result, 0, 5000) or 0
        completed = ok and Safe.IsTable(newlyCompleted) and newlyCompleted or completed
    end

    local waypoint = Addon:GetModule("Waypoint")
    local untrackItem = waypoint and waypoint.UntrackItem or nil
    if IsCallable(untrackItem) then
        local examined = 0
        for _, item in ipairs(completed) do
            examined = examined + 1
            if examined > 5000 then break end
            if Safe.IsTable(item) and Safe.AsNonNegativeInteger(item.missing, 1, 999999) == 0 then
                pcall(untrackItem, waypoint, item)
            end
        end
    end
    if changed > 0 and type(store._Notify) == "function" then
        store:_Notify("ownership-refreshed", {
            list = list,
            count = changed,
            completedCount = math.min(#completed, 5000),
        })
    else
        self:_RefreshUI("ownership-refreshed")
    end
end

function Controller:_ScheduleOwnershipRefresh()
    self.ownershipRefreshToken = (self.ownershipRefreshToken or 0) + 1
    local token = self.ownershipRefreshToken
    local timerAPI = Safe.IsTable(C_Timer) and C_Timer or nil
    local after = timerAPI and timerAPI.After or nil
    if not IsCallable(after) then
        self:_RefreshActiveOwnership()
        return
    end
    pcall(after, 0.20, function()
        if self.ownershipRefreshToken == token then
            self:_RefreshActiveOwnership()
        end
    end)
end

function Controller:Initialize()
    if not self.initialized then
        local store = Addon:GetModule("Store")
        if store then
            local ok, errorMessage = pcall(store.Initialize, store)
            if not ok then
                if not self.storeInitErrorReported then
                    self.storeInitErrorReported = true
                    Print("Could not initialize saved lists: " .. tostring(errorMessage))
                end
                return false
            end
            store:SetChangeHandler(function(reason, payload)
                if reason == "active-list-changed" then
                    self:_ScheduleOwnershipRefresh()
                end
                self:_RefreshUI(reason, payload)
            end)
        end

        local blueprints = Addon:GetModule("Blueprints")
        if blueprints and Addon.eventFrame then
            for _, event in ipairs(blueprints:GetEvents()) do
                if Safe.AsString(event, nil) then
                    RegisterEvent(event)
                end
            end
            RegisterEvent("HOUSING_STORAGE_UPDATED")
            RegisterEvent("HOUSING_STORAGE_ENTRY_UPDATED")
            RegisterEvent("HOUSE_DECOR_ADDED_TO_CHEST")
        end
        self.initialized = true
    end

    self.moduleInitialization = self.moduleInitialization or {}
    local function InitializeModule(name, module)
        if self.moduleInitialization[name] or not module or type(module.Initialize) ~= "function" then
            return
        end
        local ok, result = pcall(module.Initialize, module)
        if ok and result ~= false then
            self.moduleInitialization[name] = true
        elseif not ok then
            self.moduleInitErrorReported = self.moduleInitErrorReported or {}
            if not self.moduleInitErrorReported[name] then
                self.moduleInitErrorReported[name] = true
                Print("Could not initialize " .. name .. "; the addon will retry.")
            end
        end
    end
    InitializeModule("UI", UI())
    InitializeModule("CatalogIntegration", Addon:GetModule("CatalogIntegration"))
    InitializeModule("MerchantIntegration", Addon:GetModule("MerchantIntegration"))
    InitializeModule("Waypoint", Addon:GetModule("Waypoint"))
    InitializeModule("VendorNameplateIntegration", Addon:GetModule("VendorNameplateIntegration"))
    return true
end

function Controller:OnEvent(event, ...)
    event = Safe.AsString(event, nil)
    if not event then
        return
    end

    if event == "ADDON_LOADED" then
        local loadedName = Safe.AsString((...), nil)
        if loadedName == addonName then
            self:Initialize()
        elseif self.initialized and (loadedName == "Blizzard_HousingTemplates"
            or loadedName == "Blizzard_HousingDashboard"
            or loadedName == "Blizzard_HousingBlueprint") then
            local integration = Addon:GetModule("CatalogIntegration")
            if integration and type(integration.Initialize) == "function" then
                pcall(integration.Initialize, integration)
            end
        end
        return
    end

    if not self:Initialize() then
        return
    end

    if event == "HOUSING_STORAGE_UPDATED"
        or event == "HOUSING_STORAGE_ENTRY_UPDATED"
        or event == "HOUSE_DECOR_ADDED_TO_CHEST"
    then
        self:_ScheduleOwnershipRefresh()
        return
    end

    if event == "MERCHANT_SHOW" or event == "MERCHANT_UPDATE" or event == "MERCHANT_CLOSED" then
        local merchant = Addon:GetModule("MerchantIntegration")
        if merchant and type(merchant.OnEvent) == "function" then
            pcall(merchant.OnEvent, merchant, event, ...)
        end
        return
    end

    local blueprints = Addon:GetModule("Blueprints")
    if blueprints then
        for _, blueprintEvent in ipairs(blueprints:GetEvents()) do
            if event == blueprintEvent then
                blueprints:OnEvent(event, ...)
                return
            end
        end
    end

    if event == "PLAYER_LOGIN" or event == "PLAYER_REGEN_ENABLED" then
        if event == "PLAYER_LOGIN" then
            local integration = Addon:GetModule("CatalogIntegration")
            if integration and type(integration.Initialize) == "function" then
                pcall(integration.Initialize, integration)
            end
            self:_ScheduleOwnershipRefresh()
        end
        self:_RefreshUI(event)
    end
end

local function FindList(store, query)
    query = Safe.TrimmedString(query, nil, 96)
    if not query then
        return nil
    end
    local byID = store:GetList(query)
    if byID then
        return byID
    end
    local lowerQuery = query:lower()
    for _, list in ipairs(store:GetLists()) do
        if list.name:lower() == lowerQuery then
            return list
        end
    end
end

local TEST_UI_MODES = {
    default = true,
    dense = true,
    empty = true,
    readonly = true,
}

local function HandleTestUICommand(rest)
    local mode = Safe.TrimmedString(rest, "default", 16):lower()
    if mode ~= "off" and not TEST_UI_MODES[mode] then
        Print("Usage: /dsl testui [default|dense|empty|readonly|off]")
        return
    end

    local ui = UI()
    if not Safe.IsTable(ui) then
        Print("UI preview is unavailable.")
        return
    end

    local method
    if mode == "off" then
        method = ui.ClearTestPreview
    else
        method = ui.ShowTestPreview
    end
    if not IsCallable(method) then
        Print("UI preview is unavailable.")
        return
    end

    local ok, success, reason
    if mode == "off" then
        ok, success, reason = pcall(method, ui)
    else
        ok, success, reason = pcall(method, ui, mode)
    end
    success = ok and Safe.AsBoolean(success, false) or false
    reason = Safe.AsString(reason, nil)
    if success then
        Print(mode == "off" and "UI preview closed." or ("UI preview: " .. mode .. "."))
    elseif reason == "not-active" then
        Print("UI preview is not active.")
    else
        Print("UI preview is unavailable.")
    end
end

function Controller:HandleSlashCommand(message)
    message = Safe.AsString(message, "")
    local command, rest = message:match("^%s*(%S*)%s*(.-)%s*$")
    command = command and command:lower() or ""

    if command == "testui" then
        HandleTestUICommand(rest)
        return
    end

    if not self:Initialize() then
        return
    end

    local store = Addon:GetModule("Store")
    local blueprints = Addon:GetModule("Blueprints")
    local ui = UI()

    if command == "" or command == "show" or command == "toggle" then
        if ui and type(ui.Toggle) == "function" then
            ui:Toggle()
        end
    elseif command == "new" then
        local list, errorCode = store:CreateList(rest, { kind = "manual" })
        if list then
            Print("Created and selected " .. list.name .. ".")
        else
            Print("Could not create a shopping list (" .. tostring(errorCode) .. ").")
        end
    elseif command == "use" then
        local list = FindList(store, rest)
        if list then
            store:SetActiveList(list.id)
            Print("Active list: " .. list.name .. ".")
        else
            Print("Shopping list not found.")
        end
    elseif command == "lists" then
        local active = store:GetActiveList()
        for _, list in ipairs(store:GetLists()) do
            local marker = active and active.id == list.id and "*" or " "
            Print(string.format("%s %s — %s", marker, list.id, list.name))
        end
    elseif command == "blueprint" then
        local ok, errorCode = blueprints:RequestContents(rest)
        if ok then
            Print("Reading blueprint contents…")
        else
            Print("Could not read that blueprint (" .. tostring(errorCode) .. ").")
        end
    elseif command == "save" then
        local list, errorCode = blueprints:CreateListFromPending(rest ~= "" and rest or nil)
        if list then
            if ui and IsCallable(ui.ClearBlueprintDraft) then
                pcall(ui.ClearBlueprintDraft, ui)
            end
            Print("Created " .. list.name .. " from the blueprint.")
            if ui and IsCallable(ui.Toggle) then
                pcall(ui.Toggle, ui, true)
            end
        else
            Print("No blueprint draft is ready (" .. tostring(errorCode) .. ").")
        end
    else
        Print("Commands: show, new <name>, use <list>, lists, blueprint <code>, save [name], testui <mode|off>")
    end
end

Addon:RegisterModule("Controller", Controller)
