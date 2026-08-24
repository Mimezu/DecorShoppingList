local _, Addon = ...

local Theme = {}
Addon:RegisterModule("Theme", Theme)

local Safe = Addon.Safe

-- Keep every static Blizzard template/atlas decision in this file. Housing art
-- has changed names during development, so each atlas is optional and the UI
-- always has a Blizzard-texture fallback.
local ATLAS = {
    window = { "housing-basic-container" },
    header = { "housing-basic-container-woodheader" },
    inset = { "housing-basic-panel-innerblackbox" },
    row = { "housing-dashboard-initiatives-tasks-listitem-bg", "housing-bulletinboard-list-item-bg-dark" },
    divider = { "housing-bulletinboard-list-item-divider" },
}

local COLORS = {
    parchment = { 0.93, 0.82, 0.58 },
    title = { 1.00, 0.90, 0.63 },
    text = { 0.96, 0.91, 0.80 },
    muted = { 0.66, 0.62, 0.53 },
    dark = { 0.035, 0.027, 0.018, 0.97 },
    inset = { 0.012, 0.010, 0.008, 0.94 },
    wood = { 0.30, 0.17, 0.075, 1 },
    border = { 0.49, 0.31, 0.13, 1 },
    hover = { 0.82, 0.58, 0.22, 0.13 },
    selected = { 0.45, 0.27, 0.08, 0.46 },
    warning = { 1.00, 0.67, 0.16 },
    success = { 0.45, 0.82, 0.38 },
}

Theme.colors = COLORS

local function hasAtlas(name)
    if type(name) ~= "string" or not Safe.IsTable(C_Texture) then
        return false
    end
    local getAtlasInfo = C_Texture.GetAtlasInfo
    if not Safe.IsReadable(getAtlasInfo) or type(getAtlasInfo) ~= "function" then
        return false
    end
    local ok, info = pcall(getAtlasInfo, name)
    return ok and Safe.IsReadable(info) and info ~= nil
end

function Theme:SetAtlasIfAvailable(texture, name, useAtlasSize)
    if not texture or not texture.SetAtlas or not hasAtlas(name) then
        return false
    end
    texture:SetAtlas(name, useAtlasSize == true)
    return true
end

function Theme:SetFirstAtlas(texture, atlasKey, useAtlasSize)
    if not texture or not texture.SetAtlas then
        return false
    end
    local candidates = ATLAS[atlasKey]
    if not candidates then
        return false
    end
    for _, name in ipairs(candidates) do
        if self:SetAtlasIfAvailable(texture, name, useAtlasSize) then
            return true
        end
    end
    return false
end

local function createFrame(frameType, parent, template)
    if template then
        local ok, frame = pcall(CreateFrame, frameType, nil, parent, template)
        if ok and frame then
            return frame
        end
    end
    return CreateFrame(frameType, nil, parent)
end

function Theme:CreateFrame(frameType, parent, template)
    return createFrame(frameType, parent, template)
end

function Theme:ApplyBackdrop(frame, background, border)
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = background or "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            edgeFile = border or "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true,
            tileSize = 32,
            edgeSize = 24,
            insets = { left = 7, right = 7, top = 7, bottom = 7 },
        })
        frame:SetBackdropColor(unpack(COLORS.dark))
        frame:SetBackdropBorderColor(unpack(COLORS.border))
    end
end

function Theme:FitWindowToScreen(frame, width, height)
    if not frame or not UIParent then return end
    local parentWidth = Safe.AsNumber(UIParent:GetWidth(), width + 40)
    local parentHeight = Safe.AsNumber(UIParent:GetHeight(), height + 40)
    local availableWidth = math.max(1, parentWidth - 40)
    local availableHeight = math.max(1, parentHeight - 40)
    local scale = math.min(1, availableWidth / width, availableHeight / height)
    frame:SetScale(math.max(0.50, scale))
end

