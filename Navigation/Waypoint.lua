local _, Addon = ...

local Safe = Addon.Safe
local Waypoint = {}

local initialized = false
local ownedTomTomUIDs = {}
local nativeLease
local nativeTrackedItemKey
local housingTrackedItemKeys = {}
local trackedVendorNPCByItemKey = {}
local trackedVendorNPCCounts = {}

local function Field(tableValue, key)
    if not Safe.IsTable(tableValue) then
        return nil
    end
    local value = tableValue[key]
    return Safe.IsReadable(value) and value or nil
end

local function GetItemKey(item)
    if not Safe.IsTable(item) then return nil end
    local key = Safe.TrimmedString(Field(item, "key"), nil, 256)
    if key then return key end
    local decorID = Safe.AsPositiveInteger(Field(item, "decorID"), nil, 2147483647)
        or Safe.AsPositiveInteger(Field(item, "recordID"), nil, 2147483647)
    return decorID and ("decor:" .. decorID) or nil
end

local function NotifyVendorMarkers()
    local integration = Addon:GetModule("VendorNameplateIntegration")
    local refresh = integration and Field(integration, "Refresh") or nil
    if Safe.IsReadable(refresh) and type(refresh) == "function" then
        Safe.Call(refresh, integration)
    end
end

local function SetTrackedVendor(itemKey, source)
    if not itemKey then return end
    local previous = trackedVendorNPCByItemKey[itemKey]
    local npcID = Safe.AsPositiveInteger(Field(source, "npcID"), nil, 2147483647)
    if previous == npcID then return end
    if previous then
        local count = (trackedVendorNPCCounts[previous] or 1) - 1
        trackedVendorNPCCounts[previous] = count > 0 and count or nil
    end
    trackedVendorNPCByItemKey[itemKey] = npcID
    if npcID then
        trackedVendorNPCCounts[npcID] = (trackedVendorNPCCounts[npcID] or 0) + 1
    end
    NotifyVendorMarkers()
end

local function ClearTrackedVendor(itemKey)
    if not itemKey then return end
    local npcID = trackedVendorNPCByItemKey[itemKey]
    if not npcID then return end
    local count = (trackedVendorNPCCounts[npcID] or 1) - 1
    trackedVendorNPCCounts[npcID] = count > 0 and count or nil
    trackedVendorNPCByItemKey[itemKey] = nil
    NotifyVendorMarkers()
end

local function ClearAllTrackedVendors()
    if not next(trackedVendorNPCByItemKey) then return end
    trackedVendorNPCByItemKey = {}
    trackedVendorNPCCounts = {}
    NotifyVendorMarkers()
end

local function ReadableFunction(value)
    return Safe.IsReadable(value) and type(value) == "function" and value or nil
end

local function IsReadableNumber(value)
    return Safe.AsNumber(value, nil) ~= nil
end

local function IsPositiveInteger(value)
    value = Safe.AsNumber(value, nil)
    return value ~= nil and value > 0 and value % 1 == 0
end

local function CoordinatesAreValid(mapID, x, y)
    return IsPositiveInteger(mapID)
        and IsReadableNumber(x) and x >= 0 and x <= 1
        and IsReadableNumber(y) and y >= 0 and y <= 1
end

local function ReadMapPoint(point)
    if not Safe.IsTable(point) then
        return nil
    end

    local mapID = Field(point, "uiMapID")
    local position = Field(point, "position")
    if not IsPositiveInteger(mapID) or not Safe.IsTable(position) then
        return nil
    end

    local x, y
    local getXY = ReadableFunction(Field(position, "GetXY"))
    if getXY then
        local ok, first, second = Safe.Call(getXY, position)
        if ok then
            x, y = first, second
        end
    else
        x, y = Field(position, "x"), Field(position, "y")
    end

    if not CoordinatesAreValid(mapID, x, y) then
        return nil
    end
    return { mapID = mapID, x = x, y = y }
end

