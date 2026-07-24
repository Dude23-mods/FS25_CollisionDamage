-- Unfallschaden Sensor
-- Runtime detection and damage handling for FS25_CollisionDamage.

if FSCollisionDamage == nil then
    FSCollisionDamage = {}
end

function FSCollisionDamage:shouldLogDebugGate(state, result, speed, speedDrop)
    if self.DIAGNOSTIC_LOGGING ~= true then
        return false
    end

    result = tostring(result or "unknown")

    -- The performance test build keeps the useful candidate diagnostics but
    -- suppresses routine 250 ms gate spam. Detailed candidate outcomes are still
    -- written by finishDiagnosticAttempt(), so the log remains useful without
    -- causing a visible pause during impacts.
    if result == "trackingInitialized"
        or result == "candidateRejectedBeforeSensor"
        or result == "candidateAcceptedSensorCheck"
        or result == "candidateRejectedNoSensorContact" then
        return false
    end

    local now = g_time or 0
    local throttle = self.DIAGNOSTIC_THROTTLE_MS or 1200
    local key = result

    state = state or {}
    state.debugGateLastByResult = state.debugGateLastByResult or {}

    local last = state.debugGateLastByResult[key] or -100000
    if now - last < throttle then
        return false
    end

    state.debugGateLastByResult[key] = now
    return true
end

function FSCollisionDamage:logDebugGate(vehicle, state, result, speed, previousSpeed, referenceSpeed, speedDrop, extra)
    if not self:shouldLogDebugGate(state, result, speed, speedDrop) then
        return
    end

    local velX, velZ = self:getVehicleVelocityXZ(vehicle)
    local moveDirX, moveDirZ = self:getVehicleMovementDirection(vehicle)
    local aabbs = self:getSensorVehicleAABBs(vehicle)
    local aabbCount = aabbs ~= nil and #aabbs or 0
    local now = g_time or 0

    print(string.format(
        "[%s] DEBUG-GATE %s | result=%s | speed %.1f->%.1f | reference %.1f | drop %.1f | thresholds speed>=%.1f drop>=%.1f | vel=(%.3f,%.3f) | moveDir=(%s,%s) | aabbs=%d | lastDamageAge=%d | interval=%dms | %s",
        self.MOD_NAME,
        tostring(self:getVehicleDebugName(vehicle)),
        tostring(result or "unknown"),
        previousSpeed or 0,
        speed or 0,
        referenceSpeed or 0,
        speedDrop or 0,
        self.MIN_SPEED_KMH or 0,
        self.MIN_SPEED_DROP_KMH or 0,
        velX or 0,
        velZ or 0,
        tostring(moveDirX),
        tostring(moveDirZ),
        aabbCount,
        math.floor(now - ((state ~= nil and state.lastDamageTime) or 0)),
        self.CHECK_INTERVAL_MS or 0,
        tostring(extra or "")
    ))
end

-- ============================================================
-- Detection
-- ============================================================

function FSCollisionDamage:getRecentSensorAABBs(state, now)
    if state == nil then
        return nil
    end

    now = now or g_time or 0

    if state.lastSensorAABBs ~= nil
        and state.lastSensorAABBTime ~= nil
        and now - state.lastSensorAABBTime <= (self.SENSOR_PREVIOUS_AABB_MAX_AGE_MS or 1600) then
        return state.lastSensorAABBs
    end

    return nil
end

function FSCollisionDamage:updateSensorAABBTracking(state, aabbs, now)
    if state == nil or aabbs == nil then
        return
    end

    state.lastSensorAABBs = aabbs
    state.lastSensorAABBTime = now or g_time or 0
end

function FSCollisionDamage:checkVehicle(vehicle, state, kinematics)
    -- Version 1.2.0.0 uses a conservative sensor approach. Vehicle dynamics
    -- only decide whether a check is worth doing; damage is applied only after
    -- a short directional raycast confirms a valid foreign target immediately
    -- in the travel direction. Braking, steering and turning alone can never
    -- create damage.
    self:resetOverlapContext()
    self:resetRaycastContext()

    kinematics = kinematics or self:getVehicleKinematics(vehicle)
    local speed = kinematics ~= nil and kinematics.speed or nil
    if speed == nil then
        self:logDebugGate(vehicle, state, "speedNil", nil, nil, nil, nil, "getVehicleKinematics returned nil speed")
        return
    end

    local now = g_time or 0
    local velX, velZ = kinematics.velX, kinematics.velZ
    local moveDirX, moveDirZ = kinematics.moveDirX, kinematics.moveDirZ

    state = state or self:getVehicleState(vehicle)

    local attachmentSignature = self:getVehicleAttachmentSignature(vehicle)
    if state.lastAttachmentSignature == nil then
        state.lastAttachmentSignature = attachmentSignature
    elseif attachmentSignature ~= nil and attachmentSignature ~= state.lastAttachmentSignature then
        state.lastAttachmentSignature = attachmentSignature
        self:markAttachmentRegistryDirty()
        self:markVehicleAttachmentActivity(vehicle, now, "attachmentSignatureChanged")
        self:logAttachmentSuppression(vehicle, "attachmentSignatureChanged")
        local aabbsToStore = self:getSensorVehicleAABBs(vehicle)
        self:updateSensorAABBTracking(state, aabbsToStore, now)
        self:updateVehicleTracking(state, speed, nil, true, moveDirX, moveDirZ, velX, velZ)
        return
    end

    -- Keep the previous sensor boxes from normal driving. The old diagnostic
    -- build only stored them after a sensor candidate had already happened.
    -- That made the first real impact on a vehicle much harder to confirm,
    -- because the post-impact box and direction could already be from the
    -- rebound state.
    local previousSensorAABBs = self:getRecentSensorAABBs(state, now)
    local currentSensorAABBs = nil
    local currentSensorAABBKnown = false

    local function getCurrentSensorAABBs()
        if currentSensorAABBKnown ~= true then
            currentSensorAABBs = self:getSensorVehicleAABBs(vehicle)
            currentSensorAABBKnown = true
        end

        return currentSensorAABBs
    end

    local function storeCurrentSensorAABBs()
        local aabbsToStore = getCurrentSensorAABBs()
        self:updateSensorAABBTracking(state, aabbsToStore, now)
        return aabbsToStore
    end

    if state.lastSpeed == nil then
        self:logDebugGate(vehicle, state, "trackingInitialized", speed, nil, speed, 0, "first speed sample; no previous value yet")
        storeCurrentSensorAABBs()
        self:updateVehicleTracking(state, speed, nil, false, moveDirX, moveDirZ, velX, velZ)
        return
    end

    local previousSpeed = state.lastSpeed
    local referenceSpeed, speedDrop = self:getRecentSpeedDrop(state, previousSpeed, speed)
    local highestCandidateSpeed = math.max(speed or 0, previousSpeed or 0, referenceSpeed or 0)

    if highestCandidateSpeed < self.MIN_SPEED_KMH or speedDrop < self.MIN_SPEED_DROP_KMH then
        state.hadForeignHit = false
        state.lastHitNode = nil
        local reason = ""
        if highestCandidateSpeed < self.MIN_SPEED_KMH then
            reason = reason .. "highestCandidateSpeedBelowThreshold "
        end
        if speedDrop < self.MIN_SPEED_DROP_KMH then
            reason = reason .. "speedDropBelowThreshold "
        end
        self:logDebugGate(vehicle, state, "candidateRejectedBeforeSensor", speed, previousSpeed, referenceSpeed, speedDrop, reason)
        storeCurrentSensorAABBs()
        self:updateVehicleTracking(state, speed, nil, false, moveDirX, moveDirZ, velX, velZ)
        return
    end

    if self:isVehicleInAttachmentSuppression(vehicle, state, now) then
        self:logAttachmentSuppression(vehicle, "recentAttachmentActivity")
        storeCurrentSensorAABBs()
        self:updateVehicleTracking(state, speed, nil, true, moveDirX, moveDirZ, velX, velZ)
        return
    end

    if now - (state.lastDamageTime or 0) < self.DAMAGE_COOLDOWN_MS then
        self:logDebugGate(vehicle, state, "candidateRejectedCooldown", speed, previousSpeed, referenceSpeed, speedDrop, "damage cooldown active")
        storeCurrentSensorAABBs()
        self:updateVehicleTracking(state, speed, nil, false, moveDirX, moveDirZ, velX, velZ)
        return
    end

    -- For an impact candidate prefer the last stable movement vector from
    -- before this sample. The current physics velocity may already describe
    -- the rebound, which points the raycast away from the obstacle.
    local travelDirX, travelDirZ = self:getBestMovementDirection(state, moveDirX, moveDirZ, true)
    if travelDirX == nil then
        self:logDebugGate(vehicle, state, "candidateRejectedNoDirection", speed, previousSpeed, referenceSpeed, speedDrop, "no usable travel direction")
        storeCurrentSensorAABBs()
        self:updateVehicleTracking(state, speed, nil, false, moveDirX, moveDirZ, velX, velZ)
        return
    end

    local aabbs = getCurrentSensorAABBs()
    if aabbs == nil then
        state.hadForeignHit = false
        state.lastHitNode = nil
        self:logDebugGate(vehicle, state, "candidateRejectedNoSensorAABB", speed, previousSpeed, referenceSpeed, speedDrop, "getSensorVehicleAABBs returned nil")
        self:updateVehicleTracking(state, speed, nil, false, moveDirX, moveDirZ, velX, velZ)
        return
    end

    local ownNodes = self:buildOwnNodeLookup(vehicle)

    self:logDebugGate(vehicle, state, "candidateAcceptedSensorCheck", speed, previousSpeed, referenceSpeed, speedDrop, string.format("travelDir=(%.3f,%.3f) previousSensorAABBs=%s", travelDirX or 0, travelDirZ or 0, tostring(previousSensorAABBs ~= nil)))

    self:startDiagnosticAttempt(vehicle, state, {
        speed = speed,
        previousSpeed = previousSpeed,
        referenceSpeed = referenceSpeed,
        speedDrop = speedDrop,
        aabbCount = #aabbs,
        isSensorBased = true,
        travelDirX = travelDirX,
        travelDirZ = travelDirZ,
        isHeavy = self:isHeavyMachine(vehicle)
    })

    local hasContactHit, hitNode, hitObject, contactMode = self:findSensorImpactContact(
        vehicle,
        aabbs,
        previousSensorAABBs,
        ownNodes,
        speedDrop,
        speed,
        travelDirX,
        travelDirZ
    )

    if not hasContactHit then
        state.hadForeignHit = false
        state.lastHitNode = nil
        self:logDebugGate(vehicle, state, "candidateRejectedNoSensorContact", speed, previousSpeed, referenceSpeed, speedDrop, "sensor raycasts missed or rejected every target")
        self:finishDiagnosticAttempt(vehicle, state, "sensorNoValidContact")
        self:updateSensorAABBTracking(state, aabbs, now)
        self:updateVehicleTracking(state, speed, nil, false, moveDirX, moveDirZ, velX, velZ)
        return
    end

    state.hadForeignHit = true
    state.lastHitNode = hitNode

    local damage, impactProfile, mass = self:calculateDamage(vehicle, speedDrop, referenceSpeed)
    local damageApplied = self:applyDamage(vehicle, damage, speedDrop, referenceSpeed, speed, hitNode, hitObject, contactMode, impactProfile, mass)

    if damageApplied then
        state.lastDamageTime = now
        self:applyCounterpartDamage(vehicle, damage, hitNode, hitObject, contactMode, impactProfile)
        self:finishDiagnosticAttempt(vehicle, state, "damageApplied", hitNode, hitObject, contactMode)
    else
        self:finishDiagnosticAttempt(vehicle, state, "damageApplyFailed", hitNode, hitObject, contactMode)
    end

    self:updateSensorAABBTracking(state, aabbs, now)
    self:updateVehicleTracking(state, speed, nil, true, moveDirX, moveDirZ, velX, velZ)
end

function FSCollisionDamage:getSensorVehicleAABBs(vehicle)
    local cache = self:getCheckCacheBucket("sensorAABBsByVehicle")
    if cache ~= nil and cache[vehicle] ~= nil then
        local cached = cache[vehicle]
        return cached ~= false and cached or nil
    end

    local aabbs = {}
    local rootVehicle = self:getVehicleTrainRoot(vehicle) or vehicle

    -- Use the drivable/root vehicle body as sensor source. Attached tools are
    -- still included in the own-node lookup, but they must not enlarge the
    -- detection area because raised frontloaders and bale spikes caused the
    -- reproducible ModHub false positives.
    self:addVehicleAABB(rootVehicle, aabbs)

    if vehicle ~= rootVehicle then
        self:addVehicleAABB(vehicle, aabbs)
    end

    local result = #aabbs > 0 and aabbs or nil
    if cache ~= nil then
        cache[vehicle] = result or false
    end

    return result
