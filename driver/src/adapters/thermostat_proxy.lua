local Diagnostics = require("src.core.diagnostics")

-- Adapter for the Control4 thermostat proxy (control4_thermostat_proxy.c4i),
-- used by Control4-branded wireless thermostats. It shares Thermostat V2's
-- variable IDs but is dual-setpoint (separate heat and cool setpoints) and
-- reports/accepts temperatures in the project's scale, so this adapter is
-- scale-aware (°F or °C) rather than Celsius-only.
local Thermostat = {}

local VARIABLE_SCALE = 1100
local VARIABLE_HVAC_MODE = 1104
local VARIABLE_FAN_MODE = 1105
local VARIABLE_HVAC_STATE = 1107
local VARIABLE_FAN_STATE = 1108
local VARIABLE_IS_CONNECTED = 1112
local VARIABLE_HVAC_MODES_LIST = 1120
local VARIABLE_FAN_MODES_LIST = 1121
local VARIABLE_TEMPERATURE_F = 1130
local VARIABLE_TEMPERATURE_C = 1131
local VARIABLE_HEAT_SETPOINT_F = 1132
local VARIABLE_HEAT_SETPOINT_C = 1133
local VARIABLE_COOL_SETPOINT_F = 1134
local VARIABLE_COOL_SETPOINT_C = 1135
local VARIABLE_DEADBAND_F = 1146
local VARIABLE_DEADBAND_C = 1147

local WATCHED = {
    VARIABLE_SCALE,
    VARIABLE_HVAC_MODE,
    VARIABLE_FAN_MODE,
    VARIABLE_HVAC_STATE,
    VARIABLE_FAN_STATE,
    VARIABLE_IS_CONNECTED,
    VARIABLE_HVAC_MODES_LIST,
    VARIABLE_FAN_MODES_LIST,
    VARIABLE_TEMPERATURE_F,
    VARIABLE_TEMPERATURE_C,
    VARIABLE_HEAT_SETPOINT_F,
    VARIABLE_HEAT_SETPOINT_C,
    VARIABLE_COOL_SETPOINT_F,
    VARIABLE_COOL_SETPOINT_C,
}

-- Sanity bounds for requested setpoints; the thermostat enforces its own
-- limits and deadband on top of these.
local SETPOINT_LIMITS = {
    F = { min = 40, max = 95 },
    C = { min = 5, max = 35 },
}

local tracked = {}

local function lower(value)
    return string.lower(tostring(value or ""))
end

local function safeGetVariable(deviceId, variableId)
    local ok, value = pcall(function()
        return C4:GetVariable(deviceId, variableId)
    end)
    if ok then
        return value
    end
    return nil
end

local function number(value)
    return tonumber(value)
end

local function boolValue(value)
    local v = lower(value)
    return v == "1" or v == "true" or v == "on" or v == "yes"
end

local function parseList(value)
    local result = {}
    for item in tostring(value or ""):gmatch("[^,]+") do
        item = item:gsub("^%s+", ""):gsub("%s+$", "")
        if item ~= "" then
            table.insert(result, item)
        end
    end
    return result
end

local function unitFromScale(scale)
    return lower(scale):sub(1, 1) == "c" and "C" or "F"
end

local function findInList(list, requested)
    local wanted = lower(requested)
    for _, entry in ipairs(list or {}) do
        if lower(entry) == wanted then
            return entry
        end
    end
    return nil
end

local function toUnit(value, fromUnit, toUnitName)
    if value == nil or fromUnit == toUnitName then
        return value
    end
    if toUnitName == "C" then
        return (value - 32) * 5 / 9
    end
    return value * 9 / 5 + 32
end

local function roundTenth(value)
    return math.floor(value * 10 + 0.5) / 10
end

