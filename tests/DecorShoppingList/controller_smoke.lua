-- Controller boundary smoke tests. Run from the Retail workspace root.

local addonRoot = ""
local Addon = {}

local function LoadAddonFile(relativePath)
    local chunk, errorMessage = loadfile(addonRoot .. relativePath)
    assert(chunk, errorMessage)
    chunk("DecorShoppingList", Addon)
end

local messages = {}
DEFAULT_CHAT_FRAME = {
    AddMessage = function(_, message)
        messages[#messages + 1] = message
    end,
}

LoadAddonFile("Bootstrap.lua")
LoadAddonFile("Core/SafeValue.lua")
LoadAddonFile("Core/Controller.lua")

local Controller = assert(Addon:GetModule("Controller"))
local previewModes = {}
local previewClears = 0
local storeTouched = false

Addon:RegisterModule("UI", {
    ShowTestPreview = function(_, mode)
        previewModes[#previewModes + 1] = mode
        return true, mode
    end,
    ClearTestPreview = function()
        previewClears = previewClears + 1
        return true
    end,
})
Addon:RegisterModule("Store", {
    Initialize = function()
        storeTouched = true
        error("testui touched Store")
    end,
})

Controller:HandleSlashCommand("testui")
Controller:HandleSlashCommand("testui dense")
Controller:HandleSlashCommand("testui empty")
Controller:HandleSlashCommand("testui readonly")
Controller:HandleSlashCommand("testui off")
Controller:HandleSlashCommand("testui unknown")
assert(not storeTouched, "testui initialized or touched Store")
assert(table.concat(previewModes, ",") == "default,dense,empty,readonly", "testui modes were not routed exactly")
assert(previewClears == 1, "testui off did not clear the preview exactly once")
assert(#messages == 6 and messages[6]:find("Usage:", 1, true), "unknown testui mode did not print concise help")

-- Replace the hostile Store with normal save-boundary mocks.
local changeHandler
Addon:RegisterModule("Store", {
    Initialize = function() return {} end,
    SetChangeHandler = function(_, handler) changeHandler = handler end,
    GetActiveList = function() return nil end,
})
local createdName
Addon:RegisterModule("Blueprints", {
    GetEvents = function() return {} end,
    CreateListFromPending = function(_, name)
        createdName = name
        return { id = "2", name = name or "Blueprint List" }
    end,
})
local sequence = {}
Addon:RegisterModule("UI", {
    ClearBlueprintDraft = function()
        sequence[#sequence + 1] = "clear-draft"
        return true
    end,
    Toggle = function(_, forceShown)
        assert(forceShown == true, "save did not request a visible UI")
        sequence[#sequence + 1] = "show-ui"
    end,
})
local registeredEvents = {}
Addon.eventFrame = {
    RegisterEvent = function(_, event) registeredEvents[event] = true end,
}

Controller:HandleSlashCommand("save Saved From Slash")
assert(createdName == "Saved From Slash", "slash save did not pass the requested list name")
assert(table.concat(sequence, ",") == "clear-draft,show-ui", "slash save did not reconcile draft before showing UI")
assert(type(changeHandler) == "function", "controller initialization did not establish the Store callback")
assert(registeredEvents.HOUSE_DECOR_ADDED_TO_CHEST,
    "direct House Chest acquisition event was not registered")

-- Confirmed ownership completion is untracked before the consolidated Store
-- notification, while the completed row remains in its list.
local completedItem = { key = "decor:42", desired = 1, owned = 0, missing = 1 }
local completedList = { id = "active", items = { [completedItem.key] = completedItem } }
local untrackedItem
local ownershipNotice
Addon:RegisterModule("Store", {
    GetActiveList = function() return completedList end,
    _Notify = function(_, reason, payload)
        ownershipNotice = { reason = reason, payload = payload }
    end,
})
Addon:RegisterModule("Catalog", {
    RefreshListOwnership = function()
        completedItem.owned = 1
        completedItem.missing = 0
        return 1, { completedItem }
    end,
})
Addon:RegisterModule("Waypoint", {
    UntrackItem = function(_, item)
        untrackedItem = item
        return true, "untracked"
    end,
})
Controller:_RefreshActiveOwnership()
assert(untrackedItem == completedItem, "newly completed decor was not automatically untracked")
assert(completedList.items[completedItem.key] == completedItem, "automatic completion removed the list row")
assert(ownershipNotice and ownershipNotice.reason == "ownership-refreshed"
    and ownershipNotice.payload.completedCount == 1,
    "automatic completion did not emit one consolidated ownership refresh")

print("Decor Shopping List controller smoke tests passed")
