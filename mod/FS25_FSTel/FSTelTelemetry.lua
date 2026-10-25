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

-- Target ~25 updates per second (40ms)
FSTelTelemetry.TARGET_HZ = 25
FSTelTelemetry.UPDATE_INTERVAL_MS = math.floor(1000 / FSTelTelemetry.TARGET_HZ)

FSTelTelemetry.lastSendTime = 0
FSTelTelemetry.packetSeq = 0
FSTelTelemetry.telemetryFilePath = nil
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
    self.xmlFilePath = basePath .. "fstel_telemetry.xml"

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

    -- 1. Standard FS19/FS22 controlledVehicle
    if g_currentMission.controlledVehicle ~= nil then
        return g_currentMission.controlledVehicle
    end

    -- 2. FS22/FS25 g_localPlayer:getCurrentVehicle()
    if g_localPlayer ~= nil and type(g_localPlayer.getCurrentVehicle) == "function" then
        local ok, veh = pcall(function() return g_localPlayer:getCurrentVehicle() end)
        if ok and veh ~= nil then return veh end
    end

    -- 3. FS25 g_currentMission.player:getCurrentVehicle()
    if g_currentMission.player ~= nil and type(g_currentMission.player.getCurrentVehicle) == "function" then
        local ok, veh = pcall(function() return g_currentMission.player:getCurrentVehicle() end)
        if ok and veh ~= nil then return veh end
    end

    -- 4. FS25 g_currentMission.interactiveVehicle
    if g_currentMission.interactiveVehicle ~= nil then
        return g_currentMission.interactiveVehicle
    end

    -- 5. FS25 vehicleSystem
    if g_currentMission.vehicleSystem ~= nil and type(g_currentMission.vehicleSystem.getControlledVehicle) == "function" then
        local ok, veh = pcall(function() return g_currentMission.vehicleSystem:getControlledVehicle() end)
        if ok and veh ~= nil then return veh end
    end

    return nil
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
                    local implObj = item.object
                    local implInfo = {
                        index = idx,
                        name = (implObj.getName ~= nil) and tostring(implObj:getName()) or "Implement",
                        isSelected = (vehicle.selectedImplement == item),
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

            if g_farmManager ~= nil and g_currentMission.playerFarmId ~= nil then
                local farm = g_farmManager:getFarmById(g_currentMission.playerFarmId)
                if farm ~= nil and farm.money ~= nil then
                    env.money = math.floor(farm.money)
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

    local currentTime = g_time or 0
    if (currentTime - self.lastSendTime) < self.UPDATE_INTERVAL_MS then
        return
    end
    self.lastSendTime = currentTime

    if g_currentMission == nil then
        return
    end

    local vehicle = self:getControlledVehicle()
    local vehData = nil

    if vehicle ~= nil then
        vehData = self:extractVehicleData(vehicle)
    else
        -- Active on foot
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
                print(string.format("[%s] Successfully writing telemetry packets to disk! (Seq #%d)", self.MOD_NAME, self.packetSeq))
                self.hasLoggedFirstWrite = true
            end
        end
    elseif self.useXmlFallback and self.xmlFilePath ~= nil then
        local xmlFile = createXMLFile("fstelDoc", self.xmlFilePath, "fstel")
        if xmlFile ~= nil and xmlFile ~= 0 then
            setXMLString(xmlFile, "fstel#payload", jsonStr)
            saveXMLFile(xmlFile)
            delete(xmlFile)
            if not self.hasLoggedFirstWrite then
                print(string.format("[%s] Successfully writing XML telemetry to disk! (Seq #%d)", self.MOD_NAME, self.packetSeq))
                self.hasLoggedFirstWrite = true
            end
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
