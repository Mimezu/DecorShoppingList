local _, Addon = ...

local Safe = Addon.Safe
local VendorNameplates = {}

local initialized = false
local activeUnits = {}
local markers = {}
local friendlyNPCLease
local writingFriendlyNPCCVar = false

local FRIENDLY_NPC_CVAR = "nameplateShowFriendlyNPCs"

local function Field(tableValue, key)
    if not Safe.IsTable(tableValue) then return nil end
    local value = tableValue[key]
    return Safe.IsReadable(value) and value or nil
end

local function Callable(value)
    return Safe.IsReadable(value) and type(value) == "function" and value or nil
end

local function ReadFriendlyNPCNameplates()
    local cvarAPI = Safe.IsTable(C_CVar) and C_CVar or nil
    local getBool = cvarAPI and Callable(Field(cvarAPI, "GetCVarBool"))
    if getBool then
        local ok, enabled = Safe.Call(getBool, FRIENDLY_NPC_CVAR)
        if ok then
            enabled = Safe.AsBoolean(enabled, nil)
            if enabled ~= nil then return enabled end
        end
    end

    local getValue = cvarAPI and Callable(Field(cvarAPI, "GetCVar"))
    if not getValue then return nil end
    local ok, value = Safe.Call(getValue, FRIENDLY_NPC_CVAR)
    value = ok and Safe.TrimmedString(value, nil, 16) or nil
    if value == "1" then return true end
    if value == "0" then return false end
    return nil
end

local function NotifyFriendlyNPCState()
    local ui = Addon:GetModule("UI")
    local refresh = ui and Callable(Field(ui, "RefreshFriendlyNPCNameplatesButton"))
    if refresh then Safe.Call(refresh, ui) end
end

local function WriteFriendlyNPCNameplates(enabled)
    local cvarAPI = Safe.IsTable(C_CVar) and C_CVar or nil
    local setValue = cvarAPI and Callable(Field(cvarAPI, "SetCVar"))
    if not setValue then return false end
    writingFriendlyNPCCVar = true
    local ok = Safe.Call(setValue, FRIENDLY_NPC_CVAR, enabled and "1" or "0")
    writingFriendlyNPCCVar = false
    return ok and ReadFriendlyNPCNameplates() == enabled
end