end

function FSCollisionDamage:getSensorRaycastProfile(vehicle)
    local isHeavy = self:isHeavyMachine(vehicle)
    if isHeavy then
        return {
            maxDistance = self.HEAVY_SENSOR_RAYCAST_MAX_DISTANCE,
            backOffset = self.SENSOR_RAYCAST_BACK_OFFSET,
            sideOffsetMax = self.HEAVY_SENSOR_RAYCAST_SIDE_OFFSET_MAX,
            sideFraction = self.HEAVY_SENSOR_RAYCAST_SIDE_FRACTION,
            minHeight = self.HEAVY_SENSOR_RAYCAST_MIN_HEIGHT,
            maxHeight = self.HEAVY_SENSOR_RAYCAST_MAX_HEIGHT,
            heightFractions = self.HEAVY_SENSOR_RAYCAST_HEIGHT_FRACTIONS
        }
    end

    return {
        maxDistance = self.SENSOR_RAYCAST_MAX_DISTANCE,
        backOffset = self.SENSOR_RAYCAST_BACK_OFFSET,
        sideOffsetMax = self.SENSOR_RAYCAST_SIDE_OFFSET_MAX,
        sideFraction = self.SENSOR_RAYCAST_SIDE_FRACTION,
        minHeight = self.SENSOR_RAYCAST_MIN_HEIGHT,
        maxHeight = self.SENSOR_RAYCAST_MAX_HEIGHT,
        heightFractions = self.SENSOR_RAYCAST_HEIGHT_FRACTIONS
    }
end

function FSCollisionDamage:findSensorImpactContact(vehicle, aabbs, previousAABBs, ownNodes, speedDrop, speed, travelDirX, travelDirZ)
    if raycastAll == nil then
        self:addDiagnosticAttempt("sensorRaycast", "skippedNoRaycastAll")
        return false, nil, nil, nil
    end

    local dirX, dirZ = self:normalizeHorizontalDirection(travelDirX, travelDirZ)
    if dirX == nil then
        self:addDiagnosticAttempt("sensorRaycast", "skippedNoDirection")
        return false, nil, nil, nil
    end

    local profile = self:getSensorRaycastProfile(vehicle)
    local ownAttachmentHitNode = nil
    local hasHit, hitNode, hitObject, attachedHitNode = self:raycastAgainstAABBs(vehicle, aabbs, ownNodes, dirX, dirZ, profile)
    if attachedHitNode ~= nil then
        ownAttachmentHitNode = attachedHitNode
    end

    if hasHit and self:isValidSensorCollisionTarget(hitNode, hitObject) then
        self:addDiagnosticAttempt("sensorRaycast", "hit:" .. self:getNodeDebugName(hitNode) .. "/" .. self:getObjectDebugName(hitObject))
        return true, hitNode, hitObject, "sensorRaycast"
    end

    if hasHit then
        self:addDiagnosticAttempt("sensorRaycast", "rejectedTarget:" .. self:getNodeDebugName(hitNode) .. "/" .. self:getObjectDebugName(hitObject))
    else
        self:addDiagnosticAttempt("sensorRaycast", "miss")
    end

    if self.SENSOR_RAYCAST_PREVIOUS_ENABLED == true and previousAABBs ~= nil then
        hasHit, hitNode, hitObject, attachedHitNode = self:raycastAgainstAABBs(vehicle, previousAABBs, ownNodes, dirX, dirZ, profile)
        if ownAttachmentHitNode == nil and attachedHitNode ~= nil then
            ownAttachmentHitNode = attachedHitNode
        end
        if hasHit and self:isValidSensorCollisionTarget(hitNode, hitObject) then
            self:addDiagnosticAttempt("sensorRaycastPrevious", "hit:" .. self:getNodeDebugName(hitNode) .. "/" .. self:getObjectDebugName(hitObject))
            return true, hitNode, hitObject, "sensorRaycastPrevious"
        end
        self:addDiagnosticAttempt("sensorRaycastPrevious", hasHit and ("rejectedTarget:" .. self:getNodeDebugName(hitNode) .. "/" .. self:getObjectDebugName(hitObject)) or "miss")
    end

    if self.SENSOR_RAYCAST_SWEEP_ENABLED == true and previousAABBs ~= nil then
        local sweptAABBs = self:getSweptAABBs(previousAABBs, aabbs)
        hasHit, hitNode, hitObject, attachedHitNode = self:raycastAgainstAABBs(vehicle, sweptAABBs, ownNodes, dirX, dirZ, profile)
        if ownAttachmentHitNode == nil and attachedHitNode ~= nil then
            ownAttachmentHitNode = attachedHitNode
        end
        if hasHit and self:isValidSensorCollisionTarget(hitNode, hitObject) then
            self:addDiagnosticAttempt("sensorRaycastSweep", "hit:" .. self:getNodeDebugName(hitNode) .. "/" .. self:getObjectDebugName(hitObject))
            return true, hitNode, hitObject, "sensorRaycastSweep"
        end
        self:addDiagnosticAttempt("sensorRaycastSweep", hasHit and ("rejectedTarget:" .. self:getNodeDebugName(hitNode) .. "/" .. self:getObjectDebugName(hitObject)) or "miss")
    end

    hasHit, hitNode, hitObject = self:tryAttachedSensorRaycastContact(
        vehicle,
        ownNodes,
        speedDrop,
        speed,
        dirX,
        dirZ,
        profile
    )

    if hasHit then
        return true, hitNode, hitObject, "sensorAttachedRaycast"
    end

    local proxyHitNode = ownAttachmentHitNode
    if proxyHitNode == nil then
        proxyHitNode = self:getForwardAttachedToolProxyNode(vehicle, dirX, dirZ)
    end

    if self:isAttachedToolProxyImpactAllowed(vehicle, proxyHitNode, speedDrop, speed) then
        self:addDiagnosticAttempt("attachedToolProxy", "hit:" .. self:getNodeDebugName(proxyHitNode))
        return true, proxyHitNode, nil, "attachedToolProxy"
    end

    if self.SENSOR_FRONT_PROBE_ENABLED == true then
        local contactMode
        hasHit, hitNode, hitObject, contactMode = self:trySensorFrontProbeContact(
            vehicle,
            aabbs,
            previousAABBs,
            ownNodes,
            speedDrop,
            speed,
            dirX,
            dirZ
        )

        if hasHit then
            return true, hitNode, hitObject, contactMode
        end
    else
        self:addDiagnosticAttempt("sensorFrontProbe", "disabled")
    end

    return false, nil, nil, nil
end

function FSCollisionDamage:tryAttachedSensorRaycastContact(vehicle, ownNodes, speedDrop, speed, dirX, dirZ, profile)
    if self.ATTACHED_SENSOR_RAYCAST_ENABLED ~= true then
        self:addDiagnosticAttempt("sensorAttachedRaycast", "disabled")
        return false, nil, nil
    end

    if (speedDrop or 0) < (self.ATTACHED_SENSOR_RAYCAST_MIN_DROP_KMH or 18.0) then
        self:addDiagnosticAttempt("sensorAttachedRaycast", "skippedDropTooSmall")
        return false, nil, nil
    end

    if ((speedDrop or 0) + (speed or 0)) < (self.ATTACHED_SENSOR_RAYCAST_MIN_REFERENCE_SPEED_KMH or 20.0) then
        self:addDiagnosticAttempt("sensorAttachedRaycast", "skippedReferenceTooLow")
        return false, nil, nil
    end

    if (speed or 0) > (self.ATTACHED_SENSOR_RAYCAST_MAX_END_SPEED_KMH or 18.0) then
        self:addDiagnosticAttempt("sensorAttachedRaycast", "skippedEndSpeedTooHigh")
        return false, nil, nil
    end

    local attachedAABBs = self:getAttachedSensorAABBs(vehicle, dirX, dirZ)
    if attachedAABBs == nil then
        self:addDiagnosticAttempt("sensorAttachedRaycast", "skippedNoAttachedAABB")
        return false, nil, nil
    end

    local hasHit, hitNode, hitObject = self:raycastAgainstAABBs(vehicle, attachedAABBs, ownNodes, dirX, dirZ, profile)
    if hasHit and self:isValidSensorCollisionTarget(hitNode, hitObject) then
        self:addDiagnosticAttempt("sensorAttachedRaycast", "hit:" .. self:getNodeDebugName(hitNode) .. "/" .. self:getObjectDebugName(hitObject))
        return true, hitNode, hitObject
    end

    self:addDiagnosticAttempt("sensorAttachedRaycast", hasHit and ("rejectedTarget:" .. self:getNodeDebugName(hitNode) .. "/" .. self:getObjectDebugName(hitObject)) or "miss")
    return false, nil, nil
end

function FSCollisionDamage:getAttachedSensorAABBs(vehicle, dirX, dirZ)
    local forwardAttachedVehicles = self:collectForwardAttachedVehicles(vehicle, dirX, dirZ)
    if forwardAttachedVehicles == nil then
        return nil
    end

    local aabbs = {}
    local maxAABBs = self.ATTACHED_SENSOR_RAYCAST_MAX_AABBS or 4
    for _, entry in ipairs(forwardAttachedVehicles) do
        if entry.aabb ~= nil then
            table.insert(aabbs, entry.aabb)
            if #aabbs >= maxAABBs then
                break
            end
        end
    end

    return #aabbs > 0 and aabbs or nil
end

function FSCollisionDamage:collectForwardAttachedVehicles(vehicle, dirX, dirZ)
    local rootVehicle = self:getVehicleTrainRoot(vehicle) or vehicle
    local rootAABB = self:getSingleVehicleAABB(rootVehicle)
    if rootAABB == nil then
        return nil
    end

    local rootCenterX = (rootAABB[1] + rootAABB[2]) * 0.5
    local rootCenterZ = (rootAABB[5] + rootAABB[6]) * 0.5
    local results = {}
    local vehicleLookup = self:buildVehicleTrainVehicleLookup(vehicle)

    for trainVehicle, _ in pairs(vehicleLookup or {}) do
        if trainVehicle ~= nil and trainVehicle ~= rootVehicle then
            local aabb = self:getSingleVehicleAABB(trainVehicle)
            if aabb ~= nil then
                local centerX = (aabb[1] + aabb[2]) * 0.5
                local centerZ = (aabb[5] + aabb[6]) * 0.5
                local forwardOffset = ((centerX - rootCenterX) * (dirX or 0)) + ((centerZ - rootCenterZ) * (dirZ or 0))

                if forwardOffset >= -0.75 then
                    table.insert(results, {
                        vehicle = trainVehicle,
                        aabb = aabb,
                        forwardOffset = forwardOffset
                    })
                end
            end
        end
    end

    table.sort(results, function(a, b)
        return (a.forwardOffset or 0) > (b.forwardOffset or 0)
    end)

    return #results > 0 and results or nil
end

function FSCollisionDamage:getForwardAttachedToolProxyNode(vehicle, dirX, dirZ)
    local forwardAttachedVehicles = self:collectForwardAttachedVehicles(vehicle, dirX, dirZ)
    if forwardAttachedVehicles == nil then
        return nil
    end

    for _, entry in ipairs(forwardAttachedVehicles) do
        if (entry.forwardOffset or -999999) >= -0.25 then
            local attachedVehicle = entry.vehicle
            local node = attachedVehicle ~= nil and attachedVehicle.rootNode or nil
            if node == nil and attachedVehicle ~= nil and attachedVehicle.components ~= nil and attachedVehicle.components[1] ~= nil then
                node = attachedVehicle.components[1].node
            end

            if node ~= nil and node ~= 0 then
                return node
            end
        end
    end

    return nil
end

function FSCollisionDamage:isAttachedToolProxyImpactAllowed(vehicle, ownAttachmentHitNode, speedDrop, speed)
    if self.ATTACHED_TOOL_PROXY_ENABLED ~= true then
        return false
    end

    if ownAttachmentHitNode == nil or ownAttachmentHitNode == 0 then
        return false
    end

    if (speedDrop or 0) < (self.ATTACHED_TOOL_PROXY_MIN_DROP_KMH or 28.0) then
        return false
    end

    if ((speedDrop or 0) + (speed or 0)) < (self.ATTACHED_TOOL_PROXY_MIN_REFERENCE_SPEED_KMH or 28.0) then
        return false
    end

    if (speed or 0) > (self.ATTACHED_TOOL_PROXY_MAX_END_SPEED_KMH or 5.0) then
        return false
    end

    return true