local function SamePoint(first, second)
    if not Safe.IsTable(first) or not Safe.IsTable(second) then
        return false
    end
    local firstMapID = Safe.AsPositiveInteger(Field(first, "mapID"), nil, 2147483647)
    local secondMapID = Safe.AsPositiveInteger(Field(second, "mapID"), nil, 2147483647)
    local firstX = Safe.AsNumber(Field(first, "x"), nil)
    local secondX = Safe.AsNumber(Field(second, "x"), nil)
    local firstY = Safe.AsNumber(Field(first, "y"), nil)
    local secondY = Safe.AsNumber(Field(second, "y"), nil)
    if not firstMapID or not secondMapID or firstX == nil or secondX == nil
        or firstY == nil or secondY == nil then
        return false
    end
    return firstMapID == secondMapID
        and math.abs(firstX - secondX) < 0.00001
        and math.abs(firstY - secondY) < 0.00001
end

local function CreateMapPoint(point)
    if not Safe.IsTable(point) then
        return nil
    end

    local mapID = Field(point, "mapID")
    local x = Field(point, "x")
    local y = Field(point, "y")
    local mapPointType = Safe.IsTable(UiMapPoint) and UiMapPoint or nil
    local create = ReadableFunction(mapPointType and Field(mapPointType, "CreateFromCoordinates"))
    if not CoordinatesAreValid(mapID, x, y) or not create then
        return nil
    end

    local ok, mapPoint = Safe.Call(create, mapID, x, y)
    return ok and Safe.IsReadable(mapPoint) and mapPoint or nil
end

local function GetCurrentNativePoint()
    local mapAPI = Safe.IsTable(C_Map) and C_Map or nil
    local getWaypoint = ReadableFunction(mapAPI and Field(mapAPI, "GetUserWaypoint"))
    if not getWaypoint then
        return "unavailable"
    end
    local ok, point = Safe.Call(getWaypoint)
    if not ok or not Safe.IsReadable(point) then
        return "unavailable"
    end
    if point == nil then
        return "absent"
    end

    local readablePoint = ReadMapPoint(point)
    if not readablePoint then
        return "unavailable"
    end
    return "point", readablePoint
end

local function GetSuperTrackState()
    local superTrack = Safe.IsTable(C_SuperTrack) and C_SuperTrack or nil
    local isTracking = ReadableFunction(superTrack and Field(superTrack, "IsSuperTrackingUserWaypoint"))
    if not isTracking then
        return "unavailable"
    end
    local ok, value = Safe.Call(isTracking)
    if not ok then
        return "unavailable"
    end
    value = Safe.AsBoolean(value, nil)
    if value == nil then
        return "unavailable"
    end
    return value and "enabled" or "disabled"
end

local function SetUserWaypointSuperTracked(enabled)
    local superTrack = Safe.IsTable(C_SuperTrack) and C_SuperTrack or nil
    local setTracking = ReadableFunction(superTrack and Field(superTrack, "SetSuperTrackedUserWaypoint"))
    if not setTracking then
        return false
    end
    if not Safe.Call(setTracking, enabled == true) then
        return false
    end
    local expected = enabled and "enabled" or "disabled"
    return GetSuperTrackState() == expected
end

local function GetMapName(mapID)
    local mapAPI = Safe.IsTable(C_Map) and C_Map or nil
    local getMapInfo = mapAPI and ReadableFunction(Field(mapAPI, "GetMapInfo"))
    if getMapInfo then
        local ok, info = Safe.Call(getMapInfo, mapID)
        local name = ok and Safe.IsTable(info) and Safe.TrimmedString(Field(info, "name"), nil, 256) or nil
        if name then return name end
    end
    return "map " .. tostring(mapID)
end

