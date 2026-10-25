--[[
    FSTel - Telemetry & Virtual Button Box Exporter for Farming Simulator 25
    Compatible with GIANTS Engine 10 / FS25

    Hooks into the active vehicle and broadcasts structured telemetry over UDP localhost.
]]

FSTelTelemetry = {}
FSTelTelemetry.MOD_NAME = g_currentModName or "FS25_FSTel"
FSTelTelemetry.VERSION = "1.0.0.0"

-- Configuration
FSTelTelemetry.HOST = "127.0.0.1"
FSTelTelemetry.PORT = 41234
FSTelTelemetry.TARGET_HZ = 30 -- Target 30 updates per second (~33ms)
FSTelTelemetry.UPDATE_INTERVAL_MS = math.floor(1000 / FSTelTelemetry.TARGET_HZ)

-- State
FSTelTelemetry.socket = nil
FSTelTelemetry.udp = nil
FSTelTelemetry.isSocketReady = false
FSTelTelemetry.lastSendTime = 0
FSTelTelemetry.packetSeq = 0

-- =========================================================================
-- Pure-Lua Safe JSON Serializer (No external dependencies required)
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
        -- Format integer or float cleanly
        if math.floor(val) == val then
            return string.format("%d", val)
        else
            return string.format("%.3f", val)
        end
    elseif t == "string" then
        return escapeString(val)
    elseif t == "table" then
        -- Check if it's an array (numeric consecutive keys starting at 1)
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
-- Mod Lifecycle & UDP Networking
-- =========================================================================

function FSTelTelemetry:loadMap(name)
    print(string.format("[%s] Initializing FSTel Telemetry Mod v%s...", self.MOD_NAME, self.VERSION))
    self:initNetwork()
end

function FSTelTelemetry:deleteMap()
    if self.udp ~= nil then
        pcall(function()
            self.udp:close()
        end)
        self.udp = nil
    end
    self.isSocketReady = false
    print(string.format("[%s] Network socket closed.", self.MOD_NAME))
end

function FSTelTelemetry:initNetwork()
    local hasSocket, socketModule = pcall(function()
        return require("socket")
    end)

    if hasSocket and socketModule ~= nil then
        self.socket = socketModule
        local ok, client = pcall(function()
            local u = self.socket.udp()
            u:setpeername(self.HOST, self.PORT)
            u:settimeout(0)
            return u
        end)

        if ok and client ~= nil then
            self.udp = client
            self.isSocketReady = true
            print(string.format("[%s] UDP socket connected to %s:%d (Target: %d Hz)", self.MOD_NAME, self.HOST, self.PORT, self.TARGET_HZ))
        else
            print(string.format("[%s] WARNING: Failed to create UDP socket: %s", self.MOD_NAME, tostring(client)))
        end
    else
        print(string.format("[%s] WARNING: 'socket' library not available in GIANTS Engine runtime. Direct socket disabled.", self.MOD_NAME))
    end
end

-- =========================================================================
-- Telemetry Extraction
-- =========================================================================

