-- Native waypoint lease behavioral smoke tests. Run from the Retail workspace root.

local addonRoot = ""

DEFAULT_CHAT_FRAME = { AddMessage = function() end }
TomTom = nil

local function LoadAddonFile(addon, relativePath)
    local chunk, errorMessage = loadfile(addonRoot .. relativePath)
    assert(chunk, errorMessage)
    chunk("DecorShoppingList", addon)
end

local function NewWaypoint()
    local addon = {}
    LoadAddonFile(addon, "Bootstrap.lua")
    LoadAddonFile(addon, "Core/SafeValue.lua")
    LoadAddonFile(addon, "Navigation/Waypoint.lua")
    return assert(addon:GetModule("Waypoint")), addon
end

local function Point(mapID, x, y)
    return {
        uiMapID = mapID,
        position = { GetXY = function() return x, y end },
    }
end

local function AssertPoint(point, expectedMapID, expectedX, expectedY, message)
    assert(type(point) == "table" and point.uiMapID == expectedMapID, message)
    local x, y = point.position:GetXY()
    assert(math.abs(x - expectedX) < 0.00001 and math.abs(y - expectedY) < 0.00001, message)
end

local function InstallNativeMock(options)
    options = options or {}
    local state = {
        point = options.point,
        superTracked = options.superTracked == true,
        setCalls = 0,
        clearCalls = 0,
        superTrackWrites = 0,
        unreadablePoint = options.unreadablePoint == true,
        failClear = options.failClear == true,
        failSet = options.failSet == true,
        rejectSet = options.rejectSet == true,
        rejectSetAt = options.rejectSetAt,
        ignoreSet = options.ignoreSet == true,
        ignoreSetAt = options.ignoreSetAt,
        ignoreClear = options.ignoreClear == true,
        ignoreSuperTrack = options.ignoreSuperTrack == true,
        unreadableAfterSet = options.unreadableAfterSet == true,
        unreadableGetAt = options.unreadableGetAt,
        getCalls = 0,
        failSuperTrack = options.failSuperTrack == true,
    }

    UiMapPoint = {
        CreateFromCoordinates = function(mapID, x, y)
            return Point(mapID, x, y)
        end,
    }
    C_Map = {
        GetUserWaypoint = function()
            state.getCalls = state.getCalls + 1
            if state.getCalls == state.unreadableGetAt then error("transient unreadable waypoint") end
            if state.unreadablePoint then error("unreadable waypoint") end
            return state.point
        end,
        CanSetUserWaypointOnMap = function() return true end,
        SetUserWaypoint = function(point)
            state.setCalls = state.setCalls + 1
            if state.failSet then error("set failed") end
            if state.rejectSet or state.setCalls == state.rejectSetAt then return false end
            if not state.ignoreSet and state.setCalls ~= state.ignoreSetAt then state.point = point end
            if state.unreadableAfterSet then state.unreadablePoint = true end
            return true
        end,
        ClearUserWaypoint = function()
            state.clearCalls = state.clearCalls + 1
            if state.failClear then error("clear failed") end
            if not state.ignoreClear then state.point = nil end
        end,
    }
    C_SuperTrack = {
        IsSuperTrackingUserWaypoint = function()
            return state.superTracked
        end,
        SetSuperTrackedUserWaypoint = function(enabled)
            state.superTrackWrites = state.superTrackWrites + 1
            if state.failSuperTrack then error("supertrack failed") end
            if not state.ignoreSuperTrack then state.superTracked = enabled == true end
        end,
    }
    return state
end

-- A clean Blizzard rejection is not a successful native waypoint.
do
    local state = InstallNativeMock({ point = nil, rejectSet = true })
    local waypoint = NewWaypoint()
    local success = waypoint:TrackSource({ mapID = 20, x = 0.20, y = 0.30 }, "Rejected")
    assert(not success and state.point == nil and state.superTrackWrites == 0,
        "SetUserWaypoint=false was reported as native success")
