# Decor Shopping List

Decor Shopping List turns Housing blueprint requirements and Housing Catalog entries into named, persistent acquisition lists.

Its standalone window uses Blizzard Housing art and control conventions without changing Blizzard frames.

## Current MVP

- Keeps up to 200 named lists; one list is explicitly active.
- Captures matching blueprint results while Blizzard's import or content-list UI is visible, then prepares a missing-decor draft.
- Preserves blueprint required, owned, and missing quantities.
- Adds **Add to Active List** to supported Housing Decor Catalog context menus.
- Marks visible merchant items that are still needed by the active list and shows the remaining quantity.
- Provides search, source filters, quantity controls, completed-row cleanup, and list management.
- Uses verified source coordinates with TomTom or Blizzard navigation, then falls back to Blizzard decor content tracking.
- **Clear Waypoints** tries to remove only owned TomTom pins and the current native waypoint lease, and reports partial or failed cleanup.
- Confirmed Housing ownership changes update owned and missing quantities. Newly completed decor is untracked automatically and remains visible until **Clear obtained**.
- Refreshes active-list ownership while preserving each row’s desired quantity.
- Uses bounded pooled rows with addon-owned, Blizzard-textured scrollbars; it does not use Blizzard `WowScrollBox` or `MinimalScrollBar` templates.

## Using the addon

Open the window from the Addon Compartment, or enter `/decorlist` (short form: `/dsl`).

Choose **New** to create a list. In Blizzard's Housing Decor Catalog, right-click a decor card and choose **Add to Active List**. Catalog additions always go to the active list.

At a merchant, needed items on the current page receive a gold icon border and a quantity badge. The marker follows the active list and disappears when the item is no longer needed.

When the addon captures a matching blueprint result, a banner shows the missing-decor draft. **Create List** saves it as a new active list without overwriting another list. To request a blueprint directly, use:

```text
/decorlist blueprint <share code>
```

Other commands:

```text
/decorlist new <name>
/decorlist use <name or id>
/decorlist lists
/decorlist save [name]
```

## Developer preview

`/dsl testui [default|dense|empty|readonly|off]` opens optional layout-review states. Preview data is temporary; preview actions do not change SavedVariables or waypoints. Use `/dsl testui off` to restore the previous window state.

## Coordinate coverage

Blueprint and Catalog APIs identify decor and provide display-oriented source text, but not a universal structured `mapID/x/y` location. The addon therefore uses versioned source providers.

The bundled Home Bound 1.55 snapshot provides 1,497 decor records and 2,205 vendor coordinate sources, imported from Bettiold's addon with permission. It is generated into Decor Shopping List, so Home Bound is not required at runtime and its SavedVariables are never read. **Track** uses a mapped vendor coordinate when available, then falls back to Blizzard decor tracking. Tracked mapped vendors display the addon icon on their visible friendly nameplate. **Show NPC Plates** and **Hide NPC Plates** temporarily toggle only Blizzard’s Friendly NPC Nameplates setting and restore its prior value when toggled back, on logout, or on reload. The addon never places raid markers. See [SOURCES.md](docs/SOURCES.md) for attribution and the provider contract.

Vendor pins can be exact. Crafted items, achievements, promotions, instances, and broad drops often need a different action or no single coordinate.

**Clear Waypoints** can be retried after a partial failure. It never stops Blizzard decor content tracking; tracked decor remains under player control in Blizzard's interface.

## Compatibility and safety

- Retail interface: `120100`
- Optional integration: TomTom
- No permanent `OnUpdate`
- No hooks into Blizzard frame scripts or data providers
- No reads from or writes to other addons' SavedVariables
- External API/event values are normalized before display or persistence

In-game validation steps are in [QA.md](docs/QA.md).
The staged product and engineering roadmap is in [PLAN.md](docs/PLAN.md).
