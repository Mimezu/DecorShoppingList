-- Long-list view-cache smoke tests. Run from the Retail workspace root.

local addonRoot = ""
local addon = {}

local function LoadAddonFile(relativePath)
    local chunk, errorMessage = loadfile(addonRoot .. relativePath)
    assert(chunk, errorMessage)
    chunk("DecorShoppingList", addon)
end

LoadAddonFile("Bootstrap.lua")
LoadAddonFile("Core/SafeValue.lua")

local registryCalls = 0
addon:RegisterModule("SourceRegistry", {
    GetDisplaySource = function(_, item)
        registryCalls = registryCalls + 1
        return "Vendor " .. tostring(item.recordID), {
            type = "vendor",
            label = "Vendor " .. tostring(item.recordID),
            mapID = 1,
            x = 0.5,
            y = 0.5,
        }
    end,
})

LoadAddonFile("UI/MainWindow.lua")
local UI = assert(addon:GetModule("UI"))

local list = { items = {}, order = {} }
for index = 1, 1497 do
    local key = "decor:" .. index
    list.order[index] = key
    list.items[key] = {
        key = key,
        recordID = index,
        name = "Decor " .. index,
        desired = 1,
        owned = 0,
        missing = 1,
    }
end

UI.searchText = ""
UI.filterIndex = 1
local first = UI:GetFilteredItems(list)
assert(#first == 1497, "default view lost long-list rows")
assert(registryCalls == 0, "default view resolved off-screen sources")

local second = UI:GetFilteredItems(list)
assert(second == first and registryCalls == 0, "unchanged view did not reuse its cache")

UI.searchText = "vendor 1497"
UI.filteredItemsCache = nil
local searched = UI:GetFilteredItems(list)
assert(#searched == 1 and searched[1].recordID == 1497, "source search returned the wrong row")
assert(registryCalls == 1497, "source search did not perform one bounded source pass")

local callsAfterSearch = registryCalls
UI:GetFilteredItems(list)
assert(registryCalls == callsAfterSearch, "unchanged source search repeated the full-list scan")

UI.listSummaries = {}
local originalGetListItems = UI.GetListItems
local summaryBuilds = 0
UI.GetListItems = function(self, target)
    summaryBuilds = summaryBuilds + 1
    return originalGetListItems(self, target)
end
local summary = UI:GetListSummary(list)
assert(summary.itemCount == 1497 and summary.missing == 1497 and not summary.hasObtained,
    "long-list summary was incorrect")
assert(UI:GetListSummary(list) == summary and summaryBuilds == 1,
    "unchanged scroll/list repaint rebuilt the long-list summary")

print("Decor Shopping List long-list view smoke tests passed")