end

function FSCollisionDamage:isValidSensorCollisionTarget(hitNode, hitObject)
    if hitNode == nil or hitNode == 0 then
        self:recordIgnoredCollision("sensorNilNode", hitNode, hitObject)
        return false
    end

    if hitObject ~= nil then
        return true
    end

    if self:isTrafficCollisionNode(hitNode) then
        return true
    end

    if self:isAnonymousDynamicCollisionNode(hitNode) then
        return true
    end

    if self:shouldIgnoreRoadCollisionNode(hitNode) then
        self:recordIgnoredCollision("sensorRoadLike", hitNode, hitObject)
        return false
    end

    if self:isNamedStaticObstacleCollisionNode(hitNode) then
        return true
    end

    if self.SENSOR_ALLOW_GENERIC_STATIC == true and not self:isAnonymousGenericMapCollisionNode(hitNode) then
        return true
    end

    self:recordIgnoredCollision("sensorGenericStaticBlocked", hitNode, hitObject)
    return false
end

function FSCollisionDamage:isTrafficCollisionNode(nodeId)
    if nodeId == nil or nodeId == 0 then
        return false
    end


    local node = nodeId
    local guard = 0
    local hasTrafficParent = false
    local hasVehicleNumberNode = false

    while node ~= nil and node ~= 0 and guard < 32 do
        local nodeName = getName ~= nil and getName(node) or nil
        local name = string.lower(tostring(nodeName or ""))

        if name ~= "" then
            if string.find(name, "trafficcollision", 1, true) ~= nil
                or string.find(name, "traffic_collision", 1, true) ~= nil
                or string.find(name, "trafficvehicle", 1, true) ~= nil
                or string.find(name, "traffic_vehicle", 1, true) ~= nil
                or string.find(name, "trafficcar", 1, true) ~= nil
                or string.find(name, "traffic_car", 1, true) ~= nil
                or string.find(name, "traffictruck", 1, true) ~= nil
                or string.find(name, "traffic_truck", 1, true) ~= nil
                or string.find(name, "multipurposetruck", 1, true) ~= nil then
                return true
            end

            if string.find(name, "traffic", 1, true) ~= nil then
                hasTrafficParent = true
            end

            if string.match(name, "^vehicle%d+$") ~= nil then
                -- Base-game traffic collision nodes can be named vehicle09,
                -- sometimes without a resolvable owning object. Treat such a
                -- direct anonymous vehicle node as traffic-like crash evidence.
                hasVehicleNumberNode = true
                return true
            end
        end

        if getParent == nil then
            break
        end

        node = getParent(node)
        guard = guard + 1
    end

    return hasTrafficParent and hasVehicleNumberNode
end

function FSCollisionDamage:isAnonymousDynamicCollisionNode(nodeId)
    if nodeId == nil or nodeId == 0 then
        return false
    end

    local node = nodeId
    local guard = 0
    while node ~= nil and node ~= 0 and guard < 32 do
        if self:isDynamicOrKinematicRigidBody(node) then
            return true
        end

        if getParent == nil then
            break
        end

        node = getParent(node)
        guard = guard + 1
    end

    return false
end

function FSCollisionDamage:isDynamicOrKinematicRigidBody(nodeId)
    if nodeId == nil or nodeId == 0 or getRigidBodyType == nil then
        return false
    end

    local ok, rigidBodyType = pcall(getRigidBodyType, nodeId)
    if not ok or rigidBodyType == nil then
        return false
    end

    if type(rigidBodyType) == "string" then
        local name = string.lower(rigidBodyType)
        return string.find(name, "dynamic", 1, true) ~= nil
            or string.find(name, "kinematic", 1, true) ~= nil
    end

    if type(rigidBodyType) == "number" then
        local noneType = RigidBodyType ~= nil and RigidBodyType.NONE or nil
        local staticType = RigidBodyType ~= nil and RigidBodyType.STATIC or nil
        local noRigidBodyType = RigidBodyType ~= nil and RigidBodyType.NO_RIGID_BODY or nil

        if noneType ~= nil and rigidBodyType == noneType then
            return false
        end
        if noRigidBodyType ~= nil and rigidBodyType == noRigidBodyType then
            return false
        end
        if staticType ~= nil and rigidBodyType == staticType then
            return false
        end

        if RigidBodyType ~= nil then
            local dynamicType = RigidBodyType.DYNAMIC
            local kinematicType = RigidBodyType.KINEMATIC
            if dynamicType ~= nil and rigidBodyType == dynamicType then
                return true
            end
            if kinematicType ~= nil and rigidBodyType == kinematicType then
                return true
            end
        end
    end

    return false
end

function FSCollisionDamage:isNamedStaticObstacleCollisionNode(nodeId)
    if nodeId == nil or nodeId == 0 then
        return false
    end

    if self:shouldIgnoreRoadCollisionNode(nodeId) then
        return false
    end

    return self:nodeNameChainContainsAny(nodeId, self.NAMED_STATIC_OBSTACLE_NODE_NAME_PARTS)
end

function FSCollisionDamage:shouldIgnoreRoadCollisionNode(nodeId)
    if nodeId == nil or nodeId == 0 then
        return false
    end

    local node = nodeId
    local guard = 0
    local hasRoadParent = false
    local hasRoadMeshName = false

    while node ~= nil and node ~= 0 and guard < 32 do
        local nodeName = getName ~= nil and getName(node) or nil
        local name = string.lower(tostring(nodeName or ""))

        if self:textContainsAny(name, self.ROAD_SURFACE_NODE_NAME_PARTS) then
            hasRoadParent = true
        end

        if string.match(name, "^curve%d*m?%d*") ~= nil
            or string.match(name, "^street%d+m?") ~= nil
            or name == "street"
            or name == "road" then
            hasRoadMeshName = true
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

    return hasRoadParent and hasRoadMeshName
end

function FSCollisionDamage:isAnonymousGenericMapCollisionNode(nodeId)
    if nodeId == nil or nodeId == 0 then
        return true
    end

    local node = nodeId
    local guard = 0

    while node ~= nil and node ~= 0 and guard < 32 do
        local nodeName = getName ~= nil and getName(node) or nil
        if self:isGenericAnonymousNodeName(nodeName) then
            return true
        end

        if getParent == nil then
            break
        end

        node = getParent(node)
        guard = guard + 1
    end

    return false
end

function FSCollisionDamage:isGenericAnonymousNodeName(nodeName)
    if nodeName == nil or nodeName == "" then
        return false
    end

    local name = string.lower(tostring(nodeName))

    if name == "col" or name == "collision" then
        return true
    end

    if string.sub(name, 1, 5) == "pcube" then
        return true
    end

    if string.sub(name, 1, 11) == "polysurface" then
        return true
    end

    if string.sub(name, 1, 3) == "lod" then
        return true
    end

    if string.find(name, "grounddivider", 1, true) ~= nil
        or string.find(name, "ground_divider", 1, true) ~= nil then
        return true
    end

    return false
end