end

-- A claimed set must match immediate C_Map readback.
do
    local state = InstallNativeMock({ point = nil, ignoreSet = true })
    local waypoint = NewWaypoint()
    local success = waypoint:TrackSource({ mapID = 21, x = 0.30, y = 0.40 }, "No readback")
    assert(not success and state.superTrackWrites == 0,
        "missing native waypoint readback was reported as success")
end

-- A stored map pin with unavailable supertracking is reported as degraded,
-- never as a fully visible Blizzard navigation waypoint.
do
    local state = InstallNativeMock({ point = nil, failSuperTrack = true })
    local waypoint = NewWaypoint()
    local success, mode = waypoint:TrackSource({ mapID = 22, x = 0.40, y = 0.50 }, "Map only")
    assert(success and mode == "native-map", "failed supertracking was reported as full native success")
    AssertPoint(state.point, 22, 0.40, 0.50, "degraded native map pin was not retained")
end

-- Coordinate tracking reports the item's active TomTom state and drops the
-- state when TomTom says the pin no longer exists.
do
    local valid = true
    local uid = { 24, 0.25, 0.35 }
    TomTom = {
        AddWaypoint = function() return uid end,
        IsValidWaypoint = function(_, candidate) return candidate == uid and valid end,
        RemoveWaypoint = function() valid = false end,
    }
    local waypoint, addon = NewWaypoint()
    addon:RegisterModule("SourceRegistry", {
        GetSourcesForItem = function()
            return { { type = "vendor", mapID = 24, x = 0.25, y = 0.35 } }
        end,
        IsCoordinateSource = function() return true end,
    })
    local item = { key = "decor:240", recordID = 240, name = "Tracked decor" }
    local success, mode = waypoint:TrackItem(item)
    assert(success and mode == "tomtom" and waypoint:IsItemTracked(item),
        "active TomTom item was not reported as tracked")
    local stopped, stoppedMode = waypoint:ToggleItem(item)
    assert(stopped and stoppedMode == "untracked" and not waypoint:IsItemTracked(item) and not valid,
        "TomTom Track button did not toggle the item off")
    valid = true
    assert(waypoint:ToggleItem(item), "TomTom Track button did not toggle the item on again")
    valid = false
    assert(not waypoint:IsItemTracked(item), "removed TomTom pin kept its tracked state")
    TomTom = nil
end

-- Blizzard Housing tracking is queried directly rather than remembered as a
-- stale click state.
do
    local tracked = true
    Enum = {
        ContentTrackingType = { Decor = 7 },
        ContentTrackingStopType = { Manual = 2 },
    }
    C_ContentTracking = {
        IsTracking = function(trackingType, decorID)
            return trackingType == 7 and decorID == 241 and tracked
        end,
        StopTracking = function(trackingType, decorID, stopType)
            assert(trackingType == 7 and decorID == 241 and stopType == 2,
                "Housing toggle used the wrong tracking arguments")
            tracked = false
        end,
        StartTracking = function(trackingType, decorID)
            assert(trackingType == 7 and decorID == 241, "Housing bulk track used the wrong arguments")
            tracked = true
            return nil
        end,
    }
    local waypoint = NewWaypoint()
    local item = { key = "decor:241", recordID = 241 }
    assert(waypoint:IsItemTracked(item), "active Blizzard decor tracking was not detected")
    local stopped, mode = waypoint:ToggleItem(item)
    assert(stopped and mode == "untracked" and not waypoint:IsItemTracked(item),
        "Housing Track button did not toggle the item off")
    local bulkTracked, bulkMode = waypoint:TrackItemBulk(item)
    assert(bulkTracked and bulkMode == "housing" and waypoint:HasTrackedItems({ item }),
        "Housing Track All did not activate or report the item")
    C_ContentTracking = nil
    Enum = nil
end

