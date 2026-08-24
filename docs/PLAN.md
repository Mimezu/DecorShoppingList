# Product and implementation plan

## Product promise

Decor Shopping List turns a Housing project into a readable acquisition plan. It distinguishes owned decor, blueprint requirements, and sources that can be routed to a location.

The addon remains standalone. Its window follows Blizzard Housing visuals while owning its frames and data.

## Implemented architecture

```text
Housing blueprint contents event ──> normalized missing-decor draft ──> explicit new list
Blizzard Catalog right-click ──────> supported tagged menu ───────────> active list
saved multi-list store ────────────> search/filter/quantity UI
active list + merchant page ──────> visual needed-item markers
list item ─────────────────────────> source registry
source registry ───────────────────> TomTom / native waypoint / decor content tracking
```

The source registry separates blueprint parsing from acquisition data. A blueprint identifies the decor and quantities; a provider supplies zero or more honest acquisition sources. This prevents display text from being mistaken for structured coordinates.

## Release stages

### 0.1 — working foundation

- Multiple persistent lists and active-list semantics.
- Matching visible Blizzard blueprint-result capture plus manual share-code request.
- Supported Catalog context-menu addition.
- Blizzard Housing visual shell and readable task-style rows.
- Versioned source providers and safe navigation fallbacks.
- Permissioned Home Bound vendor coordinates and merchant-page markers.
- Static, parser, and core behavioral tests.

Exit condition: complete the in-game matrix in `QA.md` without Lua, taint, protected-action, count, or persistence defects.

### 0.2 — expanded acquisition coverage

- Maintain and review the permissioned vendor coordinate snapshot as game data changes.
- Show coverage in the window: mapped location, Blizzard-trackable, non-coordinate action, or unknown.
- Add providers/actions for crafting recipes, quest and reputation requirements, achievements, instance entrances, and Auction House searches.
- Add a compact details drawer for cost, prerequisites, and alternative sources.

Exit condition: every bundled source record has a documented origin and redistribution right; no source type is represented by a misleading waypoint.

### 0.3 — decor runs

- Group missing items by source, vendor, and zone.
- Add several selected locations as an owned TomTom route.
- Offer **Next Stop** and **Add Zone Route** while preserving player/other-addon pins.
- Recompute the remaining route after blueprint storage counts change.

Exit condition: route creation is deterministic, bounded, reversible, and never clears waypoints not owned by Decor Shopping List.

### Later — planning quality

- Per-character versus account shopping preferences.
- Share/export lists without embedding private character data.
- Optional list notes and source selection when several acquisitions exist.
- Coverage/update tooling for new game builds and provider schema migrations.

## Design rules

- Blueprint imports always create drafts; saving is explicit and never overwrites a list.
- Catalog additions go only to the visibly active list and are idempotent.
- Manual/catalog quantities mean “units I plan to acquire.” Blueprint quantities track Blizzard ownership.
- Invalid blueprint requirements remain fully missing until the blueprint itself becomes valid.
- A coordinate is shown only when a provider supplies structured `mapID/x/y` data.
- Crafted, instanced, promotional, or random-drop decor may need an action instead of a pin.
- No permanent `OnUpdate`; event work is debounced and bounded.
- Blizzard Housing frames are observed only where needed for request provenance and are never hooked or mutated.

## Main risks and mitigations

| Risk | Mitigation |
|---|---|
| Housing APIs and internal atlases change | Feature detection, protected calls, fallbacks, and a patch QA matrix |
| Global blueprint events have no caller identity | Correlate addon requests by share code; accept unsolicited results only while Blizzard's native request UI is visible |
| Source data drifts or has unclear rights | Versioned provider schema, explicit attribution/permission, deterministic generation, and snapshot regression tests |
| One decor has several or non-coordinate sources | Store multiple typed sources and select an appropriate action rather than inventing one pin |
| TomTom/native waypoint ownership conflicts | Track addon UIDs, lease native state, and restore only if the current point is still ours |
| Secret/unreadable API values taint logic | Normalize before comparison, arithmetic, indexing, formatting, or persistence |
