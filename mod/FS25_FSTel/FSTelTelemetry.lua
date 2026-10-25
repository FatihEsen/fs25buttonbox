--[[
    FSTel - Telemetry & Virtual Button Box Exporter for Farming Simulator 25
    Compatible with GIANTS Engine 10 / FS25

    High-speed, bidirectional telemetry & control pipeline for FS25.
]]

print("[FSTel] ========================================================")
print("[FSTel] FSTel Telemetry & Control Engine starting up...")
print("[FSTel] Diagnostics:")
print("[FSTel]   type(io) = " .. type(io))
if type(io) == "table" then
    print("[FSTel]   type(io.open) = " .. type(io.open))
end
print("[FSTel]   type(loadXMLFile) = " .. type(loadXMLFile))
print("[FSTel]   type(getUserProfileAppPath) = " .. type(getUserProfileAppPath))
if getUserProfileAppPath ~= nil then
    print("[FSTel]   getUserProfileAppPath() = " .. tostring(getUserProfileAppPath()))
end
print("[FSTel] ========================================================")

FSTelTelemetry = {}
FSTelTelemetry.MOD_NAME = g_currentModName or "FS25_FSTel"
FSTelTelemetry.VERSION = "1.0.0.0"

-- Target ~25 updates per second (40ms)
FSTelTelemetry.TARGET_HZ = 25
FSTelTelemetry.UPDATE_INTERVAL_MS = math.floor(1000 / FSTelTelemetry.TARGET_HZ)

FSTelTelemetry.lastSendTime = 0
FSTelTelemetry.packetSeq = 0
FSTelTelemetry.lastActionSeq = 0
FSTelTelemetry.jsonFilePath = nil
FSTelTelemetry.actionXmlPath = nil
FSTelTelemetry.xmlFilePath = nil
FSTelTelemetry.useIoOpen = false
FSTelTelemetry.useXmlFallback = false
FSTelTelemetry.hasLoggedSetup = false
FSTelTelemetry.hasLoggedFirstWrite = false
FSTelTelemetry.hasLoggedUpdateError = false

-- Bitwise Helper
local function safeBitAnd(a, b)
    if bitAND ~= nil then return bitAND(a, b) end
    if bit ~= nil and bit.band ~= nil then return bit.band(a, b) end
    return ((math.floor(a / b) % 2) == 1) and b or 0
end

-- =========================================================================
-- Pure-Lua Safe JSON Serializer
-- =========================================================================
local FSTelJson = {}

local function escapeString(s)
    local matches = {
        ['\\'] = '\\\\',
        ['"']  = '\\"',
        ['\b'] = '\\b',
        ['\f'] = '\\f',
        ['\n'] = '\\n',
        ['\r'] = '\\r',
        ['\t'] = '\\t'
    }
    return '"' .. s:gsub('["\\%z\1-\31]', function(c)
        return matches[c] or string.format('\\u%.4X', string.byte(c))
    end) .. '"'
end

function FSTelJson.encode(val)
    local t = type(val)
    if t == "nil" then
        return "null"
    elseif t == "boolean" then
        return val and "true" or "false"
    elseif t == "number" then
        if val ~= val or val == math.huge or val == -math.huge then
            return "0"
        end
        if math.floor(val) == val then
            return string.format("%d", val)
        else
            return string.format("%.2f", val)
        end
    elseif t == "string" then
        return escapeString(val)
    elseif t == "table" then
        local isArray = true
        local maxIndex = 0
        local count = 0
        for k, _ in pairs(val) do
            if type(k) == "number" and math.floor(k) == k and k >= 1 then
                if k > maxIndex then maxIndex = k end
            else
                isArray = false
                break
            end
            count = count + 1
        end

        if isArray and (count == maxIndex or count == 0) then
            local items = {}
            for i = 1, maxIndex do
                items[i] = FSTelJson.encode(val[i])
            end
            return "[" .. table.concat(items, ",") .. "]"
        else
            local entries = {}
            for k, v in pairs(val) do
                if type(k) == "string" or type(k) == "number" then
                    table.insert(entries, escapeString(tostring(k)) .. ":" .. FSTelJson.encode(v))
                end
            end
            return "{" .. table.concat(entries, ",") .. "}"
        end
    end
    return "null"
end

-- =========================================================================
-- Transport Initialization
-- =========================================================================

