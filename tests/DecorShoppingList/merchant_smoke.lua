-- Run from the Retail workspace root with a Lua 5.1-compatible runtime.

local addonRoot = ""
local addonName = "DecorShoppingList"
local Addon = {}

local function LoadAddonFile(relativePath)
    local chunk, errorMessage = loadfile(addonRoot .. relativePath)
    assert(chunk, errorMessage)
    chunk(addonName, Addon)
end

local function NewWidget(shown)
    local widget = { shown = shown ~= false }
    function widget:SetAllPoints() end
    function widget:EnableMouse() end
    function widget:GetFrameLevel() return 4 end
    function widget:SetFrameLevel() end
    function widget:SetPoint() end
    function widget:SetSize() end
    function widget:SetHeight() end
    function widget:SetWidth() end
    function widget:SetColorTexture() end
    function widget:SetTexture() end
    function widget:SetVertexColor() end
    function widget:SetTextColor() end
    function widget:IsShown() return self.shown end
    function widget:Show() self.shown = true end
    function widget:Hide() self.shown = false end
    function widget:CreateTexture() return NewWidget() end
    function widget:CreateFontString() return NewWidget() end
    function widget:SetFormattedText(formatString, value)
        self.text = string.format(formatString, value)
    end
    return widget
end

function CreateFrame()
    return NewWidget()
end

local hookedUpdate
function hooksecurefunc(name, callback)
    assert(name == "MerchantFrame_Update", "unexpected merchant hook target")
    hookedUpdate = callback
end
function MerchantFrame_Update() end

MERCHANT_ITEMS_PER_PAGE = 3
MerchantFrame = NewWidget()
MerchantFrame.page = 1
MerchantFrame.selectedTab = 1
local merchantButton1 = NewWidget()
local merchantButton2 = NewWidget()
local merchantButton3 = NewWidget()
_G.MerchantItem1ItemButton = merchantButton1
_G.MerchantItem2ItemButton = merchantButton2
_G.MerchantItem3ItemButton = merchantButton3

local merchantItems = { [1] = 5001, [2] = 5002, [3] = 5003 }
function GetMerchantItemID(index)
    return merchantItems[index]
end

LoadAddonFile("Bootstrap.lua")
LoadAddonFile("Core/SafeValue.lua")

local activeList = {
    order = { "decor:100", "decor:101", "decor:102", "decor:103" },
    items = {
        ["decor:100"] = { itemID = 5001, missing = 2 },
        ["decor:101"] = { itemID = 5002, missing = 0 },
        ["decor:102"] = { itemID = 5999, missing = 1 },
        ["decor:103"] = { recordID = 103, missing = 4 },
    },
}
Addon:RegisterModule("Store", {
    GetActiveList = function()
        return activeList
    end,
})
Addon:RegisterModule("SourceRegistry", {
    GetItemIDsForDecorID = function(_, recordID)
        _G.decorShoppingListMerchantMappingCalls = (_G.decorShoppingListMerchantMappingCalls or 0) + 1
        return recordID == 103 and { 5003 } or {}
    end,
})
Addon.eventFrame = {
    registered = {},
    RegisterEvent = function(self, event)
        self.registered[event] = true
    end,
}

LoadAddonFile("Integrations/Merchant.lua")
local Merchant = assert(Addon:GetModule("MerchantIntegration"))
assert(Merchant:Initialize(), "merchant integration did not initialize")
assert(Addon.eventFrame.registered.MERCHANT_SHOW and Addon.eventFrame.registered.MERCHANT_UPDATE
    and Addon.eventFrame.registered.MERCHANT_CLOSED, "merchant events were not registered")
assert(type(hookedUpdate) == "function", "merchant page refresh hook was not installed")

assert(Merchant:Refresh() == 2, "wrong number of merchant items highlighted")
local overlay = assert(Merchant.overlays[merchantButton1], "matching merchant item has no overlay")
assert(overlay.shown, "matching merchant overlay is hidden")
assert(overlay.glow and overlay.fill, "matching merchant item lacks the stronger gold glow/fill")
assert(overlay.badge.count.text == "2", "merchant badge does not show the missing quantity")
assert(not Merchant.overlays[merchantButton2], "completed item was highlighted")
local crosswalkOverlay = assert(Merchant.overlays[merchantButton3], "record-only decor was not resolved for the merchant")
assert(crosswalkOverlay.badge.count.text == "4", "record-only decor has the wrong merchant quantity")
local firstMappingCalls = _G.decorShoppingListMerchantMappingCalls
assert(Merchant:Refresh() == 2 and _G.decorShoppingListMerchantMappingCalls == firstMappingCalls,
    "unchanged merchant repaint rebuilt the active-list index")

activeList.items["decor:100"].missing = 0
Merchant:InvalidateNeeded()
hookedUpdate()
assert(Merchant.highlightedCount == 1 and not overlay.shown, "merchant update left a stale overlay")

activeList.items["decor:100"].missing = 3
Merchant:Refresh("item-quantity-changed")
assert(Merchant.highlightedCount == 2 and overlay.badge.count.text == "3", "merchant event did not refresh quantity")
Merchant:OnEvent("MERCHANT_CLOSED")
assert(Merchant.highlightedCount == 0 and not overlay.shown and not crosswalkOverlay.shown,
    "merchant close did not hide overlays")

print("Decor Shopping List merchant overlay smoke tests passed")