local function ClearOwnedTomTomWaypoints()
    local owned = 0
    for _ in pairs(ownedTomTomUIDs) do
        owned = owned + 1
    end
    if owned == 0 then
        return { success = true, status = "none", removed = 0, remaining = 0 }
    end

    local tomTom = Field(_G, "TomTom")
    local removeWaypoint = Safe.IsTable(tomTom) and ReadableFunction(Field(tomTom, "RemoveWaypoint"))
    if not removeWaypoint then
        return { success = false, status = "unavailable", removed = 0, remaining = owned }
    end

    local remaining = {}
    local removed = 0
    for uid in pairs(ownedTomTomUIDs) do
        local ok = Safe.Call(removeWaypoint, tomTom, uid)
        if not ok then
            remaining[uid] = ownedTomTomUIDs[uid]
        else
            removed = removed + 1
        end
    end
    ownedTomTomUIDs = remaining
    local remainingCount = owned - removed
    return {
        success = remainingCount == 0,
        status = remainingCount == 0 and "cleared" or (removed > 0 and "partial" or "failed"),
        removed = removed,
        remaining = remainingCount,
    }
end

local function ClearOwnedTomTomForItem(itemKey)
    if not itemKey then return true, false end
    local tomTom = Field(_G, "TomTom")
    local removeWaypoint = Safe.IsTable(tomTom) and ReadableFunction(Field(tomTom, "RemoveWaypoint"))
    local found, removedAll = false, true
    for uid, metadata in pairs(ownedTomTomUIDs) do
        if Safe.IsTable(metadata) and metadata.itemKey == itemKey then
            found = true
            if not removeWaypoint or not Safe.Call(removeWaypoint, tomTom, uid) then
                removedAll = false
            else
                ownedTomTomUIDs[uid] = nil
            end
        end
    end
    return removedAll, found
end

local function FinishSuperTrackRestore(lease, observedState)
    if not lease.appliedSuperTrackState then
        return true, "not-owned"
    end

    local currentState = observedState or GetSuperTrackState()
    if currentState == "unavailable" then
        return false, "supertrack-unavailable"
    end

    -- A later player/owner change wins. Do not restore the older leased state.
    if currentState ~= lease.appliedSuperTrackState then
        return true, "supertrack-preserved"
    end

    local previousState = lease.previousSuperTrackState
    if previousState == "unavailable" or previousState == currentState then
        return true, "supertrack-unchanged"
    end

    local restored = SetUserWaypointSuperTracked(previousState == "enabled")
    return restored, restored and "supertrack-restored" or "supertrack-failed"
end