function FSCollisionDamage:getSweptAABBs(previousAABBs, currentAABBs)
    if previousAABBs == nil then
        return currentAABBs
    end

    local sweptAABBs = {}
    local currentCount = currentAABBs ~= nil and #currentAABBs or 0
    local count = math.max(#previousAABBs, currentCount)

    for i = 1, count do
        local previousAABB = previousAABBs[i]
        local currentAABB = currentAABBs ~= nil and currentAABBs[i] or nil

        if previousAABB ~= nil and currentAABB ~= nil then
            table.insert(sweptAABBs, {
                math.min(previousAABB[1], currentAABB[1]),
                math.max(previousAABB[2], currentAABB[2]),
                math.min(previousAABB[3], currentAABB[3]),
                math.max(previousAABB[4], currentAABB[4]),
                math.min(previousAABB[5], currentAABB[5]),
                math.max(previousAABB[6], currentAABB[6])
            })
        elseif currentAABB ~= nil then
            table.insert(sweptAABBs, currentAABB)
        elseif previousAABB ~= nil then
            table.insert(sweptAABBs, previousAABB)
        end
    end

    return #sweptAABBs > 0 and sweptAABBs or nil
end

function FSCollisionDamage:getRecentSpeedDrop(state, previousSpeed, speed)
    local now = g_time or 0
    local referenceSpeed = state.speedReference or previousSpeed or speed
    local referenceTime = state.speedReferenceTime or now

    if now - referenceTime > self.SPEED_DROP_WINDOW_MS then
        referenceSpeed = previousSpeed or speed
        referenceTime = now
    end

    if previousSpeed ~= nil and previousSpeed > referenceSpeed then
        referenceSpeed = previousSpeed
        referenceTime = now
    end

    if speed > referenceSpeed then
        referenceSpeed = speed
        referenceTime = now
    end

    state.speedReference = referenceSpeed
    state.speedReferenceTime = referenceTime

    return referenceSpeed, math.max(0, referenceSpeed - speed)
end

function FSCollisionDamage:updateVehicleTracking(state, speed, aabbs, resetSpeedWindow, moveDirX, moveDirZ, velX, velZ)
    state.lastSpeed = speed
    state.lastAABBs = aabbs
    state.lastVelX = velX
    state.lastVelZ = velZ

    if moveDirX ~= nil and moveDirZ ~= nil then
        state.lastMoveDirX = moveDirX
        state.lastMoveDirZ = moveDirZ
    end

    if resetSpeedWindow == true or state.speedReference == nil then
        local now = g_time or 0
        state.speedReference = speed
        state.speedReferenceTime = now
        state.sustainedSpeedReference = speed
        state.sustainedSpeedReferenceTime = now
    end
end

function FSCollisionDamage:trySensorFrontProbeContact(vehicle, aabbs, previousAABBs, ownNodes, speedDrop, speed, travelDirX, travelDirZ)
    local profile = self:getFrontProbeProfile("sensor")

    local function check(probeAABBs, mode)
        if probeAABBs == nil then
            self:addDiagnosticAttempt(mode, "skippedNoAABB")
            return false, nil, nil, nil
        end

        local hasHit, hitNode, hitObject, contactMode = self:tryFrontProbeContact(
            vehicle,
            probeAABBs,
            ownNodes,
            speedDrop,
            speed,
            travelDirX,
            travelDirZ,
            profile,
            mode
        )

        if hasHit then
            if self:isValidSensorCollisionTarget(hitNode, hitObject) then
                self:addDiagnosticAttempt(mode, "valid:" .. self:getNodeDebugName(hitNode) .. "/" .. self:getObjectDebugName(hitObject))
                return true, hitNode, hitObject, contactMode
            end

            self:addDiagnosticAttempt(mode, "rejectedTarget:" .. self:getNodeDebugName(hitNode) .. "/" .. self:getObjectDebugName(hitObject))
        end

        return false, nil, nil, nil
    end

    local hasHit, hitNode, hitObject, contactMode = check(aabbs, "sensorFrontProbe")
    if hasHit then
        return true, hitNode, hitObject, contactMode
    end

    if previousAABBs ~= nil then
        hasHit, hitNode, hitObject, contactMode = check(previousAABBs, "sensorFrontProbePrevious")
        if hasHit then
            return true, hitNode, hitObject, contactMode
        end

        hasHit, hitNode, hitObject, contactMode = check(self:getSweptAABBs(previousAABBs, aabbs), "sensorFrontProbeSweep")
        if hasHit then
            return true, hitNode, hitObject, contactMode
        end
    end

    return false, nil, nil, nil
end

function FSCollisionDamage:tryFrontProbeContact(vehicle, aabbs, ownNodes, speedDrop, speed, travelDirX, travelDirZ, profile, contactMode)
    if profile == nil then
        self:addDiagnosticAttempt(contactMode or "frontProbe", "skippedNoProfile")
        return false, nil, nil, nil
    end

    if (speedDrop or 0) < profile.minDropKmh then
        self:addDiagnosticAttempt(contactMode or "frontProbe", "skippedDropTooSmall")
        return false, nil, nil, nil
    end

    if (speed or 0) > profile.maxEndSpeedKmh then
        self:addDiagnosticAttempt(contactMode or "frontProbe", "skippedEndSpeedTooHigh")
        return false, nil, nil, nil
    end

    local dirX, dirZ = self:getVehicleForwardDirection(vehicle, travelDirX, travelDirZ)
    if dirX == nil then
        self:addDiagnosticAttempt(contactMode or "frontProbe", "skippedNoDirection")
        return false, nil, nil, nil
    end

    local probeAABBs = self:getFrontProbeAABBs(aabbs, dirX, dirZ, profile)
    if probeAABBs == nil then
        self:addDiagnosticAttempt(contactMode or "frontProbe", "skippedNoProbeAABB")
        return false, nil, nil, nil
    end

    local hasHit, hitNode, hitObject = self:hasForeignCollisionShapeNearAABBs(
        vehicle,
        probeAABBs,
        ownNodes,
        profile.marginX,
        profile.marginY,
        profile.marginZ,
        false
    )

    self:addDiagnosticAttempt(contactMode or "frontProbe", hasHit and "hit" or "miss")
    if hasHit then
        return true, hitNode, hitObject, contactMode or "frontProbe"
    end

    return false, nil, nil, nil
end

function FSCollisionDamage:getFrontProbeProfile(profileName)
    if profileName == "sensor" then
        return {
            minDropKmh = self.SENSOR_FRONT_PROBE_MIN_DROP_KMH,
            maxEndSpeedKmh = self.SENSOR_FRONT_PROBE_MAX_END_SPEED_KMH,
            distance = self.SENSOR_FRONT_PROBE_DISTANCE,
            step = self.SENSOR_FRONT_PROBE_STEP,
            depth = self.SENSOR_FRONT_PROBE_DEPTH,
            sideFraction = self.SENSOR_FRONT_PROBE_SIDE_FRACTION,
            sideOffsetMax = self.SENSOR_FRONT_PROBE_SIDE_OFFSET_MAX,
            minHeight = self.SENSOR_FRONT_PROBE_MIN_HEIGHT,
            maxHeight = self.SENSOR_FRONT_PROBE_MAX_HEIGHT,
            marginX = self.SENSOR_FRONT_PROBE_MARGIN_X,
            marginY = self.SENSOR_FRONT_PROBE_MARGIN_Y,
            marginZ = self.SENSOR_FRONT_PROBE_MARGIN_Z
        }
    end

    if profileName == "combine" then
        return {
            minDropKmh = self.COMBINE_FRONT_PROBE_MIN_DROP_KMH,
            maxEndSpeedKmh = self.COMBINE_FRONT_PROBE_MAX_END_SPEED_KMH,
            distance = self.COMBINE_FRONT_PROBE_DISTANCE,
            step = self.COMBINE_FRONT_PROBE_STEP,
            depth = self.COMBINE_FRONT_PROBE_DEPTH,
            sideFraction = self.COMBINE_FRONT_PROBE_SIDE_FRACTION,
            sideOffsetMax = self.COMBINE_FRONT_PROBE_SIDE_OFFSET_MAX,
            minHeight = self.COMBINE_FRONT_PROBE_MIN_HEIGHT,
            maxHeight = self.COMBINE_FRONT_PROBE_MAX_HEIGHT,
            marginX = self.COMBINE_FRONT_PROBE_MARGIN_X,
            marginY = self.COMBINE_FRONT_PROBE_MARGIN_Y,
            marginZ = self.COMBINE_FRONT_PROBE_MARGIN_Z
        }
    end

    return {
        minDropKmh = self.HEAVY_FRONT_PROBE_MIN_DROP_KMH,
        maxEndSpeedKmh = self.HEAVY_FRONT_PROBE_MAX_END_SPEED_KMH,
        distance = self.HEAVY_FRONT_PROBE_DISTANCE,
        step = self.HEAVY_FRONT_PROBE_STEP,
        depth = self.HEAVY_FRONT_PROBE_DEPTH,
        sideFraction = self.HEAVY_FRONT_PROBE_SIDE_FRACTION,
        sideOffsetMax = self.HEAVY_FRONT_PROBE_SIDE_OFFSET_MAX,
        minHeight = self.HEAVY_FRONT_PROBE_MIN_HEIGHT,
        maxHeight = self.HEAVY_FRONT_PROBE_MAX_HEIGHT,
        marginX = self.HEAVY_FRONT_PROBE_MARGIN_X,
        marginY = self.HEAVY_FRONT_PROBE_MARGIN_Y,
        marginZ = self.HEAVY_FRONT_PROBE_MARGIN_Z
    }
end

function FSCollisionDamage:getFrontProbeAABBs(aabbs, dirX, dirZ, profile)
    if aabbs == nil or profile == nil then
        return nil
    end

    local probeAABBs = {}

    for _, aabb in ipairs(aabbs) do
        self:addFrontProbeAABBsForBox(probeAABBs, aabb, dirX, dirZ, profile)
    end

    return #probeAABBs > 0 and probeAABBs or nil
end

function FSCollisionDamage:addFrontProbeAABBsForBox(probeAABBs, aabb, dirX, dirZ, profile)
    if probeAABBs == nil or aabb == nil or profile == nil then
        return
    end

    local minX, maxX, minY, maxY, minZ, maxZ = aabb[1], aabb[2], aabb[3], aabb[4], aabb[5], aabb[6]
    if minX == nil then
        return
    end

    local centerX = (minX + maxX) * 0.5
    local centerZ = (minZ + maxZ) * 0.5
    local halfX = math.max(0.05, (maxX - minX) * 0.5)
    local halfZ = math.max(0.05, (maxZ - minZ) * 0.5)
    local sideX = -dirZ
    local sideZ = dirX
    local frontDistance = math.abs(dirX) * halfX + math.abs(dirZ) * halfZ
    local sideExtent = math.abs(sideX) * halfX + math.abs(sideZ) * halfZ
    local sideHalf = math.min(profile.sideOffsetMax, sideExtent * profile.sideFraction)
    local depthHalf = profile.depth
    local radiusX = math.abs(sideX) * sideHalf + math.abs(dirX) * depthHalf
    local radiusZ = math.abs(sideZ) * sideHalf + math.abs(dirZ) * depthHalf
    local probeMinY = minY + profile.minHeight
    local probeMaxY = math.min(maxY, minY + profile.maxHeight)

    if probeMaxY <= probeMinY then
        probeMinY = minY
        probeMaxY = maxY
    end

    local distance = profile.step
    while distance <= profile.distance do
        local probeCenterX = centerX + dirX * (frontDistance + distance)
        local probeCenterZ = centerZ + dirZ * (frontDistance + distance)

        table.insert(probeAABBs, {
            probeCenterX - radiusX,
            probeCenterX + radiusX,
            probeMinY,
            probeMaxY,
            probeCenterZ - radiusZ,
            probeCenterZ + radiusZ
        })

        distance = distance + profile.step
    end
end

function FSCollisionDamage:getVehicleState(vehicle)
    self.vehicleStates = self.vehicleStates or setmetatable({}, { __mode = "k" })

    local state = self.vehicleStates[vehicle]
    if state == nil then
        state = {
            lastSpeed = nil,
            lastDamageTime = -100000,
            hadForeignHit = false,
            lastHitNode = nil,
            lastAABBs = nil,
            lastSensorAABBs = nil,
            lastSensorAABBTime = nil,
            speedReference = nil,
            speedReferenceTime = 0,
            sustainedSpeedReference = nil,
            sustainedSpeedReferenceTime = 0,
            lastMoveDirX = nil,
            lastMoveDirZ = nil,
            lastVelX = nil,
            lastVelZ = nil,
            lastDiagnosticLogTime = -100000,
            vehicleTimer = 0,
        }
        self.vehicleStates[vehicle] = state
    end

    return state
end

function FSCollisionDamage:getVehicleKinematics(vehicle)
    if vehicle == nil then
        return nil
    end

    local cache = self:getCheckCacheBucket("kinematicsByVehicle")
    if cache ~= nil and cache[vehicle] ~= nil then
        return cache[vehicle]
    end

    local node = vehicle.rootNode
    if node == nil and vehicle.components ~= nil and vehicle.components[1] ~= nil then
        node = vehicle.components[1].node
    end

    local speed = nil
    if vehicle.getLastSpeed ~= nil then
        local ok, lastSpeed = pcall(vehicle.getLastSpeed, vehicle, true)
        if ok and lastSpeed ~= nil then
            speed = math.abs(lastSpeed)
        end
    end

    local vx, vy, vz = nil, nil, nil
    if node ~= nil and getLinearVelocity ~= nil then
        local ok, velocityX, velocityY, velocityZ = pcall(getLinearVelocity, node)
        if ok then
            vx, vy, vz = velocityX, velocityY, velocityZ
        end
    end

    if speed == nil and vx ~= nil then
        if MathUtil ~= nil and MathUtil.vector3Length ~= nil then
            speed = MathUtil.vector3Length(vx, vy or 0, vz or 0) * 3.6
        else
            speed = math.sqrt((vx or 0) * (vx or 0) + (vy or 0) * (vy or 0) + (vz or 0) * (vz or 0)) * 3.6
        end
    end

    local moveDirX, moveDirZ = nil, nil
    if vx ~= nil and vz ~= nil then
        local length = math.sqrt(vx * vx + vz * vz)
        if length >= 0.25 then
            moveDirX = vx / length
            moveDirZ = vz / length
        end
    end

    if moveDirX == nil and (speed or 0) >= (self.MIN_TRACK_SPEED_KMH or 0.5) and vehicle.getVehicleWorldDirection ~= nil then
        local ok, directionX, directionY, directionZ = pcall(vehicle.getVehicleWorldDirection, vehicle)
        if ok then
            local forwardX = tonumber(directionX)
            local forwardZ = tonumber(directionZ)
            if forwardZ == nil then
                forwardZ = tonumber(directionY)
            end

            if forwardX ~= nil and forwardZ ~= nil then
                local directionLength = math.sqrt(forwardX * forwardX + forwardZ * forwardZ)
                if directionLength > 0.0001 then
                    local movementSign = tonumber(vehicle.movingDirection) or 0
                    if movementSign == 0 then
                        local signedSpeed = tonumber(vehicle.lastSignedSpeedReal) or tonumber(vehicle.lastSignedSpeed) or 0
                        movementSign = signedSpeed < 0 and -1 or 1
                    end
                    movementSign = movementSign < 0 and -1 or 1
                    moveDirX = forwardX / directionLength * movementSign
                    moveDirZ = forwardZ / directionLength * movementSign
                end
            end
        end
    end

    local result = {
        node = node,
        speed = speed,
        velX = vx,
        velZ = vz,
        moveDirX = moveDirX,
        moveDirZ = moveDirZ
    }

    if cache ~= nil then
        cache[vehicle] = result
    end

    return result
end

function FSCollisionDamage:getVehicleVelocityXZ(vehicle)
    local kinematics = self:getVehicleKinematics(vehicle)
    if kinematics == nil then
        return nil, nil
    end

    return kinematics.velX, kinematics.velZ
end

function FSCollisionDamage:getVehicleMovementDirection(vehicle)
    local kinematics = self:getVehicleKinematics(vehicle)
    if kinematics == nil then
        return nil, nil
    end

    return kinematics.moveDirX, kinematics.moveDirZ
end

function FSCollisionDamage:getBestMovementDirection(state, moveDirX, moveDirZ, preferPrevious)
    if preferPrevious == true and state ~= nil and state.lastMoveDirX ~= nil and state.lastMoveDirZ ~= nil then
        return state.lastMoveDirX, state.lastMoveDirZ
    end

    if moveDirX ~= nil and moveDirZ ~= nil then
        return moveDirX, moveDirZ
    end

    if state ~= nil and state.lastMoveDirX ~= nil and state.lastMoveDirZ ~= nil then
        return state.lastMoveDirX, state.lastMoveDirZ
    end

    return nil, nil
end

function FSCollisionDamage:getVehicleOrientationDirections(vehicle, alignDirX, alignDirZ)
    local node = vehicle ~= nil and vehicle.rootNode or nil
    if node == nil and vehicle ~= nil and vehicle.components ~= nil and vehicle.components[1] ~= nil then
        node = vehicle.components[1].node
    end

    if node ~= nil and localToWorld ~= nil then
        local originX, _, originZ = localToWorld(node, 0, 0, 0)
        local forwardX, _, forwardZ = localToWorld(node, 0, 0, 1)
        local sideX, _, sideZ = localToWorld(node, 1, 0, 0)

        if originX ~= nil and forwardX ~= nil and sideX ~= nil then
            forwardX, forwardZ = self:normalizeHorizontalDirection(forwardX - originX, forwardZ - originZ)
            sideX, sideZ = self:normalizeHorizontalDirection(sideX - originX, sideZ - originZ)

            if forwardX ~= nil and sideX ~= nil then
                local alignX, alignZ = self:normalizeHorizontalDirection(alignDirX, alignDirZ)
                if alignX ~= nil then
                    local dot = forwardX * alignX + forwardZ * alignZ
                    if dot < 0 then
                        forwardX = -forwardX
                        forwardZ = -forwardZ
                        sideX = -sideX
                        sideZ = -sideZ
                    end
                end

                return forwardX, forwardZ, sideX, sideZ
            end
        end
    end

    local fallbackForwardX, fallbackForwardZ = self:normalizeHorizontalDirection(alignDirX, alignDirZ)
    if fallbackForwardX == nil then
        return nil, nil, nil, nil
    end

    return fallbackForwardX, fallbackForwardZ, -fallbackForwardZ, fallbackForwardX
end

function FSCollisionDamage:getVehicleForwardDirection(vehicle, alignDirX, alignDirZ)
    local forwardX, forwardZ = self:getVehicleOrientationDirections(vehicle, alignDirX, alignDirZ)
    if forwardX ~= nil then
        return forwardX, forwardZ
    end

    return self:normalizeHorizontalDirection(alignDirX, alignDirZ)
end

function FSCollisionDamage:calculateDamage(vehicle, speedDrop, previousSpeed)
    local damage = speedDrop * self.DAMAGE_PER_KMH_DROP
    local isHeavyMachine, mass = self:isHeavyMachine(vehicle)

    damage = damage * self:getImpactSpeedMultiplier(previousSpeed)
    damage = damage * self:getMassDamageMultiplier(mass)

    local impactProfile = "standard"
    local maxDamage = self.MAX_DAMAGE

    if isHeavyMachine then
        impactProfile = "heavy"
        damage = damage * self.HEAVY_MACHINE_MULTIPLIER
        damage = math.max(damage, self:getHeavyMachineMinimumDamage(speedDrop, previousSpeed))
        maxDamage = self.HEAVY_MACHINE_MAX_DAMAGE
    end

    damage = math.max(damage, self:getImpactMinimumDamage(speedDrop, previousSpeed))

    return self:finalizeCalculatedDamage(damage, maxDamage), impactProfile, mass
end

function FSCollisionDamage:finalizeCalculatedDamage(damage, maxDamage)
    damage = tonumber(damage) or 0
    maxDamage = tonumber(maxDamage) or self.MAX_DAMAGE

    damage = math.min(maxDamage, math.max(self.MIN_DAMAGE, damage))
    damage = damage * self:getDamageMultiplier()

    return self:clampDamageValue(damage)
end

function FSCollisionDamage:getDamageMultiplier()
    local multiplier = tonumber(self.DAMAGE_MULTIPLIER) or 1.0
    return math.max(0, multiplier)
end

function FSCollisionDamage:clampDamageValue(value)
    value = tonumber(value) or 0
    return math.min(1, math.max(0, value))
end

function FSCollisionDamage:isHeavyMachine(vehicle)
    if vehicle == nil then
        return false, nil
    end

    local mass = self:getVehicleMassTonnes(vehicle)

    if vehicle.spec_combine ~= nil or (vehicle.spec_pipe ~= nil and vehicle.spec_fillUnit ~= nil) then
        return true, mass
    end

    if mass ~= nil and mass >= self.HEAVY_MACHINE_MIN_MASS_T then
        return true, mass
    end

    return false, mass
end

function FSCollisionDamage:getVehicleMassTonnes(vehicle)
    if vehicle == nil or vehicle.getTotalMass == nil then
        return nil
    end

    local ok, mass = pcall(vehicle.getTotalMass, vehicle, false)
    if not ok or mass == nil then
        return nil
    end

    mass = tonumber(mass)
    if mass == nil or mass <= 0 then
        return nil
    end

    -- Giants usually returns tonnes here. This fallback keeps the value sane if
    -- a modded vehicle returns kilograms instead.
    if mass > 100 then
        mass = mass / 1000
    end

    return mass
end

function FSCollisionDamage:getMassDamageMultiplier(mass)
    mass = tonumber(mass) or 0

    if mass <= self.MASS_BASELINE_T then
        return 1
    end

    local bonus = math.min(self.MASS_MAX_BONUS, (mass - self.MASS_BASELINE_T) * 0.035)
    return 1 + bonus
end

function FSCollisionDamage:getHeavyMachineMinimumDamage(speedDrop, previousSpeed)
    speedDrop = tonumber(speedDrop) or 0
    previousSpeed = tonumber(previousSpeed) or 0

    if previousSpeed < self.HEAVY_MACHINE_MODERATE_SPEED_KMH then
        return 0
    end

    if speedDrop >= self.HEAVY_MACHINE_VERY_STRONG_DROP_KMH then
        return self.HEAVY_MACHINE_VERY_STRONG_MIN_DAMAGE
    end

    if speedDrop >= self.HEAVY_MACHINE_STRONG_DROP_KMH then
        return self.HEAVY_MACHINE_STRONG_MIN_DAMAGE
    end

    if speedDrop >= self.HEAVY_MACHINE_MODERATE_DROP_KMH then
        return self.HEAVY_MACHINE_MODERATE_MIN_DAMAGE
    end

    return 0
end

function FSCollisionDamage:getImpactSpeedMultiplier(previousSpeed)
    previousSpeed = tonumber(previousSpeed) or 0

    if previousSpeed >= self.VERY_HIGH_IMPACT_SPEED_KMH then
        return self.VERY_HIGH_IMPACT_MULTIPLIER
    end

    if previousSpeed >= self.HIGH_IMPACT_SPEED_KMH then
        return self.HIGH_IMPACT_MULTIPLIER
    end

    if previousSpeed >= self.MEDIUM_IMPACT_SPEED_KMH then
        return self.MEDIUM_IMPACT_MULTIPLIER
    end

    return 1
end

function FSCollisionDamage:getImpactMinimumDamage(speedDrop, previousSpeed)
    speedDrop = tonumber(speedDrop) or 0
    previousSpeed = tonumber(previousSpeed) or 0

    if previousSpeed < self.STRONG_IMPACT_SPEED_KMH then
        return 0
    end

    if speedDrop >= self.VERY_STRONG_IMPACT_DROP_KMH then
        return self.VERY_STRONG_IMPACT_MIN_DAMAGE
    end

    if speedDrop >= self.STRONG_IMPACT_DROP_KMH then
        return self.STRONG_IMPACT_MIN_DAMAGE
    end

    return 0
end

function FSCollisionDamage:isLowSpeedVehicleBrakeContact(sourceVehicle, hitObject, speedDrop, newSpeed, contactMode)
    local targetVehicle = self:resolveVehicleObject(hitObject)
    if targetVehicle == nil or sourceVehicle == nil or targetVehicle == sourceVehicle then
        return false
    end

    if self:isKnownAttachedOrSameTrain(sourceVehicle, targetVehicle)
        or self:isDirectAttachmentRelation(sourceVehicle, targetVehicle)
        or self:isVehicleLinkedByLiveAttachmentData(sourceVehicle, targetVehicle) then
        return true
    end

    local mode = string.lower(tostring(contactMode or ""))
    if string.find(mode, "traffic", 1, true) ~= nil then
        return false
    end

    -- Slow or very mild vehicle/tool contact should not create accident damage.
    -- The Kredo braking false positive appears exactly like this: a small speed
    -- drop against a damageable implement while the combination is braking.
    return ((newSpeed or 0) <= 2.0 and (speedDrop or 0) <= 6.0)
        or ((speedDrop or 0) <= 6.5 and string.find(mode, "velocitydelta", 1, true) == nil)
end

function FSCollisionDamage:applyDamage(vehicle, damage, speedDrop, previousSpeed, newSpeed, hitNode, hitObject, contactMode, impactProfile, mass)
    if vehicle == nil or vehicle.isServer == false or not self:getIsServerContext() then
        return false
    end

    if self:isLowSpeedVehicleBrakeContact(vehicle, hitObject, speedDrop, newSpeed, contactMode) then
        self:addDiagnosticAttempt("damage", "suppressedLowSpeedVehicleBrakeContact")
        if self.DAMAGE_LOGGING == true then
            print(string.format(
                "[%s] %s | collision damage suppressed | low speed vehicle brake contact | hit=%s | object=%s | mode=%s | profile=%s",
                self.MOD_NAME,
                tostring(self:getVehicleDebugName(vehicle)),
                self:getNodeDebugName(hitNode),
                self:getObjectDebugName(hitObject),
                tostring(contactMode or "direct"),
                tostring(impactProfile or "standard")
            ))
        end
        return false
    end

    if contactMode ~= "attachedToolProxy" and self:isHitOwnAttachedVehicle(vehicle, hitNode, hitObject) then
        self:addDiagnosticAttempt("damage", "suppressedOwnAttachedVehicle")
        if self.DAMAGE_LOGGING == true then
            print(string.format(
                "[%s] %s | collision damage suppressed | own attached vehicle/train | hit=%s | object=%s | mode=%s | profile=%s",
                self.MOD_NAME,
                tostring(self:getVehicleDebugName(vehicle)),
                self:getNodeDebugName(hitNode),
                self:getObjectDebugName(hitObject),
                tostring(contactMode or "direct"),
                tostring(impactProfile or "standard")
            ))
        end
        return false
    end

    local damageApplied, beforeDamage, afterDamage = self:addDamageToVehicle(vehicle, damage)
    if not damageApplied then
        return false
    end

    if self.DAMAGE_LOGGING == true then
        print(string.format(
            "[%s] %s | collision damage +%.3f | damage %.3f -> %.3f | %.1f -> %.1f km/h | drop %.1f km/h | hit=%s | object=%s | mode=%s | profile=%s | mass=%s",
            self.MOD_NAME,
            tostring(self:getVehicleDebugName(vehicle)),
            damage,
            beforeDamage,
            afterDamage,
            previousSpeed,
            newSpeed,
            speedDrop,
            self:getNodeDebugName(hitNode),
            self:getObjectDebugName(hitObject),
            tostring(contactMode or "direct"),
            tostring(impactProfile or "standard"),
            self:formatMass(mass)
        ))
    end

    return true
end

function FSCollisionDamage:applyCounterpartDamage(sourceVehicle, damage, hitNode, hitObject, contactMode, impactProfile)
    if self.COUNTERPART_DAMAGE_ENABLED ~= true or not self:getIsServerContext() then
        return false
    end

    local targetVehicle = self:getCounterpartDamageVehicle(sourceVehicle, hitNode, hitObject)
    if targetVehicle == nil then
        self:addDiagnosticAttempt("counterpartDamage", "noDamageableVehicleTarget")
        return false
    end

    if self:isKnownAttachedOrSameTrain(sourceVehicle, targetVehicle)
        or self:isDirectAttachmentRelation(sourceVehicle, targetVehicle)
        or self:isVehicleLinkedByLiveAttachmentData(sourceVehicle, targetVehicle) then
        self:addDiagnosticAttempt("counterpartDamage", "suppressedOwnAttachedVehicle")
        return false
    end

    local now = g_time or 0
    local targetState = self:getVehicleState(targetVehicle)
    if now - (targetState.lastDamageTime or 0) < self.DAMAGE_COOLDOWN_MS then
        self:addDiagnosticAttempt("counterpartDamage", "targetCooldown")
        return false
    end

    local damageApplied, beforeDamage, afterDamage = self:addDamageToVehicle(targetVehicle, damage)
    if not damageApplied then
        self:addDiagnosticAttempt("counterpartDamage", "noDamageMethod")
        return false
    end

    -- Mark the target as recently damaged so the same physical crash cannot be
    -- counted again from the target vehicle's next update tick.
    targetState.lastDamageTime = now

    if self.DAMAGE_LOGGING == true then
        print(string.format(
            "[%s] %s | counterpart collision damage +%.3f | damage %.3f -> %.3f | source=%s | hit=%s | object=%s | mode=%s | profile=%s",
            self.MOD_NAME,
            tostring(self:getVehicleDebugName(targetVehicle)),
            damage,
            beforeDamage,
            afterDamage,
            tostring(self:getVehicleDebugName(sourceVehicle)),
            self:getNodeDebugName(hitNode),
            self:getObjectDebugName(hitObject),
            tostring(contactMode or "direct"),
            tostring(impactProfile or "standard")
        ))
    end

    self:addDiagnosticAttempt("counterpartDamage", "applied")
    return true
end

function FSCollisionDamage:addDamageToVehicle(vehicle, damage)
    if vehicle == nil then
        return false, 0, 0
    end

    damage = tonumber(damage) or 0
    if damage <= 0 then
        local currentDamage = self:getCurrentDamage(vehicle)
        return false, currentDamage, currentDamage
    end

    local beforeDamage = self:getCurrentDamage(vehicle)
    local targetDamage = self:clampDamageValue(beforeDamage + damage)

    if targetDamage <= beforeDamage then
        return false, beforeDamage, beforeDamage
    end

    if vehicle.setDamageAmount ~= nil then
        vehicle:setDamageAmount(targetDamage, true)
    elseif vehicle.addDamageAmount ~= nil then
        vehicle:addDamageAmount(damage, true)
    else
        return false, beforeDamage, beforeDamage
    end

    return true, beforeDamage, self:getCurrentDamage(vehicle)
end

function FSCollisionDamage:getCounterpartDamageVehicle(sourceVehicle, hitNode, hitObject)
    local targetVehicle = self:getDamageableCounterpartCandidate(sourceVehicle, hitObject)
    if targetVehicle ~= nil then
        return targetVehicle
    end

    local nodeObject = self:getNodeObject(hitNode)
    if nodeObject ~= nil and nodeObject ~= hitObject then
        targetVehicle = self:getDamageableCounterpartCandidate(sourceVehicle, nodeObject)
        if targetVehicle ~= nil then
            return targetVehicle
        end
    end

    -- Some sub objects are mapped to their root vehicle only indirectly. Use the
    -- root vehicle as a fallback if the directly hit object itself is not
    -- damageable, for example with unusual tool or trailer node registrations.
    if hitObject ~= nil and hitObject.getRootVehicle ~= nil then
        targetVehicle = self:getDamageableCounterpartCandidate(sourceVehicle, hitObject:getRootVehicle())
        if targetVehicle ~= nil then
            return targetVehicle
        end
    end

    if nodeObject ~= nil and nodeObject.getRootVehicle ~= nil then
        targetVehicle = self:getDamageableCounterpartCandidate(sourceVehicle, nodeObject:getRootVehicle())
        if targetVehicle ~= nil then
            return targetVehicle
        end
    end

    return nil
end

function FSCollisionDamage:getDamageableCounterpartCandidate(sourceVehicle, candidate)
    if not self:isDamageableCounterpartVehicle(sourceVehicle, candidate) then
        return nil
    end

    return candidate
end

function FSCollisionDamage:isDamageableCounterpartVehicle(sourceVehicle, candidate)
    if sourceVehicle == nil or candidate == nil or type(candidate) ~= "table" then
        return false
    end

    if candidate == sourceVehicle then
        return false
    end

    if candidate.isServer == false then
        return false
    end

    if candidate.rootNode == nil then
        return false
    end

    if candidate.spec_wearable == nil then
        return false
    end

    if candidate.setDamageAmount == nil and candidate.addDamageAmount == nil then
        return false
    end

    -- Do not damage the same vehicle train twice. Own trailers and attached
    -- tools are already part of the source vehicle AABBs and must not become a
    -- second accident participant, even if a modded tool exposes an unusual
    -- rootVehicle/attacher relationship.
    if self:isKnownAttachedOrSameTrain(sourceVehicle, candidate)
        or self:isDirectAttachmentRelation(sourceVehicle, candidate)
        or self:isVehicleLinkedByLiveAttachmentData(sourceVehicle, candidate) then
        return false
    end

    local sourceRoot = self:getVehicleTrainRoot(sourceVehicle) or sourceVehicle
    local candidateRoot = self:getVehicleTrainRoot(candidate) or candidate

    if candidate.getIsAttachedTo ~= nil and candidate:getIsAttachedTo(sourceRoot) then
        return false
    end

    if sourceVehicle.getIsAttachedTo ~= nil and sourceVehicle:getIsAttachedTo(candidateRoot) then
        return false
    end

    return true
end

function FSCollisionDamage:getCurrentDamage(vehicle)
    if vehicle ~= nil and vehicle.getDamageAmount ~= nil then
        return vehicle:getDamageAmount() or 0
    end

    if vehicle ~= nil and vehicle.spec_wearable ~= nil then
        return vehicle.spec_wearable.damage or 0
    end

    return 0
end

-- ============================================================
-- Directional raycast fallback
-- ============================================================

function FSCollisionDamage:raycastAgainstAABBs(vehicle, aabbs, ownNodes, dirX, dirZ, profile)
    if aabbs == nil then
        return false, nil, nil, nil
    end

    local trainRoot = self:getVehicleTrainRoot(vehicle)
    local trainVehicles = self.currentVehicleTrainVehicles or self:buildCollisionVehicleLookup(vehicle)
    local resolvedOwnNodes = ownNodes or self:buildOwnNodeLookup(vehicle)
    local attachedOwnNodes = nil
    if self.ATTACHED_TOOL_PROXY_ENABLED == true then
        attachedOwnNodes = self:buildAttachedOwnNodeLookup(vehicle)
    end
    local bestHitNode = nil
    local bestHitObject = nil
    local bestPriority = -1
    local ownAttachmentHitNode = nil

    for _, aabb in ipairs(aabbs) do
        local hasHit, hitNode, hitObject, attachedHitNode = self:raycastFromAABB(vehicle, aabb, resolvedOwnNodes, dirX, dirZ, profile, trainRoot, trainVehicles, attachedOwnNodes)
        if ownAttachmentHitNode == nil and attachedHitNode ~= nil then
            ownAttachmentHitNode = attachedHitNode
        end

        if hasHit then
            local priority = self:getCollisionCandidatePriority(hitNode, hitObject)
            if priority > bestPriority then
                bestPriority = priority
                bestHitNode = hitNode
                bestHitObject = hitObject
            end

            if priority >= (self.COLLISION_STOP_PRIORITY or 90) then
                return true, hitNode, hitObject, ownAttachmentHitNode
            end
        end
    end

    if bestHitNode ~= nil then
        return true, bestHitNode, bestHitObject, ownAttachmentHitNode
    end

    return false, nil, nil, ownAttachmentHitNode
end

function FSCollisionDamage:raycastFromAABB(vehicle, aabb, ownNodes, dirX, dirZ, profile, trainRoot, trainVehicles, attachedOwnNodes)
    local points = self:getDirectionalRaycastPoints(aabb, dirX, dirZ, profile)
    if points == nil then
        return false, nil, nil, nil
    end

    self.currentVehicle = vehicle
    self.currentVehicleTrainRoot = trainRoot or self:getVehicleTrainRoot(vehicle)
    self.currentVehicleTrainVehicles = trainVehicles or self.currentVehicleTrainVehicles or self:buildCollisionVehicleLookup(vehicle)
    self.currentOwnNodes = ownNodes or self:buildOwnNodeLookup(vehicle)
    self.currentOwnAttachmentNodes = attachedOwnNodes
    local ownAttachmentHitNode = nil

    for _, point in ipairs(points) do
        self.currentRaycastHit = false
        self.currentRaycastHitNode = nil
        self.currentRaycastHitObject = nil
        self.currentRaycastHitPriority = -1
        self.currentRaycastHitReason = nil
        self.currentRaycastOwnAttachmentHit = false
        self.currentRaycastOwnAttachmentHitNode = nil

        raycastAll(
            point[1],
            point[2],
            point[3],
            dirX,
            0,
            dirZ,
            profile.maxDistance,
            "raycastContactCallback",
            self,
            nil
        )

        if ownAttachmentHitNode == nil and self.currentRaycastOwnAttachmentHit == true then
            ownAttachmentHitNode = self.currentRaycastOwnAttachmentHitNode
        end

        if self.currentRaycastHit == true then
            local hitNode = self.currentRaycastHitNode
            local hitObject = self.currentRaycastHitObject
            self:resetRaycastContext()
            return true, hitNode, hitObject, ownAttachmentHitNode
        end
    end

    self:resetRaycastContext()
    return false, nil, nil, ownAttachmentHitNode
end

function FSCollisionDamage:getDirectionalRaycastPoints(aabb, dirX, dirZ, profile)
    if aabb == nil or dirX == nil or dirZ == nil or profile == nil then
        return nil
    end

    local minX, maxX, minY, maxY, minZ, maxZ = aabb[1], aabb[2], aabb[3], aabb[4], aabb[5], aabb[6]
    if minX == nil then
        return nil
    end

    local centerX = (minX + maxX) * 0.5
    local centerZ = (minZ + maxZ) * 0.5
    local halfX = math.max(0.05, (maxX - minX) * 0.5)
    local halfZ = math.max(0.05, (maxZ - minZ) * 0.5)
    local height = math.max(0.1, maxY - minY)
    local supportDistance = math.abs(dirX) * halfX + math.abs(dirZ) * halfZ
    local frontDistance = math.max(0.05, supportDistance - profile.backOffset)
    local startX = centerX + dirX * frontDistance
    local startZ = centerZ + dirZ * frontDistance
    local sideX = -dirZ
    local sideZ = dirX
    local sideExtent = math.abs(sideX) * halfX + math.abs(sideZ) * halfZ
    local sideOffset = math.min(profile.sideOffsetMax, sideExtent * profile.sideFraction)
    local heightFractions = profile.heightFractions or { 0.35, 0.62 }
    local points = {}

    local function addPoint(offset, y)
        table.insert(points, { startX + sideX * offset, y, startZ + sideZ * offset })
    end

    for _, fraction in ipairs(heightFractions) do
        local y = minY + math.min(profile.maxHeight, math.max(profile.minHeight, height * fraction))
        addPoint(0, y)

        if sideOffset > 0.20 then
            addPoint(sideOffset, y)
            addPoint(-sideOffset, y)
        end
    end

    return #points > 0 and points or nil
end

function FSCollisionDamage:processCollisionCallbackNode(nodeId, isRaycast)
    if nodeId == nil or nodeId == 0 then
        return true
    end

    if self:isOwnNode(nodeId) then
        if isRaycast == true and self:isOwnAttachedNode(nodeId) then
            self.currentRaycastOwnAttachmentHit = true
            if self.currentRaycastOwnAttachmentHitNode == nil then
                self.currentRaycastOwnAttachmentHitNode = nodeId
            end
        end
        self:recordIgnoredCollision("ownNode", nodeId, nil)
        return true
    end

    if g_terrainNode ~= nil and nodeId == g_terrainNode then
        self:recordIgnoredCollision("terrain", nodeId, nil)
        return true
    end

    if self:shouldIgnoreMapCollisionNode(nodeId) then
        self:recordIgnoredCollision("mapBoundaryOrWater", nodeId, nil)
        return true
    end

    local object = self:getNodeObject(nodeId)
    if self:isOwnOrAttachedObject(object) then
        self:recordIgnoredCollision("ownOrAttachedObject", nodeId, object)
        return true
    end

    if self:shouldIgnoreLooseCollisionObject(nodeId, object) then
        self:recordIgnoredCollision("looseCargoObject", nodeId, object)
        return true
    end

    if self:shouldIgnoreInteractionTrigger(nodeId, object) then
        self:recordIgnoredCollision("interactionTrigger", nodeId, object)
        return true
    end

    local shouldStop = self:considerCollisionCandidate(nodeId, object, isRaycast == true)
    return not shouldStop
end

function FSCollisionDamage:raycastContactCallback(nodeId, x, y, z, distance, nx, ny, nz, subShapeIndex, shapeId, isLast)
    -- Returning true continues searching. Only high-confidence targets stop the
    -- callback early; lower-confidence anonymous map nodes are kept as fallback
    -- while the query continues looking for better objects behind/above them.
    return self:processCollisionCallbackNode(nodeId, true)
end

function FSCollisionDamage:normalizeHorizontalDirection(dirX, dirZ)
    dirX = tonumber(dirX)
    dirZ = tonumber(dirZ)

    if dirX == nil or dirZ == nil then
        return nil, nil
    end

    local length = math.sqrt(dirX * dirX + dirZ * dirZ)
    if length < 0.001 then
        return nil, nil
    end

    return dirX / length, dirZ / length
end

function FSCollisionDamage:resetRaycastContext()
    self.currentVehicle = nil
    self.currentVehicleTrainRoot = nil
    self.currentVehicleTrainVehicles = nil
    self.currentOwnNodes = nil
    self.currentOwnAttachmentNodes = nil
    self.currentRaycastHit = false
    self.currentRaycastHitNode = nil
    self.currentRaycastHitObject = nil
    self.currentRaycastHitPriority = -1
    self.currentRaycastHitReason = nil
    self.currentRaycastOwnAttachmentHit = false
    self.currentRaycastOwnAttachmentHitNode = nil
end

-- ============================================================
-- Overlap query
-- ============================================================

function FSCollisionDamage:hasForeignCollisionShapeNearVehicle(vehicle, aabb, ownNodes, marginX, marginY, marginZ, exactTest, trainRoot, trainVehicles)
    local minX, maxX, minY, maxY, minZ, maxZ = aabb[1], aabb[2], aabb[3], aabb[4], aabb[5], aabb[6]
    if minX == nil then
        return false, nil, nil
    end

    self.currentVehicle = vehicle
    self.currentVehicleTrainRoot = trainRoot or self:getVehicleTrainRoot(vehicle)
    self.currentVehicleTrainVehicles = trainVehicles or self.currentVehicleTrainVehicles or self:buildCollisionVehicleLookup(vehicle)
    self.currentOwnNodes = ownNodes or self:buildOwnNodeLookup(vehicle)
    self.currentHit = false
    self.currentHitNode = nil
    self.currentHitObject = nil
    self.currentHitPriority = -1
    self.currentHitReason = nil

    overlapBox(
        (minX + maxX) * 0.5,
        (minY + maxY) * 0.5,
        (minZ + maxZ) * 0.5,
        0,
        0,
        0,
        math.max(0.25, ((maxX - minX) * 0.5) + (marginX or 0)),
        math.max(0.25, ((maxY - minY) * 0.5) + (marginY or 0)),
        math.max(0.25, ((maxZ - minZ) * 0.5) + (marginZ or 0)),
        "overlapCallback",
        self,
        nil,
        true,
        true,
        true,
        exactTest == true
    )

    local hit = self.currentHit == true
    local hitNode = self.currentHitNode
    local hitObject = self.currentHitObject

    self:resetOverlapContext()

    return hit, hitNode, hitObject
end

function FSCollisionDamage:overlapCallback(nodeId, subShapeIndex)
    -- overlapBox expects true to continue and false to stop. High-confidence
    -- targets may stop the query; anonymous static nodes only become fallback
    -- candidates so they cannot hide a better vehicle/placeable/traffic hit.
    return self:processCollisionCallbackNode(nodeId, false)
end

function FSCollisionDamage:hasForeignCollisionShapeNearAABBs(vehicle, aabbs, ownNodes, marginX, marginY, marginZ, exactTest)
    if aabbs == nil then
        return false, nil, nil
    end

    local trainRoot = self:getVehicleTrainRoot(vehicle)
    local trainVehicles = self.currentVehicleTrainVehicles or self:buildCollisionVehicleLookup(vehicle)
    local resolvedOwnNodes = ownNodes or self:buildOwnNodeLookup(vehicle)
    local bestHitNode = nil
    local bestHitObject = nil
    local bestPriority = -1

    for _, aabb in ipairs(aabbs) do
        local hasHit, hitNode, hitObject = self:hasForeignCollisionShapeNearVehicle(
            vehicle,
            aabb,
            resolvedOwnNodes,
            marginX,
            marginY,
            marginZ,
            exactTest,
            trainRoot,
            trainVehicles
        )

        if hasHit then
            local priority = self:getCollisionCandidatePriority(hitNode, hitObject)
            if priority > bestPriority then
                bestPriority = priority
                bestHitNode = hitNode
                bestHitObject = hitObject
            end

            if priority >= (self.COLLISION_STOP_PRIORITY or 90) then
                return true, hitNode, hitObject
            end
        end
    end

    if bestHitNode ~= nil then
        return true, bestHitNode, bestHitObject
    end

    return false, nil, nil
end

function FSCollisionDamage:getVehicleAABBs(vehicle)
    local aabbs = {}

    -- Performance-safe source area: only the current train root, the checked
    -- vehicle and a small number of directly attached vehicles are used for
    -- broad collision searches. The full attachment registry is deliberately
    -- not used here; on large savegames it can pull far too many machines into
    -- the source train and make every overlap/raycast query extremely costly.
    local vehicleLookup = self:buildCollisionVehicleLookup(vehicle)
    for trainVehicle, _ in pairs(vehicleLookup) do
        self:addVehicleAABB(trainVehicle, aabbs)
        if self.COLLISION_MAX_TRAIN_VEHICLES ~= nil and #aabbs >= self.COLLISION_MAX_TRAIN_VEHICLES then
            break
        end
    end

    return #aabbs > 0 and aabbs or nil
end

function FSCollisionDamage:buildCollisionVehicleLookup(vehicle)
    local cache = self:getCheckCacheBucket("collisionLookupByVehicle")
    if cache ~= nil and cache[vehicle] ~= nil then
        return cache[vehicle]
    end

    local vehicleLookup = {}
    local maxVehicles = self.COLLISION_MAX_TRAIN_VEHICLES or 8
    local count = 0

    local function add(candidate)
        candidate = self:resolveVehicleObject(candidate)
        if type(candidate) ~= "table" or candidate.rootNode == nil or vehicleLookup[candidate] == true then
            return false
        end

        if count >= maxVehicles then
            return false
        end

        vehicleLookup[candidate] = true
        count = count + 1
        return true
    end

    local rootVehicle = self:getVehicleTrainRoot(vehicle) or vehicle
    add(rootVehicle)
    add(vehicle)

    if self.COLLISION_INCLUDE_DIRECT_ATTACHED_VEHICLES == true then
        local function addDirect(source)
            if count >= maxVehicles then
                return
            end

            local direct = self:getDirectAttachedVehicleLookup(source)
            for childVehicle, _ in pairs(direct) do
                add(childVehicle)
                if count >= maxVehicles then
                    return
                end
            end
        end

        addDirect(rootVehicle)
        addDirect(vehicle)
    end

    if cache ~= nil then
        cache[vehicle] = vehicleLookup
    end

    return vehicleLookup
end

function FSCollisionDamage:addVehicleAABB(vehicle, aabbs)
    local aabb = self:getSingleVehicleAABB(vehicle)
    if aabb ~= nil then
        table.insert(aabbs, aabb)
    end
end

function FSCollisionDamage:getSingleVehicleAABB(vehicle)
    if vehicle == nil then
        return nil
    end

    local cache = self:getCheckCacheBucket("singleAABBByVehicle")
    if cache ~= nil and cache[vehicle] ~= nil then
        local cached = cache[vehicle]
        return cached ~= false and cached or nil
    end

    local minX, maxX, minY, maxY, minZ, maxZ = nil, nil, nil, nil, nil, nil

    local function includeNode(node)
        if node == nil then
            return
        end

        local nodeMinX, nodeMaxX, nodeMinY, nodeMaxY, nodeMinZ, nodeMaxZ = getRigidBodyAABB(node)
        if nodeMinX == nil then
            return
        end

        if minX == nil then
            minX, maxX = nodeMinX, nodeMaxX
            minY, maxY = nodeMinY, nodeMaxY
            minZ, maxZ = nodeMinZ, nodeMaxZ
        else
            minX = math.min(minX, nodeMinX)
            maxX = math.max(maxX, nodeMaxX)
            minY = math.min(minY, nodeMinY)
            maxY = math.max(maxY, nodeMaxY)
            minZ = math.min(minZ, nodeMinZ)
            maxZ = math.max(maxZ, nodeMaxZ)
        end
    end

    if vehicle.components ~= nil then
        for _, component in pairs(vehicle.components) do
            includeNode(component.node)
        end
    end

    if minX == nil then
        includeNode(vehicle.rootNode)
    end

    if minX == nil then
        if cache ~= nil then
            cache[vehicle] = false
        end
        return nil
    end

    local result = { minX, maxX, minY, maxY, minZ, maxZ }
    if cache ~= nil then
        cache[vehicle] = result
    end

    return result
end

function FSCollisionDamage:buildOwnNodeLookup(vehicle)
    local cache = self:getCheckCacheBucket("ownNodeLookupByVehicle")
    if cache ~= nil and cache[vehicle] ~= nil then
        return cache[vehicle]
    end

    local nodes = {}

    -- Own-node detection must include the complete attached vehicle train, not
    -- only direct attachments. Frontloader -> tool chains can otherwise appear
    -- as a foreign collision during steering/braking tests.
    local vehicleLookup = self:buildVehicleTrainVehicleLookup(vehicle)

    for trainVehicle, _ in pairs(vehicleLookup) do
        self:addVehicleNodesToLookup(trainVehicle, nodes)
    end

    if cache ~= nil then
        cache[vehicle] = nodes
    end

    return nodes
end

function FSCollisionDamage:buildAttachedOwnNodeLookup(vehicle)
    local cache = self:getCheckCacheBucket("attachedOwnNodeLookupByVehicle")
    if cache ~= nil and cache[vehicle] ~= nil then
        return cache[vehicle]
    end

    local nodes = {}
    local rootVehicle = self:getVehicleTrainRoot(vehicle) or vehicle
    local vehicleLookup = self:buildVehicleTrainVehicleLookup(vehicle)

    for trainVehicle, _ in pairs(vehicleLookup) do
        if trainVehicle ~= nil and trainVehicle ~= rootVehicle then
            self:addVehicleNodesToLookup(trainVehicle, nodes)
        end
    end

    if cache ~= nil then
        cache[vehicle] = nodes
    end

    return nodes
end

function FSCollisionDamage:isHitOwnAttachedVehicle(sourceVehicle, hitNode, hitObject)
    if sourceVehicle == nil then
        return false
    end

    self:ensureAttachmentRegistryFresh()

    local objectVehicle = self:resolveVehicleObject(hitObject)
    if objectVehicle ~= nil then
        if self:isKnownAttachedOrSameTrain(sourceVehicle, objectVehicle) then
            return true
        end
        if self:isDirectAttachmentRelation(sourceVehicle, objectVehicle) then
            return true
        end
    end

    local nodeObject = self:getNodeObject(hitNode)
    local nodeVehicle = self:resolveVehicleObject(nodeObject)
    if nodeVehicle ~= nil then
        if self:isKnownAttachedOrSameTrain(sourceVehicle, nodeVehicle) then
            return true
        end
        if self:isDirectAttachmentRelation(sourceVehicle, nodeVehicle) then
            return true
        end
        if self:isVehicleLinkedByLiveAttachmentData(sourceVehicle, nodeVehicle) then
            return true
        end
    end

    if self.HIT_NODE_VEHICLE_SCAN_ENABLED == true then
        local hitNodeVehicle = self:findVehicleByNode(hitNode)
        if hitNodeVehicle ~= nil then
            if self:isKnownAttachedOrSameTrain(sourceVehicle, hitNodeVehicle) then
                return true
            end
            if self:isDirectAttachmentRelation(sourceVehicle, hitNodeVehicle) then
                return true
            end
            if self:isVehicleLinkedByLiveAttachmentData(sourceVehicle, hitNodeVehicle) then
                return true
            end
        end
    end

    return false
end

function FSCollisionDamage:isOwnNode(nodeId)
    if nodeId == nil or nodeId == 0 then
        return false
    end

    for trainVehicle, _ in pairs(self.currentVehicleTrainVehicles or {}) do
        if trainVehicle ~= nil and trainVehicle.getIsVehicleNode ~= nil then
            local ok, isVehicleNode = pcall(trainVehicle.getIsVehicleNode, trainVehicle, nodeId)
            if ok and isVehicleNode == true then
                return true
            end
        end
    end

    if self.currentOwnNodes == nil then
        return false
    end

    local node = nodeId
    local guard = 0
    while node ~= nil and node ~= 0 and guard < 64 do
        if self.currentOwnNodes[node] == true then
            return true
        end

        if getParent == nil then
            break
        end

        node = getParent(node)
        guard = guard + 1
    end

    return false
end

function FSCollisionDamage:isOwnAttachedNode(nodeId)
    if nodeId == nil or nodeId == 0 then
        return false
    end

    local rootVehicle = self.currentVehicleTrainRoot or self:getVehicleTrainRoot(self.currentVehicle)
    for trainVehicle, _ in pairs(self.currentVehicleTrainVehicles or {}) do
        if trainVehicle ~= nil and trainVehicle ~= rootVehicle and trainVehicle.getIsVehicleNode ~= nil then
            local ok, isVehicleNode = pcall(trainVehicle.getIsVehicleNode, trainVehicle, nodeId)
            if ok and isVehicleNode == true then
                return true
            end
        end
    end

    if self.currentOwnAttachmentNodes == nil then
        return false
    end

    local node = nodeId
    local guard = 0
    while node ~= nil and node ~= 0 and guard < 64 do
        if self.currentOwnAttachmentNodes[node] == true then
            return true
        end

        if getParent == nil then
            break
        end

        node = getParent(node)
        guard = guard + 1
    end

    return false
end

function FSCollisionDamage:isOwnOrAttachedObject(object)
    if object == nil or self.currentVehicle == nil then
        return false
    end

    if self:isObjectInCurrentVehicleTrain(object) then
        return true
    end

    local vehicleObject = self:resolveVehicleObject(object)
    if vehicleObject ~= nil and self:isKnownAttachedOrSameTrain(self.currentVehicle, vehicleObject) then
        return true
    end

    if object == self.currentVehicle then
        return true
    end

    if object.getRootVehicle ~= nil and object:getRootVehicle() == self.currentVehicle then
        return true
    end

    if object.getIsAttachedTo ~= nil and object:getIsAttachedTo(self.currentVehicle) then
        return true
    end

    if self.currentVehicle.getIsAttachedTo ~= nil and self.currentVehicle:getIsAttachedTo(object) then
        return true
    end

    return false
end

function FSCollisionDamage:shouldIgnoreLooseCollisionObject(nodeId, object)
    if object == nil then
        return false
    end

    -- Loose cargo should not count as an accident target. This prevents frontloader
    -- tests with bale spike/bales/pallets from turning cargo contact into vehicle
    -- damage while still allowing true vehicle/placeable/static collisions.
    if self:resolveVehicleObject(object) ~= nil then
        return false
    end

    local text = string.lower(tostring(object.typeName or object.className or object.configFileName or ""))
    if object.getFullName ~= nil then
        local ok, name = pcall(object.getFullName, object)
        if ok and name ~= nil then
            text = text .. " " .. string.lower(tostring(name))
        end
    end
    if object.getName ~= nil then
        local ok, name = pcall(object.getName, object)
        if ok and name ~= nil then
            text = text .. " " .. string.lower(tostring(name))
        end
    end

    local nodeText = ""
    if nodeId ~= nil and nodeId ~= 0 and getName ~= nil then
        local ok, name = pcall(getName, nodeId)
        if ok and name ~= nil then
            nodeText = string.lower(tostring(name))
        end
    end

    local combined = text .. " " .. nodeText
    return string.find(combined, "bale", 1, true) ~= nil
        or string.find(combined, "ballen", 1, true) ~= nil
        or string.find(combined, "pallet", 1, true) ~= nil
        or string.find(combined, "palette", 1, true) ~= nil
        or string.find(combined, "bigbag", 1, true) ~= nil
end

function FSCollisionDamage:considerCollisionCandidate(nodeId, object, isRaycast)
    local priority, reason = self:getCollisionCandidatePriority(nodeId, object)
    local currentPriorityField = isRaycast == true and "currentRaycastHitPriority" or "currentHitPriority"
    local currentNodeField = isRaycast == true and "currentRaycastHitNode" or "currentHitNode"
    local currentObjectField = isRaycast == true and "currentRaycastHitObject" or "currentHitObject"
    local currentReasonField = isRaycast == true and "currentRaycastHitReason" or "currentHitReason"
    local currentHitField = isRaycast == true and "currentRaycastHit" or "currentHit"

    if priority > (self[currentPriorityField] or -1) then
        self[currentHitField] = true
        self[currentNodeField] = nodeId
        self[currentObjectField] = object
        self[currentPriorityField] = priority
        self[currentReasonField] = reason
    end

    if reason == "roadLikeStatic" then
        self:recordIgnoredCollision("roadLikeCandidate", nodeId, object)
    end

    return priority >= (self.COLLISION_STOP_PRIORITY or 90)
end

function FSCollisionDamage:getCollisionCandidatePriority(nodeId, object)
    if object ~= nil then
        local targetVehicle = self:resolveVehicleObject(object)
        if targetVehicle ~= nil then
            return self.CANDIDATE_PRIORITY_OTHER_VEHICLE or 100, "otherVehicle"
        end

        return self.CANDIDATE_PRIORITY_OBJECT or 85, "luaObject"
    end

    if self:isTrafficCollisionNode(nodeId) then
        return self.CANDIDATE_PRIORITY_TRAFFIC or 95, "trafficNode"
    end

    if self:isAnonymousDynamicCollisionNode(nodeId) then
        return self.CANDIDATE_PRIORITY_DYNAMIC_ANONYMOUS or 72, "dynamicAnonymous"
    end

    if self:isNamedStaticObstacleCollisionNode(nodeId) then
        return self.CANDIDATE_PRIORITY_NAMED_STATIC or 55, "namedStatic"
    end

    if self:shouldIgnoreRoadCollisionNode(nodeId) then
        return self.CANDIDATE_PRIORITY_ROAD_LIKE_STATIC or 8, "roadLikeStatic"
    end

    if self:isAnonymousGenericMapCollisionNode(nodeId) then
        return self.CANDIDATE_PRIORITY_GENERIC_STATIC or 25, "genericStatic"
    end

    return self.CANDIDATE_PRIORITY_UNKNOWN_STATIC or 35, "unknownStatic"
end

function FSCollisionDamage:shouldIgnoreMapCollisionNode(nodeId)
    return self:nodeNameChainContainsAny(nodeId, self.IGNORED_NODE_NAME_PARTS)
end

function FSCollisionDamage:shouldIgnoreInteractionTrigger(nodeId, object)
    if self:nodeNameChainContainsAny(nodeId, self.IGNORED_TRIGGER_NODE_NAME_PARTS) then
        return true
    end

    return self:objectTextContainsAny(object, self.IGNORED_TRIGGER_OBJECT_TEXT_PARTS)
end

function FSCollisionDamage:nodeNameChainContainsAny(nodeId, patterns)
    if nodeId == nil or nodeId == 0 or patterns == nil then
        return false
    end

    local node = nodeId
    local guard = 0

    while node ~= nil and node ~= 0 and guard < 32 do
        local nodeName = getName ~= nil and getName(node) or nil
        if self:textContainsAny(nodeName, patterns) then
            return true
        end

        if getParent == nil then
            break
        end

        node = getParent(node)
        guard = guard + 1
    end

    return false
end

function FSCollisionDamage:objectTextContainsAny(object, patterns)
    if object == nil or patterns == nil then
        return false
    end

    return self:textContainsAny(object.className, patterns)
        or self:textContainsAny(object.typeName, patterns)
        or self:textContainsAny(object.configFileName, patterns)
end

function FSCollisionDamage:textContainsAny(text, patterns)
    if text == nil or text == "" or patterns == nil then
        return false
    end

    local lowerText = string.lower(tostring(text))

    for _, pattern in ipairs(patterns) do
        if pattern ~= nil and string.find(lowerText, string.lower(tostring(pattern)), 1, true) ~= nil then
            return true
        end
    end

    return false
end

function FSCollisionDamage:getNodeObject(nodeId)
    if g_currentMission == nil or g_currentMission.getNodeObject == nil then
        return nil
    end

    local node = nodeId
    local guard = 0

    while node ~= nil and node ~= 0 and guard < 16 do
        local object = g_currentMission:getNodeObject(node)
        if object ~= nil then
            return object
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

    return nil
end

function FSCollisionDamage:resetOverlapContext()
    self.currentVehicle = nil
    self.currentVehicleTrainRoot = nil
    self.currentVehicleTrainVehicles = nil
    self.currentOwnNodes = nil
    self.currentHit = false
    self.currentHitNode = nil
    self.currentHitObject = nil
    self.currentHitPriority = -1
    self.currentHitReason = nil
end

-- ============================================================
-- Helpers / logging
-- ============================================================

function FSCollisionDamage:startDiagnosticAttempt(vehicle, state, details)
    if self.DIAGNOSTIC_LOGGING ~= true then
        self.currentDiagnostic = nil
        return
    end

    self.currentDiagnostic = {
        vehicle = vehicle,
        state = state,
        details = details or {},
        attempts = {},
        ignoredCounts = {},
        ignoredSamples = {}
    }
end

function FSCollisionDamage:addDiagnosticAttempt(mode, result)
    if self.DIAGNOSTIC_LOGGING ~= true or self.currentDiagnostic == nil then
        return
    end

    table.insert(self.currentDiagnostic.attempts, string.format("%s=%s", tostring(mode or "unknown"), tostring(result or "unknown")))
end

function FSCollisionDamage:recordIgnoredCollision(reason, nodeId, object)
    if self.DIAGNOSTIC_LOGGING ~= true or self.currentDiagnostic == nil then
        return
    end

    reason = tostring(reason or "unknown")
    local counts = self.currentDiagnostic.ignoredCounts
    counts[reason] = (counts[reason] or 0) + 1

    local samples = self.currentDiagnostic.ignoredSamples
    if #samples < self.DIAGNOSTIC_REJECT_SAMPLE_LIMIT then
        table.insert(samples, string.format(
            "%s:%s/%s",
            reason,
            self:getNodeDebugName(nodeId),
            self:getObjectDebugName(object)
        ))
    end
end

function FSCollisionDamage:finishDiagnosticAttempt(vehicle, state, result, hitNode, hitObject, contactMode)
    if self.DIAGNOSTIC_LOGGING ~= true or self.currentDiagnostic == nil then
        self.currentDiagnostic = nil
        return
    end

    local diagnostic = self.currentDiagnostic
    self.currentDiagnostic = nil

    state = state or diagnostic.state
    local now = g_time or 0
    if result ~= "damageApplied" and state ~= nil and now - (state.lastDiagnosticLogTime or -100000) < self.DIAGNOSTIC_THROTTLE_MS then
        return
    end

    if state ~= nil then
        state.lastDiagnosticLogTime = now
    end

    local details = diagnostic.details or {}
    local attempts = #diagnostic.attempts > 0 and table.concat(diagnostic.attempts, ",") or "none"
    local ignored = self:formatDiagnosticCounts(diagnostic.ignoredCounts)
    local samples = #diagnostic.ignoredSamples > 0 and table.concat(diagnostic.ignoredSamples, " | ") or "none"
    local aabbText = self:getDiagnosticAABBText(vehicle, details)

    print(string.format(
        "[%s] DIAG %s | result=%s | mode=%s | multiplier=%d%% | speed %.1f->%.1f | drop %.1f | sustainedDrop %.1f | deltaV %.1f | aabbs=%s | combine=%s | heavy=%s | candidates=overlap:%s/raycast:%s | attempts=%s | ignored=%s | samples=%s | hit=%s | object=%s | nodeObject=%s | nodeVehicle=%s | hitPath=%s",
        self.MOD_NAME,
        tostring(self:getVehicleDebugName(vehicle or diagnostic.vehicle)),
        tostring(result or "unknown"),
        tostring(contactMode or "nil"),
        math.floor(self:getDamageMultiplier() * 100 + 0.5),
        details.referenceSpeed or 0,
        details.speed or 0,
        details.speedDrop or 0,
        details.sustainedSpeedDrop or 0,
        details.velocityDeltaKmh or 0,
        aabbText,
        tostring(details.isCombine == true),
        tostring(details.isHeavy == true),
        tostring(self.currentHitReason or "none"),
        tostring(self.currentRaycastHitReason or "none"),
        attempts,
        ignored,
        samples,
        self:getNodeDebugName(hitNode),
        self:getObjectDebugName(hitObject),
        self:getNodeObjectDebugName(hitNode),
        self:getNodeVehicleDebugName(hitNode),
        self:getNodePathDebugName(hitNode)
    ))
end

function FSCollisionDamage:formatDiagnosticCounts(counts)
    if counts == nil then
        return "none"
    end

    local parts = {}
    for reason, count in pairs(counts) do
        table.insert(parts, string.format("%s:%d", tostring(reason), tonumber(count) or 0))
    end

    table.sort(parts)
    return #parts > 0 and table.concat(parts, ",") or "none"
end

function FSCollisionDamage:getDiagnosticAABBText(vehicle, details)
    local count = details ~= nil and details.aabbCount or nil
    local text = tostring(count or 0)

    if details == nil or details.isCombine ~= true then
        return text
    end

    local aabbs = self:getVehicleAABBs(vehicle)
    local aabb = aabbs ~= nil and aabbs[1] or nil
    if aabb == nil then
        return text .. "/combineAABB=nil"
    end

    local width = math.max(0, (aabb[2] or 0) - (aabb[1] or 0))
    local height = math.max(0, (aabb[4] or 0) - (aabb[3] or 0))
    local depth = math.max(0, (aabb[6] or 0) - (aabb[5] or 0))
    return string.format("%s/%.2fx%.2fx%.2f", text, width, height, depth)
end

addModEventListener(FSCollisionDamage)
