-- Unfallschaden
-- Version: 1.2.0.0
-- Script mod for Farming Simulator 25 / Landwirtschafts-Simulator 25
-- Author tag: Dude23

FSCollisionDamage = {}
FSCollisionDamage.MOD_NAME = g_currentModName or "FS25_Unfallschaden"
FSCollisionDamage.VERSION = "1.2.0.0"

-- ============================================================
-- Settings
-- ============================================================

-- DEBUG BUILD: verbose diagnostics enabled. This build is intended only for
-- local testing and log analysis, not for ModHub submission.
-- Collision checks run from one global scheduler. The global loop is
-- deliberately slow and expensive overlap/raycast checks are only performed after
-- a strong impact candidate was detected. This avoids frame spikes during normal
-- steering/braking with frontloaders or attached tools.
FSCollisionDamage.CHECK_INTERVAL_MS = 350
FSCollisionDamage.MIN_TRACK_SPEED_KMH = 0.5

-- Some impacts slow the vehicle down over several physics frames instead of
-- producing one large speed drop. The recent-speed window catches these
-- gradual impacts without reacting to normal driving by itself; contact with
-- a foreign collision shape is still required.
FSCollisionDamage.SPEED_DROP_WINDOW_MS = 1100

-- Large machines can be slowed down by wide building walls over a longer
-- physical contact phase. This additional window is only used with confirmed
-- contact and a low end speed, so normal braking in open space remains ignored.
FSCollisionDamage.DAMAGE_COOLDOWN_MS = 1400

-- Slow parking and maneuvering should not cause damage.
FSCollisionDamage.MIN_SPEED_KMH = 10.0
FSCollisionDamage.MIN_SPEED_DROP_KMH = 10.0

-- Side swipes and angled impacts do not always reduce the total speed enough
-- for a normal speed-drop based crash. A horizontal velocity-vector change is
-- therefore also accepted as an impact candidate, but still only with a
-- confirmed foreign collision shape.
FSCollisionDamage.MIN_DAMAGE = 0.010     -- 1.0%
FSCollisionDamage.MAX_DAMAGE = 0.045     -- 4.5%
FSCollisionDamage.DAMAGE_PER_KMH_DROP = 0.0012

-- If the confirmed crash target is another usable vehicle, trailer or tool
-- with the Giants wearable damage system, the target receives the same damage
-- amount as the vehicle that caused the impact. Static map objects, buildings,
-- trees, terrain and traffic/non-wearable objects are not affected.
FSCollisionDamage.COUNTERPART_DAMAGE_ENABLED = true

-- Player-facing damage multiplier. It can be changed in the ESC menu under
-- game settings. Default 100% keeps the normal behaviour.
FSCollisionDamage.DAMAGE_MULTIPLIER_DEFAULT_STATE = 5
FSCollisionDamage.DAMAGE_MULTIPLIER = 1.0
FSCollisionDamage.DAMAGE_MULTIPLIER_OPTIONS = {
    0.0,
    0.25,
    0.50,
    0.75,
    1.00,
    1.25,
    1.50,
    2.00,
    3.00
}
FSCollisionDamage.DAMAGE_MULTIPLIER_TEXTS = {
    "0 %",
    "25 %",
    "50 %",
    "75 %",
    "100 %",
    "125 %",
    "150 %",
    "200 %",
    "300 %"
}

-- A 25-30 km/h impact is already a serious crash for slow machines such as
-- combines. The base calculation still uses the measured speed drop, but
-- stronger impact bands prevent low top-speed vehicles from feeling almost
-- immune compared with 40+ km/h tractors.
FSCollisionDamage.MEDIUM_IMPACT_SPEED_KMH = 25.0
FSCollisionDamage.HIGH_IMPACT_SPEED_KMH = 35.0
FSCollisionDamage.VERY_HIGH_IMPACT_SPEED_KMH = 55.0
FSCollisionDamage.MEDIUM_IMPACT_MULTIPLIER = 1.25
FSCollisionDamage.HIGH_IMPACT_MULTIPLIER = 1.35
FSCollisionDamage.VERY_HIGH_IMPACT_MULTIPLIER = 1.55

-- Heavy, slow machines often hit at lower speeds but with far more mass.
-- After a confirmed collision, these machines receive a stronger and more
-- visible damage amount without weakening the brake/contact safeguards.
FSCollisionDamage.HEAVY_MACHINE_MIN_MASS_T = 10.0
FSCollisionDamage.HEAVY_MACHINE_MULTIPLIER = 1.65
FSCollisionDamage.HEAVY_MACHINE_MAX_DAMAGE = 0.070
FSCollisionDamage.HEAVY_MACHINE_MODERATE_SPEED_KMH = 20.0
FSCollisionDamage.HEAVY_MACHINE_MODERATE_DROP_KMH = 9.0
FSCollisionDamage.HEAVY_MACHINE_MODERATE_MIN_DAMAGE = 0.030
FSCollisionDamage.HEAVY_MACHINE_STRONG_DROP_KMH = 12.0
FSCollisionDamage.HEAVY_MACHINE_STRONG_MIN_DAMAGE = 0.045
FSCollisionDamage.HEAVY_MACHINE_VERY_STRONG_DROP_KMH = 20.0
FSCollisionDamage.HEAVY_MACHINE_VERY_STRONG_MIN_DAMAGE = 0.060

FSCollisionDamage.MASS_BASELINE_T = 6.0
FSCollisionDamage.MASS_MAX_BONUS = 0.35

FSCollisionDamage.STRONG_IMPACT_SPEED_KMH = 25.0
FSCollisionDamage.STRONG_IMPACT_DROP_KMH = 12.0
FSCollisionDamage.STRONG_IMPACT_MIN_DAMAGE = 0.025
FSCollisionDamage.VERY_STRONG_IMPACT_DROP_KMH = 20.0
FSCollisionDamage.VERY_STRONG_IMPACT_MIN_DAMAGE = 0.035

-- Wider proximity box and tighter contact box around the vehicle AABB.
-- The wide box is used to know whether an obstacle was already nearby;
-- the tight box confirms actual contact at the moment of the speed drop.
FSCollisionDamage.SENSOR_RAYCAST_MAX_DISTANCE = 2.10
FSCollisionDamage.SENSOR_RAYCAST_BACK_OFFSET = 0.08
FSCollisionDamage.SENSOR_RAYCAST_SIDE_OFFSET_MAX = 1.80
FSCollisionDamage.SENSOR_RAYCAST_SIDE_FRACTION = 0.92
FSCollisionDamage.SENSOR_RAYCAST_MIN_HEIGHT = 0.45
FSCollisionDamage.SENSOR_RAYCAST_MAX_HEIGHT = 2.45
FSCollisionDamage.SENSOR_RAYCAST_HEIGHT_FRACTIONS = { 0.28, 0.56, 0.82 }
FSCollisionDamage.SENSOR_RAYCAST_PREVIOUS_ENABLED = true
FSCollisionDamage.SENSOR_RAYCAST_SWEEP_ENABLED = true
FSCollisionDamage.SENSOR_PREVIOUS_AABB_MAX_AGE_MS = 1600
FSCollisionDamage.SENSOR_ALLOW_GENERIC_STATIC = false

FSCollisionDamage.SENSOR_FRONT_PROBE_MIN_DROP_KMH = 20.0
FSCollisionDamage.SENSOR_FRONT_PROBE_MAX_END_SPEED_KMH = 6.5
FSCollisionDamage.SENSOR_FRONT_PROBE_DISTANCE = 1.15
FSCollisionDamage.SENSOR_FRONT_PROBE_STEP = 0.65
FSCollisionDamage.SENSOR_FRONT_PROBE_DEPTH = 0.32
FSCollisionDamage.SENSOR_FRONT_PROBE_SIDE_FRACTION = 0.72
FSCollisionDamage.SENSOR_FRONT_PROBE_SIDE_OFFSET_MAX = 1.35
FSCollisionDamage.SENSOR_FRONT_PROBE_MIN_HEIGHT = 0.20
FSCollisionDamage.SENSOR_FRONT_PROBE_MAX_HEIGHT = 2.35
FSCollisionDamage.SENSOR_FRONT_PROBE_MARGIN_X = 0.06
FSCollisionDamage.SENSOR_FRONT_PROBE_MARGIN_Y = 0.12
FSCollisionDamage.SENSOR_FRONT_PROBE_MARGIN_Z = 0.06
FSCollisionDamage.SENSOR_FRONT_PROBE_ENABLED = true

-- Frontloader/tools are part of the own vehicle train and are therefore ignored
-- as counterpart targets. For strong impacts where the attached front tool is
-- the physical contact surface, use the tool only as an additional sensor
-- source and still apply the damage to the driven root vehicle.
FSCollisionDamage.ATTACHED_SENSOR_RAYCAST_ENABLED = true
FSCollisionDamage.ATTACHED_SENSOR_RAYCAST_MIN_DROP_KMH = 14.0
FSCollisionDamage.ATTACHED_SENSOR_RAYCAST_MIN_REFERENCE_SPEED_KMH = 18.0
FSCollisionDamage.ATTACHED_SENSOR_RAYCAST_MAX_END_SPEED_KMH = 22.0
FSCollisionDamage.ATTACHED_SENSOR_RAYCAST_MAX_AABBS = 4
FSCollisionDamage.ATTACHED_TOOL_PROXY_ENABLED = true
FSCollisionDamage.ATTACHED_TOOL_PROXY_MIN_DROP_KMH = 18.0
FSCollisionDamage.ATTACHED_TOOL_PROXY_MIN_REFERENCE_SPEED_KMH = 20.0
FSCollisionDamage.ATTACHED_TOOL_PROXY_MAX_END_SPEED_KMH = 8.0

FSCollisionDamage.HEAVY_SENSOR_RAYCAST_MAX_DISTANCE = 2.70
FSCollisionDamage.HEAVY_SENSOR_RAYCAST_SIDE_OFFSET_MAX = 2.90
FSCollisionDamage.HEAVY_SENSOR_RAYCAST_SIDE_FRACTION = 0.90
FSCollisionDamage.HEAVY_SENSOR_RAYCAST_MIN_HEIGHT = 0.30
FSCollisionDamage.HEAVY_SENSOR_RAYCAST_MAX_HEIGHT = 3.20
FSCollisionDamage.HEAVY_SENSOR_RAYCAST_HEIGHT_FRACTIONS = { 0.20, 0.45, 0.72 }

-- Anonymous static map nodes are especially unsafe as crash evidence. On some
-- maps, hard braking on an open road overlaps helper collision nodes such as
-- pCube/polySurface/LOD/col even though no real crash happened. Damage against
-- such nodes is blocked for normal braking. Very severe impacts are still
-- allowed, because some real map walls/fences only report generic nodes such as
-- LOD0 without an owning object.
FSCollisionDamage.ROAD_SURFACE_NODE_NAME_PARTS = {
    "strassen",
    "straße",
    "strasse",
    "roads",
    "roadnetwork"
}

FSCollisionDamage.NAMED_STATIC_OBSTACLE_NODE_NAME_PARTS = {
    "streetlightpole",
    "lightpole",
    "lamp",
    "laterne",
    "busstop",
    "bus_stop",
    "fence",
    "zaun",
    "wall",
    "mauer",
    "building",
    "buildings",
    "gebaeude",
    "gebäude",
    "barn",
    "halle",
    "panel",
    "gate",
    "tor",
    "tree",
    "trees",
    "oak",
    "beech",
    "spruce",
    "baum",
    "kroneemsland",
    "trailer"
}