local function ClearNativeLease()
    if not nativeLease then
        return { success = true, status = "none" }
    end

    local lease = nativeLease
    if lease.phase == "verify-point" then
        local currentStatus, currentPoint = GetCurrentNativePoint()
        if currentStatus == "unavailable" then
            return { success = false, status = "partial", detail = "post-operation-waypoint-unavailable" }
        end
        local expectedState = lease.expectedPostPointState
        local matchesExpected = expectedState == "absent" and currentStatus == "absent"
            or expectedState == "point" and currentStatus == "point"
                and SamePoint(currentPoint, lease.expectedPostPoint)
        if matchesExpected then
            lease.phase = "supertrack"
            nativeLease = lease
            return ClearNativeLease()
        end
        if currentStatus == "point" and SamePoint(currentPoint, lease.ours) then
            -- The prior point operation was a no-op. Retry it through the
            -- normal owned-point path.
            lease.phase = "point"
            nativeLease = lease
            return ClearNativeLease()
        end
        nativeLease = nil
        return { success = true, status = "preserved", detail = "post-operation-waypoint-changed" }
    end

    if lease.phase == "supertrack" then
        local currentStatus, currentPoint = GetCurrentNativePoint()
        if currentStatus == "unavailable" then
            return { success = false, status = "partial", detail = "post-restore-waypoint-unavailable" }
        end

        local expectedState = lease.expectedPostPointState
        local stillExpected = expectedState == "absent" and currentStatus == "absent"
            or expectedState == "point" and currentStatus == "point"
                and SamePoint(currentPoint, lease.expectedPostPoint)
        if not stillExpected then
            -- The player or another owner changed the waypoint after our point
            -- restore succeeded. Their newer waypoint and supertrack state win.
            nativeLease = nil
            return {
                success = true,
                status = "preserved",
                detail = "post-restore-waypoint-changed",
            }
        end

        local restored, detail = FinishSuperTrackRestore(lease)
        if restored then
            nativeLease = nil
            return { success = true, status = lease.pointOutcome or "preserved", detail = detail }
        end
        return { success = false, status = "partial", detail = detail }
    end

    local currentStatus, currentPoint = GetCurrentNativePoint()
    if currentStatus == "unavailable" then
        return { success = false, status = "unavailable", detail = "current-waypoint-unavailable" }
    end

    -- A readable later change owns the current state. Releasing the lease is
    -- safe because no restoration or clearing remains ours to perform.
    if currentStatus ~= "point" or not SamePoint(currentPoint, lease.ours) then
        nativeLease = nil
        return { success = true, status = "preserved", detail = "current-waypoint-changed" }
    end

    -- Capture this while our point is still current. Restoring/clearing the
    -- point itself may change Blizzard's reported supertrack state.
    local currentSuperTrackState = GetSuperTrackState()
    local mapAPI = Safe.IsTable(C_Map) and C_Map or nil
    local pointOutcome
    if lease.previousPointState == "point" then
        local previousPoint = CreateMapPoint(lease.previous)
        local setWaypoint = mapAPI and ReadableFunction(Field(mapAPI, "SetUserWaypoint"))
        if not previousPoint or not setWaypoint then
            return { success = false, status = "unavailable", detail = "restore-api-unavailable" }
        end
        local restoredOK, wasRestored = Safe.Call(setWaypoint, previousPoint)
        if not restoredOK or Safe.AsBoolean(wasRestored, false) ~= true then
            return { success = false, status = "failed", detail = "restore-failed" }
        end
        local restoredStatus, restoredPoint = GetCurrentNativePoint()
        if restoredStatus == "unavailable" then
            lease.phase = "verify-point"
            lease.pointOutcome = "restored"
            lease.expectedPostPointState = "point"
            lease.expectedPostPoint = lease.previous
            nativeLease = lease
            return { success = false, status = "partial", detail = "restore-readback-unavailable" }
        end
        if restoredStatus ~= "point" or not SamePoint(restoredPoint, lease.previous) then
            return { success = false, status = "failed", detail = "restore-readback-failed" }
        end
        pointOutcome = "restored"
    elseif lease.previousPointState == "absent" then
        local clearWaypoint = mapAPI and ReadableFunction(Field(mapAPI, "ClearUserWaypoint"))
        if not clearWaypoint then
            return { success = false, status = "unavailable", detail = "clear-api-unavailable" }
        end
        if not Safe.Call(clearWaypoint) then
            return { success = false, status = "failed", detail = "clear-failed" }
        end
        local clearedStatus = GetCurrentNativePoint()
        if clearedStatus == "unavailable" then
            lease.phase = "verify-point"
            lease.pointOutcome = "cleared"
            lease.expectedPostPointState = "absent"
            lease.expectedPostPoint = nil
            nativeLease = lease
            return { success = false, status = "partial", detail = "clear-readback-unavailable" }
        end
        if clearedStatus ~= "absent" then
            return { success = false, status = "failed", detail = "clear-readback-failed" }
        end
        pointOutcome = "cleared"
    else
        return { success = false, status = "unavailable", detail = "prior-waypoint-unavailable" }
    end

    local superTrackRestored, detail = FinishSuperTrackRestore(lease, currentSuperTrackState)
    if superTrackRestored then
        nativeLease = nil
        return { success = true, status = pointOutcome, detail = detail }
    end

    -- The point operation succeeded, but retain the remaining supertrack lease
    -- so a later Clear call can retry without touching the restored waypoint.
    lease.phase = "supertrack"
    lease.pointOutcome = pointOutcome
    lease.expectedPostPointState = lease.previousPointState
    lease.expectedPostPoint = lease.previous
    nativeLease = lease
    return { success = false, status = "partial", detail = detail }
end

