# In-game QA checklist

Static tests cannot reproduce Retail's protected/secret-value behavior or load-on-demand Housing lifecycle. Complete this matrix in-game before declaring 0.2.0 release-ready.

## Automated verification

From the Retail workspace root, run:

```powershell
& tools/Test-DecorShoppingList.ps1 -RequireLua -RequireBehavior
luacheck Interface/AddOns/DecorShoppingList tests/DecorShoppingList --config tests/DecorShoppingList/.luacheckrc
busted tests/DecorShoppingList/smoke_spec.lua
```

The main gate uses LuaJIT when a native Lua 5.1 compiler is unavailable. These checks use mocked WoW APIs; they are not Wowless or an in-game runtime.

## Load and persistence

- Log in with no Housing UI previously opened; confirm no Lua errors.
- Open from the Addon Compartment and with `/decorlist` and `/dsl`.
- Create, rename, select, and delete several lists; reload and verify names, order, active list, and quantities persist.
- Delete the last list and verify a safe default list is recreated.
- Test at small and large UI scales. Close/reopen after changing scale so the MVP fit-to-screen pass reruns.

## Housing Catalog

- Load the Housing Catalog after login and right-click a normal decor entry.
- Confirm **Add to Active List** names the active list and adds exactly one row.
- Repeat the action; confirm it remains one row and does not lower a larger desired quantity.
- Right-click bundle children and non-decor entries; confirm the addon does not add an invalid menu action.
- Repeat after `/reload`, after the Housing Dashboard loads, and in combat.

## Blueprints

- Import/view a blueprint with missing decor and confirm a draft banner appears.
- Compare several row IDs and required/missing counts with Blizzard's Blueprint List.
- Choose **Later** and verify existing lists are unchanged.
- Create the draft list and verify a separate active list is made.
- Trigger Housing storage updates and confirm active-list ownership refreshes without changing desired quantities.
- Add an already-listed blueprint decor through the catalog and confirm blueprint ownership refresh remains active.
- Test `/decorlist blueprint <share code>` and invalid/expired codes.

## Navigation

- Start with Friendly NPC Nameplates off. Use **NPC Plates** to turn them on, confirm tracked vendor markers appear, then toggle back and verify the prior setting returns.
- Repeat with Friendly NPC Nameplates initially on, `/reload`, and logout. Confirm the temporary override restores the initial value and does not alter friendly-player or enemy nameplates.
- While the temporary override is active, change Friendly NPC Nameplates in Blizzard Settings; confirm the newer external choice is preserved.

- With TomTom enabled, track a mapped Home Bound vendor; verify the vendor title and normalized coordinate.
- On both factions, verify faction-restricted vendors from the other faction are not offered while neutral vendors remain available.
- Add several pins, choose **Clear Waypoints**, and verify only this addon's TomTom pins are removed.
- Simulate an unavailable waypoint provider; confirm cleanup reports partial/failure instead of claiming every waypoint was cleared, then succeeds when retried.
- Disable TomTom and verify native waypoint creation and safe restoration of a prior waypoint.
- With TomTom disabled, test a remote vendor and verify chat names the destination map. Open that map and confirm the pin exists.
- Test a Blizzard-rejected native pin and a pin that cannot be supertracked; confirm neither is reported as a full waypoint.
- Change the native waypoint manually after tracking, then clear; verify the addon does not overwrite the newer waypoint.
- For an unmapped decor, verify Blizzard decor tracking starts when supported and failure is explained without a Lua error.
- Track decor that Blizzard is already tracking; confirm it remains tracked.
- Confirm **Clear Waypoints** does not stop Blizzard decor tracking; stop it through Blizzard's interface.

## Merchants

- Open a vendor that sells items on the active list; verify each still-needed item has a gold icon border and remaining-quantity badge.
- Change pages and confirm markers follow the visible merchant item indexes without appearing on unrelated items.
- Change desired quantity, clear an obtained item, or switch the active list while the merchant is open; verify markers refresh immediately.
- Open Buyback and close the merchant; verify every shopping-list marker is hidden.
- Test alongside merchant-layout addons and confirm buttons, clicks, tooltips, prices, and paging remain owned by Blizzard/the layout addon.

## UI and safety

- Verify the window uses Housing container/header/inset/list art and remains independent of Blizzard frames.
- Exercise search, every source filter, mouse-wheel scrolling, quantities, Clear obtained, tooltips, Help, Escape, and both close buttons.
- Open a list with at least 1,000 rows. Drag the scrollbar thumb, click its track, and wheel over rows and row buttons; movement should remain responsive and advance several rows per wheel notch.
- Confirm the bounded pooled rows and addon-owned Blizzard-textured scrollbars behave correctly; this build does not claim `WowScrollBox` or `MinimalScrollBar` template integration.
- Test with missing Housing atlases/templates; fallback art should remain usable.
- Test while entering/leaving combat and confirm no protected-action or taint errors.
- Confirm no continuous `OnUpdate` activity while the window is hidden or shown.

## Developer preview

- Run `/dsl testui default`, `dense`, `empty`, and `readonly`; verify each state is clearly marked Preview.
- Confirm list edits, blueprint saving, tracking, and Clear Waypoints are disabled in preview.
- Run `/dsl testui off`; verify the prior list, search, source filter, scroll position, draft visibility, and window state return.
- Reload and confirm preview data never entered SavedVariables and no waypoint changed.
