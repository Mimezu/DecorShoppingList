# Source-provider contract

Source providers are registered through:

```lua
local registry = DecorShoppingList:GetModule("SourceRegistry")
registry:RegisterProvider(provider)
```

A schema-version 1 provider has this shape:

```lua
local provider = {
    id = "publisher-package-name",
    version = "1.0.0",
    schemaVersion = 1,
    provenance = {
        name = "Dataset name",
        url = "https://example.invalid/source",
        license = "License identifier",
        notes = "How the records were verified",
    },
    records = {
        {
            decorID = 123,
            itemID = 456,
            sources = {
                {
                    type = "vendor",
                    label = "Vendor name",
                    npcID = 789,
                    mapID = 1,
                    x = 0.50,
                    y = 0.50,
                    zoneName = "Zone name",
                    faction = "Alliance", -- optional: Alliance or Horde
                    requirements = "Optional requirement text",
                },
            },
        },
    },
}
```

Coordinates are normalized map fractions from `0` through `1`, not percentages. A record may use `decorID`/`recordID`, `itemID`, or both. Multiple source records are supported.

Faction-specific vendor sources may set `faction` to `Alliance` or `Horde`. They are hidden from the opposite faction when the player's faction can be read; neutral sources omit the field.

Registration snapshots supported fields instead of retaining the provider's tables. Each provider is bounded to 20,000 examined records and each record to 32 examined sources.

`sourceText` from Blizzard's catalog is display-only. Providers must not parse it into coordinates or identifiers. Source records must be independently verified or imported with explicit redistribution permission.

## Bundled Home Bound snapshot

`Sources/HomeBoundVendors.lua` is a generated, standalone snapshot of Home Bound 1.55 vendor data by Bettiold, imported with permission. It contains 1,497 decor records and 2,205 vendor coordinate sources. Decor Shopping List does not load Home Bound, inspect its SavedVariables, or require it at runtime. The generator classifies the faction-exclusive neighborhood maps (2351 Horde, 2352 Alliance) when upstream vendor rows have no explicit faction icon.

To regenerate after receiving permission for an updated source version, run `tools/Generate-DecorShoppingListHomeBound.lua` with Home Bound's `db.lua`, the generated provider output path, and the source version. The generator joins `vendorItems`, `decorItem`, and `vendors`, normalizes percentage coordinates to map fractions, retains faction restrictions, sorts output deterministically, and rejects records exceeding the provider source limit.