function FSTelTelemetry:initTransport()
    if self.hasLoggedSetup then return end
    self.hasLoggedSetup = true

    local basePath = ""
    if getUserProfileAppPath ~= nil then
        basePath = getUserProfileAppPath()
    end

    if basePath == nil or basePath == "" then
        basePath = "D:/Documents/My Games/FarmingSimulator2025/"
    end

    basePath = basePath:gsub("\\", "/")
    if not basePath:match("/$") then
        basePath = basePath .. "/"
    end

    self.jsonFilePath = basePath .. "fstel_telemetry.json"
    self.actionXmlPath = basePath .. "fstel_action.xml"
    self.xmlFilePath = basePath .. "fstel_telemetry.xml"

    if type(io) == "table" and type(io.open) == "function" then
        local testFile = io.open(self.jsonFilePath, "w")
        if testFile ~= nil then
            testFile:write('{"status":"init"}\n')
            testFile:close()
            self.useIoOpen = true
            print(string.format("[%s] High-speed Bidirectional IPC active: %s", self.MOD_NAME, self.jsonFilePath))
            return
        end
    end

    if createXMLFile ~= nil and saveXMLFile ~= nil and setXMLString ~= nil then
        self.useXmlFallback = true
        print(string.format("[%s] GIANTS XML IPC active: %s", self.MOD_NAME, self.xmlFilePath))
        return
    end

    print(string.format("[%s] ERROR: Neither io.open nor GIANTS XML file API available!", self.MOD_NAME))
end

function FSTelTelemetry:loadMap(name)
    self:initTransport()
end

function FSTelTelemetry:deleteMap()
    print(string.format("[%s] Exiting map.", self.MOD_NAME))
end

-- =========================================================================
-- Vehicle Detection (FS25 multi-fallback)
-- =========================================================================

function FSTelTelemetry:getControlledVehicle()
    if g_currentMission == nil then
        return nil
    end

    if g_currentMission.controlledVehicle ~= nil then
        return g_currentMission.controlledVehicle
    end

    if g_localPlayer ~= nil and type(g_localPlayer.getCurrentVehicle) == "function" then
        local ok, veh = pcall(function() return g_localPlayer:getCurrentVehicle() end)
        if ok and veh ~= nil then return veh end
    end

    if g_currentMission.player ~= nil and type(g_currentMission.player.getCurrentVehicle) == "function" then
        local ok, veh = pcall(function() return g_currentMission.player:getCurrentVehicle() end)
        if ok and veh ~= nil then return veh end
    end

    if g_currentMission.interactiveVehicle ~= nil then
        return g_currentMission.interactiveVehicle
    end

    if g_currentMission.vehicleSystem ~= nil and type(g_currentMission.vehicleSystem.getControlledVehicle) == "function" then
        local ok, veh = pcall(function() return g_currentMission.vehicleSystem:getControlledVehicle() end)
        if ok and veh ~= nil then return veh end
    end

    return nil
end

-- =========================================================================
-- In-Game Action Executor (Direct Vehicle Control)
-- =========================================================================