function Theme:CreateWindow(title, width, height, strata)
    local frame = createFrame("Frame", UIParent, "BackdropTemplate")
    frame:SetSize(width, height)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata(strata or "DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(window)
        local inCombat = false
        if Safe.IsReadable(InCombatLockdown) and type(InCombatLockdown) == "function" then
            local ok, result = pcall(InCombatLockdown)
            inCombat = ok and Safe.AsBoolean(result, false) == true
        end
        if not inCombat then
            window:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(window)
        window:StopMovingOrSizing()
    end)
    self:FitWindowToScreen(frame, width, height)
    frame:HookScript("OnShow", function(window)
        Theme:FitWindowToScreen(window, width, height)
    end)
    local scaleWatcher = CreateFrame("Frame", nil, frame)
    scaleWatcher:RegisterEvent("UI_SCALE_CHANGED")
    scaleWatcher:RegisterEvent("DISPLAY_SIZE_CHANGED")
    scaleWatcher:SetScript("OnEvent", function()
        Theme:FitWindowToScreen(frame, width, height)
    end)
    frame.ScaleWatcher = scaleWatcher
    self:ApplyBackdrop(frame)

    local background = frame:CreateTexture(nil, "BACKGROUND", nil, 0)
    background:SetPoint("TOPLEFT", 9, -9)
    background:SetPoint("BOTTOMRIGHT", -9, 9)
    if self:SetFirstAtlas(background, "window", false) then
        if frame.SetBackdropColor then
            frame:SetBackdropColor(0, 0, 0, 0)
            frame:SetBackdropBorderColor(0, 0, 0, 0)
        end
    else
        background:SetTexture("Interface\\FrameGeneral\\UI-Background-Rock")
        background:SetHorizTile(true)
        background:SetVertTile(true)
        background:SetVertexColor(0.18, 0.11, 0.055, 0.82)
    end

    local header = frame:CreateTexture(nil, "BORDER")
    header:SetPoint("TOPLEFT", 14, -13)
    header:SetPoint("TOPRIGHT", -14, -13)
    header:SetHeight(43)
    if not self:SetFirstAtlas(header, "header", false) then
        header:SetTexture("Interface\\FrameGeneral\\UI-Background-Rock")
        header:SetHorizTile(true)
        header:SetVertexColor(unpack(COLORS.wood))
    end
    frame.HeaderTexture = header

    local titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("TOP", 0, -24)
    titleText:SetText(title)
    titleText:SetTextColor(unpack(COLORS.title))
    frame.TitleText = titleText

    local close = createFrame("Button", frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -7, -7)
    close:SetScript("OnClick", function()
        frame:Hide()
    end)
    frame.CloseButton = close
    return frame
end

function Theme:SetWindowHeaderHeight(frame, height)
    if not frame or not frame.HeaderTexture or not frame.TitleText then return false end
    height = Safe.AsPositiveInteger(height, nil, 100)
    if not height then return false end
    frame.HeaderTexture:SetHeight(height)
    frame.TitleText:ClearAllPoints()
    frame.TitleText:SetPoint("TOP", 0, -13 - math.floor((height - 18) / 2))
    return true
end

function Theme:AddWindowIcon(frame, texturePath, iconSize)
    if not frame or type(texturePath) ~= "string" or texturePath == "" then
        return nil
    end
    iconSize = Safe.AsPositiveInteger(iconSize, 30, 64)
    local holderSize = iconSize + 8
    local holder = createFrame("Frame", frame)
    holder:SetSize(holderSize, holderSize)
    holder:SetPoint("TOPLEFT", frame, "TOPLEFT", iconSize >= 38 and 17 or 22, -17)
    holder:SetFrameLevel(Safe.AsNonNegativeInteger(frame:GetFrameLevel(), 0, 10000) + 3)
    holder:EnableMouse(false)

    local icon = holder:CreateTexture(nil, "ARTWORK")
    icon:SetSize(iconSize, iconSize)
    icon:SetPoint("CENTER")
    icon:SetTexture(texturePath)
    icon:SetTexCoord(0.04, 0.96, 0.04, 0.96)

    local border = holder:CreateTexture(nil, "OVERLAY")
    border:SetSize(iconSize + 16, iconSize + 16)
    border:SetPoint("CENTER")
    border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    border:SetVertexColor(1.0, 0.78, 0.30, 1.0)

    holder.Icon = icon
    holder.Border = border
    frame.HeaderIcon = holder
    return holder
end

function Theme:CreateInset(parent)
    local inset = createFrame("Frame", parent, "BackdropTemplate")
    if inset.SetBackdrop then
        inset:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 24,
            edgeSize = 13,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        inset:SetBackdropColor(unpack(COLORS.inset))
        inset:SetBackdropBorderColor(0.34, 0.23, 0.12, 1)
    end
    local art = inset:CreateTexture(nil, "BACKGROUND", nil, 1)
    art:SetAllPoints()
    if self:SetFirstAtlas(art, "inset", false) then
        if inset.SetBackdropColor then
            inset:SetBackdropColor(0, 0, 0, 0)
            inset:SetBackdropBorderColor(0, 0, 0, 0)
        end
    else
        art:Hide()
    end
    inset.HousingArt = art
    return inset
