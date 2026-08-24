local _, Addon = ...

local eventFrame = CreateFrame("Frame")
Addon.eventFrame = eventFrame

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local controller = Addon:GetModule("Controller")
    if Addon.Safe.IsTable(controller) and Addon.Safe.IsReadable(controller.OnEvent)
        and type(controller.OnEvent) == "function" then
        pcall(controller.OnEvent, controller, event, ...)
    end
end)

SLASH_DECORSHOPPINGLIST1 = "/decorlist"
SLASH_DECORSHOPPINGLIST2 = "/dsl"
SlashCmdList.DECORSHOPPINGLIST = function(message)
    local controller = Addon:GetModule("Controller")
    if Addon.Safe.IsTable(controller) and Addon.Safe.IsReadable(controller.HandleSlashCommand)
        and type(controller.HandleSlashCommand) == "function" then
        pcall(controller.HandleSlashCommand, controller, message)
    end
end

function DecorShoppingList_OnAddonCompartmentClick()
    local controller = Addon:GetModule("Controller")
    local ui = Addon:GetModule("UI")
    if Addon.Safe.IsTable(controller) and Addon.Safe.IsReadable(controller.Initialize)
        and type(controller.Initialize) == "function" then
        pcall(controller.Initialize, controller)
    end
    if Addon.Safe.IsTable(ui) and Addon.Safe.IsReadable(ui.Toggle)
        and type(ui.Toggle) == "function" then
        pcall(ui.Toggle, ui)
    end
end