local function NPCIDFromUnit(unit)
    local unitGUID = Callable(UnitGUID)
    if not unitGUID then return nil end
    local ok, guid = Safe.Call(unitGUID, unit)
    guid = ok and Safe.TrimmedString(guid, nil, 256) or nil
    if not guid then return nil end

    local fields = {}
    for field in string.gmatch(guid, "[^-]+") do
        fields[#fields + 1] = field
        if #fields >= 7 then break end
    end
    if fields[1] ~= "Creature" and fields[1] ~= "Vehicle" then return nil end
    return Safe.AsPositiveInteger(tonumber(fields[6]), nil, 2147483647)
end

local function CreateMarker(nameplate)
    local createFrame = Callable(CreateFrame)
    if not createFrame or not Safe.IsTable(nameplate) then return nil end
    local ok, marker = Safe.Call(createFrame, "Frame", nil, nameplate)
    if not ok or not Safe.IsTable(marker) then return nil end

    marker:SetSize(38, 38)
    marker:SetPoint("BOTTOM", nameplate, "TOP", 0, 8)
    marker:EnableMouse(false)
    local getFrameLevel = Callable(Field(nameplate, "GetFrameLevel"))
    local levelOK, rawLevel = false, nil
    if getFrameLevel then
        levelOK, rawLevel = Safe.Call(getFrameLevel, nameplate)
    end
    local plateLevel = Safe.AsNonNegativeInteger(levelOK and rawLevel, 0, 10000)
    marker:SetFrameLevel((plateLevel or 0) + 20)

    local glow = marker:CreateTexture(nil, "BACKGROUND")
    glow:SetPoint("CENTER")
    glow:SetSize(38, 38)
    glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(1, 0.72, 0.16, 0.9)

    local icon = marker:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("CENTER")
    icon:SetSize(27, 27)
    icon:SetTexture("Interface\\AddOns\\DecorShoppingList\\Assets\\DecorShoppingListIcon")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    marker:Hide()
    return marker
end

function VendorNameplates:UpdateUnit(unit)
    unit = Safe.TrimmedString(unit, nil, 64)
    if not unit then return end

    local namePlateAPI = Safe.IsTable(C_NamePlate) and C_NamePlate or nil
    local getNamePlate = namePlateAPI and Callable(Field(namePlateAPI, "GetNamePlateForUnit"))
    local waypoint = Addon:GetModule("Waypoint")
    local isTracked = waypoint and Callable(Field(waypoint, "IsVendorNPCTracked"))
    local npcID = NPCIDFromUnit(unit)
    local trackedOK, trackedValue = false, false
    if npcID and isTracked then
        trackedOK, trackedValue = Safe.Call(isTracked, waypoint, npcID)
    end
    trackedValue = trackedOK and Safe.AsBoolean(trackedValue, false) == true

    local marker = markers[unit]
    if not trackedValue or not getNamePlate then
        if marker then marker:Hide() end
        return
    end

    local ok, nameplate = Safe.Call(getNamePlate, unit)
    if not ok or not Safe.IsTable(nameplate) then
        if marker then marker:Hide() end
        return
    end

    if not marker or marker:GetParent() ~= nameplate then
        if marker then marker:Hide() end
        marker = CreateMarker(nameplate)
        markers[unit] = marker
    end
    if marker then marker:Show() end
end

function VendorNameplates:Refresh()
    for unit in pairs(activeUnits) do
        self:UpdateUnit(unit)
    end
end

function VendorNameplates:GetFriendlyNPCNameplatesState()
    return ReadFriendlyNPCNameplates()
end

function VendorNameplates:ToggleFriendlyNPCNameplates()
    local current = ReadFriendlyNPCNameplates()
    if current == nil then
        return false, nil, "unavailable"
    end

    if friendlyNPCLease and current ~= friendlyNPCLease.applied then
        -- A newer external change owns the setting. Release the older lease
        -- before treating this click as a new temporary toggle.
        friendlyNPCLease = nil
    end

    local target
    local restoring = friendlyNPCLease ~= nil
    local nextLease
    if restoring then
        target = friendlyNPCLease.previous
    else
        target = not current
        nextLease = { previous = current, applied = target }
        friendlyNPCLease = nextLease
    end

    if not WriteFriendlyNPCNameplates(target) then
        if nextLease then friendlyNPCLease = nil end
        NotifyFriendlyNPCState()
        return false, current, "set-failed"
    end

    if restoring then friendlyNPCLease = nil end
    NotifyFriendlyNPCState()
    return true, target, restoring and "restored" or "temporary"
end

function VendorNameplates:RestoreFriendlyNPCNameplates()
    local lease = friendlyNPCLease
    if not lease then return true, "none" end
    local current = ReadFriendlyNPCNameplates()
    if current == nil then return false, "unavailable" end
    if current ~= lease.applied then
        friendlyNPCLease = nil
        NotifyFriendlyNPCState()
        return true, "preserved"
    end
    if not WriteFriendlyNPCNameplates(lease.previous) then
        return false, "restore-failed"
    end
    friendlyNPCLease = nil
    NotifyFriendlyNPCState()
    return true, "restored"
end

function VendorNameplates:OnEvent(event, unit)
    event = Safe.AsString(event, nil)
    if not event then return end
    if event == "NAME_PLATE_UNIT_ADDED" then
        unit = Safe.TrimmedString(unit, nil, 64)
        if not unit then return end
        activeUnits[unit] = true
        self:UpdateUnit(unit)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        unit = Safe.TrimmedString(unit, nil, 64)
        if not unit then return end
        activeUnits[unit] = nil
        if markers[unit] then markers[unit]:Hide() end
    elseif event == "CVAR_UPDATE" then
        local cvarName = Safe.TrimmedString(unit, nil, 128)
        if cvarName and string.lower(cvarName) == string.lower(FRIENDLY_NPC_CVAR) then
            local current = ReadFriendlyNPCNameplates()
            if not writingFriendlyNPCCVar and friendlyNPCLease
                and current ~= nil and current ~= friendlyNPCLease.applied
            then
                friendlyNPCLease = nil
            end
            NotifyFriendlyNPCState()
        end
    elseif event == "PLAYER_LOGOUT" then
        self:RestoreFriendlyNPCNameplates()
    end
end

function VendorNameplates:Initialize()
    if initialized then return true end
    local createFrame = Callable(CreateFrame)
    if not createFrame or not Safe.IsTable(C_NamePlate) or not Callable(UnitGUID) then
        return false
    end
    local ok, frame = Safe.Call(createFrame, "Frame")
    if not ok or not Safe.IsTable(frame) then return false end
    frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    frame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    frame:RegisterEvent("CVAR_UPDATE")
    frame:RegisterEvent("PLAYER_LOGOUT")
    frame:SetScript("OnEvent", function(_, event, unit)
        VendorNameplates:OnEvent(event, unit)
    end)
    initialized = true
    return true
end

Addon:RegisterModule("VendorNameplateIntegration", VendorNameplates)
