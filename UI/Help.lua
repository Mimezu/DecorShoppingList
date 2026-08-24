local _, Addon = ...

local Help = {}
Addon:RegisterModule("Help", Help)

local TOPICS = {
    {
        title = "Getting Started",
        summary = "The active list receives new Housing Catalog decor.",
        body = [[Choose New to create a list. Selecting a list makes it active.

Search matches decor names and displayed sources. The source button cycles through Vendors, Crafting, Loot, Quest / Rep, and Unknown.

Each row shows desired, owned, and missing quantities. Use − and + to change the desired amount.]],
    },
    {
        title = "Blueprint Imports",
        summary = "An import remains a draft until you save it.",
        body = [[When Blizzard shows the contents of an imported Housing blueprint, the addon prepares a missing-decor draft. The banner shows its entry count and total missing pieces.

Choose Create List to save a separate list and make it active. Later hides the banner without changing any list. Blueprint imports never overwrite an existing list.

Only missing decor is added. Blueprint rows retain required and missing quantities and refresh when Housing storage changes.]],
    },
    {
        title = "Housing Catalog",
        summary = "Right-click a decor entry to add it to the active list.",
        body = [[Open Blizzard’s Housing Decor Catalog, right-click a decor entry, and choose “Add to Active List.”

If no list is active, create or select one first. Adding existing decor does not create a duplicate or lower its desired quantity.

Manual and Catalog quantities are acquisition goals. Confirmed Housing ownership changes update their owned and missing counts automatically.]],
    },
    {
        title = "Finding Decor",
        summary = "Track uses mapped coordinates first, then Blizzard decor tracking.",
        body = [[When a source provider includes a location, Track adds a TomTom waypoint or uses Blizzard’s single built-in waypoint. An active button stays highlighted, shows a gold Housing checkmark, and reads Untrack. Choose it again to stop tracking only that decor. The chat message names the destination map. If Blizzard saves the map pin but cannot start navigation, the addon says so instead of reporting a full waypoint.

Without a mapped location, Track asks Blizzard to track the decor when supported. That is decor tracking, not a map waypoint. Already-tracked decor remains tracked.

When a tracked mapped vendor has a visible friendly nameplate, the Decor Shopping List icon appears above it. Show NPC Plates and Hide NPC Plates temporarily toggle Blizzard’s Friendly NPC Nameplates setting. Toggle it back to restore the prior setting; logout and reload also restore it. A newer change made elsewhere is preserved.

Track All applies to the current search and source-filter results. It adds multiple TomTom pins when available; without TomTom, Blizzard Housing tracking is used where supported. Once anything in that view is active, the button becomes Untrack All.

Crafted decor, instances, achievements, promotions, and broad drops may not have one useful coordinate. Those rows keep Blizzard’s source description, and Track explains when no destination is available.

Clear Waypoints tries to remove only this addon’s TomTom pins and Blizzard waypoint. When it still owns the current waypoint, it clears it or restores the earlier one. If part cannot be cleared safely, the addon reports it and keeps the unfinished cleanup available for another try.

Blizzard decor tracking is unchanged. Manage tracked decor through Blizzard’s interface.]],
    },
    {
        title = "At a Merchant",
        summary = "Needed items are marked on the current merchant page.",
        body = [[A bright gold frame and soft glow mark merchant items still needed by the active list. The badge shows how many remain.

Markers update when quantities or the active list change, and when the merchant page changes. Completed and unrelated items remain unmarked.

The markers are visual only. Buying, prices, paging, and item tooltips remain controlled by Blizzard.]],
    },
    {
        title = "List Management",
        summary = "Selecting a list also makes it the Catalog destination.",
        body = [[The left rail holds your saved lists. Rename changes the active list’s name. Delete removes that list and its entries after confirmation.

When confirmed Housing ownership makes an entry complete, its tracking and vendor marker stop automatically. The completed row remains visible. Clear obtained removes completed rows after retrying any tracking cleanup that still remains. Lists persist between sessions.

If saved data comes from a newer addon version, editing is disabled and the data remains untouched. Update the addon to resume editing.]],
    },
    {
        title = "Developer Preview",
        summary = "Optional layout states use temporary display data.",
        body = [[Use /dsl testui with default, dense, empty, or readonly to inspect the window. This preview is for development and visual review; it is not part of the normal shopping workflow.

Preview actions are disabled. SavedVariables and waypoints are not changed.

Use /dsl testui off to return to your lists and restore the previous window state.]],
    },
}