-- Rebuild the unit-dependent parts of state/capabilities from the raw values.
local function refresh(device)
    local info = tracked[device.id]
    local raw = info.raw
    local unit = unitFromScale(raw[VARIABLE_SCALE])
    local suffix = unit == "C" and "C" or "F"

    local function pick(fVar, cVar)
        return number(raw[suffix == "F" and fVar or cVar])
    end

    info.unit = unit
    device.capabilities.temperature_unit = unit
    device.capabilities.hvac_modes = info.hvacModes
    device.capabilities.fan_modes = info.fanModes
    device.capabilities.deadband = pick(VARIABLE_DEADBAND_F, VARIABLE_DEADBAND_C)
    device.capabilities.setpoint_min = SETPOINT_LIMITS[unit].min
    device.capabilities.setpoint_max = SETPOINT_LIMITS[unit].max

    device.state.scale = unit
    device.state.connected = raw[VARIABLE_IS_CONNECTED] == nil and true or boolValue(raw[VARIABLE_IS_CONNECTED])
    device.state.current_temperature = pick(VARIABLE_TEMPERATURE_F, VARIABLE_TEMPERATURE_C)
    device.state.heat_setpoint = pick(VARIABLE_HEAT_SETPOINT_F, VARIABLE_HEAT_SETPOINT_C)
    device.state.cool_setpoint = pick(VARIABLE_COOL_SETPOINT_F, VARIABLE_COOL_SETPOINT_C)
    device.state.current_temperature_c = number(raw[VARIABLE_TEMPERATURE_C])
    device.state.current_temperature_f = number(raw[VARIABLE_TEMPERATURE_F])
    device.state.hvac_mode = raw[VARIABLE_HVAC_MODE] and lower(raw[VARIABLE_HVAC_MODE]) or nil
    device.state.hvac_state = raw[VARIABLE_HVAC_STATE] and lower(raw[VARIABLE_HVAC_STATE]) or nil
    device.state.fan_mode = raw[VARIABLE_FAN_MODE] and lower(raw[VARIABLE_FAN_MODE]) or nil
    device.state.fan_state = raw[VARIABLE_FAN_STATE] and lower(raw[VARIABLE_FAN_STATE]) or nil
end

function Thermostat.matches(device)
    local driver = lower(device and device.proxy and device.proxy.driver)
    return driver == "control4_thermostat_proxy.c4i"
end

function Thermostat.reset()
    tracked = {}
end

function Thermostat.initialize(device)
    local raw = {}
    for _, variableId in ipairs(WATCHED) do
        raw[variableId] = safeGetVariable(device.id, variableId)
    end
    raw[VARIABLE_DEADBAND_F] = safeGetVariable(device.id, VARIABLE_DEADBAND_F)
    raw[VARIABLE_DEADBAND_C] = safeGetVariable(device.id, VARIABLE_DEADBAND_C)

    if raw[VARIABLE_HVAC_MODE] == nil
        or (raw[VARIABLE_TEMPERATURE_F] == nil and raw[VARIABLE_TEMPERATURE_C] == nil)
        or (raw[VARIABLE_HEAT_SETPOINT_F] == nil and raw[VARIABLE_HEAT_SETPOINT_C] == nil) then
        return false, "Required thermostat state variables are unavailable"
    end

    for _, variableId in ipairs(WATCHED) do
        if raw[variableId] ~= nil then
            local ok = pcall(function()
                C4:RegisterVariableListener(device.id, variableId)
            end)
            if not ok then
                return false, "Unable to register thermostat state listener " .. tostring(variableId)
            end
        end
    end

    local hvacModes = parseList(raw[VARIABLE_HVAC_MODES_LIST])
    if #hvacModes == 0 then
        hvacModes = { "Off", "Heat", "Cool", "Auto" }
    end

    tracked[device.id] = {
        raw = raw,
        hvacModes = hvacModes,
        fanModes = parseList(raw[VARIABLE_FAN_MODES_LIST]),
    }

    device.supported = true
    device.capabilities = { setpoint_mode = "dual" }
    device.state = {}
    device.actions = { "set_hvac_mode", "set_heat_setpoint", "set_cool_setpoint" }
    if #tracked[device.id].fanModes > 0 then
        table.insert(device.actions, "set_fan_mode")
    end
    refresh(device)

    Diagnostics.info("climate", "initialized dual-setpoint thermostat", {
        device_id = device.id,
        unit = tracked[device.id].unit,
        hvac_modes = hvacModes,
    })

    return true
