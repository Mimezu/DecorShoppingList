# Changelog

## 0.2.0 - 2026-08-24

- Added persistent multiple shopping lists and active-list selection.
- Added missing-decor blueprint drafts and blueprint-only ownership refresh.
- Added supported Blizzard Housing Catalog right-click insertion.
- Added Blizzard Housing-style standalone list and help windows.
- Added bounded pooled list rows with addon-owned Blizzard-textured scrollbars.
- Added optional TomTom, native waypoint leasing, and idempotent Blizzard decor tracking.
- Added a versioned, provenance-aware source-provider registry.
- Added 1,497 vendor decor mappings with 2,205 coordinates from Home Bound 1.55 by Bettiold, imported with permission.
- Added faction-aware source filtering and a reproducible vendor-data generator.
- Corrected faction inference for paired neighborhood vendors so Alliance routes to Devin Slatesmith instead of Merki, with the inverse behavior for Horde.
- Added non-interactive merchant icon borders and quantity badges for items still needed by the active list.
- Added memory-only developer preview states for layout review.
- Replaced opaque row highlights with restrained Housing-style hover and selection states.
- Corrected enabled-control tooltips so Track no longer reports a false waypoint failure.
- Fixed long-list scrollbar stalls by caching filtered views, resolving only visible default-view sources, and forwarding wheel input from row controls.
- Reduced catalog and merchant stutter by removing duplicate refreshes, caching merchant needs, and ignoring unchanged item additions.
- Fixed native waypoint false positives by checking Blizzard’s set result, pin readback, and navigation state. Decor tracking is now reported separately from map waypoints.
- Added live gold Track-button borders for active TomTom pins, Blizzard waypoints, and Housing decor tracking.
- Strengthened merchant markers with a thicker gold frame, soft fill, and glow while keeping the quantity badge.
- Added the official Decor Shopping List icon to the main Housing-style window header.
- Made row tracking a true Track / Untrack toggle and replaced the square outline with Blizzard’s shaped panel-button highlight.
- Strengthened the active tracking state with the button’s native locked highlight and a gold Housing checkmark.
- Increased the main wood header and official icon by about 30 percent.
- Added batched Track All / Untrack All for the current filtered view.
- Fixed the SearchBox placeholder remaining visible while typing.
- Clear obtained now untracks completed decor before removing rows, and Track All skips decor with nothing left to collect.
- Added an official-icon marker above visible friendly nameplates for mapped vendors currently tracked by the addon.
- Added a temporary NPC Plates toggle that restores the player’s previous Friendly NPC Nameplates setting and preserves newer external changes.
- Clarified the nameplate toggle with action labels: Show NPC Plates and Hide NPC Plates.
- Confirmed Housing acquisitions, including decor added directly to the House Chest, now update every active-list entry and automatically untrack newly completed decor without deleting its row.
- Added native LuaJIT, Luacheck, LuaLS, Busted, and static validation coverage.
- Added an in-game QA checklist.