-- A non-throwing supertrack no-op is also degraded; pcall success alone is
-- not proof that Blizzard navigation became visible.
do
    local state = InstallNativeMock({ point = nil, ignoreSuperTrack = true })
    local waypoint = NewWaypoint()
    local success, mode = waypoint:TrackSource({ mapID = 23, x = 0.45, y = 0.55 }, "Map only")
    assert(success and mode == "native-map" and not state.superTracked,
        "silent supertrack no-op was reported as full native success")
end

local function TrackNative(waypoint, mapID, x, y)
    local success, mode = waypoint:TrackSource({ mapID = mapID, x = x, y = y }, "Smoke source")
    assert(success and mode == "native", "native source was not tracked")
end

-- Native Blizzard waypoints toggle off by restoring the prior leased point.
do
    local state = InstallNativeMock({ point = Point(25, 0.10, 0.20), superTracked = false })
    local waypoint, addon = NewWaypoint()
    addon:RegisterModule("SourceRegistry", {
        GetSourcesForItem = function()
            return { { type = "vendor", mapID = 26, x = 0.30, y = 0.40 } }
        end,
        IsCoordinateSource = function() return true end,
    })
    local item = { key = "decor:260", recordID = 260, name = "Native tracked decor" }
    local tracked, trackMode = waypoint:ToggleItem(item)
    assert(tracked and trackMode == "native" and waypoint:IsItemTracked(item),
        "native Track button did not toggle the item on")
    local stopped, stopMode = waypoint:ToggleItem(item)
    assert(stopped and stopMode == "untracked" and not waypoint:IsItemTracked(item),
        "native Track button did not toggle the item off")
    AssertPoint(state.point, 25, 0.10, 0.20, "native toggle did not restore the prior point")
end

-- Prior point and supertrack state are restored when our lease still owns them.
do
    local state = InstallNativeMock({ point = Point(1, 0.10, 0.20), superTracked = false })
    local waypoint = NewWaypoint()
    TrackNative(waypoint, 2, 0.30, 0.40)
    local success, result = waypoint:Clear()
    assert(success and result.success and result.status == "cleared", "structured clear did not report success")
    assert(result.native.status == "restored" and result.native.detail == "supertrack-restored",
        "native lease did not report point/supertrack restoration")
    assert(result.tomtom.status == "none" and result.contentTracking == "untouched",
        "structured clear changed an unowned subsystem")
    AssertPoint(state.point, 1, 0.10, 0.20, "prior native point was not restored")
    assert(state.superTracked == false, "prior supertrack state was not restored")
end

-- Never overwrite a prior native state that cannot be read and restored.
do
    local state = InstallNativeMock({ point = Point(3, 0.20, 0.25), unreadablePoint = true })
    local waypoint = NewWaypoint()
    local success = waypoint:TrackSource({ mapID = 4, x = 0.40, y = 0.45 }, "Unreadable prior")
    assert(not success and state.setCalls == 0, "unreadable prior state was overwritten")
    state.unreadablePoint = false
    AssertPoint(state.point, 3, 0.20, 0.25, "unreadable prior point changed")
    local cleared, result = waypoint:Clear()
    assert(cleared and result.status == "nothing-owned" and result.native.status == "none",
        "refused overwrite unexpectedly created a lease")
end

-- A failed clear retains the lease so a later Clear can retry safely.
do
    local state = InstallNativeMock({ point = nil, superTracked = false, failClear = true })
    local waypoint = NewWaypoint()
    TrackNative(waypoint, 5, 0.50, 0.55)
    local firstSuccess, first = waypoint:Clear()
    assert(not firstSuccess and first.partial and first.status == "partial-failure",
        "clear failure did not return structured partial failure")
    assert(first.native.status == "failed" and first.native.detail == "clear-failed",
        "clear failure detail was not retained")
    state.failClear = false
    local retrySuccess, retry = waypoint:Clear()
    assert(retrySuccess and retry.native.status == "cleared", "retained native lease was not retryable")
    assert(state.point == nil and state.superTracked == false, "retry did not finish lease restoration")
end