function FSTelTelemetry:executeAction(actionName, vehicle)
    if vehicle == nil then return end

    print(string.format("[%s] Executing in-game command: %s on %s", self.MOD_NAME, actionName, vehicle:getName() or "Machine"))

    pcall(function()
        if actionName == "ENGINE_START" then
            if vehicle.getIsMotorStarted ~= nil and vehicle:getIsMotorStarted() then
                if vehicle.stopMotor ~= nil then vehicle:stopMotor() end
            else
                if vehicle.startMotor ~= nil then vehicle:startMotor() end
            end

        elseif actionName == "CRUISE_TOGGLE" then
            if vehicle.spec_drivable ~= nil and vehicle.spec_drivable.cruiseControl ~= nil then
                local cur = vehicle.spec_drivable.cruiseControl.state or 0
                local nextState = (cur == 1) and 0 or 1
                if vehicle.setCruiseControlState ~= nil then
                    vehicle:setCruiseControlState(nextState)
                else
                    vehicle.spec_drivable.cruiseControl.state = nextState
                end
            end

        elseif actionName == "CRUISE_SPEED_UP" then
            if vehicle.changeCruiseControlSpeed ~= nil then
                vehicle:changeCruiseControlSpeed(1)
            elseif vehicle.spec_drivable ~= nil and vehicle.spec_drivable.cruiseControl ~= nil then
                vehicle.spec_drivable.cruiseControl.speed = (vehicle.spec_drivable.cruiseControl.speed or 15) + 1
            end

        elseif actionName == "CRUISE_SPEED_DOWN" then
            if vehicle.changeCruiseControlSpeed ~= nil then
                vehicle:changeCruiseControlSpeed(-1)
            elseif vehicle.spec_drivable ~= nil and vehicle.spec_drivable.cruiseControl ~= nil then
                vehicle.spec_drivable.cruiseControl.speed = math.max(1, (vehicle.spec_drivable.cruiseControl.speed or 15) - 1)
            end

        elseif actionName == "LIGHTS_BEACON" then
            if vehicle.setBeaconLightsVisibility ~= nil and vehicle.spec_lights ~= nil then
                vehicle:setBeaconLightsVisibility(not vehicle.spec_lights.beaconLightsActive)
            end

        elseif actionName == "LIGHTS_CYCLE" then
            if vehicle.setLightsTypesMask ~= nil and vehicle.spec_lights ~= nil then
                local cur = vehicle.spec_lights.lightsTypesMask or 0
                local nextMask = 0
                if cur == 0 then nextMask = 1
                elseif cur == 1 then nextMask = 3
                elseif cur >= 3 then nextMask = 0 end
                vehicle:setLightsTypesMask(nextMask)
            end

        elseif actionName == "LIGHTS_WORK_FRONT" then
            if vehicle.spec_lights ~= nil and vehicle.setLightsTypesMask ~= nil then
                local cur = vehicle.spec_lights.lightsTypesMask or 0
                local nextMask = (safeBitAnd(cur, 4) ~= 0) and (cur - 4) or (cur + 4)
                vehicle:setLightsTypesMask(nextMask)
            end

        elseif actionName == "LIGHTS_WORK_BACK" then
            if vehicle.spec_lights ~= nil and vehicle.setLightsTypesMask ~= nil then
                local cur = vehicle.spec_lights.lightsTypesMask or 0
                local nextMask = (safeBitAnd(cur, 8) ~= 0) and (cur - 8) or (cur + 8)
                vehicle:setLightsTypesMask(nextMask)
            end

        elseif actionName == "TOOL_LOWER" then
            local done = false
            if vehicle.actionEventLower ~= nil then
                local ok = pcall(function() vehicle:actionEventLower(nil, 1, nil, false) end)
                if ok then done = true end
            end

            local activeTarget = nil
            local specAV = vehicle.spec_attacherVehicles
            if specAV ~= nil and specAV.selectedImplement ~= nil then
                activeTarget = specAV.selectedImplement.object or specAV.selectedImplement
            elseif vehicle.getSelectedImplement ~= nil then
                local sel = vehicle:getSelectedImplement()
                if sel ~= nil then activeTarget = sel.object or sel end
            end
            if activeTarget == nil and vehicle.getAttachedImplements ~= nil then
                local att = vehicle:getAttachedImplements()
                if att ~= nil and #att > 0 then
                    activeTarget = att[1].object or att[1]
                end
            end

            if activeTarget ~= nil and not done then
                if activeTarget.actionEventLower ~= nil then
                    local ok = pcall(function() activeTarget:actionEventLower(nil, 1, nil, false) end)
                    if ok then done = true end
                end
                if not done and Attachable ~= nil and Attachable.actionEventLower ~= nil then
                    local ok = pcall(function() Attachable.actionEventLower(activeTarget, nil, 1, nil, false) end)
                    if ok then done = true end
                end
            end

            if not done then
                local t = activeTarget or vehicle
                local isLowered = false
                if t.getIsLowered ~= nil then
                    isLowered = t:getIsLowered() and true or false
                end
                local nextState = not isLowered
                if t.setLowered ~= nil then
                    pcall(function() t:setLowered(nextState) end)
                end
                if t.setIsLowered ~= nil then
                    pcall(function() t:setIsLowered(nextState) end)
                end
                if vehicle.setLowered ~= nil and t ~= vehicle then
                    pcall(function() vehicle:setLowered(nextState) end)
                end
            end

        elseif actionName == "TOOL_LOWER_ALL" then
            if vehicle.setAllLowered ~= nil then
                local anyLowered = false
                if vehicle.getAttachedImplements ~= nil then
                    for _, it in ipairs(vehicle:getAttachedImplements()) do
                        if it.object ~= nil and it.object.getIsLowered ~= nil and it.object:getIsLowered() then
                            anyLowered = true
                            break
                        end
                    end
                end
                vehicle:setAllLowered(not anyLowered)
            end

        elseif actionName == "TOOL_PTO" then
            local target = (vehicle.selectedImplement ~= nil and vehicle.selectedImplement.object) or (vehicle.getAttachedImplements ~= nil and vehicle:getAttachedImplements()[1] and vehicle:getAttachedImplements()[1].object)
            if target ~= nil and target.setIsTurnedOn ~= nil then
                local isTurnedOn = (target.getIsTurnedOn ~= nil) and target:getIsTurnedOn() or false
                target:setIsTurnedOn(not isTurnedOn)
            end

        elseif actionName == "TOOL_PTO_ALL" then
            if vehicle.getAttachedImplements ~= nil then
                local anyOn = false
                for _, it in ipairs(vehicle:getAttachedImplements()) do
                    if it.object ~= nil and it.object.getIsTurnedOn ~= nil and it.object:getIsTurnedOn() then
                        anyOn = true
                        break
                    end
                end
                for _, it in ipairs(vehicle:getAttachedImplements()) do
                    if it.object ~= nil and it.object.setIsTurnedOn ~= nil then
                        it.object:setIsTurnedOn(not anyOn)
                    end
                end
            end

        elseif actionName == "TOOL_FOLD" then
            local done = false
            if vehicle.actionEventFold ~= nil then
                local ok = pcall(function() vehicle:actionEventFold(nil, 1, nil, false) end)
                if ok then done = true end
            end

            local target = nil
            local specAV = vehicle.spec_attacherVehicles
            if specAV ~= nil and specAV.selectedImplement ~= nil then
                local obj = specAV.selectedImplement.object or specAV.selectedImplement
                if obj ~= nil and obj.spec_foldable ~= nil then target = obj end
            end
            if target == nil and vehicle.spec_foldable ~= nil then
                target = vehicle
            end
            if target == nil and vehicle.getAttachedImplements ~= nil then
                for _, it in ipairs(vehicle:getAttachedImplements()) do
                    if it.object ~= nil and it.object.spec_foldable ~= nil then
                        target = it.object
                        break
                    end
                end
            end

            if target ~= nil and not done then
                if target.actionEventFold ~= nil then
                    local ok = pcall(function() target:actionEventFold(nil, 1, nil, false) end)
                    if ok then done = true end
                end
                if not done and Foldable ~= nil and Foldable.actionEventFold ~= nil then
                    local ok = pcall(function() Foldable.actionEventFold(target, nil, 1, nil, false) end)
                    if ok then done = true end
                end
            end

            if target ~= nil and target.spec_foldable ~= nil and not done then
                local spec = target.spec_foldable
                local foldDir = spec.foldMoveDirection or 0
                if foldDir == 0 then
                    local isFolded = false
                    if target.getIsFolded ~= nil then
                        isFolded = target:getIsFolded() and true or false
                    elseif spec.foldAnimTime ~= nil then
                        isFolded = (spec.foldAnimTime >= 0.5)
                    end
                    local turnOnDir = spec.turnOnFoldDirection or 1
                    foldDir = isFolded and -turnOnDir or turnOnDir
                else
                    foldDir = -foldDir
                end
                if target.setFoldState ~= nil then
                    pcall(function() target:setFoldState(foldDir, true) end)
                end
            end

        elseif actionName == "PIPE_TOGGLE" then
            local target = vehicle
            if vehicle.spec_pipe == nil and vehicle.getAttachedImplements ~= nil then
                for _, it in ipairs(vehicle:getAttachedImplements()) do
                    if it.object ~= nil and it.object.spec_pipe ~= nil then
                        target = it.object
                        break
                    end
                end
            end
            if target ~= nil and target.spec_pipe ~= nil and target.setPipeState ~= nil then
                local cur = target.spec_pipe.currentState or 1
                target:setPipeState((cur == 1) and 2 or 1)
            end

        elseif actionName == "TOOL_SELECT" then
            local done = false
            if vehicle.actionEventCycleImplement ~= nil then
                local ok = pcall(function() vehicle:actionEventCycleImplement(nil, 1, nil, false) end)
                if ok then done = true end
            end
            if not done and AttacherVehicles ~= nil and AttacherVehicles.actionEventCycleImplement ~= nil then
                local ok = pcall(function() AttacherVehicles.actionEventCycleImplement(vehicle, nil, 1, nil, false) end)
                if ok then done = true end
            end

            if not done then
                local specAV = vehicle.spec_attacherVehicles
                local list = (vehicle.getAttachedImplements ~= nil and vehicle:getAttachedImplements()) or (specAV and specAV.attachedImplements)
                if list ~= nil and #list > 0 then
                    local currentSel = (specAV and specAV.selectedImplement) or (vehicle.getSelectedImplement ~= nil and vehicle:getSelectedImplement())
                    local curIdx = 0
                    for i, it in ipairs(list) do
                        if it == currentSel or (it.object ~= nil and it.object == currentSel) then
                            curIdx = i
                            break
                        end
                    end
                    local nextIdx = (curIdx % #list) + 1
                    if vehicle.setSelectedImplement ~= nil then
                        pcall(function() vehicle:setSelectedImplement(list[nextIdx]) end)
                    elseif specAV ~= nil and specAV.setSelectedImplement ~= nil then
                        pcall(function() specAV:setSelectedImplement(list[nextIdx]) end)
                    end
                end
            end

        elseif actionName == "AI_WORKER" or actionName == "TOGGLE_AI" then
            local done = false
            if vehicle.actionEventToggleAI ~= nil then
                local ok = pcall(function() vehicle:actionEventToggleAI(nil, 1, nil, false) end)
                if ok then done = true end
            end
            if not done and AIJobVehicle ~= nil and AIJobVehicle.actionEventToggleAI ~= nil then
                local ok = pcall(function() AIJobVehicle.actionEventToggleAI(vehicle, nil, 1, nil, false) end)
                if ok then done = true end
            end
            if not done then
                local isAi = false
                if vehicle.getIsAIActive ~= nil then
                    isAi = vehicle:getIsAIActive() and true or false
                end
                if isAi then
                    if vehicle.stopCurrentAIJob ~= nil then
                        pcall(function() vehicle:stopCurrentAIJob(1) end)
                    elseif vehicle.stopAIVehicle ~= nil then
                        pcall(function() vehicle:stopAIVehicle(1) end)
                    end
                else
                    if vehicle.startAIVehicle ~= nil then
                        pcall(function() vehicle:startAIVehicle() end)
                    elseif vehicle.toggleAIVehicle ~= nil then
                        pcall(function() vehicle:toggleAIVehicle() end)
                    end
                end
            end

        elseif actionName == "HANDBRAKE" then
            if vehicle.setHandbrake ~= nil then
                local isSet = (vehicle.getHandbrake ~= nil) and vehicle:getHandbrake() or false
                vehicle:setHandbrake(not isSet)
            end

        elseif actionName == "LIGHTS_HAZARD" then
            if vehicle.setTurnLightState ~= nil and vehicle.spec_lights ~= nil then
                local cur = vehicle.spec_lights.turnLightState or 0
                vehicle:setTurnLightState((cur == 3) and 0 or 3)
            end

        elseif actionName == "FRONT_HITCH" or actionName == "REAR_HITCH" then
            if vehicle.getAttachedImplements ~= nil then
                local list = vehicle:getAttachedImplements()
                for _, it in ipairs(list) do
                    if it.object ~= nil and it.object.setLowered ~= nil then
                        local isLowered = (it.object.getIsLowered ~= nil) and it.object:getIsLowered() or false
                        it.object:setLowered(not isLowered)
                        break
                    end
                end
            end

        elseif actionName == "DIFF_LOCK" then
            if vehicle.spec_differential ~= nil and vehicle.spec_differential.setDiffState ~= nil then
                vehicle.spec_differential:setDiffState(1, not vehicle.spec_differential.diffState1)
            end

        elseif actionName == "ALL_WHEEL_DRIVE" then
            if vehicle.spec_allWheelDrive ~= nil and vehicle.spec_allWheelDrive.setAwdState ~= nil then
                vehicle.spec_allWheelDrive:setAwdState(not vehicle.spec_allWheelDrive.awdActive)
            end
        end
    end)
end

function FSTelTelemetry:processIncomingActions(vehicle)
    if self.actionXmlPath == nil then return end

    pcall(function()
        if fileExists ~= nil and fileExists(self.actionXmlPath) and loadXMLFile ~= nil then
            local xmlId = loadXMLFile("fstelAction", self.actionXmlPath)
            if xmlId ~= nil and xmlId ~= 0 then
                local seq = getXMLInt(xmlId, "action#seq") or 0
                local action = getXMLString(xmlId, "action#name")
                delete(xmlId)

                if seq > 0 and seq ~= self.lastActionSeq and action ~= nil then
                    self.lastActionSeq = seq
                    self:executeAction(action, vehicle)
                end
            end
        end
    end)
end

-- =========================================================================
-- Safe Vehicle Data Extraction
-- =========================================================================

function FSTelTelemetry:extractVehicleData(vehicle)
    local data = {
        id = 0,
        name = "Machine",
        typeName = "Tractor",
        isControlled = true,
        speedKmh = 0,
        speedMph = 0,
        gear = 1,
        gearName = "D",
        isAutomatic = true,
        isEngineStarted = false,
        rpm = 850,
        minRpm = 800,
        maxRpm = 2200,
        motorLoadPercent = 0,
        operatingHours = 0,
        cruiseControl = {
            isActive = false,
            targetSpeed = 15
        },
        fuel = {
            fillLevel = 0,
            capacity = 0,
            fillPercent = 0
        },
        def = {
            fillLevel = 0,
            capacity = 0,
            fillPercent = 0
        },
        lights = {
            beaconActive = false,
            turnLightState = 0,
            highBeam = false,
            lowBeam = false,
            workLightsFront = false,
            workLightsBack = false
        },
        drivetrain = {
            handbrake = false,
            allWheelDrive = true,
            diffLockFront = false,
            diffLockRear = false
        },
        implements = {}
    }

    if vehicle == nil then
        return data
    end

    pcall(function()
        if vehicle.id ~= nil then data.id = tonumber(vehicle.id) or 0 end
        if vehicle.typeName ~= nil then data.typeName = tostring(vehicle.typeName) end

        if vehicle.getName ~= nil then
            local n = vehicle:getName()
            if n ~= nil then data.name = tostring(n) end
        end

        if vehicle.getLastSpeed ~= nil then
            local kmh = vehicle:getLastSpeed() or 0
            if kmh < 0.05 then kmh = 0 end
            data.speedKmh = kmh
            data.speedMph = kmh * 0.621371
        end

        if vehicle.operatingTime ~= nil then
            data.operatingHours = (vehicle.operatingTime or 0) / (1000 * 60 * 60)
        end

        if vehicle.getIsMotorStarted ~= nil then
            data.isEngineStarted = vehicle:getIsMotorStarted() and true or false
        end

        if vehicle.getMotor ~= nil then
            local motor = vehicle:getMotor()
            if motor ~= nil then
                if motor.getLastMotorRpm ~= nil then data.rpm = math.floor(motor:getLastMotorRpm() or 850) end
                if motor.getMinRpm ~= nil then data.minRpm = math.floor(motor:getMinRpm() or 800) end
                if motor.getMaxRpm ~= nil then data.maxRpm = math.floor(motor:getMaxRpm() or 2200) end

                if motor.getMotorLoadPercentage ~= nil then
                    data.motorLoadPercent = (motor:getMotorLoadPercentage() or 0) * 100
                elseif motor.actualLoadPercentage ~= nil then
                    data.motorLoadPercent = (motor.actualLoadPercentage or 0) * 100
                end

                if motor.currentGear ~= nil then
                    data.gear = tonumber(motor.currentGear) or 1
                    if motor.gearRatio ~= nil and motor.gearRatio < 0 then
                        data.gearName = "R"
                    elseif motor.currentGear == 0 then
                        data.gearName = "N"
                    else
                        data.gearName = tostring(motor.currentGear)
                    end
                end
            end
        end

        local specDrivable = vehicle.spec_drivable
        if specDrivable ~= nil and specDrivable.cruiseControl ~= nil then
            data.cruiseControl.isActive = (specDrivable.cruiseControl.state == 1)
            data.cruiseControl.targetSpeed = specDrivable.cruiseControl.speed or 0
        end

        if vehicle.getFillUnits ~= nil then
            for _, fillUnit in pairs(vehicle:getFillUnits()) do
                local fillType = fillUnit.fillType or 0
                local fillLevel = fillUnit.fillLevel or 0
                local capacity = fillUnit.capacity or 0
                local pct = (capacity > 0) and ((fillLevel / capacity) * 100) or 0

                local fName = ""
                if g_fillTypeManager ~= nil and g_fillTypeManager.getFillTypeNameByIndex ~= nil then
                    fName = string.upper(g_fillTypeManager:getFillTypeNameByIndex(fillType) or "")
                end

                if string.find(fName, "DIESEL") or string.find(fName, "METHANE") or string.find(fName, "ELECTRIC") then
                    data.fuel.fillLevel = fillLevel
                    data.fuel.capacity = capacity
                    data.fuel.fillPercent = pct
                elseif string.find(fName, "DEF") or string.find(fName, "ADBLUE") then
                    data.def.fillLevel = fillLevel
                    data.def.capacity = capacity
                    data.def.fillPercent = pct
                end
            end
        end

        local specLights = vehicle.spec_lights
        if specLights ~= nil then
            data.lights.beaconActive = specLights.beaconLightsActive and true or false
            data.lights.turnLightState = specLights.turnLightState or 0
            data.lights.workLightsFront = specLights.workLightsFrontActive and true or false
            data.lights.workLightsBack = specLights.workLightsBackActive and true or false

            if specLights.lightsTypesMask ~= nil then
                data.lights.lowBeam = (safeBitAnd(specLights.lightsTypesMask, 1) ~= 0)
                data.lights.highBeam = (safeBitAnd(specLights.lightsTypesMask, 2) ~= 0)
            end
        end

        if vehicle.getAttachedImplements ~= nil then
            local attachedList = vehicle:getAttachedImplements()
            for idx, item in ipairs(attachedList) do
                if item.object ~= nil then
                    local isSel = false
                    local specAV = vehicle.spec_attacherVehicles
                    if specAV ~= nil and specAV.selectedImplement ~= nil then
                        isSel = (specAV.selectedImplement == item or specAV.selectedImplement.object == implObj)
                    elseif vehicle.getSelectedImplement ~= nil then
                        local sel = vehicle:getSelectedImplement()
                        isSel = (sel == item or sel == implObj or (sel ~= nil and sel.object == implObj))
                    elseif vehicle.selectedImplement ~= nil then
                        isSel = (vehicle.selectedImplement == item or vehicle.selectedImplement.object == implObj)
                    elseif idx == 1 then
                        isSel = true
                    end

                    local implInfo = {
                        index = idx,
                        name = (implObj.getName ~= nil) and tostring(implObj:getName()) or "Implement",
                        isSelected = isSel,
                        isLowered = false,
                        isTurnedOn = false,
                        isFolded = false,
                        foldPercent = 0,
                        pipeDischarging = false,
                        fillUnits = {}
                    }

                    if implObj.getIsLowered ~= nil then
                        implInfo.isLowered = implObj:getIsLowered() and true or false
                    end
                    if implObj.getIsTurnedOn ~= nil then
                        implInfo.isTurnedOn = implObj:getIsTurnedOn() and true or false
                    end

                    if implObj.spec_foldable ~= nil then
                        local sf = implObj.spec_foldable
                        if sf.foldAnimTime ~= nil then
                            implInfo.foldPercent = (sf.foldAnimTime or 0) * 100
                        end
                        if implObj.getIsFolded ~= nil then
                            implInfo.isFolded = implObj:getIsFolded() and true or false
                        end
                    end

                    if implObj.spec_pipe ~= nil then
                        implInfo.pipeDischarging = (implObj.spec_pipe.currentState == 1)
                    end

                    if implObj.getFillUnits ~= nil then
                        for uIdx, uUnit in pairs(implObj:getFillUnits()) do
                            local fLevel = uUnit.fillLevel or 0
                            local fCap = uUnit.capacity or 0
                            local fType = uUnit.fillType or 0
                            local fTypeName = "MATERIAL"
                            if g_fillTypeManager ~= nil and g_fillTypeManager.getFillTypeNameByIndex ~= nil then
                                fTypeName = g_fillTypeManager:getFillTypeNameByIndex(fType) or fTypeName
                            end

                            table.insert(implInfo.fillUnits, {
                                unitIndex = uIdx,
                                fillTypeName = tostring(fTypeName),
                                fillLevel = fLevel,
                                capacity = fCap,
                                fillPercent = (fCap > 0) and ((fLevel / fCap) * 100) or 0
                            })
                        end
                    end

                    table.insert(data.implements, implInfo)
                end
            end
        end
    end)

    return data
end

function FSTelTelemetry:extractEnvironmentData()
    local env = {
        clock = "12:00",
        dayTimeMs = 0,
        day = 1,
        month = 1,
        temperature = 20,
        weather = "SUNNY",
        money = 0
    }

    pcall(function()
        if g_currentMission ~= nil then
            local missionEnv = g_currentMission.environment
            if missionEnv ~= nil then
                if missionEnv.dayTime ~= nil then
                    env.dayTimeMs = missionEnv.dayTime
                    local totalMinutes = math.floor(missionEnv.dayTime / (1000 * 60))
                    local hours = math.floor(totalMinutes / 60) % 24
                    local mins = totalMinutes % 60
                    env.clock = string.format("%02d:%02d", hours, mins)
                end
                if missionEnv.currentDay ~= nil then env.day = missionEnv.currentDay end
                if missionEnv.currentMonth ~= nil then env.month = missionEnv.currentMonth end
                if missionEnv.weather ~= nil and missionEnv.weather.getCurrentTemperature ~= nil then
                    env.temperature = missionEnv.weather:getCurrentTemperature()
                end
            end

            local moneyFound = false
            if g_currentMission.getMoney ~= nil then
                local ok, m = pcall(function() return g_currentMission:getMoney() end)
                if ok and m ~= nil and type(m) == "number" then
                    env.money = math.floor(m)
                    moneyFound = true
                end
            end

            if not moneyFound and g_farmManager ~= nil then
                local farmId = nil
                if g_currentMission.getFarmId ~= nil then
                    local ok, fid = pcall(function() return g_currentMission:getFarmId() end)
                    if ok then farmId = fid end
                end
                if farmId == nil and g_currentMission.playerFarmId ~= nil then
                    farmId = g_currentMission.playerFarmId
                end
                if farmId == nil and g_localPlayer ~= nil and g_localPlayer.farmId ~= nil then
                    farmId = g_localPlayer.farmId
                end
                if farmId == nil and g_currentMission.player ~= nil and g_currentMission.player.farmId ~= nil then
                    farmId = g_currentMission.player.farmId
                end
                if farmId == nil then farmId = 1 end

                local farm = g_farmManager:getFarmById(farmId)
                if farm ~= nil then
                    if farm.getBalance ~= nil then
                        local ok, bal = pcall(function() return farm:getBalance() end)
                        if ok and bal ~= nil then env.money = math.floor(bal) moneyFound = true end
                    end
                    if not moneyFound and farm.money ~= nil then
                        env.money = math.floor(farm.money)
                    end
                end
            end
        end
    end)

    return env
end

-- =========================================================================
-- Protected Safe Update Loop
-- =========================================================================

function FSTelTelemetry:safeUpdate(dt)
    if not self.hasLoggedSetup then
        self:initTransport()
    end

    if g_currentMission == nil then
        return
    end

    local vehicle = self:getControlledVehicle()

    -- Process any incoming button commands from Web Terminal (via GIANTS native loadXMLFile)
    self:processIncomingActions(vehicle)

    local currentTime = g_time or 0
    if (currentTime - self.lastSendTime) < self.UPDATE_INTERVAL_MS then
        return
    end
    self.lastSendTime = currentTime

    local vehData = nil

    if vehicle ~= nil then
        vehData = self:extractVehicleData(vehicle)
    else
        vehData = {
            id = 0,
            name = "On Foot (No Vehicle)",
            typeName = "Foot",
            isControlled = false,
            speedKmh = 0,
            speedMph = 0,
            gear = 0,
            gearName = "N",
            isAutomatic = true,
            isEngineStarted = false,
            rpm = 0,
            minRpm = 800,
            maxRpm = 2200,
            motorLoadPercent = 0,
            operatingHours = 0,
            cruiseControl = { isActive = false, targetSpeed = 0 },
            fuel = { fillLevel = 0, capacity = 0, fillPercent = 0 },
            def = { fillLevel = 0, capacity = 0, fillPercent = 0 },
            lights = { beaconActive = false, turnLightState = 0, highBeam = false, lowBeam = false, workLightsFront = false, workLightsBack = false },
            drivetrain = { handbrake = false, allWheelDrive = false, diffLockFront = false, diffLockRear = false },
            implements = {}
        }
    end

    self.packetSeq = (self.packetSeq + 1) % 1000000
    local packet = {
        protocol = "FSTEL_1.0",
        seq = self.packetSeq,
        timestamp = currentTime,
        inGame = true,
        vehicle = vehData,
        environment = self:extractEnvironmentData()
    }

    local jsonStr = FSTelJson.encode(packet)

    if self.useIoOpen and self.jsonFilePath ~= nil then
        local f = io.open(self.jsonFilePath, "w")
        if f ~= nil then
            f:write(jsonStr)
            f:close()
            if not self.hasLoggedFirstWrite then
                print(string.format("[%s] Successfully streaming in-game telemetry! (Seq #%d)", self.MOD_NAME, self.packetSeq))
                self.hasLoggedFirstWrite = true
            end
        end
    elseif self.useXmlFallback and self.xmlFilePath ~= nil then
        local xmlFile = createXMLFile("fstelDoc", self.xmlFilePath, "fstel")
        if xmlFile ~= nil and xmlFile ~= 0 then
            setXMLString(xmlFile, "fstel#payload", jsonStr)
            saveXMLFile(xmlFile)
            delete(xmlFile)
        end
    end
end

function FSTelTelemetry:update(dt)
    local ok, err = pcall(function()
        self:safeUpdate(dt)
    end)
    if not ok and not self.hasLoggedUpdateError then
        print(string.format("[%s] CRITICAL update error: %s", self.MOD_NAME, tostring(err)))
        self.hasLoggedUpdateError = true
    end
end

-- Register Mod Event Listener into GIANTS Engine
addModEventListener(FSTelTelemetry)