-- Collision callbacks no longer stop at the first anonymous scene node. They
-- collect the best available candidate and prefer real Lua objects, vehicles,
-- traffic nodes and dynamic collision bodies over generic static map geometry.
-- Name-based road/object hints remain only low-priority hints for anonymous
-- fallback nodes; they are not the primary target selection mechanism.
FSCollisionDamage.COLLISION_STOP_PRIORITY = 90
FSCollisionDamage.CANDIDATE_PRIORITY_OTHER_VEHICLE = 100
FSCollisionDamage.CANDIDATE_PRIORITY_TRAFFIC = 95
FSCollisionDamage.CANDIDATE_PRIORITY_OBJECT = 85
FSCollisionDamage.CANDIDATE_PRIORITY_DYNAMIC_ANONYMOUS = 72
FSCollisionDamage.CANDIDATE_PRIORITY_NAMED_STATIC = 55
FSCollisionDamage.CANDIDATE_PRIORITY_UNKNOWN_STATIC = 35
FSCollisionDamage.CANDIDATE_PRIORITY_GENERIC_STATIC = 25
FSCollisionDamage.CANDIDATE_PRIORITY_ROAD_LIKE_STATIC = 8

-- AI traffic collision shapes from the base game do not always have an owning
-- object. They appear as anonymous nodes such as multiPurposeTruck or vehicle09.
-- They must not be treated like generic map helper nodes, otherwise real crashes
-- against moving traffic are filtered out. The target itself is still not damaged
-- unless it is a normal wearable vehicle.
FSCollisionDamage.COMBINE_FRONT_PROBE_MIN_DROP_KMH = 8.0
FSCollisionDamage.COMBINE_FRONT_PROBE_MAX_END_SPEED_KMH = 10.0
FSCollisionDamage.COMBINE_FRONT_PROBE_DISTANCE = 5.20
FSCollisionDamage.COMBINE_FRONT_PROBE_STEP = 0.75
FSCollisionDamage.COMBINE_FRONT_PROBE_DEPTH = 0.35
FSCollisionDamage.COMBINE_FRONT_PROBE_SIDE_FRACTION = 0.28
FSCollisionDamage.COMBINE_FRONT_PROBE_SIDE_OFFSET_MAX = 1.20
FSCollisionDamage.COMBINE_FRONT_PROBE_MIN_HEIGHT = 0.15
FSCollisionDamage.COMBINE_FRONT_PROBE_MAX_HEIGHT = 2.40
FSCollisionDamage.COMBINE_FRONT_PROBE_MARGIN_X = 0.06
FSCollisionDamage.COMBINE_FRONT_PROBE_MARGIN_Y = 0.12
FSCollisionDamage.COMBINE_FRONT_PROBE_MARGIN_Z = 0.06

-- Broader front probe for other heavy machines. It remains as a later fallback
-- after the combine-specific narrow probe.
FSCollisionDamage.HEAVY_FRONT_PROBE_MIN_DROP_KMH = 10.0
FSCollisionDamage.HEAVY_FRONT_PROBE_MAX_END_SPEED_KMH = 8.0
FSCollisionDamage.HEAVY_FRONT_PROBE_DISTANCE = 4.20
FSCollisionDamage.HEAVY_FRONT_PROBE_STEP = 1.05
FSCollisionDamage.HEAVY_FRONT_PROBE_DEPTH = 0.55
FSCollisionDamage.HEAVY_FRONT_PROBE_SIDE_FRACTION = 0.95
FSCollisionDamage.HEAVY_FRONT_PROBE_SIDE_OFFSET_MAX = 3.20
FSCollisionDamage.HEAVY_FRONT_PROBE_MIN_HEIGHT = 0.25
FSCollisionDamage.HEAVY_FRONT_PROBE_MAX_HEIGHT = 3.40
FSCollisionDamage.HEAVY_FRONT_PROBE_MARGIN_X = 0.08
FSCollisionDamage.HEAVY_FRONT_PROBE_MARGIN_Y = 0.12
FSCollisionDamage.HEAVY_FRONT_PROBE_MARGIN_Z = 0.08

-- Mild braking near the same obstacle is ignored while the vehicle still rolls.
FSCollisionDamage.INFO_LOGGING = false
FSCollisionDamage.DAMAGE_LOGGING = false
FSCollisionDamage.DIAGNOSTIC_LOGGING = false
FSCollisionDamage.DIAGNOSTIC_THROTTLE_MS = 1200
FSCollisionDamage.DIAGNOSTIC_REJECT_SAMPLE_LIMIT = 3
FSCollisionDamage.DIAGNOSTIC_NODE_PATH_MAX_DEPTH = 10
FSCollisionDamage.DIAGNOSTIC_NODE_PATH_MAX_LENGTH = 260

-- Performance guard for diagnostic builds. A previous fallback scanned the full
-- mission vehicle list and parent chains during regular collision checks. That
-- is too expensive on heavily modded saves and can reduce FPS drastically.
FSCollisionDamage.MISSION_VEHICLE_TRAIN_SCAN_ENABLED = false
FSCollisionDamage.HIT_NODE_VEHICLE_SCAN_ENABLED = false
FSCollisionDamage.COLLISION_MAX_TRAIN_VEHICLES = 8
FSCollisionDamage.COLLISION_INCLUDE_DIRECT_ATTACHED_VEHICLES = false
FSCollisionDamage.OWN_NODE_FULL_HIERARCHY_ENABLED = false

FSCollisionDamage.ATTACHMENT_REGISTRY_KEEPALIVE_MS = 2000
FSCollisionDamage.ATTACHMENT_EVENT_SUPPRESSION_MS = 3500
FSCollisionDamage.ATTACHMENT_REGISTRY_MAX_DEPTH = 32

FSCollisionDamage.VEHICLE_REGISTRY_REFRESH_MS = 5000
FSCollisionDamage.VEHICLE_REGISTRY_SOURCE_SCAN_MAX_ENTRIES = 6000
FSCollisionDamage.VEHICLE_REGISTRY_GENERIC_FIELD_SCAN_MAX_FIELDS = 80

-- Permanent map/global collision shapes that must not count as crash targets.
-- Names are checked case-insensitively along the node parent chain.
-- This includes invisible map boundary walls; driving into them should not
-- damage a vehicle like a normal object crash.
FSCollisionDamage.IGNORED_NODE_NAME_PARTS = {
    "waterplane",
    "water_plane",
    "water plane",
    "mapboundaries",
    "mapboundary",
    "map_boundaries",
    "map_boundary",
    "map boundaries",
    "map boundary",
    "grounddivider",
    "ground_divider"
}

-- Interaction triggers are not physical crash targets. They can be large,
-- invisible areas near or behind buildings and may otherwise confirm a crash
-- that actually happened against a wall. Keep this list specific; broad
-- patterns like "trigger" would be too risky.
FSCollisionDamage.IGNORED_TRIGGER_NODE_NAME_PARTS = {
    "filltrigger",
    "loadtrigger",
    "unloadtrigger",
    "selltrigger",
    "buytrigger",
    "purchasetrigger",
    "farmhousetrigger",
    "sleeptrigger",
    "workshoptrigger",
    "repairtrigger",
    "servicetrigger"
}

FSCollisionDamage.IGNORED_TRIGGER_OBJECT_TEXT_PARTS = {
    "filltrigger",
    "loadtrigger",
    "unloadtrigger",
    "selltrigger",
    "buytrigger",
    "farmhousetrigger",
    "workshoptrigger"
}

-- ============================================================
-- Lifecycle
-- ============================================================

function FSCollisionDamage:loadMap()
    self.vehicleStates = setmetatable({}, { __mode = "k" })
    self.isMissionLoaded = true
    self.didLogRuntimeStatus = false
    self.globalCheckTimer = 0
    self:resetVehicleRegistry()
    self:resetAttachmentRegistry()

    self:resetOverlapContext()
    self:resetRaycastContext()
    self.currentDiagnostic = nil
    self:loadDamageMultiplierSetting()
    self:installGameSettingsHooks()
    self:subscribeVehicleRegistryMessages()

    if self.INFO_LOGGING == true then
        print(string.format("[%s] Unfallschaden v%s geladen", self.MOD_NAME, self.VERSION))
    end

    if self.DIAGNOSTIC_LOGGING == true then
        print(string.format("[%s] Diagnose aktiv | Kandidatenbewertung aktiv | Schadenshoehe=%d%%", self.MOD_NAME, math.floor(self:getDamageMultiplier() * 100 + 0.5)))
    end
end

function FSCollisionDamage:deleteMap()
    self:unsubscribeVehicleRegistryMessages()
    self.vehicleStates = nil
    self.isMissionLoaded = false
    self.didLogRuntimeStatus = false
    self.globalCheckTimer = 0
    self:resetVehicleRegistry()
    self:resetAttachmentRegistry()

    self:resetOverlapContext()
    self:resetRaycastContext()
    self.currentDiagnostic = nil
end

function FSCollisionDamage:beginCollisionCheckCache()
    self.currentCheckCache = {
        kinematicsByVehicle = setmetatable({}, { __mode = "k" }),
        trainLookupByVehicle = setmetatable({}, { __mode = "k" }),
        directAttachedLookupByVehicle = setmetatable({}, { __mode = "k" }),
        collisionLookupByVehicle = setmetatable({}, { __mode = "k" }),
        singleAABBByVehicle = setmetatable({}, { __mode = "k" }),
        sensorAABBsByVehicle = setmetatable({}, { __mode = "k" }),
        ownNodeLookupByVehicle = setmetatable({}, { __mode = "k" }),
        attachedOwnNodeLookupByVehicle = setmetatable({}, { __mode = "k" })
    }
end

function FSCollisionDamage:endCollisionCheckCache()
    self.currentCheckCache = nil
end

function FSCollisionDamage:getCheckCacheBucket(bucketName)
    local cache = self.currentCheckCache
    if cache == nil then
        return nil
    end

    local bucket = cache[bucketName]
    if bucket == nil then
        bucket = setmetatable({}, { __mode = "k" })
        cache[bucketName] = bucket
    end

    return bucket
end

function FSCollisionDamage:runGlobalVehicleChecks(dt)
    if self.isMissionLoaded ~= true then
        return
    end

    -- Multiplayer rule: only server/host calculates crashes and writes damage.
    if not self:getIsServerContext() then
        return
    end

    self.globalCheckTimer = (self.globalCheckTimer or 0) + self:normalizeDt(dt)
    if self.globalCheckTimer < self.CHECK_INTERVAL_MS then
        return
    end

    self.globalCheckTimer = 0
    self:beginCollisionCheckCache()

    self:ensureAttachmentRegistryFresh()

    local records, stats = self:collectPrimaryDamageVehicles()
    self.lastVehicleDiscoveryStats = stats

    if not self.didLogRuntimeStatus then
        self.didLogRuntimeStatus = true
        self:logRuntimeStatus(stats)
    end

    if self.DIAGNOSTIC_LOGGING == true then
        self:logVehicleDiscoveryStats(stats)
    end

    for _, record in ipairs(records) do
        local ok, err = pcall(self.checkVehicle, self, record.vehicle, record.state, record.kinematics)
        if not ok then
            print(string.format("[%s] Fehler in Fahrzeugpruefung fuer %s: %s", self.MOD_NAME, tostring(self:getVehicleDebugName(record.vehicle)), tostring(err)))
        end
    end

    self:endCollisionCheckCache()
end