end

function Thermostat.onVariableChanged(device, variableId, value)
    local info = tracked[device.id]
    if not info or not device.state then
        return false
    end

    variableId = tonumber(variableId)
    local known = false
    for _, watched in ipairs(WATCHED) do
        if watched == variableId then
            known = true
            break
        end
    end
    if not known then
        return false
    end

    info.raw[variableId] = value
    if variableId == VARIABLE_HVAC_MODES_LIST then
        local modes = parseList(value)
        if #modes > 0 then
            info.hvacModes = modes
        end
    elseif variableId == VARIABLE_FAN_MODES_LIST then
        info.fanModes = parseList(value)
    end
    refresh(device)
    return true
end

local function send(deviceId, command, params)
    Diagnostics.info("climate_command", "sending thermostat command", {
        device_id = deviceId,
        command = command,
        params = params,
    })

    local ok, err = pcall(function()
        C4:SendToDevice(deviceId, command, params)
    end)
    if not ok then
        return false, tostring(err)
    end
    return true
end

-- Setpoints are given in the thermostat's own unit unless `unit` (f/c) is
-- passed, in which case they are converted.
local function setpointTarget(info, params)
    local value = tonumber(params and params.value)
    if not value then
        return nil
    end
    local requestedUnit = params.unit and string.upper(tostring(params.unit)):sub(1, 1) or info.unit
    if requestedUnit ~= "C" and requestedUnit ~= "F" then
        return nil
    end
    local target = roundTenth(toUnit(value, requestedUnit, info.unit))
    local limits = SETPOINT_LIMITS[info.unit]
    if target < limits.min or target > limits.max then
        return nil
    end
    return target
end

function Thermostat.execute(device, action, params)
    local info = tracked[device.id]
    if not info then
        return false, {
            code = "DEVICE_NOT_SUPPORTED",
            message = "Thermostat adapter is not initialized",
        }
    end

    if action == "set_hvac_mode" then
        local mode = findInList(info.hvacModes, params and (params.value or params.mode))
        if not mode then
            return false, {
                code = "HVAC_MODE_NOT_SUPPORTED",
                message = "HVAC mode must be one of: " .. table.concat(info.hvacModes, ", "),
            }
        end
        local ok, err = send(device.id, "SET_MODE_HVAC", { MODE = mode })
        if not ok then
            return false, { code = "COMMAND_FAILED", message = err }
        end
        return true, { device_id = device.id, action = action, requested_mode = mode }
    end

    if action == "set_fan_mode" then
        local mode = findInList(info.fanModes, params and (params.value or params.mode))
        if not mode then
            return false, {
                code = "FAN_MODE_NOT_SUPPORTED",
                message = "Fan mode must be one of: " .. table.concat(info.fanModes, ", "),
            }
        end
        local ok, err = send(device.id, "SET_MODE_FAN", { MODE = mode })
        if not ok then
            return false, { code = "COMMAND_FAILED", message = err }
        end
        return true, { device_id = device.id, action = action, requested_mode = mode }
    end

    if action == "set_heat_setpoint" or action == "set_cool_setpoint" then
        local target = setpointTarget(info, params)
        if not target then
            local limits = SETPOINT_LIMITS[info.unit]
            return false, {
                code = "INVALID_SETPOINT",
                message = "Setpoint must be a number from " .. limits.min .. " to " .. limits.max .. " °" .. info.unit,
            }
        end
        local command = action == "set_heat_setpoint" and "SET_SETPOINT_HEAT" or "SET_SETPOINT_COOL"
        local key = info.unit == "C" and "CELSIUS" or "FAHRENHEIT"
        local ok, err = send(device.id, command, { [key] = target })
        if not ok then
            return false, { code = "COMMAND_FAILED", message = err }
        end
        return true, {
            device_id = device.id,
            action = action,
            requested_setpoint = target,
            unit = info.unit,
        }
    end

    return false, {
        code = "ACTION_NOT_SUPPORTED",
        message = "Unsupported thermostat action: " .. tostring(action),
    }
end

return Thermostat