end

function Theme:CreateButton(parent, text, width, height)
    local button = createFrame("Button", parent, "UIPanelButtonTemplate")
    button:SetSize(width or 90, height or 24)
    button:SetText(text or "")
    return button
end

function Theme:CreateIconButton(parent, label, width)
    local button = self:CreateButton(parent, label, width or 25, 22)
    button:SetNormalFontObject("GameFontNormalSmall")
    button:SetHighlightFontObject("GameFontHighlightSmall")
    return button
end

function Theme:CreateSearchBox(parent, width)
    local edit = createFrame("EditBox", parent, "SearchBoxTemplate")
    edit:SetSize(width or 210, 24)
    edit:SetAutoFocus(false)
    return edit
end

function Theme:CreateScrollBar(parent)
    -- MinimalScrollBar is a ScrollBox controller, not a standalone Slider.
    -- These lists are manually pooled, so use a deterministic native Slider
    -- with Blizzard textures instead of leaving an unbound scroll controller.
    local slider = createFrame("Slider", parent, "BackdropTemplate")
    slider:SetWidth(12)
    slider:SetOrientation("VERTICAL")
    slider:SetMinMaxValues(0, 0)
    slider:SetValueStep(1)
    -- Keep dragging continuous. Quantizing the thumb itself to one row makes
    -- long lists feel stuck because several pixels can map to the same step.
    slider:SetObeyStepOnDrag(false)
    if slider.SetHitRectInsets then
        slider:SetHitRectInsets(-4, -4, 0, 0)
    end
    if slider.SetBackdrop then
        slider:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 8 })
        slider:SetBackdropColor(0.025, 0.020, 0.014, 0.95)
        slider:SetBackdropBorderColor(0.27, 0.19, 0.10, 1)
    end
    local thumb = slider:CreateTexture(nil, "ARTWORK")
    thumb:SetTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
    thumb:SetSize(18, 26)
    slider:SetThumbTexture(thumb)
    slider.decorShoppingListThumb = thumb
    return slider
end

function Theme:CreateHighlight(parent, _atlasKey, fallbackColor)
    local texture = parent:CreateTexture(nil, "HIGHLIGHT")
    texture:SetAllPoints()
    -- The dropdown mouseover atlas is opaque white when stretched across a
    -- Housing list row. A low-alpha warm wash keeps text legible and matches
    -- the surrounding wood and parchment without creating a bright slab.
    texture:SetColorTexture(unpack(fallbackColor or COLORS.hover))
    return texture
end

function Theme:CreateRowBackground(parent)
    local texture = parent:CreateTexture(nil, "BACKGROUND")
    texture:SetAllPoints()
    if not self:SetFirstAtlas(texture, "row", false) then
        texture:SetColorTexture(0.10, 0.065, 0.028, 0.33)
    end
    return texture
end

function Theme:CreateDivider(parent)
    local texture = parent:CreateTexture(nil, "ARTWORK")
    texture:SetHeight(2)
    if not self:SetFirstAtlas(texture, "divider", false) then
        texture:SetColorTexture(0.46, 0.29, 0.12, 0.85)
        texture:SetHeight(1)
    end
    return texture
end

function Theme:CreateSelectedTexture(parent)
    local texture = parent:CreateTexture(nil, "BACKGROUND", nil, 1)
    texture:SetAllPoints()
    texture:SetColorTexture(unpack(COLORS.selected))
    texture:Hide()
    return texture
end

function Theme:CreateTrackedButtonCheck(parent)
    if not parent then return nil end
    local texture = parent:CreateTexture(nil, "OVERLAY", nil, 7)
    texture:SetSize(16, 16)
    texture:SetPoint("RIGHT", parent, "LEFT", -3, 0)
    if not self:SetAtlasIfAvailable(texture, "housing-dashboard-small-checkmark", false) then
        texture:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    end
    texture:SetVertexColor(1.0, 0.82, 0.22, 1.0)
    texture:Hide()
    return texture
end

function Theme:SetTooltip(owner, title, body)
    if not owner then
        return
    end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if title and title ~= "" then
        GameTooltip:SetText(title, unpack(COLORS.title))
    end
    if body and body ~= "" then
        GameTooltip:AddLine(body, COLORS.text[1], COLORS.text[2], COLORS.text[3], true)
    end
    GameTooltip:Show()
end

function Theme:HideTooltip()
    GameTooltip:Hide()
end