function FSCollisionDamage:appendFunction(baseFunction, appendedFunction)
    if baseFunction == nil then
        return appendedFunction
    end

    if appendedFunction == nil then
        return baseFunction
    end

    -- Do not use Utils.appendedFunction here. Some GIANTS functions, especially
    -- vehicle loading/registration functions, return success values that must be
    -- preserved. Losing those return values can make the game think that a
    -- vehicle failed to load and causes follow-up errors in unrelated systems.
    return function(...)
        local function packResults(...)
            return { n = select("#", ...), ... }
        end

        local results = packResults(baseFunction(...))
        local ok, err = pcall(appendedFunction, ...)
        if not ok and FSCollisionDamage ~= nil then
            print(string.format("[%s] Hook callback failed in appended function: %s", FSCollisionDamage.MOD_NAME or "FS25_CollisionDamage", tostring(err)))
        end

        local unpackFunction = unpack or table.unpack
        if unpackFunction ~= nil then
            return unpackFunction(results, 1, results.n)
        end

        return results[1]
    end
end

function FSCollisionDamage:appendClassFunctionPreserveReturn(classTable, className, functionName, callback, hookedLookup)
    if classTable == nil or functionName == nil or classTable[functionName] == nil then
        return false
    end

    local hookKey = tostring(className) .. ":" .. tostring(functionName)
    if hookedLookup ~= nil and hookedLookup[hookKey] == true then
        return false
    end

    classTable[functionName] = self:appendFunction(classTable[functionName], callback)

    if hookedLookup ~= nil then
        hookedLookup[hookKey] = true
    end

    return true
end

-- ============================================================
-- Game settings integration
-- ============================================================

function FSCollisionDamage.gameSettingsFrameOnOpen(frame, ...)
    if FSCollisionDamage ~= nil then
        FSCollisionDamage:addGameSettingsElement(frame)
        FSCollisionDamage:updateGameSettingsElement(frame)
    end
end

function FSCollisionDamage.gameSettingsFrameUpdate(frame, ...)
    if FSCollisionDamage ~= nil then
        FSCollisionDamage:updateGameSettingsElement(frame)
    end
end

function FSCollisionDamage:installGameSettingsHooks()
    if self.gameSettingsHooksInstalled == true then
        return
    end

    local frameClass = InGameMenuSettingsFrame
    if frameClass == nil then
        return
    end

    self.gameSettingsHookedFunctions = self.gameSettingsHookedFunctions or {}
    local installed = false

    if self:appendClassFunctionPreserveReturn(frameClass, "InGameMenuSettingsFrame", "onFrameOpen", FSCollisionDamage.gameSettingsFrameOnOpen, self.gameSettingsHookedFunctions) then
        installed = true
    end

    if self:appendClassFunctionPreserveReturn(frameClass, "InGameMenuSettingsFrame", "updateGameSettings", FSCollisionDamage.gameSettingsFrameUpdate, self.gameSettingsHookedFunctions) then
        installed = true
    end

    self.gameSettingsHooksInstalled = installed
end

function FSCollisionDamage:update(dt)
    if self.gameSettingsHooksInstalled ~= true then
        self:installGameSettingsHooks()
    end

    if self.isMissionLoaded == true and self.vehicleRegistryMessageSubscriptionsInstalled ~= true then
        self:subscribeVehicleRegistryMessages()
    end

    self:runGlobalVehicleChecks(dt)
end

function FSCollisionDamage:addGameSettingsElement(frame)
    if frame == nil or frame.fsCollisionDamageInitDone == true then
        return
    end

    local layout = frame.gameSettingsLayout
    if layout == nil or layout.addElement == nil then
        return
    end

    if TextElement == nil or BitmapElement == nil or MultiTextOptionElement == nil or g_gui == nil or g_gui.getProfile == nil then
        return
    end

    self:loadDamageMultiplierSetting()

    local section = self:createGameSettingsSection()
    if section == nil then
        return
    end

    local option, container = self:createGameSettingsMultiTextOption(
        "onDamageMultiplierSettingsChanged",
        self.DAMAGE_MULTIPLIER_TEXTS,
        self:getI18nText("setting_collisionDamageMultiplier", "Unfallschaden: Schadenshoehe"),
        self:getI18nText(
            "setting_collisionDamageMultiplier_desc",
            "Legt fest, wie stark der zusaetzliche Unfallschaden ausfaellt. 100 Prozent entspricht der Standardwirkung."
        )
    )

    if option == nil or container == nil then
        return
    end

    layout:addElement(section)
    section:onGuiSetupFinished()

    layout:addElement(container)
    container:onGuiSetupFinished()

    frame.fsCollisionDamageSection = section
    frame.fsCollisionDamageMultiplierElement = option
    frame.fsCollisionDamageMultiplierContainer = container
    frame.fsCollisionDamageInitDone = true

    self:refreshGameSettingsLayout(frame, layout)
    self:updateGameSettingsElement(frame)
end

function FSCollisionDamage:createGameSettingsSection()
    local profile = g_gui:getProfile("fs25_settingsSectionHeader")
    if profile == nil then
        return nil
    end

    local textElement = TextElement.new()
    if textElement == nil or textElement.loadProfile == nil then
        return nil
    end

    textElement.name = "sectionHeader"
    textElement:loadProfile(profile, true)

    if textElement.setText ~= nil then
        textElement:setText(self:getI18nText("setting_collisionDamageSection", "Unfallschaden"))
    end

    return textElement
end

function FSCollisionDamage:createGameSettingsMultiTextOption(onClickCallback, texts, title, tooltip)
    local containerProfile = g_gui:getProfile("fs25_multiTextOptionContainer")
    local optionProfile = g_gui:getProfile("fs25_settingsMultiTextOption")
    local titleProfile = g_gui:getProfile("fs25_settingsMultiTextOptionTitle")
    local tooltipProfile = g_gui:getProfile("fs25_multiTextOptionTooltip")

    if containerProfile == nil or optionProfile == nil or titleProfile == nil or tooltipProfile == nil then
        return nil, nil
    end

    local container = BitmapElement.new()
    if container == nil or container.loadProfile == nil then
        return nil, nil
    end
    container:loadProfile(containerProfile, true)

    local option = MultiTextOptionElement.new()
    if option == nil or option.loadProfile == nil then
        return nil, nil
    end
    option:loadProfile(optionProfile, true)
    option.target = FSCollisionDamage

    if option.setCallback ~= nil then
        option:setCallback("onClickCallback", onClickCallback)
    end

    if option.setTexts ~= nil then
        option:setTexts(texts)
    end

    local titleElement = TextElement.new()
    if titleElement == nil or titleElement.loadProfile == nil then
        return nil, nil
    end
    titleElement:loadProfile(titleProfile, true)
    if titleElement.setText ~= nil then
        titleElement:setText(title)
    end

    local tooltipElement = TextElement.new()
    if tooltipElement == nil or tooltipElement.loadProfile == nil then
        return nil, nil
    end
    tooltipElement.name = "ignore"
    tooltipElement:loadProfile(tooltipProfile, true)
    if tooltipElement.setText ~= nil then
        tooltipElement:setText(tooltip)
    end

    option:addElement(tooltipElement)
    container:addElement(option)
    container:addElement(titleElement)

    option:onGuiSetupFinished()
    titleElement:onGuiSetupFinished()
    tooltipElement:onGuiSetupFinished()

    return option, container
end

function FSCollisionDamage:updateGameSettingsElement(frame)
    if frame == nil or frame.fsCollisionDamageInitDone ~= true or frame.fsCollisionDamageMultiplierElement == nil then
        return
    end

    self:loadDamageMultiplierSetting()

    local option = frame.fsCollisionDamageMultiplierElement
    self.isUpdatingSettingsUi = true

    if option.setTexts ~= nil then
        option:setTexts(self.DAMAGE_MULTIPLIER_TEXTS)
    end

    if option.setState ~= nil then
        option:setState(self:getDamageMultiplierState())
    end

    if option.setDisabled ~= nil then
        option:setDisabled(false)
    end

    self.isUpdatingSettingsUi = false

    if frame.fsCollisionDamageMultiplierContainer ~= nil and frame.fsCollisionDamageMultiplierContainer.setVisible ~= nil then
        frame.fsCollisionDamageMultiplierContainer:setVisible(true)
    end
end

function FSCollisionDamage:refreshGameSettingsLayout(frame, layout)
    if layout ~= nil and layout.invalidateLayout ~= nil then
        layout:invalidateLayout()
    end

    if frame ~= nil and frame.updateAlternatingElements ~= nil and layout ~= nil then
        frame:updateAlternatingElements(layout)
    end
end

function FSCollisionDamage:onDamageMultiplierSettingsChanged(state)
    if self.isUpdatingSettingsUi == true then
        return
    end

    state = tonumber(state)

    if state == nil and g_gui ~= nil and g_gui.currentGui ~= nil then
        local gui = g_gui.currentGui
        local page = gui.target ~= nil and gui.target.currentPage or nil
        local option = page ~= nil and page.fsCollisionDamageMultiplierElement or nil
        if option ~= nil and option.getState ~= nil then
            state = tonumber(option:getState())
        end
    end

    self:setDamageMultiplierState(state, true)
end

