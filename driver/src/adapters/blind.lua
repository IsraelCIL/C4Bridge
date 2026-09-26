local Diagnostics = require("src.core.diagnostics")

-- Adapter for the Blind proxy (blind.c4i): shades, blinds and blind groups.
-- The proxy owns its own state variables (the backing motor driver has a
-- separate CURRENT_LEVEL, which is not needed here). Level is 0 = closed,
-- 100 = open, and the proxy moves with SET_LEVEL_TARGET(LEVEL_TARGET).
local Blind = {}

local VARIABLE_FULLY_CLOSED = 1001
local VARIABLE_STOPPED = 1002
local VARIABLE_FULLY_OPEN = 1003
local VARIABLE_LEVEL = 1004
local VARIABLE_TARGET_LEVEL = 1005
local VARIABLE_TYPE = 1006
local VARIABLE_OPENING = 1008
local VARIABLE_CLOSING = 1009

local WATCHED = {
    VARIABLE_FULLY_CLOSED,
    VARIABLE_STOPPED,
    VARIABLE_FULLY_OPEN,
    VARIABLE_LEVEL,
    VARIABLE_TARGET_LEVEL,
    VARIABLE_OPENING,
    VARIABLE_CLOSING,
}

local LEVEL_OPEN = 100
local LEVEL_CLOSED = 0

local tracked = {}

local function boolValue(value)
    local normalized = string.lower(tostring(value or ""))
    return normalized == "1" or normalized == "true"
end

local function clampPercent(value)
    local number = tonumber(value)
    if not number then
        return nil
    end
    number = math.floor(number + 0.5)
    if number < 0 or number > 100 then
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

local function refresh(device)
    local raw = tracked[device.id].raw
    local opening = boolValue(raw[VARIABLE_OPENING])
    local closing = boolValue(raw[VARIABLE_CLOSING])

    device.state.level = clampPercent(raw[VARIABLE_LEVEL])
    device.state.target_level = clampPercent(raw[VARIABLE_TARGET_LEVEL])
    device.state.fully_open = boolValue(raw[VARIABLE_FULLY_OPEN])
    device.state.fully_closed = boolValue(raw[VARIABLE_FULLY_CLOSED])
    device.state.movement = opening and "opening" or (closing and "closing" or "stopped")
end

function Blind.matches(device)
    local driver = string.lower(tostring(device and device.proxy and device.proxy.driver or ""))
    return driver == "blind.c4i"
end

function Blind.reset()
    tracked = {}
end

function Blind.initialize(device)
    local raw = {}
    for _, variableId in ipairs(WATCHED) do
        raw[variableId] = safeGetVariable(device.id, variableId)
    end

    if raw[VARIABLE_LEVEL] == nil then
        device.supported = false
        device.adapter_error = "Blind Level variable (1004) is unavailable"
        return false, device.adapter_error
    end

    for _, variableId in ipairs(WATCHED) do
        if raw[variableId] ~= nil then
            local ok, err = pcall(function()
                C4:RegisterVariableListener(device.id, variableId)
            end)
            if not ok then
                device.supported = false
                device.adapter_error = "Unable to watch blind variable " .. tostring(variableId) .. ": " .. tostring(err)
                return false, device.adapter_error
            end
        end
    end

    tracked[device.id] = { raw = raw }

    device.supported = true
    device.adapter_error = nil
    device.capabilities = {
        position = true,
        stop = true,
        type = safeGetVariable(device.id, VARIABLE_TYPE),
    }
    device.state = {}
    device.actions = { "open", "close", "stop", "set_level" }
    refresh(device)

    return true
end

function Blind.onVariableChanged(device, variableId, value)
    local info = tracked[device.id]
    if not info or not device.state then
        return false
    end

    variableId = tonumber(variableId)
    for _, watched in ipairs(WATCHED) do
        if watched == variableId then
            info.raw[variableId] = value
            refresh(device)
            return true
        end
    end
    return false
end

local function send(deviceId, command, params)
    Diagnostics.info("cover_command", "sending blind command", {
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

function Blind.execute(device, action, params)
    if not tracked[device.id] or not device.supported then
        return false, {
            code = "DEVICE_NOT_SUPPORTED",
            message = "This blind is not initialized as a supported Blind device",
        }
    end

    local result = {
        device_id = device.id,
        action = action,
    }
    local sent, sendError

    if action == "open" or action == "close" or action == "set_level" then
        local target
        if action == "open" then
            target = LEVEL_OPEN
        elseif action == "close" then
            target = LEVEL_CLOSED
        else
            target = clampPercent(params and (params.value or params.level))
            if target == nil then
                return false, {
                    code = "INVALID_LEVEL",
                    message = "Level must be a number from 0 (closed) to 100 (open)",
                }
            end
        end
        sent, sendError = send(device.id, "SET_LEVEL_TARGET", { LEVEL_TARGET = target })
        result.command = "SET_LEVEL_TARGET"
        result.requested_level = target
    elseif action == "stop" then
        sent, sendError = send(device.id, "STOP")
        result.command = "STOP"
    else
        return false, {
            code = "ACTION_NOT_SUPPORTED",
            message = "Unsupported blind action: " .. tostring(action),
        }
    end

    if not sent then
        Diagnostics.error("cover_command", "Control4 command failed", {
            device_id = device.id,
            action = action,
            error = sendError,
        })
        return false, {
            code = "CONTROL4_COMMAND_FAILED",
            message = "Director rejected the blind command: " .. tostring(sendError),
        }
    end

    Diagnostics.info("cover_command", "Control4 command dispatched", result)
    return true, result
end

return Blind
