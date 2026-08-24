-- Vendor nameplate marker smoke tests. Run from the Retail workspace root.

local addonRoot = ""

DEFAULT_CHAT_FRAME = { AddMessage = function() end }

local function LoadAddonFile(addon, relativePath)
    local chunk, errorMessage = loadfile(addonRoot .. relativePath)
    assert(chunk, errorMessage)
    chunk("DecorShoppingList", addon)
end

local function Texture()
    local texture = {}
    for _, method in ipairs({ "SetPoint", "SetSize", "SetTexture", "SetBlendMode", "SetVertexColor", "SetTexCoord" }) do
        texture[method] = function() end
    end
    return texture
end

local function Frame(parent)
    local frame = { parent = parent, shown = false, scripts = {}, events = {} }
    function frame:SetSize() end
    function frame:SetPoint() end
    function frame:EnableMouse() end
    function frame:SetFrameLevel() end
    function frame:GetFrameLevel() return 4 end
    function frame:GetParent() return self.parent end
    function frame:CreateTexture() return Texture() end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:SetScript(script, callback) self.scripts[script] = callback end
    return frame
end

local plate = Frame(nil)
local eventOwner
local childFrames = {}
local friendlyNPCNameplates = false
local guids = {
    nameplate1 = "Creature-0-1-2-3-255216-0000000001",
    nameplate2 = "Creature-0-1-2-3-999999-0000000002",
}

CreateFrame = function(_, _, parent)
    local frame = Frame(parent)
    if parent then
        childFrames[#childFrames + 1] = frame
    else
        eventOwner = frame
    end
    return frame
end
UnitGUID = function(unit) return guids[unit] end
C_NamePlate = {
    GetNamePlateForUnit = function(unit)
        return unit == "nameplate1" and plate or nil
    end,
}
C_CVar = {
    GetCVarBool = function(name)
        assert(name == "nameplateShowFriendlyNPCs", "unexpected nameplate CVar read")
        return friendlyNPCNameplates
    end,
    SetCVar = function(name, value)
        assert(name == "nameplateShowFriendlyNPCs", "unexpected nameplate CVar write")
        friendlyNPCNameplates = value == "1"
    end,
}

local addon = {}
LoadAddonFile(addon, "Bootstrap.lua")
LoadAddonFile(addon, "Core/SafeValue.lua")
addon:RegisterModule("Waypoint", {
    IsVendorNPCTracked = function(_, npcID) return npcID == 255216 end,
})
LoadAddonFile(addon, "Integrations/VendorNameplates.lua")

local integration = assert(addon:GetModule("VendorNameplateIntegration"))
assert(integration:Initialize() == true, "nameplate integration did not initialize")
assert(eventOwner.events.NAME_PLATE_UNIT_ADDED and eventOwner.events.NAME_PLATE_UNIT_REMOVED,
    "nameplate events were not registered")
assert(eventOwner.events.CVAR_UPDATE and eventOwner.events.PLAYER_LOGOUT,
    "temporary friendly NPC nameplate lifecycle events were not registered")

local toggled, enabled, mode = integration:ToggleFriendlyNPCNameplates()
assert(toggled and enabled and mode == "temporary" and friendlyNPCNameplates,
    "friendly NPC nameplates were not temporarily enabled")
toggled, enabled, mode = integration:ToggleFriendlyNPCNameplates()
assert(toggled and not enabled and mode == "restored" and not friendlyNPCNameplates,
    "second toggle did not restore the prior friendly NPC setting")

assert(integration:ToggleFriendlyNPCNameplates(), "logout restoration setup failed")
eventOwner.scripts.OnEvent(eventOwner, "PLAYER_LOGOUT")
assert(not friendlyNPCNameplates, "logout did not restore the prior friendly NPC setting")

assert(integration:ToggleFriendlyNPCNameplates(), "external-change preservation setup failed")
friendlyNPCNameplates = false
eventOwner.scripts.OnEvent(eventOwner, "CVAR_UPDATE", "nameplateShowFriendlyNPCs")
local restored, restoreMode = integration:RestoreFriendlyNPCNameplates()
assert(restored and restoreMode == "none" and not friendlyNPCNameplates,
    "a newer external friendly NPC setting was overwritten")

friendlyNPCNameplates = true
toggled, enabled, mode = integration:ToggleFriendlyNPCNameplates()
assert(toggled and not enabled and mode == "temporary" and not friendlyNPCNameplates,
    "an initially enabled friendly NPC setting was not temporarily disabled")
toggled, enabled, mode = integration:ToggleFriendlyNPCNameplates()
assert(toggled and enabled and mode == "restored" and friendlyNPCNameplates,
    "an initially enabled friendly NPC setting was not restored")

eventOwner.scripts.OnEvent(eventOwner, "NAME_PLATE_UNIT_ADDED", "nameplate1")
assert(#childFrames == 1 and childFrames[1].shown, "tracked vendor marker was not shown")

eventOwner.scripts.OnEvent(eventOwner, "NAME_PLATE_UNIT_ADDED", "nameplate2")
assert(#childFrames == 1, "untracked vendor received a marker")

eventOwner.scripts.OnEvent(eventOwner, "NAME_PLATE_UNIT_REMOVED", "nameplate1")
assert(not childFrames[1].shown, "removed nameplate marker remained visible")

eventOwner.scripts.OnEvent(eventOwner, "NAME_PLATE_UNIT_ADDED", "nameplate1")
assert(childFrames[1].shown, "tracked marker did not return with its nameplate")

print("Decor Shopping List vendor nameplate smoke tests passed")