function FSCollisionDamage:setDamageMultiplierState(state, save)
    state = tonumber(state) or self.DAMAGE_MULTIPLIER_DEFAULT_STATE
    state = math.floor(state + 0.5)
    state = math.min(#self.DAMAGE_MULTIPLIER_OPTIONS, math.max(1, state))

    self.damageMultiplierState = state
    self.DAMAGE_MULTIPLIER = tonumber(self.DAMAGE_MULTIPLIER_OPTIONS[state]) or 1.0

    if save == true then
        self:saveDamageMultiplierSetting()
    end
end

function FSCollisionDamage:getDamageMultiplierState()
    if self.damageMultiplierState == nil then
        self:setDamageMultiplierState(self.DAMAGE_MULTIPLIER_DEFAULT_STATE, false)
    end

    return self.damageMultiplierState
end

function FSCollisionDamage:getSettingsFilePath()
    if getUserProfileAppPath == nil then
        return nil
    end

    return getUserProfileAppPath() .. "modSettings/FS25_CollisionDamage/settings.xml"
end

function FSCollisionDamage:ensureSettingsFolder()
    if getUserProfileAppPath == nil or createFolder == nil then
        return
    end

    createFolder(getUserProfileAppPath() .. "modSettings")
    createFolder(getUserProfileAppPath() .. "modSettings/FS25_CollisionDamage")
end

function FSCollisionDamage:loadDamageMultiplierSetting()
    if self.damageMultiplierSettingLoaded == true then
        return
    end

    self.damageMultiplierSettingLoaded = true

    local loadedState = nil
    local filePath = self:getSettingsFilePath()

    if filePath ~= nil and fileExists ~= nil and fileExists(filePath) and XMLFile ~= nil and XMLFile.loadIfExists ~= nil then
        local xmlFile = XMLFile.loadIfExists("FSCollisionDamageSettings", filePath)
        if xmlFile ~= nil then
            if xmlFile.getInt ~= nil then
                loadedState = xmlFile:getInt("collisionDamage.settings#damageMultiplierState")
            end

            if loadedState == nil and xmlFile.getFloat ~= nil then
                local loadedMultiplier = xmlFile:getFloat("collisionDamage.settings#damageMultiplier")
                loadedState = self:getStateForDamageMultiplier(loadedMultiplier)
            end

            xmlFile:delete()
        end
    end

    self:setDamageMultiplierState(loadedState or self.DAMAGE_MULTIPLIER_DEFAULT_STATE, false)
end

function FSCollisionDamage:saveDamageMultiplierSetting()
    local filePath = self:getSettingsFilePath()
    if filePath == nil or XMLFile == nil or XMLFile.create == nil then
        return
    end

    self:ensureSettingsFolder()

    local xmlFile = XMLFile.create("FSCollisionDamageSettings", filePath, "collisionDamage")
    if xmlFile ~= nil then
        if xmlFile.setInt ~= nil then
            xmlFile:setInt("collisionDamage.settings#damageMultiplierState", self:getDamageMultiplierState())
        end

        if xmlFile.setFloat ~= nil then
            xmlFile:setFloat("collisionDamage.settings#damageMultiplier", self:getDamageMultiplier())
        end

        if xmlFile.save ~= nil then
            xmlFile:save()
        end

        xmlFile:delete()
    end
end

function FSCollisionDamage:getStateForDamageMultiplier(multiplier)
    multiplier = tonumber(multiplier)
    if multiplier == nil then
        return nil
    end

    local bestState = self.DAMAGE_MULTIPLIER_DEFAULT_STATE
    local bestDistance = math.huge

    for state, option in ipairs(self.DAMAGE_MULTIPLIER_OPTIONS) do
        local distance = math.abs((tonumber(option) or 0) - multiplier)
        if distance < bestDistance then
            bestDistance = distance
            bestState = state
        end
    end

    return bestState
end

function FSCollisionDamage:getI18nText(key, fallback)
    if key ~= nil and g_i18n ~= nil and g_i18n.getText ~= nil then
        local text = g_i18n:getText(key)
        if text ~= nil and text ~= "" and text ~= key then
            return text
        end
    end

    return fallback or tostring(key or "")
end

-- Try early. loadMap tries again if the relevant game classes were not ready yet.
FSCollisionDamage:installGameSettingsHooks()

-- ============================================================
-- Debug diagnostics
-- ============================================================

function FSCollisionDamage:isValidVehicle(vehicle)
    if vehicle == nil or vehicle.rootNode == nil then
        return false
    end

    if vehicle.isServer == false then
        return false
    end

    if vehicle.spec_motorized == nil then
        return false
    end

    if vehicle.spec_wearable == nil then
        return false
    end

    return vehicle.setDamageAmount ~= nil or vehicle.addDamageAmount ~= nil
end

function FSCollisionDamage:isPrimaryVehicleForDamageCheck(vehicle)
    if vehicle == nil then
        return false
    end

    return self:getVehicleTrainRoot(vehicle) == vehicle
end

function FSCollisionDamage:getVehicleTrainRoot(vehicle)
    vehicle = self:resolveVehicleObject(vehicle) or vehicle
    if vehicle == nil then
        return nil
    end

    if vehicle.getRootVehicle ~= nil then
        local ok, nativeRoot = pcall(vehicle.getRootVehicle, vehicle)
        nativeRoot = ok and (self:resolveVehicleObject(nativeRoot) or nativeRoot) or nil
        if nativeRoot ~= nil and nativeRoot.rootNode ~= nil then
            return nativeRoot
        end
    end

    local registeredRoot = self:getRegisteredVehicleTrainRoot(vehicle)
    if registeredRoot ~= nil and registeredRoot ~= vehicle then
        return registeredRoot
    end

    local root = vehicle
    local guard = 0
    while root ~= nil and guard < 16 do
        local parent = self:getVehicleParent(root)
        if parent == nil or parent == root then
            break
        end

        root = parent
        guard = guard + 1
    end

    return root
end

function FSCollisionDamage:getVehicleParent(vehicle)
    vehicle = self:resolveVehicleObject(vehicle) or vehicle
    if vehicle == nil then
        return nil
    end

    if vehicle.getParentVehicle ~= nil then
        local ok, parent = pcall(vehicle.getParentVehicle, vehicle)
        if ok and parent ~= nil and parent ~= vehicle then
            return self:resolveVehicleObject(parent) or parent
        end
    end

    if vehicle.attacherVehicle ~= nil and vehicle.attacherVehicle ~= vehicle then
        return self:resolveVehicleObject(vehicle.attacherVehicle) or vehicle.attacherVehicle
    end

    local specAttachable = vehicle.spec_attachable
    if specAttachable ~= nil then
        if specAttachable.attacherVehicle ~= nil and specAttachable.attacherVehicle ~= vehicle then
            return self:resolveVehicleObject(specAttachable.attacherVehicle) or specAttachable.attacherVehicle
        end

        if specAttachable.attacherJoint ~= nil then
            local candidate = specAttachable.attacherJoint.vehicle or specAttachable.attacherJoint.object
            if candidate ~= nil and candidate ~= vehicle then
                return self:resolveVehicleObject(candidate) or candidate
            end
        end

        if specAttachable.inputAttacherJoint ~= nil then
            local candidate = specAttachable.inputAttacherJoint.vehicle or specAttachable.inputAttacherJoint.object
            if candidate ~= nil and candidate ~= vehicle then
                return self:resolveVehicleObject(candidate) or candidate
            end
        end
    end

    if vehicle.getRootVehicle ~= nil then
        local ok, root = pcall(vehicle.getRootVehicle, vehicle)
        if ok and root ~= nil and root ~= vehicle then
            return self:resolveVehicleObject(root) or root
        end
    end

    return nil
end

function FSCollisionDamage:buildVehicleTrainVehicleLookup(vehicle)
    local cache = self:getCheckCacheBucket("trainLookupByVehicle")
    if cache ~= nil and cache[vehicle] ~= nil then
        return cache[vehicle]
    end

    local rootVehicle = self:getVehicleTrainRoot(vehicle) or vehicle
    local vehicleLookup = {}
    if rootVehicle ~= nil then
        vehicleLookup[rootVehicle] = true
    end
    if vehicle ~= nil then
        vehicleLookup[vehicle] = true
    end

    local nativeChildListAvailable = false
    if rootVehicle ~= nil and rootVehicle.getChildVehicles ~= nil then
        local ok, childVehicles = pcall(rootVehicle.getChildVehicles, rootVehicle)
        if ok and type(childVehicles) == "table" then
            nativeChildListAvailable = true
            for _, childVehicle in pairs(childVehicles) do
                childVehicle = self:resolveVehicleObject(childVehicle) or childVehicle
                if type(childVehicle) == "table" and childVehicle.rootNode ~= nil then
                    vehicleLookup[childVehicle] = true
                end
            end
        end
    end

    if not nativeChildListAvailable then
        if self.isRefreshingAttachmentRegistry ~= true then
            self:ensureAttachmentRegistryFresh()
        end
        self:addVehicleTrainVehicleToLookup(rootVehicle, vehicleLookup, 0)
        self:addRegisteredAttachedVehiclesToLookup(rootVehicle, vehicleLookup)
        self:addRegisteredAttachedVehiclesToLookup(vehicle, vehicleLookup)
    end

    if self.MISSION_VEHICLE_TRAIN_SCAN_ENABLED == true then
        self:addMissionVehiclesFromSameTrainToLookup(rootVehicle, vehicleLookup)
    end

    if cache ~= nil then
        cache[vehicle] = vehicleLookup
        if rootVehicle ~= nil then
            cache[rootVehicle] = vehicleLookup
        end
    end

    return vehicleLookup
end

function FSCollisionDamage:addMissionVehiclesFromSameTrainToLookup(rootVehicle, vehicleLookup)
    if rootVehicle == nil or vehicleLookup == nil or g_currentMission == nil or g_currentMission.vehicles == nil then
        return
    end

    for _, candidate in pairs(g_currentMission.vehicles) do
        if type(candidate) == "table" and candidate.rootNode ~= nil and vehicleLookup[candidate] ~= true then
            local candidateRoot = self:getVehicleTrainRoot(candidate) or candidate
            if candidateRoot == rootVehicle or self:isRegisteredAttachedVehicleConnected(rootVehicle, candidate) then
                self:addVehicleTrainVehicleToLookup(candidate, vehicleLookup, 0)
            elseif candidate.getRootVehicle ~= nil then
                local nativeRoot = candidate:getRootVehicle()
                if nativeRoot ~= nil then
                    local normalizedNativeRoot = self:getVehicleTrainRoot(nativeRoot) or nativeRoot
                    if normalizedNativeRoot == rootVehicle then
                        self:addVehicleTrainVehicleToLookup(candidate, vehicleLookup, 0)
                    end
                end
            end
        end
    end
end

function FSCollisionDamage:addVehicleTrainVehicleToLookup(vehicle, vehicleLookup, depth)
    if type(vehicle) ~= "table" or vehicleLookup == nil or depth > 16 then
        return
    end

    if vehicleLookup[vehicle] == true then
        return
    end

    vehicleLookup[vehicle] = true

    local parent = self:getVehicleParent(vehicle)
    if parent ~= nil then
        self:addVehicleTrainVehicleToLookup(parent, vehicleLookup, depth + 1)
    end

    local attachedVehicles = self:getDirectAttachedVehicleLookup(vehicle)
    for attachedVehicle, _ in pairs(attachedVehicles) do
        self:addVehicleTrainVehicleToLookup(attachedVehicle, vehicleLookup, depth + 1)
    end
end

function FSCollisionDamage:getDirectAttachedVehicleLookup(vehicle)
    local cache = self:getCheckCacheBucket("directAttachedLookupByVehicle")
    if cache ~= nil and cache[vehicle] ~= nil then
        return cache[vehicle]
    end

    local vehicleLookup = {}
    if vehicle == nil then
        return vehicleLookup
    end

    local function addCandidate(candidate)
        if candidate == nil or candidate == vehicle then
            return
        end

        candidate = self:resolveVehicleObject(candidate) or candidate
        if type(candidate) == "table" and candidate ~= vehicle and candidate.rootNode ~= nil then
            vehicleLookup[candidate] = true
        end
    end

    local function addCandidatesFromAttachmentEntry(entry, depth, visited)
        if entry == nil or depth > 5 then
            return
        end

        addCandidate(entry)
        if type(entry) ~= "table" then
            return
        end

        visited = visited or {}
        if visited[entry] == true then
            return
        end
        visited[entry] = true

        for key, child in pairs(entry) do
            local keyText = string.lower(tostring(key or ""))
            if depth < 2
                or string.find(keyText, "attach", 1, true) ~= nil
                or string.find(keyText, "vehicle", 1, true) ~= nil
                or string.find(keyText, "implement", 1, true) ~= nil
                or string.find(keyText, "joint", 1, true) ~= nil
                or string.find(keyText, "object", 1, true) ~= nil
                or string.find(keyText, "root", 1, true) ~= nil
                or string.find(keyText, "parent", 1, true) ~= nil then
                addCandidatesFromAttachmentEntry(child, depth + 1, visited)
            end
        end
    end

    if vehicle.getAttachedImplements ~= nil then
        local ok, attachedImplements = pcall(vehicle.getAttachedImplements, vehicle)
        if ok and type(attachedImplements) == "table" then
            for _, implement in pairs(attachedImplements) do
                addCandidatesFromAttachmentEntry(implement, 0)
            end
        end
    end

    local specAttacherJoints = vehicle.spec_attacherJoints
    if specAttacherJoints ~= nil then
        if specAttacherJoints.attachedImplements ~= nil then
            for _, implement in pairs(specAttacherJoints.attachedImplements) do
                addCandidatesFromAttachmentEntry(implement, 0)
            end
        end

        if specAttacherJoints.attacherJoints ~= nil then
            for _, attacherJoint in pairs(specAttacherJoints.attacherJoints) do
                addCandidatesFromAttachmentEntry(attacherJoint, 0)
            end
        end
    end

    if cache ~= nil then
        cache[vehicle] = vehicleLookup
    end

    return vehicleLookup
end

function FSCollisionDamage:isObjectInCurrentVehicleTrain(object)
    if type(object) ~= "table" then
        return false
    end

    if self.currentVehicleTrainVehicles ~= nil and self.currentVehicleTrainVehicles[object] == true then
        return true
    end

    if self.currentVehicle ~= nil and self:isKnownAttachedOrSameTrain(self.currentVehicle, object) then
        return true
    end

    if self.currentVehicleTrainRoot ~= nil and object.getRootVehicle ~= nil then
        local objectRoot = self:getVehicleTrainRoot(object:getRootVehicle() or object)
        if objectRoot == self.currentVehicleTrainRoot then
            return true
        end
    elseif self.currentVehicleTrainRoot ~= nil and object.rootNode ~= nil then
        local objectRoot = self:getVehicleTrainRoot(object)
        if objectRoot == self.currentVehicleTrainRoot then
            return true
        end
    end

    if self.currentVehicleTrainVehicles ~= nil then
        for trainVehicle, _ in pairs(self.currentVehicleTrainVehicles) do
            if object.getIsAttachedTo ~= nil and object:getIsAttachedTo(trainVehicle) then
                return true
            end

            if trainVehicle.getIsAttachedTo ~= nil and trainVehicle:getIsAttachedTo(object) then
                return true
            end
        end
    end

    return false
end


-- ============================================================
-- Passive vehicle discovery/registry
-- ============================================================

function FSCollisionDamage:resetVehicleRegistry()
    self.vehicleRegistry = setmetatable({}, { __mode = "k" })
    self.vehicleRegistrySources = setmetatable({}, { __mode = "k" })
    self.vehicleRegistryDirty = true
    self.lastVehicleRegistryRefreshTime = -100000
    self.lastVehicleDiscoveryStats = nil
end

function FSCollisionDamage:subscribeVehicleRegistryMessages()
    if self.vehicleRegistryMessageSubscriptionsInstalled == true then
        return
    end

    if g_messageCenter == nil or MessageType == nil then
        return
    end

    local subscribed = false
    if MessageType.VEHICLE_ADDED ~= nil then
        g_messageCenter:subscribe(MessageType.VEHICLE_ADDED, self.onVehicleRegistryMessage, self)
        subscribed = true
    end
    if MessageType.VEHICLE_REMOVED ~= nil then
        g_messageCenter:subscribe(MessageType.VEHICLE_REMOVED, self.onVehicleRegistryMessage, self)
        subscribed = true
    end

    self.vehicleRegistryMessageSubscriptionsInstalled = subscribed
end

function FSCollisionDamage:unsubscribeVehicleRegistryMessages()
    if self.vehicleRegistryMessageSubscriptionsInstalled == true and g_messageCenter ~= nil and g_messageCenter.unsubscribeAll ~= nil then
        g_messageCenter:unsubscribeAll(self)
    end

    self.vehicleRegistryMessageSubscriptionsInstalled = false
end

function FSCollisionDamage:onVehicleRegistryMessage(...)
    self.vehicleRegistryDirty = true
    self:markAttachmentRegistryDirty()
end

function FSCollisionDamage:isVehicleLikeObject(value)
    if type(value) ~= "table" then
        return false
    end

    if value.rootNode == nil then
        return false
    end

    return value.spec_motorized ~= nil
        or value.spec_wearable ~= nil
        or value.components ~= nil
        or value.getLastSpeed ~= nil
        or value.getRootVehicle ~= nil
        or value.setDamageAmount ~= nil
        or value.addDamageAmount ~= nil
end

function FSCollisionDamage:registerVehicleCandidate(value, source)
    local vehicle = self:resolveVehicleObject(value)
    if vehicle == nil and self:isVehicleLikeObject(value) then
        vehicle = value
    end

    if vehicle == nil or not self:isVehicleLikeObject(vehicle) then
        return nil
    end

    self.vehicleRegistry = self.vehicleRegistry or setmetatable({}, { __mode = "k" })
    self.vehicleRegistrySources = self.vehicleRegistrySources or setmetatable({}, { __mode = "k" })
    self.vehicleRegistry[vehicle] = true
    self.vehicleRegistrySources[vehicle] = tostring(source or "unknown")
    return vehicle
end

function FSCollisionDamage:scanVehicleContainer(container, sourceName, stats, callback)
    stats = stats or {}
    if container == nil or type(container) ~= "table" then
        return 0
    end

    local scanned = 0
    local found = 0
    local maxEntries = self.VEHICLE_REGISTRY_SOURCE_SCAN_MAX_ENTRIES or 6000

    for _, entry in pairs(container) do
        scanned = scanned + 1
        if scanned > maxEntries then
            break
        end

        local vehicle = nil
        if self:isVehicleLikeObject(entry) then
            vehicle = entry
        else
            vehicle = self:resolveVehicleObject(entry)
        end

        if vehicle ~= nil and self:isVehicleLikeObject(vehicle) then
            found = found + 1
            if callback ~= nil then
                callback(vehicle, sourceName)
            end
        end
    end

    stats[sourceName .. "Scanned"] = scanned
    stats[sourceName .. "Found"] = found
    return found
end

function FSCollisionDamage:scanNamedVehicleFields(container, containerName, stats, callback)
    if container == nil or type(container) ~= "table" then
        return
    end

    local scannedFields = 0
    local maxFields = self.VEHICLE_REGISTRY_GENERIC_FIELD_SCAN_MAX_FIELDS or 80

    for key, value in pairs(container) do
        scannedFields = scannedFields + 1
        if scannedFields > maxFields then
            break
        end

        local keyText = string.lower(tostring(key or ""))
        if string.find(keyText, "vehicle", 1, true) ~= nil
            or keyText == "controlledvehicle"
            or keyText == "currentvehicle"
            or keyText == "enteredvehicle" then

            if self:isVehicleLikeObject(value) then
                if callback ~= nil then
                    callback(value, containerName .. "." .. tostring(key))
                end
                stats[(containerName or "container") .. "NamedFieldFound"] = (stats[(containerName or "container") .. "NamedFieldFound"] or 0) + 1
            elseif type(value) == "table" then
                self:scanVehicleContainer(value, containerName .. "." .. tostring(key), stats, callback)
            end
        end
    end

    stats[(containerName or "container") .. "FieldsScanned"] = scannedFields
end

function FSCollisionDamage:refreshVehicleRegistryFromMissionSources(force)
    local now = g_time or 0
    if force ~= true and self.vehicleRegistryDirty ~= true and now - (self.lastVehicleRegistryRefreshTime or -100000) < (self.VEHICLE_REGISTRY_REFRESH_MS or 5000) then
        return self.lastVehicleDiscoveryStats
    end

    self.vehicleRegistry = setmetatable({}, { __mode = "k" })
    self.vehicleRegistrySources = setmetatable({}, { __mode = "k" })

    local stats = {}
    local mission = g_currentMission
    local vehicleSystem = mission ~= nil and (mission.vehicleSystem or g_vehicleSystem) or g_vehicleSystem

    local function register(vehicle, sourceName)
        self:registerVehicleCandidate(vehicle, sourceName)
    end

    if vehicleSystem ~= nil then
        self:scanVehicleContainer(vehicleSystem.vehicles, "vehicleSystemVehicles", stats, register)
        self:scanVehicleContainer(vehicleSystem.ownedVehicles, "vehicleSystemOwnedVehicles", stats, register)
    end

    if mission ~= nil then
        self:scanVehicleContainer(mission.vehicles, "missionVehicles", stats, register)
        self:scanVehicleContainer(mission.controlledVehicles, "missionControlledVehicles", stats, register)

        self:registerVehicleCandidate(mission.controlledVehicle, "mission.controlledVehicle")
        self:registerVehicleCandidate(mission.currentVehicle, "mission.currentVehicle")
        self:registerVehicleCandidate(mission.enteredVehicle, "mission.enteredVehicle")

        if mission.player ~= nil then
            self:registerVehicleCandidate(mission.player.controlledVehicle, "mission.player.controlledVehicle")
            self:registerVehicleCandidate(mission.player.currentVehicle, "mission.player.currentVehicle")
            self:registerVehicleCandidate(mission.player.enteredVehicle, "mission.player.enteredVehicle")
        end
    end

    local discovered = (stats.vehicleSystemVehiclesFound or 0)
        + (stats.vehicleSystemOwnedVehiclesFound or 0)
        + (stats.missionVehiclesFound or 0)
        + (stats.missionControlledVehiclesFound or 0)

    if self.DIAGNOSTIC_LOGGING == true or discovered == 0 then
        if vehicleSystem ~= nil then
            self:scanVehicleContainer(vehicleSystem.vehicleByUniqueId, "vehicleSystemVehicleByUniqueId", stats, register)
            self:scanVehicleContainer(vehicleSystem.vehicleById, "vehicleSystemVehicleById", stats, register)
            self:scanVehicleContainer(vehicleSystem.vehiclesById, "vehicleSystemVehiclesById", stats, register)
            self:scanNamedVehicleFields(vehicleSystem, "vehicleSystem", stats, register)
        end

        if mission ~= nil then
            self:scanVehicleContainer(mission.nodeToObject, "missionNodeToObject", stats, register)
            self:scanNamedVehicleFields(mission, "mission", stats, register)
        end
    end

    if g_vehicleSystem ~= nil and g_vehicleSystem ~= vehicleSystem then
        self:scanVehicleContainer(g_vehicleSystem.vehicles, "globalVehicleSystemVehicles", stats, register)
        self:scanVehicleContainer(g_vehicleSystem.ownedVehicles, "globalVehicleSystemOwnedVehicles", stats, register)
        if self.DIAGNOSTIC_LOGGING == true then
            self:scanNamedVehicleFields(g_vehicleSystem, "globalVehicleSystem", stats, register)
        end
    end

    self.lastVehicleRegistryRefreshTime = now
    self.vehicleRegistryDirty = false
    self.lastVehicleDiscoveryStats = stats
    return stats
end

function FSCollisionDamage:collectVehicleCandidates()
    local stats = self:refreshVehicleRegistryFromMissionSources(false) or {}
    local vehicles = {}
    local lookup = {}

    local function add(vehicle, sourceName)
        vehicle = self:resolveVehicleObject(vehicle) or vehicle
        if vehicle ~= nil and self:isVehicleLikeObject(vehicle) and lookup[vehicle] ~= true then
            lookup[vehicle] = true
            table.insert(vehicles, vehicle)
            self:registerVehicleCandidate(vehicle, sourceName or "candidate")
        end
    end

    if self.vehicleRegistry ~= nil then
        for vehicle, _ in pairs(self.vehicleRegistry) do
            add(vehicle, "registry")
        end
    end

    local mission = g_currentMission
    if mission ~= nil then
        add(mission.controlledVehicle, "mission.controlledVehicle.live")
        add(mission.currentVehicle, "mission.currentVehicle.live")
        add(mission.enteredVehicle, "mission.enteredVehicle.live")

        if mission.player ~= nil then
            add(mission.player.controlledVehicle, "mission.player.controlledVehicle.live")
            add(mission.player.currentVehicle, "mission.player.currentVehicle.live")
            add(mission.player.enteredVehicle, "mission.player.enteredVehicle.live")
        end
    end

    if #vehicles == 0 and mission ~= nil then
        self:scanVehicleContainer(mission.vehicles, "missionVehiclesFallback", stats, add)
        local vehicleSystem = mission.vehicleSystem or g_vehicleSystem
        if vehicleSystem ~= nil then
            self:scanVehicleContainer(vehicleSystem.vehicles, "vehicleSystemVehiclesFallback", stats, add)
        end
    end

    stats.registryVehicles = 0
    if self.vehicleRegistry ~= nil then
        for vehicle, _ in pairs(self.vehicleRegistry) do
            if vehicle ~= nil then
                stats.registryVehicles = stats.registryVehicles + 1
            end
        end
    end

    stats.uniqueCandidateVehicles = #vehicles
    self.lastVehicleDiscoveryStats = stats
    return vehicles, stats
end

function FSCollisionDamage:collectPrimaryDamageVehicles()
    local vehicles, stats = self:collectVehicleCandidates()
    local records = {}

    stats.validVehicles = 0
    stats.validPrimaryVehicles = 0
    stats.validTrackedVehicles = 0

    for _, vehicle in ipairs(vehicles) do
        if self:isValidVehicle(vehicle) then
            stats.validVehicles = stats.validVehicles + 1
            if self:isPrimaryVehicleForDamageCheck(vehicle) then
                stats.validPrimaryVehicles = stats.validPrimaryVehicles + 1
                local state = self:getVehicleState(vehicle)
                local kinematics = self:getVehicleKinematics(vehicle)
                local speed = kinematics ~= nil and kinematics.speed or nil
                if speed ~= nil and (speed >= (self.MIN_TRACK_SPEED_KMH or 0.5) or state.lastSpeed ~= nil) then
                    stats.validTrackedVehicles = stats.validTrackedVehicles + 1
                end
                table.insert(records, {
                    vehicle = vehicle,
                    state = state,
                    kinematics = kinematics
                })
            end
        end
    end

    self.lastVehicleDiscoveryStats = stats
    return records, stats
end

function FSCollisionDamage:logVehicleDiscoveryStats(stats)
    if stats == nil or self.INFO_LOGGING ~= true then
        return
    end

    local now = g_time or 0
    if self.lastVehicleDiscoveryLogTime ~= nil and now - self.lastVehicleDiscoveryLogTime < 2500 then
        return
    end
    self.lastVehicleDiscoveryLogTime = now

    print(string.format(
        "[%s] DEBUG-Fahrzeugquellen | mission=%d/%d | vehicleSystem=%d/%d | vehicleSystemOwned=%d/%d | nodeToObject=%d/%d | registry=%d | eindeutig=%d | valid=%d | primary=%d | tracked=%d",
        self.MOD_NAME,
        stats.missionVehiclesFound or stats.missionVehiclesLiveFound or 0,
        stats.missionVehiclesScanned or stats.missionVehiclesLiveScanned or 0,
        stats.vehicleSystemVehiclesFound or stats.vehicleSystemVehiclesLiveFound or 0,
        stats.vehicleSystemVehiclesScanned or stats.vehicleSystemVehiclesLiveScanned or 0,
        stats.vehicleSystemOwnedVehiclesFound or stats.vehicleSystemOwnedVehiclesLiveFound or 0,
        stats.vehicleSystemOwnedVehiclesScanned or stats.vehicleSystemOwnedVehiclesLiveScanned or 0,
        stats.missionNodeToObjectFound or 0,
        stats.missionNodeToObjectScanned or 0,
        stats.registryVehicles or 0,
        stats.uniqueCandidateVehicles or 0,
        stats.validVehicles or 0,
        stats.validPrimaryVehicles or 0,
        stats.validTrackedVehicles or 0
    ))
end


function FSCollisionDamage:resetAttachmentRegistry()
    self.attachedVehiclePairs = setmetatable({}, { __mode = "k" })
    self.attachedVehicleParents = setmetatable({}, { __mode = "k" })
    self.attachedVehiclePairLastSeen = setmetatable({}, { __mode = "k" })
    self.recentAttachmentActivity = setmetatable({}, { __mode = "k" })
    self.lastAttachmentRegistryRefreshTime = -100000
    self.attachmentRegistryDirty = true
    self.isRefreshingAttachmentRegistry = false
end

function FSCollisionDamage:markAttachmentRegistryDirty()
    self.attachmentRegistryDirty = true
end

function FSCollisionDamage:markVehicleAttachmentActivity(vehicle, now, reason)
    vehicle = self:resolveVehicleObject(vehicle)
    if vehicle == nil then
        return
    end

    now = now or g_time or 0
    self.recentAttachmentActivity = self.recentAttachmentActivity or setmetatable({}, { __mode = "k" })

    local function mark(candidate)
        candidate = self:resolveVehicleObject(candidate)
        if candidate == nil then
            return
        end

        self.recentAttachmentActivity[candidate] = now

        if self.vehicleStates ~= nil then
            local state = self:getVehicleState(candidate)
            state.attachmentSuppressionUntil = now + (self.ATTACHMENT_EVENT_SUPPRESSION_MS or 9000)
            state.speedReference = nil
            state.sustainedSpeedReference = nil
        end
    end

    mark(vehicle)

    local rootVehicle = self:getVehicleTrainRoot(vehicle)
    if rootVehicle ~= nil then
        mark(rootVehicle)
    end

    if self.attachmentRegistryDirty ~= true then
        local nativeRoot = self:getRegisteredVehicleTrainRoot(vehicle)
        if nativeRoot ~= nil then
            mark(nativeRoot)
        end
    end

    local attachedLookup = self:getDirectAttachedVehicleLookup(vehicle)
    for attachedVehicle, _ in pairs(attachedLookup or {}) do
        mark(attachedVehicle)
    end
end

function FSCollisionDamage:isVehicleInAttachmentSuppression(vehicle, state, now)
    now = now or g_time or 0

    if state ~= nil and state.attachmentSuppressionUntil ~= nil and now < state.attachmentSuppressionUntil then
        return true
    end

    vehicle = self:resolveVehicleObject(vehicle)
    if vehicle == nil then
        return false
    end

    local function recent(candidate)
        candidate = self:resolveVehicleObject(candidate)
        if candidate == nil or self.recentAttachmentActivity == nil then
            return false
        end

        local last = self.recentAttachmentActivity[candidate]
        return last ~= nil and now - last <= (self.ATTACHMENT_EVENT_SUPPRESSION_MS or 9000)
    end

    if recent(vehicle) then
        return true
    end

    local rootVehicle = self:getVehicleTrainRoot(vehicle)
    if recent(rootVehicle) then
        return true
    end

    local nativeRoot = self:getRegisteredVehicleTrainRoot(vehicle)
    if recent(nativeRoot) then
        return true
    end

    local attachedLookup = self:getDirectAttachedVehicleLookup(vehicle)
    for attachedVehicle, _ in pairs(attachedLookup or {}) do
        if recent(attachedVehicle) then
            return true
        end
    end

    return false
end

function FSCollisionDamage:logAttachmentSuppression(vehicle, reason)
    if self.DAMAGE_LOGGING ~= true then
        return
    end

    local state = self:getVehicleState(vehicle)
    local now = g_time or 0
    if state.lastAttachmentSuppressionLogTime ~= nil and now - state.lastAttachmentSuppressionLogTime < 1500 then
        return
    end
    state.lastAttachmentSuppressionLogTime = now

    print(string.format(
        "[%s] %s | collision damage suppressed | recent attachment/coupling activity | reason=%s",
        self.MOD_NAME,
        tostring(self:getVehicleDebugName(vehicle)),
        tostring(reason or "unknown")
    ))
end

function FSCollisionDamage:getVehicleAttachmentSignature(vehicle)
    vehicle = self:resolveVehicleObject(vehicle)
    if vehicle == nil then
        return nil
    end

    local rootVehicle = self:getVehicleTrainRoot(vehicle) or vehicle
    if rootVehicle.getChildVehicleHash ~= nil then
        local ok, childVehicleHash = pcall(rootVehicle.getChildVehicleHash, rootVehicle)
        if ok and childVehicleHash ~= nil then
            return tostring(rootVehicle.rootNode or 0) .. ":" .. tostring(childVehicleHash)
        end
    end

    local ids = {}
    local seen = {}
    local function add(candidate)
        candidate = self:resolveVehicleObject(candidate)
        if candidate == nil then
            return
        end

        local id = candidate.rootNode
        if id == nil and candidate.components ~= nil and candidate.components[1] ~= nil then
            id = candidate.components[1].node
        end

        if id ~= nil and seen[id] ~= true then
            seen[id] = true
            table.insert(ids, tostring(id))
        end
    end

    add(rootVehicle)
    local vehicleLookup = self:buildVehicleTrainVehicleLookup(rootVehicle)
    for trainVehicle, _ in pairs(vehicleLookup or {}) do
        add(trainVehicle)
    end

    table.sort(ids)
    return table.concat(ids, ",")
end

function FSCollisionDamage:ensureAttachmentRegistryFresh(force)
    if self.isRefreshingAttachmentRegistry == true then
        return
    end

    local hasSnapshot = (self.lastAttachmentRegistryRefreshTime or -100000) > -99999
    if force ~= true and self.attachmentRegistryDirty ~= true and hasSnapshot then
        return
    end

    self:refreshAttachmentRegistry()
end

function FSCollisionDamage:refreshAttachmentRegistry()
    self.isRefreshingAttachmentRegistry = true

    local oldPairs = self.attachedVehiclePairs
    local oldParents = self.attachedVehicleParents
    local oldLastSeen = self.attachedVehiclePairLastSeen
    local now = g_time or 0

    self.attachedVehiclePairs = setmetatable({}, { __mode = "k" })
    self.attachedVehicleParents = setmetatable({}, { __mode = "k" })
    self.attachedVehiclePairLastSeen = setmetatable({}, { __mode = "k" })

    -- Keep recently known pairs alive for a short time. Some modded tools can
    -- briefly disappear from native attachment lists during hard braking, which
    -- is exactly when false collision hits are otherwise produced. The small
    -- grace period avoids that flicker without permanently suppressing damage
    -- after a real detach.
    if oldPairs ~= nil and oldLastSeen ~= nil then
        for vehicleA, neighbours in pairs(oldPairs) do
            if neighbours ~= nil then
                for vehicleB, _ in pairs(neighbours) do
                    local lastSeen = oldLastSeen[vehicleA] ~= nil and oldLastSeen[vehicleA][vehicleB] or nil
                    if lastSeen ~= nil and now - lastSeen <= self.ATTACHMENT_REGISTRY_KEEPALIVE_MS then
                        if oldParents ~= nil and oldParents[vehicleB] == vehicleA then
                            self:registerAttachedVehiclePair(vehicleA, vehicleB, "recent")
                        elseif oldParents ~= nil and oldParents[vehicleA] == vehicleB then
                            self:registerAttachedVehiclePair(vehicleB, vehicleA, "recent")
                        else
                            self:registerAttachedVehiclePair(vehicleA, vehicleB, "recent")
                        end

                        if self.attachedVehiclePairLastSeen[vehicleA] ~= nil then
                            self.attachedVehiclePairLastSeen[vehicleA][vehicleB] = lastSeen
                        end
                        if self.attachedVehiclePairLastSeen[vehicleB] ~= nil then
                            self.attachedVehiclePairLastSeen[vehicleB][vehicleA] = lastSeen
                        end
                    end
                end
            end
        end
    end

    local attachmentVehicles, attachmentStats = self:collectVehicleCandidates()
    for _, vehicle in ipairs(attachmentVehicles or {}) do
        self:registerVehicleAttachmentRelations(vehicle)
    end
    self.lastAttachmentVehicleDiscoveryStats = attachmentStats

    self.lastAttachmentRegistryRefreshTime = now
    self.attachmentRegistryDirty = false
    self.isRefreshingAttachmentRegistry = false
end

function FSCollisionDamage:registerVehicleAttachmentRelations(vehicle)
    vehicle = self:resolveVehicleObject(vehicle)
    if vehicle == nil or vehicle.rootNode == nil then
        return
    end

    local parent = self:getVehicleParent(vehicle)
    if parent ~= nil and parent ~= vehicle then
        self:registerAttachedVehiclePair(parent, vehicle, "parent")
    end

    if vehicle.getRootVehicle ~= nil then
        local nativeRoot = vehicle:getRootVehicle()
        nativeRoot = self:resolveVehicleObject(nativeRoot)
        if nativeRoot ~= nil and nativeRoot ~= vehicle then
            self:registerAttachedVehiclePair(nativeRoot, vehicle, "nativeRoot")
        end
    end

    local directAttached = self:getDirectAttachedVehicleLookup(vehicle)
    for attachedVehicle, _ in pairs(directAttached) do
        self:registerAttachedVehiclePair(vehicle, attachedVehicle, "directAttached")
    end

    if vehicle.childVehicles ~= nil then
        for _, childVehicle in pairs(vehicle.childVehicles) do
            self:registerAttachedVehiclePair(vehicle, childVehicle, "childVehicles")
        end
    end

    if vehicle.attachedImplements ~= nil then
        for _, implement in pairs(vehicle.attachedImplements) do
            local attachedVehicle = self:resolveVehicleObject(implement)
            if attachedVehicle ~= nil then
                self:registerAttachedVehiclePair(vehicle, attachedVehicle, "attachedImplements")
            end
        end
    end

    local specAttacherJoints = vehicle.spec_attacherJoints
    if specAttacherJoints ~= nil then
        self:registerAttachmentEntriesFromList(vehicle, specAttacherJoints.attachedImplements, "spec_attacherJoints.attachedImplements")
        self:registerAttachmentEntriesFromList(vehicle, specAttacherJoints.attacherJoints, "spec_attacherJoints.attacherJoints")
    end

    local specAttachable = vehicle.spec_attachable
    if specAttachable ~= nil then
        local attacherVehicle = self:resolveVehicleObject(specAttachable.attacherVehicle)
        if attacherVehicle ~= nil then
            self:registerAttachedVehiclePair(attacherVehicle, vehicle, "spec_attachable.attacherVehicle")
        end

        local attacherJointVehicle = self:resolveVehicleObject(specAttachable.attacherJoint)
        if attacherJointVehicle ~= nil then
            self:registerAttachedVehiclePair(attacherJointVehicle, vehicle, "spec_attachable.attacherJoint")
        end

        local inputAttacherJointVehicle = self:resolveVehicleObject(specAttachable.inputAttacherJoint)
        if inputAttacherJointVehicle ~= nil then
            self:registerAttachedVehiclePair(inputAttacherJointVehicle, vehicle, "spec_attachable.inputAttacherJoint")
        end
    end
end

function FSCollisionDamage:registerAttachmentEntriesFromList(parentVehicle, list, reason)
    if parentVehicle == nil or list == nil then
        return
    end

    for _, entry in pairs(list) do
        local attachedVehicle = self:resolveVehicleObject(entry)
        if attachedVehicle ~= nil then
            self:registerAttachedVehiclePair(parentVehicle, attachedVehicle, reason)
        end
    end
end

function FSCollisionDamage:registerAttachedVehiclePair(parentVehicle, childVehicle, reason)
    parentVehicle = self:resolveVehicleObject(parentVehicle)
    childVehicle = self:resolveVehicleObject(childVehicle)

    if parentVehicle == nil or childVehicle == nil or parentVehicle == childVehicle then
        return
    end

    if parentVehicle.rootNode == nil or childVehicle.rootNode == nil then
        return
    end

    self.attachedVehiclePairs = self.attachedVehiclePairs or setmetatable({}, { __mode = "k" })
    self.attachedVehicleParents = self.attachedVehicleParents or setmetatable({}, { __mode = "k" })
    self.attachedVehiclePairLastSeen = self.attachedVehiclePairLastSeen or setmetatable({}, { __mode = "k" })

    self.attachedVehiclePairs[parentVehicle] = self.attachedVehiclePairs[parentVehicle] or setmetatable({}, { __mode = "k" })
    self.attachedVehiclePairs[childVehicle] = self.attachedVehiclePairs[childVehicle] or setmetatable({}, { __mode = "k" })
    self.attachedVehiclePairs[parentVehicle][childVehicle] = true
    self.attachedVehiclePairs[childVehicle][parentVehicle] = true

    local now = g_time or 0
    self.attachedVehiclePairLastSeen[parentVehicle] = self.attachedVehiclePairLastSeen[parentVehicle] or setmetatable({}, { __mode = "k" })
    self.attachedVehiclePairLastSeen[childVehicle] = self.attachedVehiclePairLastSeen[childVehicle] or setmetatable({}, { __mode = "k" })
    self.attachedVehiclePairLastSeen[parentVehicle][childVehicle] = now
    self.attachedVehiclePairLastSeen[childVehicle][parentVehicle] = now

    if self.attachedVehicleParents[childVehicle] == nil then
        self.attachedVehicleParents[childVehicle] = parentVehicle
    end
end

function FSCollisionDamage:resolveVehicleObject(value, depth)
    if value == nil then
        return nil
    end

    depth = (depth or 0) + 1
    if depth > 8 then
        return nil
    end

    if type(value) ~= "table" then
        return nil
    end

    if value.rootNode ~= nil and (value.components ~= nil or value.spec_wearable ~= nil or value.getRootVehicle ~= nil or value.setDamageAmount ~= nil) then
        return value
    end

    local candidateFields = {
        "object",
        "vehicle",
        "attachedObject",
        "attachedVehicle",
        "implement",
        "attacherVehicle",
        "rootVehicle",
        "parentVehicle",
        "root",
        "parent",
        "target",
        "source"
    }

    for _, fieldName in ipairs(candidateFields) do
        local candidate = value[fieldName]
        local vehicle = self:resolveVehicleObject(candidate, depth)
        if vehicle ~= nil then
            return vehicle
        end
    end

    return nil
end

function FSCollisionDamage:getRegisteredAttachmentParent(vehicle)
    vehicle = self:resolveVehicleObject(vehicle)
    if vehicle == nil then
        return nil
    end

    if self.isRefreshingAttachmentRegistry ~= true then
        self:ensureAttachmentRegistryFresh()
    end

    if self.attachedVehicleParents == nil then
        return nil
    end

    return self.attachedVehicleParents[vehicle]
end

function FSCollisionDamage:getRegisteredVehicleTrainRoot(vehicle)
    vehicle = self:resolveVehicleObject(vehicle)
    if vehicle == nil then
        return nil
    end

    if self.isRefreshingAttachmentRegistry ~= true then
        self:ensureAttachmentRegistryFresh()
    end

    local root = vehicle
    local guard = 0
    while self.attachedVehicleParents ~= nil and self.attachedVehicleParents[root] ~= nil and guard < self.ATTACHMENT_REGISTRY_MAX_DEPTH do
        local parent = self.attachedVehicleParents[root]
        if parent == nil or parent == root then
            break
        end
        root = parent
        guard = guard + 1
    end

    return root
end

function FSCollisionDamage:addRegisteredAttachedVehiclesToLookup(vehicle, vehicleLookup)
    vehicle = self:resolveVehicleObject(vehicle)
    if vehicle == nil or vehicleLookup == nil or self.attachedVehiclePairs == nil then
        return
    end

    local stack = { vehicle }
    local visited = {}
    local depth = 0

    while #stack > 0 and depth < self.ATTACHMENT_REGISTRY_MAX_DEPTH do
        local current = table.remove(stack)
        if current ~= nil and visited[current] ~= true then
            visited[current] = true
            self:addVehicleTrainVehicleToLookup(current, vehicleLookup, 0)

            local neighbours = self.attachedVehiclePairs[current]
            if neighbours ~= nil then
                for neighbour, _ in pairs(neighbours) do
                    if neighbour ~= nil and visited[neighbour] ~= true then
                        table.insert(stack, neighbour)
                    end
                end
            end
        end
        depth = depth + 1
    end
end

function FSCollisionDamage:isRegisteredAttachedVehicleConnected(vehicleA, vehicleB)
    vehicleA = self:resolveVehicleObject(vehicleA)
    vehicleB = self:resolveVehicleObject(vehicleB)

    if vehicleA == nil or vehicleB == nil then
        return false
    end

    if vehicleA == vehicleB then
        return true
    end

    if self.isRefreshingAttachmentRegistry ~= true then
        self:ensureAttachmentRegistryFresh()
    end

    local rootA = self:getRegisteredVehicleTrainRoot(vehicleA) or vehicleA
    local rootB = self:getRegisteredVehicleTrainRoot(vehicleB) or vehicleB
    if rootA ~= nil and rootB ~= nil and rootA == rootB then
        return true
    end

    if self.attachedVehiclePairs == nil then
        return false
    end

    local stack = { vehicleA }
    local visited = {}
    local depth = 0

    while #stack > 0 and depth < self.ATTACHMENT_REGISTRY_MAX_DEPTH do
        local current = table.remove(stack)
        if current == vehicleB then
            return true
        end

        if current ~= nil and visited[current] ~= true then
            visited[current] = true
            local neighbours = self.attachedVehiclePairs[current]
            if neighbours ~= nil then
                for neighbour, _ in pairs(neighbours) do
                    if neighbour == vehicleB then
                        return true
                    end
                    if neighbour ~= nil and visited[neighbour] ~= true then
                        table.insert(stack, neighbour)
                    end
                end
            end
        end
        depth = depth + 1
    end

    return false
end

function FSCollisionDamage:isVehicleReferencedInAttachmentData(containerVehicle, targetVehicle)
    containerVehicle = self:resolveVehicleObject(containerVehicle)
    targetVehicle = self:resolveVehicleObject(targetVehicle)

    if containerVehicle == nil or targetVehicle == nil then
        return false
    end

    if containerVehicle == targetVehicle then
        return true
    end

    local tablesToScan = {
        containerVehicle.attachedImplements,
        containerVehicle.childVehicles,
        containerVehicle.spec_attacherJoints,
        containerVehicle.spec_attachable,
        targetVehicle.spec_attachable,
        targetVehicle.spec_attacherJoints
    }

    for _, attachmentData in ipairs(tablesToScan) do
        if self:attachmentTableReferencesVehicle(attachmentData, targetVehicle, 0, {}) then
            return true
        end
        if self:attachmentTableReferencesVehicle(attachmentData, containerVehicle, 0, {}) then
            return true
        end
    end

    return false
end

function FSCollisionDamage:attachmentTableReferencesVehicle(value, targetVehicle, depth, visited)
    if value == nil or targetVehicle == nil or depth > 8 then
        return false
    end

    if value == targetVehicle then
        return true
    end

    if type(value) ~= "table" then
        return false
    end

    local resolvedVehicle = self:resolveVehicleObject(value)
    if resolvedVehicle == targetVehicle then
        return true
    end

    if visited[value] == true then
        return false
    end
    visited[value] = true

    for key, child in pairs(value) do
        local keyText = string.lower(tostring(key or ""))
        local scanChild = depth < 3
            or string.find(keyText, "attach", 1, true) ~= nil
            or string.find(keyText, "vehicle", 1, true) ~= nil
            or string.find(keyText, "implement", 1, true) ~= nil
            or string.find(keyText, "joint", 1, true) ~= nil
            or string.find(keyText, "object", 1, true) ~= nil
            or string.find(keyText, "root", 1, true) ~= nil
            or string.find(keyText, "parent", 1, true) ~= nil

        if scanChild and self:attachmentTableReferencesVehicle(child, targetVehicle, depth + 1, visited) then
            return true
        end
    end

    return false
end

function FSCollisionDamage:findVehicleByNode(nodeId)
    if nodeId == nil or nodeId == 0 then
        return nil
    end

    local vehicles = self:collectVehicleCandidates()
    for _, candidate in ipairs(vehicles or {}) do
        if type(candidate) == "table" and candidate.rootNode ~= nil and self:isNodePartOfVehicle(nodeId, candidate) then
            return candidate
        end
    end

    return nil
end

function FSCollisionDamage:isNodePartOfVehicle(nodeId, vehicle)
    if nodeId == nil or nodeId == 0 or type(vehicle) ~= "table" then
        return false
    end

    if vehicle.rootNode ~= nil and self:isNodeChildOf(nodeId, vehicle.rootNode) then
        return true
    end

    if vehicle.components ~= nil then
        for _, component in pairs(vehicle.components) do
            if component.node ~= nil and self:isNodeChildOf(nodeId, component.node) then
                return true
            end
        end
    end

    return false
end

function FSCollisionDamage:isNodeChildOf(nodeId, parentNode)
    if nodeId == nil or nodeId == 0 or parentNode == nil or parentNode == 0 then
        return false
    end

    local node = nodeId
    local guard = 0
    while node ~= nil and node ~= 0 and guard < 64 do
        if node == parentNode then
            return true
        end

        if getParent == nil then
            break
        end

        local ok, parent = pcall(getParent, node)
        if not ok then
            break
        end

        node = parent
        guard = guard + 1
    end

    return false
end

function FSCollisionDamage:isVehicleLinkedByLiveAttachmentData(vehicleA, vehicleB)
    vehicleA = self:resolveVehicleObject(vehicleA)
    vehicleB = self:resolveVehicleObject(vehicleB)

    if vehicleA == nil or vehicleB == nil then
        return false
    end

    if vehicleA == vehicleB then
        return true
    end

    local directA = self:getDirectAttachedVehicleLookup(vehicleA)
    if directA[vehicleB] == true then
        return true
    end

    local directB = self:getDirectAttachedVehicleLookup(vehicleB)
    if directB[vehicleA] == true then
        return true
    end

    return self:isVehicleReferencedInAttachmentData(vehicleA, vehicleB)
        or self:isVehicleReferencedInAttachmentData(vehicleB, vehicleA)
end

function FSCollisionDamage:isKnownAttachedOrSameTrain(vehicleA, vehicleB)
    vehicleA = self:resolveVehicleObject(vehicleA)
    vehicleB = self:resolveVehicleObject(vehicleB)

    if vehicleA == nil or vehicleB == nil then
        return false
    end

    if vehicleA == vehicleB then
        return true
    end

    local rootA = self:getVehicleTrainRoot(vehicleA)
    local rootB = self:getVehicleTrainRoot(vehicleB)
    if rootA ~= nil and rootB ~= nil and rootA == rootB then
        return true
    end

    if self:isRegisteredAttachedVehicleConnected(vehicleA, vehicleB) then
        return true
    end

    if self:isVehicleReferencedInAttachmentData(vehicleA, vehicleB) or self:isVehicleReferencedInAttachmentData(vehicleB, vehicleA) then
        return true
    end

    if self:isVehicleLinkedByLiveAttachmentData(vehicleA, vehicleB) then
        return true
    end

    return false
end

function FSCollisionDamage:isDirectAttachmentRelation(vehicleA, vehicleB)
    vehicleA = self:resolveVehicleObject(vehicleA)
    vehicleB = self:resolveVehicleObject(vehicleB)

    if vehicleA == nil or vehicleB == nil or vehicleA == vehicleB then
        return vehicleA ~= nil and vehicleA == vehicleB
    end

    local rootA = self:getVehicleTrainRoot(vehicleA) or vehicleA
    local rootB = self:getVehicleTrainRoot(vehicleB) or vehicleB
    if rootA ~= nil and rootB ~= nil and rootA == rootB then
        return true
    end

    if vehicleA.getRootVehicle ~= nil then
        local ok, nativeRootA = pcall(vehicleA.getRootVehicle, vehicleA)
        nativeRootA = ok and self:resolveVehicleObject(nativeRootA) or nil
        if nativeRootA ~= nil and (nativeRootA == vehicleB or nativeRootA == rootB) then
            return true
        end
    end

    if vehicleB.getRootVehicle ~= nil then
        local ok, nativeRootB = pcall(vehicleB.getRootVehicle, vehicleB)
        nativeRootB = ok and self:resolveVehicleObject(nativeRootB) or nil
        if nativeRootB ~= nil and (nativeRootB == vehicleA or nativeRootB == rootA) then
            return true
        end
    end

    if vehicleA.getIsAttachedTo ~= nil then
        local ok, isAttached = pcall(vehicleA.getIsAttachedTo, vehicleA, vehicleB)
        if ok and isAttached == true then
            return true
        end
        ok, isAttached = pcall(vehicleA.getIsAttachedTo, vehicleA, rootB)
        if ok and isAttached == true then
            return true
        end
    end

    if vehicleB.getIsAttachedTo ~= nil then
        local ok, isAttached = pcall(vehicleB.getIsAttachedTo, vehicleB, vehicleA)
        if ok and isAttached == true then
            return true
        end
        ok, isAttached = pcall(vehicleB.getIsAttachedTo, vehicleB, rootA)
        if ok and isAttached == true then
            return true
        end
    end

    return false
end

function FSCollisionDamage:addVehicleNodesToLookup(vehicle, nodes)
    if vehicle == nil or nodes == nil then
        return
    end

    -- Store only root/component nodes in the hot path. isOwnNode() walks the
    -- parent chain of a hit node, so child collision shapes are still recognized
    -- without recursively caching hundreds of descendants every few frames. A
    -- full hierarchy cache remains available only as an emergency switch.
    if vehicle.rootNode ~= nil then
        nodes[vehicle.rootNode] = true
        if self.OWN_NODE_FULL_HIERARCHY_ENABLED == true then
            self:addNodeHierarchyToLookup(vehicle.rootNode, nodes, 0)
        end
    end

    if vehicle.components ~= nil then
        for _, component in pairs(vehicle.components) do
            if component.node ~= nil then
                nodes[component.node] = true
                if self.OWN_NODE_FULL_HIERARCHY_ENABLED == true then
                    self:addNodeHierarchyToLookup(component.node, nodes, 0)
                end
            end
        end
    end
end

function FSCollisionDamage:addNodeHierarchyToLookup(node, nodes, depth)
    if node == nil or node == 0 or nodes == nil or depth > 48 then
        return
    end

    nodes[node] = true

    if getNumOfChildren == nil or getChildAt == nil then
        return
    end

    local okNumChildren, numChildren = pcall(getNumOfChildren, node)
    if not okNumChildren or numChildren == nil then
        return
    end

    for i = 0, numChildren - 1 do
        local okChild, child = pcall(getChildAt, node, i)
        if okChild and child ~= nil and child ~= 0 then
            self:addNodeHierarchyToLookup(child, nodes, depth + 1)
        end
    end
end

function FSCollisionDamage:normalizeDt(dt)
    dt = tonumber(dt) or 0

    -- Giants normally uses milliseconds. This also supports seconds-based dt
    -- values for compatibility with unusual hook timings.
    if dt > 0 and dt < 1 then
        return dt * 1000
    end

    return dt
end

function FSCollisionDamage:getIsServerContext()
    if g_currentMission ~= nil then
        local mdi = g_currentMission.missionDynamicInfo
        if mdi ~= nil and mdi.isMultiplayer == false then
            return true
        end

        if g_currentMission.getIsServer ~= nil then
            return g_currentMission:getIsServer() == true
        end
    end

    if g_server ~= nil then
        return true
    end

    return g_client == nil
end

function FSCollisionDamage:logRuntimeStatus(stats)
    if self.INFO_LOGGING ~= true then
        return
    end

    stats = stats or self.lastVehicleDiscoveryStats or {}

    print(string.format(
        "[%s] DEBUG-Laufzeitkontrolle aktiv | Server=%s | missionVehicles=%d/%d | vehicleSystemVehicles=%d/%d | registryVehicles=%d | eindeutige Fahrzeuge=%d | pruefbare Root-Fahrzeuge=%d | getrackte Fahrzeuge=%d | globales Pruefintervall=%d ms | Speedfenster=%d ms | Schadenshoehe=%d%% | Diagnose=%s",
        self.MOD_NAME,
        tostring(self:getIsServerContext()),
        stats.missionVehiclesFound or stats.missionVehiclesFallbackFound or 0,
        stats.missionVehiclesScanned or stats.missionVehiclesFallbackScanned or 0,
        stats.vehicleSystemVehiclesFound or stats.vehicleSystemVehiclesFallbackFound or 0,
        stats.vehicleSystemVehiclesScanned or stats.vehicleSystemVehiclesFallbackScanned or 0,
        stats.registryVehicles or 0,
        stats.uniqueCandidateVehicles or 0,
        stats.validPrimaryVehicles or 0,
        stats.validTrackedVehicles or 0,
        self.CHECK_INTERVAL_MS,
        self.SPEED_DROP_WINDOW_MS,
        math.floor(self:getDamageMultiplier() * 100 + 0.5),
        tostring(self.DIAGNOSTIC_LOGGING == true)
    ))
end

function FSCollisionDamage:getVehicleDebugName(vehicle)
    if vehicle == nil then
        return "vehicle=nil"
    end

    if vehicle.getFullName ~= nil then
        local name = vehicle:getFullName()
        if name ~= nil and name ~= "" then
            return name
        end
    end

    if vehicle.getName ~= nil then
        local name = vehicle:getName()
        if name ~= nil and name ~= "" then
            return name
        end
    end

    return tostring(vehicle)
end

function FSCollisionDamage:getObjectDebugName(object)
    if object == nil then
        return "nil"
    end

    if object.getFullName ~= nil then
        local name = object:getFullName()
        if name ~= nil and name ~= "" then
            return name
        end
    end

    if object.getName ~= nil then
        local name = object:getName()
        if name ~= nil and name ~= "" then
            return name
        end
    end

    return tostring(object.configFileName or object)
end

function FSCollisionDamage:formatMass(mass)
    mass = tonumber(mass)

    if mass == nil then
        return "nil"
    end

    return string.format("%.1ft", mass)
end

function FSCollisionDamage:getNodePathDebugName(nodeId)
    if nodeId == nil or nodeId == 0 then
        return "nil"
    end

    local parts = {}
    local node = nodeId
    local guard = 0
    local maxDepth = self.DIAGNOSTIC_NODE_PATH_MAX_DEPTH or 18

    while node ~= nil and node ~= 0 and guard < maxDepth do
        local nodeName = nil
        if getName ~= nil then
            local ok, name = pcall(getName, node)
            if ok then
                nodeName = name
            end
        end

        local label = tostring(nodeName ~= nil and nodeName ~= "" and nodeName or node)
        table.insert(parts, string.format("%s(%s)", label, tostring(node)))

        if getParent == nil then
            break
        end

        local ok, parent = pcall(getParent, node)
        if not ok then
            break
        end

        node = parent
        guard = guard + 1
    end

    local text = table.concat(parts, " <- ")
    local maxLength = self.DIAGNOSTIC_NODE_PATH_MAX_LENGTH or 520
    if string.len(text) > maxLength then
        return string.sub(text, 1, maxLength) .. "..."
    end

    return text
end

function FSCollisionDamage:getNodeObjectDebugName(nodeId)
    local object = self:getNodeObject(nodeId)
    return self:getObjectDebugName(object)
end

function FSCollisionDamage:getNodeVehicleDebugName(nodeId)
    -- Do not scan g_currentMission.vehicles for every diagnostic line. On large
    -- mod lists this is a performance trap. The node object is enough to reveal
    -- whether the hit belongs to a placeable/vehicle in the current diagnosis.
    local vehicle = self:resolveVehicleObject(self:getNodeObject(nodeId))
    return self:getVehicleDebugName(vehicle)
end

function FSCollisionDamage:getNodeDebugName(nodeId)
    if nodeId == nil then
        return "nil"
    end

    local nodeName = getName ~= nil and getName(nodeId) or nil
    if nodeName ~= nil and nodeName ~= "" then
        return string.format("%s (%s)", tostring(nodeName), tostring(nodeId))
    end

    return tostring(nodeId)
end