local function addEscapeFrame(frame, globalName)
    _G[globalName] = frame
    UISpecialFrames = UISpecialFrames or {}
    for _, name in ipairs(UISpecialFrames) do
        if name == globalName then return end
    end
    table.insert(UISpecialFrames, globalName)
end

function Help:SelectTopic(index)
    local topic = TOPICS[index]
    if not topic or not self.frame then return end
    self.selectedTopic = index
    self.contentTitle:SetText(topic.title)
    self.summary:SetText(topic.summary)
    self.body:SetText(topic.body)
    for rowIndex, row in ipairs(self.topicRows) do
        row.selected:SetShown(rowIndex == index)
        row.text:SetTextColor(rowIndex == index and 1 or 0.88, rowIndex == index and 0.87 or 0.78, rowIndex == index and 0.58 or 0.62)
    end
end

function Help:Initialize()
    if self.initialized then return end
    local Theme = Addon:GetModule("Theme")
    if not Theme then return end
    self.initialized = true

    local frame = Theme:CreateWindow("Decor Shopping List Help", 760, 555, "FULLSCREEN_DIALOG")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:Hide()
    self.frame = frame
    addEscapeFrame(frame, "DecorShoppingListHelpFrame")

    local rail = Theme:CreateInset(frame)
    rail:SetPoint("TOPLEFT", 19, -68)
    rail:SetPoint("BOTTOMLEFT", 19, 52)
    rail:SetWidth(188)

    local railTitle = rail:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    railTitle:SetPoint("TOPLEFT", 14, -14)
    railTitle:SetText("HELP TOPICS")
    railTitle:SetTextColor(unpack(Theme.colors.parchment))

    self.topicRows = {}
    for index, topic in ipairs(TOPICS) do
        local row = CreateFrame("Button", nil, rail)
        row:SetHeight(38)
        row:SetPoint("TOPLEFT", 8, -42 - ((index - 1) * 40))
        row:SetPoint("TOPRIGHT", -8, -42 - ((index - 1) * 40))
        Theme:CreateHighlight(row)
        row.selected = Theme:CreateSelectedTexture(row)
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.text:SetPoint("LEFT", 10, 0)
        row.text:SetPoint("RIGHT", -8, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetText(topic.title)
        row:SetScript("OnClick", function() self:SelectTopic(index) end)
        self.topicRows[index] = row
    end

    local content = Theme:CreateInset(frame)
    content:SetPoint("TOPLEFT", rail, "TOPRIGHT", 10, 0)
    content:SetPoint("BOTTOMRIGHT", -19, 52)

    self.contentTitle = content:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    self.contentTitle:SetPoint("TOPLEFT", 22, -22)
    self.contentTitle:SetPoint("TOPRIGHT", -22, -22)
    self.contentTitle:SetJustifyH("LEFT")
    self.contentTitle:SetTextColor(unpack(Theme.colors.title))

    self.summary = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.summary:SetPoint("TOPLEFT", self.contentTitle, "BOTTOMLEFT", 0, -12)
    self.summary:SetPoint("TOPRIGHT", self.contentTitle, "BOTTOMRIGHT", 0, -12)
    self.summary:SetJustifyH("LEFT")
    self.summary:SetWordWrap(true)
    self.summary:SetTextColor(unpack(Theme.colors.parchment))

    local divider = Theme:CreateDivider(content)
    divider:SetPoint("TOPLEFT", self.summary, "BOTTOMLEFT", 0, -14)
    divider:SetPoint("TOPRIGHT", self.summary, "BOTTOMRIGHT", 0, -14)

    self.body = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.body:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -18)
    self.body:SetPoint("TOPRIGHT", divider, "BOTTOMRIGHT", 0, -18)
    self.body:SetPoint("BOTTOM", content, "BOTTOM", 0, 22)
    self.body:SetJustifyH("LEFT")
    self.body:SetJustifyV("TOP")
    self.body:SetSpacing(5)
    self.body:SetWordWrap(true)

    local close = Theme:CreateButton(frame, CLOSE or "Close", 105, 25)
    close:SetPoint("BOTTOMRIGHT", -21, 18)
    close:SetScript("OnClick", function() self:Hide() end)

    self:SelectTopic(1)
end

function Help:Show(topicIndex)
    if not self.initialized then self:Initialize() end
    if not self.frame then return end
    if topicIndex then self:SelectTopic(topicIndex) end
    self.frame:Show()
    self.frame:Raise()
end

function Help:Hide()
    if self.frame then self.frame:Hide() end
end

function Help:Toggle()
    if not self.initialized then self:Initialize() end
    if not self.frame then return end
    if Addon.Safe.AsBoolean(self.frame:IsShown(), false) then self:Hide() else self:Show() end
end
