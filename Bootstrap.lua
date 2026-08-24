local addonName, Addon = ...

Addon.name = addonName
Addon.title = "Decor Shopping List"
Addon.modules = Addon.modules or {}
Addon.callbacks = Addon.callbacks or {}

Addon.version = "0.2.0"
if type(C_AddOns) == "table" and type(C_AddOns.GetAddOnMetadata) == "function" then
    local ok, version = pcall(C_AddOns.GetAddOnMetadata, addonName, "Version")
    if ok and type(version) == "string" and version ~= "" then
        Addon.version = version
    end
end

_G.DecorShoppingList = Addon

function Addon:RegisterModule(name, module)
    assert(type(name) == "string" and name ~= "", "module name is required")
    assert(type(module) == "table", "module table is required")
    self.modules[name] = module
    return module
end

function Addon:GetModule(name)
    return self.modules[name]
end

function Addon:Print(message)
    if type(message) ~= "string" then
        return
    end
    local chatFrame = DEFAULT_CHAT_FRAME
    if type(chatFrame) == "table" and type(chatFrame.AddMessage) == "function" then
        pcall(chatFrame.AddMessage, chatFrame, "|cffd5b45cDecor Shopping List:|r " .. message)
    end
end