local function AddTomTomWaypoint(source, title, itemKey, silent)
    local tomTom = Field(_G, "TomTom")
    local addWaypoint = Safe.IsTable(tomTom) and ReadableFunction(Field(tomTom, "AddWaypoint"))
    if not addWaypoint then
        return false
    end

    local options = {
        title = title,
        persistent = false,
        minimap = true,
        world = true,
        crazy = silent ~= true,
        silent = silent == true,
        from = Safe.TrimmedString(Addon.name, "DecorShoppingList", 128),
    }
    local mapID = Field(source, "mapID")
    local x = Field(source, "x")
    local y = Field(source, "y")
    local ok, uid = Safe.Call(addWaypoint, tomTom, mapID, x, y, options)
    if not ok or not Safe.IsReadable(uid) or uid == nil then
        return false
    end

    local uidType = type(uid)
    if uidType ~= "number" and uidType ~= "string" and uidType ~= "table" then
        return false
    end

    ownedTomTomUIDs[uid] = { itemKey = itemKey }
    return true, uid
end

local function AddNativeWaypoint(source)
    if not Safe.IsTable(source) then
        return false
    end

    local mapID = Field(source, "mapID")
    local x = Field(source, "x")
    local y = Field(source, "y")
    if not CoordinatesAreValid(mapID, x, y) then
        return false
    end

    local mapAPI = Safe.IsTable(C_Map) and C_Map or nil
    local setWaypoint = mapAPI and ReadableFunction(Field(mapAPI, "SetUserWaypoint"))
    if not setWaypoint then
        return false
    end

    local canSetWaypoint = ReadableFunction(Field(mapAPI, "CanSetUserWaypointOnMap"))
    if canSetWaypoint then
        local ok, canSet = Safe.Call(canSetWaypoint, mapID)
        if not ok or Safe.AsBoolean(canSet, false) ~= true then
            return false
        end
    end

    local ours = { mapID = mapID, x = x, y = y }
    local mapPoint = CreateMapPoint(ours)
    if not mapPoint then
        return false
    end

    if nativeLease and nativeLease.phase == "supertrack" then
        local cleared = ClearNativeLease()
        if not cleared.success then
            return false
        end
    end

    local currentStatus, currentPoint = GetCurrentNativePoint()
    if currentStatus == "unavailable" then
        -- Never overwrite a prior waypoint state we cannot read and therefore
        -- cannot safely restore.
        return false
    end

    local previousLease = nativeLease
    local reusingLease = nativeLease and currentStatus == "point"
        and SamePoint(currentPoint, nativeLease.ours)
    if nativeLease and not reusingLease then
        -- A readable later waypoint change superseded the old lease.
        nativeLease = nil
        previousLease = nil
    end

    local currentSuperTrackState = GetSuperTrackState()
    local nextLease
    if reusingLease then
        local previousSuperTrackState = nativeLease.previousSuperTrackState
        if nativeLease.appliedSuperTrackState
            and currentSuperTrackState ~= "unavailable"
            and currentSuperTrackState ~= nativeLease.appliedSuperTrackState
        then
            -- Preserve a later player supertrack choice as the state to return
            -- to after this new explicit Track action finishes.
            previousSuperTrackState = currentSuperTrackState
        end
        nextLease = {
            phase = "point",
            ours = ours,
            previousPointState = nativeLease.previousPointState,
            previous = nativeLease.previous,
            previousSuperTrackState = previousSuperTrackState,
            appliedSuperTrackState = nativeLease.appliedSuperTrackState,
        }
    else
        nextLease = {
            phase = "point",
            ours = ours,
            previousPointState = currentStatus,
            previous = currentPoint,
            previousSuperTrackState = currentSuperTrackState,
        }
    end

    local ok, wasSet = Safe.Call(setWaypoint, mapPoint)
    if not ok or Safe.AsBoolean(wasSet, false) ~= true then
        nativeLease = previousLease
        return false
    end

    local appliedStatus, appliedPoint = GetCurrentNativePoint()
    if appliedStatus == "unavailable" then
        -- Blizzard accepted the write, so keep enough ownership state to
        -- restore the prior waypoint if a later readable check proves ours is
        -- current. Do not report success until that proof exists.
        nativeLease = nextLease
        return false
    end
    if appliedStatus ~= "point" or not SamePoint(appliedPoint, ours) then
        nativeLease = previousLease
        return false
    end

    nativeLease = nextLease
    local superTracked = SetUserWaypointSuperTracked(true)
    if superTracked then
        nativeLease.appliedSuperTrackState = "enabled"
    end
    return true, superTracked and "native" or "native-map"
