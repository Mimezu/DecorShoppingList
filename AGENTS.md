# Decor Shopping List

- Keep this addon standalone. Do not edit, skin, reparent, or depend on another
  user addon or its SavedVariables.
- Match Blizzard Retail Housing visuals with Blizzard-owned atlases, fonts, and
  generic templates. Do not use the Mimezu suite palette for this addon.
- Extend the Housing Catalog only through supported events or tagged menu
  extension points. Never replace Blizzard scripts or data providers.
- Treat API values as potentially secret before comparison, arithmetic,
  formatting, indexing, or persistence.
- Use events and bounded/debounced work. Do not add permanent per-frame
  `OnUpdate` handlers.
- Keep TomTom optional and remove only waypoints created by this addon.
- Preserve multiple named shopping lists; blueprint imports create list drafts,
  while catalog additions target the explicitly active list.
