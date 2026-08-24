-- Run from the Retail workspace root with a Lua 5.1-compatible runtime.

local addonRoot = ""
local addonName = "DecorShoppingList"
local Addon = {}

local function LoadAddonFile(relativePath)
    local chunk, errorMessage = loadfile(addonRoot .. relativePath)
    assert(chunk, errorMessage)
    chunk(addonName, Addon)
end

DecorShoppingListDB = nil
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
function GetServerTime()
    return 1000
end

Enum = {
    HousingBlueprintContentType = { Decor = 3, Room = 2 },
    HousingCatalogEntryType = { Decor = 1, Room = 2 },
}

local ownedByRecord = { [9] = 2, [10] = 0 }
local function CatalogInfo(entryType, recordID)
    return {
        recordID = recordID,
        entryType = entryType,
        itemID = recordID + 100,
        name = "Decor " .. recordID,
        iconTexture = 10000 + recordID,
        sourceText = "Test vendor",
        totalNumStored = ownedByRecord[recordID] or 0,
        remainingRedeemable = 0,
        totalNumPlaced = 0,
    }
end

C_HousingCatalog = {
    GetCatalogEntryInfoByRecordID = function(...)
        assert(select("#", ...) == 2, "record lookup used an obsolete extra argument")
        local entryType, recordID = ...
        return CatalogInfo(entryType, recordID)
    end,
    GetCatalogEntryInfoByItem = function(...)
        assert(select("#", ...) == 1, "item lookup used an obsolete extra argument")
        local itemID = ...
        return CatalogInfo(Enum.HousingCatalogEntryType.Decor, itemID - 100)
    end,
}

local requestedCode
C_HousingBlueprint = {
    UpdateBlueprintStringFromInput = function(code)
        return code == "RAW-CODE" and "TEST-CODE" or code
    end,
    IsShareCodeValid = function(code)
        return code == "TEST-CODE"
    end,
    RequestBlueprintContents = function(code)
        requestedCode = code
    end,
}

LoadAddonFile("Bootstrap.lua")
LoadAddonFile("Core/SafeValue.lua")
LoadAddonFile("Core/Store.lua")
LoadAddonFile("Core/Catalog.lua")
LoadAddonFile("Core/Blueprints.lua")
LoadAddonFile("Core/Controller.lua")

local Store = assert(Addon:GetModule("Store"))
local Catalog = assert(Addon:GetModule("Catalog"))
local Blueprints = assert(Addon:GetModule("Blueprints"))

Store:Initialize()
assert(Store:GetActiveList().name == "My Decor List", "default active list was not created")

assert(Blueprints:RequestContents("RAW-CODE"))
assert(requestedCode == "TEST-CODE", "share code was not normalized before request")
local received = Blueprints:OnEvent("HOUSING_BLUEPRINT_CONTENTS_RECEIVED", {
    shareCode = "RAW-CODE",
    contentGroups = {
        {
            contentType = Enum.HousingBlueprintContentType.Decor,
            entries = {
                { recordID = 9, total = 4, numMissing = 3 },
                { recordID = 9, total = 2, numMissing = 1 },
                { recordID = 10, total = 1, numMissing = 0 },
                { recordID = 11, name = "Invalid Statue", total = 3, numMissing = 0, invalid = true },
            },
        },
        {
            contentType = Enum.HousingBlueprintContentType.Room,
            entries = {
                { recordID = 99, total = 1, numMissing = 1 },
            },
        },
    },
})
assert(received, "matching blueprint response was not captured")

local draft = assert(Blueprints:GetPendingDraft())
assert(draft.totalEntries == 2, "decor duplicates or invalid entries were not normalized")
assert(draft.totalMissing == 7, "missing quantities were not aggregated")
assert(draft.items[1].desired == 6 and draft.items[1].owned == 2, "blueprint totals were normalized incorrectly")
assert(draft.items[2].name == "Invalid Statue", "blueprint entry name was not retained")
assert(draft.items[2].desired == 3 and draft.items[2].missing == 3 and draft.items[2].invalid,
    "invalid blueprint entry was not treated as fully missing")

local list = assert(Blueprints:CreateListFromPending("Smoke Blueprint"))
local blueprintItem = assert(list.items["decor:9"])
assert(Store:GetActiveList() == list, "blueprint list did not become active")
assert(blueprintItem.addedFrom == "blueprint", "blueprint provenance was not stored")

local sameItem, wasAdded = Store:AddItem(list.id, {
    recordID = 9,
    itemID = 109,
    name = "Decor 9",
    addedFrom = "catalog",
}, 1, "ensure")
assert(sameItem == blueprintItem and not wasAdded, "catalog ensure was not idempotent")
assert(blueprintItem.desired == 6 and blueprintItem.owned == 2 and blueprintItem.missing == 4,
    "catalog ensure changed the blueprint quantity state")
assert(blueprintItem.addedFrom == "blueprint", "catalog ensure replaced blueprint provenance")
local redundantNotifications = 0
Store:SetChangeHandler(function() redundantNotifications = redundantNotifications + 1 end)
local unchangedItem, unchangedAdded = Store:AddItem(list.id, {
    recordID = blueprintItem.recordID,
    itemID = blueprintItem.itemID,
    name = blueprintItem.name,
    sourceText = blueprintItem.sourceText,
    owned = blueprintItem.owned,
    missing = blueprintItem.missing,
    invalid = blueprintItem.invalid,
    addedFrom = blueprintItem.addedFrom,
}, blueprintItem.desired, "ensure")
assert(unchangedItem == blueprintItem and not unchangedAdded and redundantNotifications == 0,
    "unchanged catalog ensure emitted a redundant Store notification")