end

local function GetDecorID(item)
    if not Safe.IsTable(item) then
        return nil
    end
    local decorID = Field(item, "decorID")
    if not IsPositiveInteger(decorID) then
        decorID = Field(item, "recordID")
    end
    return IsPositiveInteger(decorID) and decorID or nil
end

local function TrackWithHousingCatalog(item)
    local decorID = GetDecorID(item)
    if not decorID then
        return false, "This decor does not have a readable tracking ID."
    end

    local contentTracking = Safe.IsTable(C_ContentTracking) and C_ContentTracking or nil
    local contentTrackingTypes = Safe.IsTable(Enum) and Field(Enum, "ContentTrackingType") or nil
    local trackingType = Safe.IsTable(contentTrackingTypes)
        and Safe.AsNonNegativeInteger(Field(contentTrackingTypes, "Decor"), nil, 100)
        or nil
    local isTracking = contentTracking and ReadableFunction(Field(contentTracking, "IsTracking"))
    if not trackingType or not isTracking then
        -- TrackHousingDecorID is a toggle. Without IsTracking we cannot call it
        -- safely because an apparently successful Track action could untrack
        -- an existing decor objective.
        return false, "Blizzard Housing decor tracking is not available."
    end

    local ok, tracked = Safe.Call(isTracking, trackingType, decorID)
    if not ok then
        return false, "Blizzard Housing decor tracking state is unavailable."
    end
    tracked = Safe.AsBoolean(tracked, nil)
    if tracked == nil then
        return false, "Blizzard Housing decor tracking state is unavailable."
    end
    if tracked then
        return true
    end

    local startTracking = ReadableFunction(Field(contentTracking, "StartTracking"))
    if startTracking then
        local started, trackingError = Safe.Call(startTracking, trackingType, decorID)
        if not started or not Safe.IsReadable(trackingError) then
            return false, "Blizzard could not track this decor right now."
        end
        -- The current API returns nil on success and a ContentTrackingError
        -- enum value on failure.
        if trackingError == nil then
            return true
        end
        return false, "Blizzard could not track this decor right now."
    end

    -- Do not fall back to Blizzard_HousingCatalogUtil.TrackHousingDecorID:
    -- that helper is a toggle, so a non-atomic pre-check could still untrack a
    -- decor if another owner changes tracking between the check and the call.
    return false, "Blizzard could not track this decor right now."
end

local function IsHousingTracked(item)
    local decorID = GetDecorID(item)
    if not decorID then return false end
    local contentTracking = Safe.IsTable(C_ContentTracking) and C_ContentTracking or nil
    local contentTrackingTypes = Safe.IsTable(Enum) and Field(Enum, "ContentTrackingType") or nil
    local trackingType = Safe.IsTable(contentTrackingTypes)
        and Safe.AsNonNegativeInteger(Field(contentTrackingTypes, "Decor"), nil, 100)
        or nil
    local isTracking = contentTracking and ReadableFunction(Field(contentTracking, "IsTracking"))
    if not trackingType or not isTracking then return false end
    local ok, tracked = Safe.Call(isTracking, trackingType, decorID)
    return ok and Safe.AsBoolean(tracked, false) == true
end

local function StopHousingTracking(item)
    if not IsHousingTracked(item) then return true, false end
    local decorID = GetDecorID(item)
    local contentTracking = Safe.IsTable(C_ContentTracking) and C_ContentTracking or nil
    local contentTrackingTypes = Safe.IsTable(Enum) and Field(Enum, "ContentTrackingType") or nil
    local stopTypes = Safe.IsTable(Enum) and Field(Enum, "ContentTrackingStopType") or nil
    local trackingType = Safe.IsTable(contentTrackingTypes)
        and Safe.AsNonNegativeInteger(Field(contentTrackingTypes, "Decor"), nil, 100)
        or nil
    local stopType = Safe.IsTable(stopTypes)
        and Safe.AsNonNegativeInteger(Field(stopTypes, "Manual"), nil, 100)
        or nil
    local stopTracking = contentTracking and ReadableFunction(Field(contentTracking, "StopTracking"))
    if not decorID or not trackingType or not stopType or not stopTracking then
        return false, true
    end
    local ok = Safe.Call(stopTracking, trackingType, decorID, stopType)
    return ok and not IsHousingTracked(item), true
