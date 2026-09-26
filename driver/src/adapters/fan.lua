local Diagnostics = require("src.core.diagnostics")

-- Adapter for the Control4 Fan proxy (fan.c4i), e.g. the Control4 fan speed
-- controller. State lives on the proxy; speed uses the proxy's 0-4 scale
-- (Off, Low, Medium, Medium High, High) as listed by its SET_SPEED command.
local Fan = {}

local VARIABLE_IS_ON = 1000
local VARIABLE_CURRENT_SPEED = 1001
local VARIABLE_PRESET_SPEED = 1003

local MAX_SPEED = 4
local SPEED_NAMES = { "low", "medium", "medium_high", "high" }

local tracked = {}

local function boolValue(value)
    local normalized = string.lower(tostring(value or ""))
    return normalized == "1" or normalized == "true" or normalized == "on"
end

local function speedValue(value)
    local number = tonumber(value)
    if not number then
        return nil
    end
    number = math.floor(number + 0.5)
    if number < 0 or number > MAX_SPEED then
        return nil
    end
    return number
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

function Fan.matches(device)
    local driver = string.lower(tostring(device and device.proxy and device.proxy.driver or ""))
    return driver == "fan.c4i"
end

function Fan.initialize(device)
    local isOn = safeGetVariable(device.id, VARIABLE_IS_ON)
    local speed = safeGetVariable(device.id, VARIABLE_CURRENT_SPEED)
    if isOn == nil or speed == nil then
        device.supported = false
        device.adapter_error = "Fan state variables (1000/1001) are unavailable"
        return false, device.adapter_error
    end

    for _, variableId in ipairs({ VARIABLE_IS_ON, VARIABLE_CURRENT_SPEED }) do
        local ok, err = pcall(function()
            C4:RegisterVariableListener(device.id, variableId)
        end)
        if not ok then
            device.supported = false
            device.adapter_error = "Unable to watch fan variable " .. tostring(variableId) .. ": " .. tostring(err)
            return false, device.adapter_error
        end
    end

    tracked[device.id] = true

    device.supported = true
    device.adapter_error = nil
    device.capabilities = {
        on_off = true,
        speeds = SPEED_NAMES,
        max_speed = MAX_SPEED,
    }
    device.state = {
        power = boolValue(isOn),
        speed = speedValue(speed),
        preset_speed = speedValue(safeGetVariable(device.id, VARIABLE_PRESET_SPEED)),
    }
    device.actions = { "on", "off", "set_speed" }

    return true
end

function Fan.onVariableChanged(device, variableId, value)
    if not tracked[device.id] or not device.state then
        return false
    end

    variableId = tonumber(variableId)

    if variableId == VARIABLE_IS_ON then
        device.state.power = boolValue(value)
        return true
    end

    if variableId == VARIABLE_CURRENT_SPEED then
        local speed = speedValue(value)
        if speed ~= nil then
            device.state.speed = speed
            device.state.power = speed > 0
            return true
        end
    end

    return false
end

local function send(deviceId, command, params)
    Diagnostics.info("fan_command", "sending fan command", {
        device_id = deviceId,
        command = command,
        params = params,
    })

    local ok, err = pcall(function()
        C4:SendToDevice(deviceId, command, params or {})
    end)

    if not ok then
        return false, tostring(err)
    end

    return true
end

-- Accepts 0-4 or a speed name ("low", "medium", "medium_high", "high", "off").
local function parseSpeed(value)
    local numeric = speedValue(value)
    if numeric ~= nil then
        return numeric
    end
    local name = string.lower(tostring(value or ""))
    if name == "off" then
        return 0
    end
    for index, speedName in ipairs(SPEED_NAMES) do
        if name == speedName then
            return index
        end
    end
    return nil
end

function Fan.execute(device, action, params)
    if not tracked[device.id] or not device.supported then
        return false, {
            code = "DEVICE_NOT_SUPPORTED",
            message = "This fan is not initialized as a supported Fan device",
        }
    end

    local result = {
        device_id = device.id,
        action = action,
    }
    local sent, sendError

    if action == "on" then
        sent, sendError = send(device.id, "ON")
        result.command = "ON"
    elseif action == "off" then
        sent, sendError = send(device.id, "OFF")
        result.command = "OFF"
    elseif action == "set_speed" then
        local speed = parseSpeed(params and (params.value or params.speed))
        if speed == nil then
            return false, {
                code = "INVALID_SPEED",
                message = "Speed must be 0-" .. tostring(MAX_SPEED) .. " or one of off, low, medium, medium_high, high",
            }
        end
        sent, sendError = send(device.id, "SET_SPEED", { SPEED = speed })
        result.command = "SET_SPEED"
        result.requested_speed = speed
    else
        return false, {
            code = "ACTION_NOT_SUPPORTED",
            message = "Unsupported fan action: " .. tostring(action),
        }
    end

    if not sent then
        Diagnostics.error("fan_command", "Control4 command failed", {
            device_id = device.id,
            action = action,
            error = sendError,
        })
        return false, {
            code = "CONTROL4_COMMAND_FAILED",
            message = "Director rejected the fan command: " .. tostring(sendError),
        }
    end

    Diagnostics.info("fan_command", "Control4 command dispatched", result)
    return true, result
end

function Fan.reset()
    tracked = {}
end

return Fan