-- A later player waypoint owns the newest state; Clear preserves it.
do
    local state = InstallNativeMock({ point = Point(6, 0.10, 0.15), superTracked = false })
    local waypoint = NewWaypoint()
    TrackNative(waypoint, 7, 0.60, 0.65)
    state.point = Point(8, 0.80, 0.85)
    state.superTracked = false
    local success, result = waypoint:Clear()
    assert(success and result.native.status == "preserved"
        and result.native.detail == "current-waypoint-changed", "later player waypoint did not win")
    AssertPoint(state.point, 8, 0.80, 0.85, "later player waypoint was modified")
    assert(state.superTracked == false, "later player supertrack state was modified")
end

-- A later supertrack choice wins even when our waypoint still owns the point.
do
    local state = InstallNativeMock({ point = Point(9, 0.15, 0.20), superTracked = false })
    local waypoint = NewWaypoint()
    TrackNative(waypoint, 10, 0.70, 0.75)
    state.superTracked = false
    local success, result = waypoint:Clear()
    assert(success and result.native.status == "restored"
        and result.native.detail == "supertrack-preserved", "later supertrack choice did not win")
    AssertPoint(state.point, 9, 0.15, 0.20, "prior point was not restored")
    assert(state.superTracked == false, "later supertrack choice was overwritten")
end

-- If point restoration succeeds but supertrack restoration fails, a later
-- player waypoint must invalidate the retry rather than inherit old state.
do
    local state = InstallNativeMock({ point = Point(11, 0.10, 0.20), superTracked = false })
    local waypoint = NewWaypoint()
    TrackNative(waypoint, 12, 0.30, 0.40)

    state.failSuperTrack = true
    local firstSuccess, first = waypoint:Clear()
    assert(not firstSuccess and first.partial and first.status == "partial-failure",
        "supertrack restore failure did not return a structured partial failure")
    assert(first.native.status == "partial" and first.native.detail == "supertrack-failed",
        "supertrack restore failure did not retain its retry phase")
    AssertPoint(state.point, 11, 0.10, 0.20, "point restoration did not finish before the retry phase")

    local writesAfterFailure = state.superTrackWrites
    state.failSuperTrack = false
    state.point = Point(13, 0.80, 0.85)
    state.superTracked = true

    local retrySuccess, retry = waypoint:Clear()
    assert(retrySuccess and retry.native.status == "preserved"
        and retry.native.detail == "post-restore-waypoint-changed",
        "later player waypoint did not invalidate the supertrack retry")
    AssertPoint(state.point, 13, 0.80, 0.85, "supertrack retry modified the later player waypoint")
    assert(state.superTracked == true, "supertrack retry overwrote the later player's state")
    assert(state.superTrackWrites == writesAfterFailure,
        "supertrack retry wrote the old prior state onto a later player waypoint")
end

-- A clean Blizzard rejection while restoring the previous point keeps the
-- lease retryable instead of claiming that cleanup succeeded.
do
    local state = InstallNativeMock({
        point = Point(14, 0.10, 0.20),
        superTracked = false,
        rejectSetAt = 2,
    })
    local waypoint = NewWaypoint()
    TrackNative(waypoint, 15, 0.30, 0.40)
    local firstSuccess, first = waypoint:Clear()
    assert(not firstSuccess and first.native.status == "failed"
        and first.native.detail == "restore-failed", "rejected restore was reported as successful")
    AssertPoint(state.point, 15, 0.30, 0.40, "rejected restore changed the owned point")

    state.rejectSetAt = nil
    local retrySuccess, retry = waypoint:Clear()
    assert(retrySuccess and retry.native.status == "restored", "rejected restore lease was not retryable")
    AssertPoint(state.point, 14, 0.10, 0.20, "retry did not restore the prior point")
end

