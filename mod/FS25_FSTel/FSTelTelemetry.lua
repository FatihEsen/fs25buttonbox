--[[
    FSTel - Telemetry & Virtual Button Box Exporter for Farming Simulator 25
    Compatible with GIANTS Engine 10 / FS25

    High-speed, zero-dependency telemetry pipeline for FS25.
]]

print("[FSTel] ========================================================")
print("[FSTel] FSTel Telemetry Engine starting up...")
print("[FSTel] Diagnostics:")
print("[FSTel]   type(io) = " .. type(io))
if type(io) == "table" then
    print("[FSTel]   type(io.open) = " .. type(io.open))
end
print("[FSTel]   type(createXMLFile) = " .. type(createXMLFile))
print("[FSTel]   type(getUserProfileAppPath) = " .. type(getUserProfileAppPath))
if getUserProfileAppPath ~= nil then
    print("[FSTel]   getUserProfileAppPath() = " .. tostring(getUserProfileAppPath()))
end
print("[FSTel] ========================================================")

FSTelTelemetry = {}
FSTelTelemetry.MOD_NAME = g_currentModName or "FS25_FSTel"
FSTelTelemetry.VERSION = "1.0.0.0"

-- Target ~20-30 updates per second
FSTelTelemetry.TARGET_HZ = 25
FSTelTelemetry.UPDATE_INTERVAL_MS = math.floor(1000 / FSTelTelemetry.TARGET_HZ)

FSTelTelemetry.lastSendTime = 0
FSTelTelemetry.packetSeq = 0
FSTelTelemetry.telemetryFilePath = nil
FSTelTelemetry.useIoOpen = false
FSTelTelemetry.useXmlFallback = false
FSTelTelemetry.hasLoggedSetup = false

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

    -- Normalize slashes
    basePath = basePath:gsub("\\", "/")
    if not basePath:match("/$") then
        basePath = basePath .. "/"
    end

    self.jsonFilePath = basePath .. "fstel_telemetry.json"
    self.xmlFilePath = basePath .. "fstel_telemetry.xml"

    -- Test if io.open is available
    if type(io) == "table" and type(io.open) == "function" then
        local testFile = io.open(self.jsonFilePath, "w")
        if testFile ~= nil then
            testFile:write('{"status":"init"}\n')
            testFile:close()
            self.useIoOpen = true
            print(string.format("[%s] High-speed JSON File IPC active: %s", self.MOD_NAME, self.jsonFilePath))
            return
        end
    end

    -- Fallback to GIANTS XML API
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
-- Safe Vehicle Data Extraction
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
        if vehicle.getName ~= nil then
            data.name = vehicle:getName() or data.name
        end

        if vehicle.getLastSpeed ~= nil then
            local kmh = vehicle:getLastSpeed()
            if kmh < 0.05 then kmh = 0 end
            data.speedKmh = kmh
            data.speedMph = kmh * 0.621371
        end

        if vehicle.operatingTime ~= nil then
            data.operatingHours = vehicle.operatingTime / (1000 * 60 * 60)
        end

        if vehicle.getIsMotorStarted ~= nil then
            data.isEngineStarted = vehicle:getIsMotorStarted()
        end

        if vehicle.getMotor ~= nil then
            local motor = vehicle:getMotor()
            if motor ~= nil then
                if motor.getLastMotorRpm ~= nil then data.rpm = motor:getLastMotorRpm() end
                if motor.getMinRpm ~= nil then data.minRpm = motor:getMinRpm() end
                if motor.getMaxRpm ~= nil then data.maxRpm = motor:getMaxRpm() end

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

        local specDrivable = vehicle.spec_drivable
        if specDrivable ~= nil and specDrivable.cruiseControl ~= nil then
            data.cruiseControl.isActive = (specDrivable.cruiseControl.state == 1)
            data.cruiseControl.targetSpeed = specDrivable.cruiseControl.speed or 0
        end

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
    if not self.hasLoggedSetup then
        self:initTransport()
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

    -- 1. High-speed JSON File
    if self.useIoOpen and self.jsonFilePath ~= nil then
        pcall(function()
            local f = io.open(self.jsonFilePath, "w")
            if f ~= nil then
                f:write(jsonStr)
                f:close()
            end
        end)
    -- 2. GIANTS XML IPC Fallback
    elseif self.useXmlFallback and self.xmlFilePath ~= nil then
        pcall(function()
            local xmlFile = createXMLFile("fstelDoc", self.xmlFilePath, "fstel")
            if xmlFile ~= nil and xmlFile ~= 0 then
                setXMLString(xmlFile, "fstel#payload", jsonStr)
                saveXMLFile(xmlFile)
                delete(xmlFile)
            end
        end)
    end
end

-- Register Mod Event Listener into GIANTS Engine
addModEventListener(FSTelTelemetry)