function FSTelTelemetry:extractVehicleData(vehicle)
    local data = {
        id = vehicle.id or 0,
        name = "Unknown Vehicle",
        typeName = vehicle.typeName or "",
        isControlled = true,
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
        cruiseControl = {
            isActive = false,
            targetSpeed = 0
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
            turnLightState = 0, -- 0: off, 1: left, 2: right, 3: hazard
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

    -- Name
    if vehicle.getName ~= nil then
        data.name = vehicle:getName() or data.name
    end

    -- Speed (getLastSpeed() returns km/h in GIANTS engine)
    if vehicle.getLastSpeed ~= nil then
        local kmh = vehicle:getLastSpeed()
        if kmh < 0.05 then kmh = 0 end
        data.speedKmh = kmh
        data.speedMph = kmh * 0.621371
    end

    -- Operating Time
    if vehicle.operatingTime ~= nil then
        data.operatingHours = vehicle.operatingTime / (1000 * 60 * 60)
    end

    -- Motor & Gear
    if vehicle.getIsMotorStarted ~= nil then
        data.isEngineStarted = vehicle:getIsMotorStarted()
    end

    if vehicle.getMotor ~= nil then
        local motor = vehicle:getMotor()
        if motor ~= nil then
            if motor.getLastMotorRpm ~= nil then
                data.rpm = motor:getLastMotorRpm()
            end
            if motor.getMinRpm ~= nil then
                data.minRpm = motor:getMinRpm()
            end
            if motor.getMaxRpm ~= nil then
                data.maxRpm = motor:getMaxRpm()
            end

            -- Engine Load (0.0 to 1.0)
            if motor.getMotorLoadPercentage ~= nil then
                data.motorLoadPercent = motor:getMotorLoadPercentage() * 100
            elseif motor.actualLoadPercentage ~= nil then
                data.motorLoadPercent = motor.actualLoadPercentage * 100
            end

            -- Gear status
            if motor.currentGear ~= nil then
                data.gear = motor.currentGear
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

    -- Cruise Control
    local specDrivable = vehicle.spec_drivable
    if specDrivable ~= nil and specDrivable.cruiseControl ~= nil then
        data.cruiseControl.isActive = (specDrivable.cruiseControl.state == 1)
        data.cruiseControl.targetSpeed = specDrivable.cruiseControl.speed or 0
    end

    -- Fill Units (Fuel, DEF/AdBlue)
    local specFillUnit = vehicle.spec_fillUnit
    if specFillUnit ~= nil and vehicle.getFillUnits ~= nil then
        for fillUnitIndex, fillUnit in pairs(vehicle:getFillUnits()) do
            local fillType = fillUnit.fillType
            local fillLevel = fillUnit.fillLevel or 0
            local capacity = fillUnit.capacity or 0
            local pct = (capacity > 0) and ((fillLevel / capacity) * 100) or 0

            if fillType == FillType.DIESEL or fillType == FillType.METHANE or fillType == FillType.ELECTRICCHARGE then
                data.fuel.fillLevel = fillLevel
                data.fuel.capacity = capacity
                data.fuel.fillPercent = pct
            elseif fillType == FillType.DEF then
                data.def.fillLevel = fillLevel
                data.def.capacity = capacity
                data.def.fillPercent = pct
            end
        end
    end

    -- Lights & Warnings
    local specLights = vehicle.spec_lights
    if specLights ~= nil then
        data.lights.beaconActive = specLights.beaconLightsActive or false
        data.lights.turnLightState = specLights.turnLightState or 0
        data.lights.workLightsFront = specLights.workLightsFrontActive or false
        data.lights.workLightsBack = specLights.workLightsBackActive or false

        if specLights.lightsTypesMask ~= nil then
            data.lights.lowBeam = (bitAND(specLights.lightsTypesMask, 1) ~= 0)
            data.lights.highBeam = (bitAND(specLights.lightsTypesMask, 2) ~= 0)
        end
    end

    -- Attached Implements
    if vehicle.getAttachedImplements ~= nil then
        local attachedList = vehicle:getAttachedImplements()
        for idx, item in ipairs(attachedList) do
            if item.object ~= nil then
                local implObj = item.object
                local implInfo = {
                    index = idx,
                    name = (implObj.getName ~= nil) and implObj:getName() or "Implement",
                    isSelected = (vehicle.selectedImplement == item),
                    isLowered = false,
                    isTurnedOn = false,
                    isFolded = false,
                    foldPercent = 0,
                    pipeDischarging = false,
                    fillUnits = {}
                }

                -- Attachable / Hydraulics
                if implObj.getIsLowered ~= nil then
                    implInfo.isLowered = implObj:getIsLowered()
                end

                -- PTO / TurnOn
                if implObj.getIsTurnedOn ~= nil then
                    implInfo.isTurnedOn = implObj:getIsTurnedOn()
                end

                -- Foldable
                if implObj.spec_foldable ~= nil then
                    local sf = implObj.spec_foldable
                    if sf.foldAnimTime ~= nil then
                        implInfo.foldPercent = sf.foldAnimTime * 100
                    end
                    if implObj.getIsFolded ~= nil then
                        implInfo.isFolded = implObj:getIsFolded()
                    end
                end

                -- Pipe & Discharge
                if implObj.spec_pipe ~= nil then
                    implInfo.pipeDischarging = (implObj.spec_pipe.currentState == 1)
                end

                -- Implement Fill Units (Fertilizer, Seeds, Grain, Water, Milk, etc.)
                if implObj.spec_fillUnit ~= nil and implObj.getFillUnits ~= nil then
                    for uIdx, uUnit in pairs(implObj:getFillUnits()) do
                        local fLevel = uUnit.fillLevel or 0
                        local fCap = uUnit.capacity or 0
                        local fType = uUnit.fillType or 0
                        local fTypeName = "UNKNOWN"
                        if g_fillTypeManager ~= nil and g_fillTypeManager:getFillTypeByIndex(fType) ~= nil then
                            fTypeName = g_fillTypeManager:getFillTypeByIndex(fType).title or fTypeName
                        end

                        table.insert(implInfo.fillUnits, {
                            unitIndex = uIdx,
                            fillTypeName = fTypeName,
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

    return data
end

function FSTelTelemetry:extractEnvironmentData()
    local env = {
        clock = "00:00",
        dayTimeMs = 0,
        day = 1,
        month = 1,
        temperature = 20,
        weather = "SUNNY",
        money = 0
    }

    if g_currentMission ~= nil then
        -- Money
        if g_currentMission.getMoney ~= nil then
            env.money = g_currentMission:getMoney()
        end

        -- Environment
        local missionEnv = g_currentMission.environment
        if missionEnv ~= nil then
            env.dayTimeMs = missionEnv.dayTime or 0
            local hours = math.floor(env.dayTimeMs / (1000 * 60 * 60))
            local minutes = math.floor((env.dayTimeMs % (1000 * 60 * 60)) / (1000 * 60))
            env.clock = string.format("%02d:%02d", hours, minutes)

            env.day = missionEnv.currentDay or 1
            env.month = missionEnv.currentMonth or 1

            if missionEnv.weather ~= nil and missionEnv.weather.getCurrentTemperature ~= nil then
                env.temperature = missionEnv.weather:getCurrentTemperature()
            end
        end
    end

    return env
end

-- =========================================================================
-- Main Update Loop
-- =========================================================================

function FSTelTelemetry:update(dt)
    if not self.isSocketReady or self.udp == nil then
        return
    end

    local currentTime = g_time or 0
    if (currentTime - self.lastSendTime) < self.UPDATE_INTERVAL_MS then
        return
    end
    self.lastSendTime = currentTime

    -- Only send if we are actively in a mission and seated in a vehicle
    if g_currentMission == nil or g_currentMission.controlledVehicle == nil then
        return
    end

    local vehicle = g_currentMission.controlledVehicle

    self.packetSeq = (self.packetSeq + 1) % 1000000
    local packet = {
        protocol = "FSTEL_1.0",
        seq = self.packetSeq,
        timestamp = currentTime,
        vehicle = self:extractVehicleData(vehicle),
        environment = self:extractEnvironmentData()
    }

    local jsonStr = FSTelJson.encode(packet)

    -- UDP Non-blocking send
    pcall(function()
        self.udp:send(jsonStr)
    end)
end

-- Register Mod Event Listener into GIANTS Engine
addModEventListener(FSTelTelemetry)