end

function Waypoint:Initialize()
    if initialized then
        return
    end
    initialized = true
end

function Waypoint:ValidateCoordinates(mapID, x, y)
    return CoordinatesAreValid(mapID, x, y)
end

function Waypoint:TrackSource(source, title, itemKey)
    if not Safe.IsTable(source) then
        return false, "This source does not have a valid map location."
    end
    local mapID = Field(source, "mapID")
    local x = Field(source, "x")
    local y = Field(source, "y")
    if not CoordinatesAreValid(mapID, x, y) then
        return false, "This source does not have a valid map location."
    end

    title = Safe.TrimmedString(title, nil, 512)
        or Safe.TrimmedString(Field(source, "label"), nil, 512)
        or "Decor source"

    if AddTomTomWaypoint(source, title, itemKey) then
        return true, "tomtom"
    end
    local nativeSet, nativeMode = AddNativeWaypoint(source)
    if nativeSet then
        return true, nativeMode, GetMapName(mapID)
    end
    return false, "No compatible waypoint provider is available for this location."
end

function Waypoint:TrackItem(item)
    if not Safe.IsTable(item) then
        return false, "This decor entry is not available."
    end

    local itemKey = GetItemKey(item)
    local registry = Addon:GetModule("SourceRegistry")
    local sources = registry and registry:GetSourcesForItem(item) or {}
    local coordinateFailure
    for _, source in ipairs(sources) do
        if registry:IsCoordinateSource(source) then
            local title = Safe.TrimmedString(Field(item, "name"), nil, 512)
                or Safe.TrimmedString(Field(item, "title"), nil, 512)
            local success, modeOrReason, locationName = self:TrackSource(source, title, itemKey)
            if success then
                if modeOrReason == "native" or modeOrReason == "native-map" then
                    if nativeTrackedItemKey and nativeTrackedItemKey ~= itemKey then
                        ClearTrackedVendor(nativeTrackedItemKey)
                    end
                    nativeTrackedItemKey = itemKey
                end
                SetTrackedVendor(itemKey, source)
                return true, modeOrReason, locationName
            end
            coordinateFailure = modeOrReason
        end
    end

    local tracked, trackingReason = TrackWithHousingCatalog(item)
    if tracked then
        ClearTrackedVendor(itemKey)
        if itemKey then housingTrackedItemKeys[itemKey] = true end
        return true, "housing"
    end

    return false, coordinateFailure
        or trackingReason
        or "No mapped location or Blizzard Housing tracking is available for this decor."
end

function Waypoint:IsItemTracked(item)
    local itemKey = GetItemKey(item)
    if not itemKey then return false end

    local tomTom = Field(_G, "TomTom")
    local isValidWaypoint = Safe.IsTable(tomTom) and ReadableFunction(Field(tomTom, "IsValidWaypoint"))
    for uid, metadata in pairs(ownedTomTomUIDs) do
        if Safe.IsTable(metadata) and metadata.itemKey == itemKey then
            if not isValidWaypoint then return true end
            local ok, valid = Safe.Call(isValidWaypoint, tomTom, uid)
            if ok and Safe.AsBoolean(valid, false) == true then return true end
            ownedTomTomUIDs[uid] = nil
        end
    end

    if nativeTrackedItemKey == itemKey and nativeLease then
        local status, point = GetCurrentNativePoint()
        if status == "point" and SamePoint(point, nativeLease.ours) then
            return true
        end
        if status ~= "unavailable" then nativeTrackedItemKey = nil end
    end
    ClearTrackedVendor(itemKey)
    local housingTracked = IsHousingTracked(item)
    if housingTracked then
        housingTrackedItemKeys[itemKey] = true
    else
        housingTrackedItemKeys[itemKey] = nil
    end
    return housingTracked