Store:SetChangeHandler(nil)
local _, invalidMode = Store:AddItem(list.id, { recordID = 9 }, 1, {})
assert(invalidMode == "invalid-mode", "public add mode was not normalized safely")

local manualItem = assert(Store:AddItem(list.id, {
    recordID = 10,
    itemID = 110,
    name = "Manual goal",
    owned = 0,
    addedFrom = "manual",
}, 2, "replace"))

ownedByRecord[9] = 5
ownedByRecord[10] = 2
ownedByRecord[11] = 3
local refreshed, completed = Catalog:RefreshListOwnership(list)
assert(refreshed == 2, "ownership refresh count was incorrect")
assert(blueprintItem.owned == 5 and blueprintItem.missing == 1, "blueprint ownership did not refresh")
assert(manualItem.owned == 2 and manualItem.missing == 0, "manual acquisition was not completed")
assert(#completed == 1 and completed[1] == manualItem, "newly completed decor was not reported for untracking")
assert(list.items["decor:11"].missing == 3, "invalid blueprint entry was auto-completed")

local resolved = assert(Catalog:ResolveItem(109))
assert(resolved.recordID == 9 and resolved.entryType == Enum.HousingCatalogEntryType.Decor,
    "direct catalog record fields were not resolved")
assert(resolved.owned == 5, "catalog ownership fields were not summed correctly")

local hiddenReceived = Blueprints:OnEvent("HOUSING_BLUEPRINT_CONTENTS_RECEIVED", {
    shareCode = "HIDDEN-CODE",
    contentGroups = {},
})
assert(not hiddenReceived, "hidden unsolicited contents from another consumer were captured")

HousingBlueprintContentListFrame = { IsShown = function() return true end }
assert(not Blueprints:OnEvent("HOUSING_BLUEPRINT_CONTENTS_RECEIVED", {
    shareCode = "VISIBLE-UNKNOWN-CODE",
    contentGroups = {},
}), "visible native frame without identity methods failed open")

HousingBlueprintContentListFrame = {
    IsShown = function() return true end,
    GetTargetGUID = function() return "House-1" end,
    IsShowingBlueprintForTarget = function(_, code, houseGUID)
        assert(houseGUID == "House-1", "content list target GUID was not supplied")
        return code == "NATIVE-CODE"
    end,
}
local nativeReceived = Blueprints:OnEvent("HOUSING_BLUEPRINT_CONTENTS_RECEIVED", {
    shareCode = "NATIVE-CODE",
    contentGroups = {
        {
            contentType = Enum.HousingBlueprintContentType.Decor,
            entries = {
                { recordID = 10, total = 2, numMissing = 2 },
            },
        },
    },
})
assert(nativeReceived, "unsolicited native Housing contents were not captured")
assert(Blueprints:GetPendingDraft().shareCode == "NATIVE-CODE", "native draft share code was not retained")
assert(not Blueprints:OnEvent("HOUSING_BLUEPRINT_CONTENTS_RECEIVED", {
    shareCode = "OTHER-NATIVE-CODE",
    contentGroups = {},
}), "visible native frame accepted a blueprint it was not showing")

HousingBlueprintContentListFrame = nil
HousingBlueprintImportFrame = {
    ValidationContent = {
        IsShown = function() return true end,
        IsShowingBlueprint = function(_, code) return code == "TARGET-CODE" end,
    },
}
assert(Blueprints:OnEvent("HOUSING_BLUEPRINT_CONTENTS_RECEIVED", {
    shareCode = "TARGET-CODE",
    contentGroups = {},
}), "visible native validation target was not accepted")

assert(Blueprints:RequestContents("TEST-CODE"))
local mismatchReceived = Blueprints:OnEvent("HOUSING_BLUEPRINT_CONTENTS_RECEIVED", {
    shareCode = "OTHER-CODE",
    contentGroups = {},
})
assert(not mismatchReceived, "mismatched terminal response was captured")
assert(Blueprints:RequestContents("TEST-CODE"), "mismatched response left the request pipeline locked")
Blueprints:OnEvent("HOUSING_BLUEPRINT_CONTENTS_FAILURE", nil, 1)
assert(Blueprints:RequestContents("TEST-CODE"), "failure event left the request pipeline locked")
assert(Blueprints:OnEvent("HOUSING_BLUEPRINT_CONTENTS_RECEIVED", {
    shareCode = "TEST-CODE",
    contentGroups = {
        {
            contentType = Enum.HousingBlueprintContentType.Decor,
            entries = {
                { recordID = 12, name = "Saved Chair", total = 1, numMissing = 1 },
            },
        },
    },
}), "save-command draft was not prepared")

local clearedDrafts, toggledUI = 0, 0
Addon:RegisterModule("UI", {
    ClearBlueprintDraft = function()
        clearedDrafts = clearedDrafts + 1
        return true
    end,
    Toggle = function(_, forceShown)
        assert(forceShown == true, "save command did not request the visible UI")
        toggledUI = toggledUI + 1
    end,
})
Addon.eventFrame = { RegisterEvent = function() end }
Addon:GetModule("Controller"):HandleSlashCommand("save Smoke Save")
assert(clearedDrafts == 1 and toggledUI == 1, "external save did not reconcile the UI draft")
assert(Blueprints:GetPendingDraft() == nil, "external save left the core draft pending")

print("Decor Shopping List core smoke tests passed")
