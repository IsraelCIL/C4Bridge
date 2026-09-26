local Diagnostics = require("src.core.diagnostics")

-- Adapter for the legacy Light proxy (light.c4i), still used by most
-- Control4-branded dimmers/switches (LDZ-101/102, LDZ-5S1, ...) in older
-- projects. State uses the same variable IDs as Light V2, but the proxy
-- takes the classic ON / OFF / SET_LEVEL commands instead of
-- SET_BRIGHTNESS_TARGET.
local LightV1 = {}

local VARIABLE_STATE = 1000
local VARIABLE_LEVEL = 1001

local tracked = {}

local function clampPercent(value)
    local number = tonumber(value)
    if not number then
        return nil
    end

    number = math.floor(number + 0.5)
    if number < 0 then
        return 0
    end
    if number > 100 then
        return 100
    end
    return number
end

local function boolValue(value)
    local normalized = string.lower(tostring(value or ""))
    return normalized == "1" or normalized == "true" or normalized == "on"
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

function LightV1.matches(device)
    local driver = string.lower(tostring(device and device.proxy and device.proxy.driver or ""))
    return driver == "light.c4i"
end

function LightV1.initialize(device)
    local stateValue = safeGetVariable(device.id, VARIABLE_STATE)
    if stateValue == nil then
        device.supported = false
        device.adapter_error = "Light State variable (1000) is unavailable"
        return false, device.adapter_error
    end

    -- Non-dimming switches (e.g. LDZ-101 in switch mode) have no level.
    local levelValue = safeGetVariable(device.id, VARIABLE_LEVEL)
    local dimmable = levelValue ~= nil

    tracked[device.id] = {
        dimmable = dimmable,
    }

    device.supported = true
    device.adapter_error = nil
    device.capabilities = {
        on_off = true,
        brightness = dimmable,
        brightness_feedback = dimmable,
    }
    device.state = {
        power = boolValue(stateValue),
        brightness = dimmable and clampPercent(levelValue) or nil,
    }
    device.actions = { "on", "off" }
    if dimmable then
        table.insert(device.actions, "set_brightness")
    end

    local stateListenerOk, stateListenerError = pcall(function()
        C4:RegisterVariableListener(device.id, VARIABLE_STATE)
    end)

    if not stateListenerOk then
        tracked[device.id] = nil
        device.supported = false
        device.adapter_error = "Unable to watch Light State: " .. tostring(stateListenerError)
        return false, device.adapter_error
    end

    if dimmable then
        local levelListenerOk, levelListenerError = pcall(function()
            C4:RegisterVariableListener(device.id, VARIABLE_LEVEL)
        end)

        if not levelListenerOk then
            pcall(function()
                C4:UnregisterVariableListener(device.id, VARIABLE_STATE)
            end)
            tracked[device.id] = nil
            device.supported = false
            device.adapter_error = "Unable to watch light level: " .. tostring(levelListenerError)
            return false, device.adapter_error
        end
    end

    return true
end

function LightV1.onVariableChanged(device, variableId, value)
    local info = tracked[device.id]
    if not info or not device.state then
        return false
    end

    variableId = tonumber(variableId)

    if variableId == VARIABLE_STATE then
        device.state.power = boolValue(value)
        return true
    end

    if variableId == VARIABLE_LEVEL and info.dimmable then
        local level = clampPercent(value)
        if level ~= nil then
            device.state.brightness = level
            device.state.power = level > 0
            return true
        end
    end

    return false
end

local function send(deviceId, command, params)
    Diagnostics.info("light_command", "sending light v1 command", {
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

function LightV1.execute(device, action, params)
    local info = tracked[device.id]
    if not info or not device.supported then
        return false, {
            code = "DEVICE_NOT_SUPPORTED",
            message = "This light is not initialized as a supported Light device",
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
    elseif action == "set_brightness" then
        if not info.dimmable then
            return false, {
                code = "ACTION_NOT_SUPPORTED",
                message = "This light does not expose dimmer brightness",
            }
        end

        local target = clampPercent(params and (params.value or params.brightness))
        if target == nil then
            return false, {
                code = "INVALID_BRIGHTNESS",
                message = "Brightness must be a number from 0 to 100",
            }
        end

        sent, sendError = send(device.id, "SET_LEVEL", { LEVEL = target })
        result.command = "SET_LEVEL"
        result.requested_brightness = target
    else
        return false, {
            code = "ACTION_NOT_SUPPORTED",
            message = "Unsupported light action: " .. tostring(action),
        }
    end

    if not sent then
        Diagnostics.error("light_command", "Control4 command failed", {
            device_id = device.id,
            action = action,
            error = sendError,
        })
        return false, {
            code = "CONTROL4_COMMAND_FAILED",
            message = "Director rejected the light command: " .. tostring(sendError),
        }
    end

    Diagnostics.info("light_command", "Control4 command dispatched", result)
    return true, result
end

function LightV1.reset()
    tracked = {}
end

return LightV1