end

function Waypoint:UntrackItem(item)
    local itemKey = GetItemKey(item)
    if not itemKey then return false, "This decor entry is not available." end

    local success = true
    local changed = false
    local tomTomSuccess, hadTomTom = ClearOwnedTomTomForItem(itemKey)
    success = success and tomTomSuccess
    changed = changed or hadTomTom

    if nativeTrackedItemKey == itemKey then
        local native = ClearNativeLease()
        success = success and native.success
        changed = true
        if native.success then nativeTrackedItemKey = nil end
    end

    local housingSuccess, hadHousing = StopHousingTracking(item)
    success = success and housingSuccess
    changed = changed or hadHousing
    if housingSuccess then housingTrackedItemKeys[itemKey] = nil end

    if success then ClearTrackedVendor(itemKey) end
    if success and changed then return true, "untracked" end
    if success then return true, "not-tracked" end
    return false, "Some tracking could not be stopped. Try again."
end

function Waypoint:ToggleItem(item)
    if self:IsItemTracked(item) then
        return self:UntrackItem(item)
    end
    return self:TrackItem(item)
end

function Waypoint:TrackItemBulk(item)
    if not Safe.IsTable(item) then
        return false, "This decor entry is not available."
    end
    local itemKey = GetItemKey(item)
    local registry = Addon:GetModule("SourceRegistry")
    local sources = registry and registry:GetSourcesForItem(item) or {}
    if registry then
        for _, source in ipairs(sources) do
            if registry:IsCoordinateSource(source) then
                local title = Safe.TrimmedString(Field(item, "name"), nil, 512)
                    or Safe.TrimmedString(Field(item, "title"), nil, 512)
                    or "Decor source"
                if AddTomTomWaypoint(source, title, itemKey, true) then
                    SetTrackedVendor(itemKey, source)
                    return true, "tomtom"
                end
            end
        end
    end
    local tracked, reason = TrackWithHousingCatalog(item)
    if tracked then
        ClearTrackedVendor(itemKey)
        if itemKey then housingTrackedItemKeys[itemKey] = true end
        return true, "housing"
    end
    return false, reason or "Bulk tracking needs TomTom or Blizzard Housing tracking."
end

function Waypoint:HasTrackedItems(items)
    if not Safe.IsTable(items) then return false end
    local keys = {}
    local examined = 0
    for _, item in ipairs(items) do
        examined = examined + 1
        if examined > 5000 then break end
        local key = GetItemKey(item)
        if key then keys[key] = true end
    end
    if nativeTrackedItemKey and keys[nativeTrackedItemKey] then return true end
    for _, metadata in pairs(ownedTomTomUIDs) do
        if Safe.IsTable(metadata) and metadata.itemKey and keys[metadata.itemKey] then return true end
    end
    for key in pairs(housingTrackedItemKeys) do
        if keys[key] then return true end
    end
    return false
end

function Waypoint:IsVendorNPCTracked(npcID)
    npcID = Safe.AsPositiveInteger(npcID, nil, 2147483647)
    return npcID ~= nil and (trackedVendorNPCCounts[npcID] or 0) > 0
end

function Waypoint:Clear()
    local tomtom = ClearOwnedTomTomWaypoints()
    local native = ClearNativeLease()
    if native.success then nativeTrackedItemKey = nil end
    local success = tomtom.success and native.success
    if success then ClearAllTrackedVendors() end
    local changed = tomtom.removed > 0
        or native.status == "cleared"
        or native.status == "restored"
    local status
    if success then
        status = changed and "cleared" or "nothing-owned"
    elseif tomtom.success or native.success then
        status = "partial-failure"
    else
        status = "failed"
    end

    return success, {
        success = success,
        partial = status == "partial-failure",
        changed = changed,
        status = status,
        tomtom = tomtom,
        native = native,
        contentTracking = "untouched",
    }
end

Addon:RegisterModule("Waypoint", Waypoint)
