--[[
    FSTel - Telemetry & Virtual Button Box Exporter for Farming Simulator 25
    Compatible with GIANTS Engine 10 / FS25

    Hooks into the active vehicle and broadcasts structured telemetry over UDP localhost.
]]

print("[FSTel] ========================================================")
print("[FSTel] FSTel Telemetry Mod script loaded by GIANTS Engine 10")
print("[FSTel] ========================================================")

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
FSTelTelemetry.hasLoggedSocketFail = false
FSTelTelemetry.lastSendTime = 0
FSTelTelemetry.packetSeq = 0

-- Bitwise Helper
local function safeBitAnd(a, b)
    if bitAND ~= nil then return bitAND(a, b) end
    if bit ~= nil and bit.band ~= nil then return bit.band(a, b) end
    return ((math.floor(a / b) % 2) == 1) and b or 0
end

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
        if math.floor(val) == val then
            return string.format("%d", val)
        else
            return string.format("%.3f", val)
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
-- Mod Lifecycle & UDP Networking
-- =========================================================================

function FSTelTelemetry:loadMap(name)
    print(string.format("[%s] loadMap triggered. Initializing network...", self.MOD_NAME))
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
    if self.isSocketReady and self.udp ~= nil then
        return true
    end

    local socketModule = nil
    if type(socket) == "table" and type(socket.udp) == "function" then
        socketModule = socket
    else
        local ok, mod = pcall(function()
            return require("socket")
        end)
        if ok and mod ~= nil then
            socketModule = mod
        end
    end

    if socketModule ~= nil then
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
            print(string.format("[%s] SUCCESS: UDP socket connected to %s:%d (Target rate: %d Hz)", self.MOD_NAME, self.HOST, self.PORT, self.TARGET_HZ))
            return true
        else
            if not self.hasLoggedSocketFail then
                print(string.format("[%s] WARNING: Failed to create UDP socket: %s", self.MOD_NAME, tostring(client)))
                self.hasLoggedSocketFail = true
            end
        end
    else
        if not self.hasLoggedSocketFail then
            print(string.format("[%s] WARNING: Lua 'socket' module not found in runtime.", self.MOD_NAME))
            self.hasLoggedSocketFail = true
        end
    end

    return false
end

-- =========================================================================
-- Safe Telemetry Extraction
-- =========================================================================

function FSTelTelemetry:extractVehicleData(vehicle)
    local data = {
        id = vehicle.id or 0,
        name = "Vehicle",
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

    pcall(function()
        -- Name
        if vehicle.getName ~= nil then
            data.name = vehicle:getName() or data.name
        end

        -- Speed
        if vehicle.getLastSpeed ~= nil then
            local kmh = vehicle:getLastSpeed()
            if kmh < 0.05 then kmh = 0 end
            data.speedKmh = kmh
            data.speedMph = kmh * 0.621371
        end

        -- Operating Hours
        if vehicle.operatingTime ~= nil then
            data.operatingHours = vehicle.operatingTime / (1000 * 60 * 60)
        end

        -- Motor
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

                if motor.getMotorLoadPercentage ~= nil then
                    data.motorLoadPercent = motor:getMotorLoadPercentage() * 100
                elseif motor.actualLoadPercentage ~= nil then
                    data.motorLoadPercent = motor.actualLoadPercentage * 100
                end

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

        -- Cruise
        local specDrivable = vehicle.spec_drivable
        if specDrivable ~= nil and specDrivable.cruiseControl ~= nil then
            data.cruiseControl.isActive = (specDrivable.cruiseControl.state == 1)
            data.cruiseControl.targetSpeed = specDrivable.cruiseControl.speed or 0
        end

        -- Fuel & DEF
        if vehicle.getFillUnits ~= nil then
            for _, fillUnit in pairs(vehicle:getFillUnits()) do
                local fillType = fillUnit.fillType
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

        -- Lights
        local specLights = vehicle.spec_lights
        if specLights ~= nil then
            data.lights.beaconActive = specLights.beaconLightsActive or false
            data.lights.turnLightState = specLights.turnLightState or 0
            data.lights.workLightsFront = specLights.workLightsFrontActive or false
            data.lights.workLightsBack = specLights.workLightsBackActive or false

            if specLights.lightsTypesMask ~= nil then
                data.lights.lowBeam = (safeBitAnd(specLights.lightsTypesMask, 1) ~= 0)
                data.lights.highBeam = (safeBitAnd(specLights.lightsTypesMask, 2) ~= 0)
            end
        end

        -- Implements
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

                    if implObj.getIsLowered ~= nil then
                        implInfo.isLowered = implObj:getIsLowered()
                    end
                    if implObj.getIsTurnedOn ~= nil then
                        implInfo.isTurnedOn = implObj:getIsTurnedOn()
                    end

                    if implObj.spec_foldable ~= nil then
                        local sf = implObj.spec_foldable
                        if sf.foldAnimTime ~= nil then
                            implInfo.foldPercent = sf.foldAnimTime * 100
                        end
                        if implObj.getIsFolded ~= nil then
                            implInfo.isFolded = implObj:getIsFolded()
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

            local farm = g_farmManager:getFarmById(g_currentMission.playerFarmId)
            if farm ~= nil and farm.money ~= nil then
                env.money = math.floor(farm.money)
            end
        end
    end)

    return env
end

-- =========================================================================
-- Main Update Loop
-- =========================================================================

function FSTelTelemetry:update(dt)
    if not self.isSocketReady then
        self:initNetwork()
        if not self.isSocketReady then
            return
        end
    end

    local currentTime = g_time or 0
    if (currentTime - self.lastSendTime) < self.UPDATE_INTERVAL_MS then
        return
    end
    self.lastSendTime = currentTime

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

    pcall(function()
        self.udp:send(jsonStr)
    end)
end

-- Register Mod Event Listener into GIANTS Engine
addModEventListener(FSTelTelemetry)
