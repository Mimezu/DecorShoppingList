describe("Decor Shopping List native smoke fixtures", function()
    it("passes core storage, catalog, and blueprint behavior", function()
        dofile("tests/DecorShoppingList/smoke.lua")
    end)

    it("passes waypoint ownership and restoration behavior", function()
        dofile("tests/DecorShoppingList/waypoint_smoke.lua")
    end)

    it("passes controller command boundaries", function()
        dofile("tests/DecorShoppingList/controller_smoke.lua")
    end)

    it("passes source registry and imported vendor behavior", function()
        dofile("tests/DecorShoppingList/source_registry_smoke.lua")
    end)

    it("passes merchant shopping-list overlays", function()
        dofile("tests/DecorShoppingList/merchant_smoke.lua")
    end)

    it("marks only visible tracked vendor nameplates", function()
        dofile("tests/DecorShoppingList/vendor_nameplate_smoke.lua")
    end)

    it("keeps long-list default rendering and scrolling bounded", function()
        dofile("tests/DecorShoppingList/ui_view_smoke.lua")
    end)
end)