-- A restoration write that returns true but leaves our point in place fails
-- readback and keeps the lease retryable.
do
    local state = InstallNativeMock({
        point = Point(16, 0.10, 0.20),
        superTracked = false,
        ignoreSetAt = 2,
    })
    local waypoint = NewWaypoint()
    TrackNative(waypoint, 17, 0.30, 0.40)
    local firstSuccess, first = waypoint:Clear()
    assert(not firstSuccess and first.native.detail == "restore-readback-failed",
        "ignored restore write passed its readback check")
    AssertPoint(state.point, 17, 0.30, 0.40, "ignored restore unexpectedly changed the point")
    state.ignoreSetAt = nil
    assert(waypoint:Clear(), "ignored restore lease was not retryable")
    AssertPoint(state.point, 16, 0.10, 0.20, "restore retry did not recover the prior point")
end

-- A non-throwing ClearUserWaypoint no-op must not release ownership.
do
    local state = InstallNativeMock({ point = nil, superTracked = false, ignoreClear = true })
    local waypoint = NewWaypoint()
    TrackNative(waypoint, 18, 0.50, 0.60)
    local firstSuccess, first = waypoint:Clear()
    assert(not firstSuccess and first.native.detail == "clear-readback-failed",
        "silent clear no-op was reported as success")
    AssertPoint(state.point, 18, 0.50, 0.60, "silent clear no-op changed the point")
    state.ignoreClear = false
    assert(waypoint:Clear(), "silent clear no-op lease was not retryable")
    assert(state.point == nil, "clear retry did not remove the owned point")
end

-- If Blizzard accepts a point but readback is transiently unavailable, retain
-- recovery state without reporting success; a later Clear can safely restore.
do
    local state = InstallNativeMock({
        point = Point(19, 0.10, 0.20),
        superTracked = false,
        unreadableAfterSet = true,
    })
    local waypoint = NewWaypoint()
    local success = waypoint:TrackSource({ mapID = 20, x = 0.60, y = 0.70 }, "Unreadable readback")
    assert(not success, "unreadable forward readback was reported as success")
    state.unreadableAfterSet = false
    state.unreadablePoint = false
    local clearSuccess, clearResult = waypoint:Clear()
    assert(clearSuccess and clearResult.native.status == "restored",
        "unreadable forward readback did not retain a restorable lease")
    AssertPoint(state.point, 19, 0.10, 0.20, "retained lease did not restore the prior point")
end

-- A transiently unreadable restore readback enters a verification phase. The
-- next Clear proves the prior point, then restores supertracking.
do
    local state = InstallNativeMock({
        point = Point(21, 0.10, 0.20),
        superTracked = false,
        unreadableGetAt = 4,
    })
    local waypoint = NewWaypoint()
    TrackNative(waypoint, 22, 0.30, 0.40)
    local firstSuccess, first = waypoint:Clear()
    assert(not firstSuccess and first.native.status == "partial"
        and first.native.detail == "restore-readback-unavailable",
        "transient restore readback did not retain verification state")
    AssertPoint(state.point, 21, 0.10, 0.20, "restore operation did not set the prior point")
    local retrySuccess, retry = waypoint:Clear()
    assert(retrySuccess and retry.native.status == "restored",
        "verified restore did not finish cleanup")
    assert(state.superTracked == false, "verified restore did not restore supertracking")
end

-- The same verification phase handles a transiently unreadable clear.
do
    local state = InstallNativeMock({ point = nil, superTracked = false, unreadableGetAt = 4 })
    local waypoint = NewWaypoint()
    TrackNative(waypoint, 23, 0.50, 0.60)
    local firstSuccess, first = waypoint:Clear()
    assert(not firstSuccess and first.native.detail == "clear-readback-unavailable",
        "transient clear readback did not retain verification state")
    assert(state.point == nil, "clear operation did not remove the point")
    local retrySuccess, retry = waypoint:Clear()
    assert(retrySuccess and retry.native.status == "cleared", "verified clear did not finish cleanup")
    assert(state.superTracked == false, "verified clear did not restore supertracking")
end

print("Decor Shopping List waypoint smoke tests passed")
