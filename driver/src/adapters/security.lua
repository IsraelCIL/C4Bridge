local Diagnostics = require("src.core.diagnostics")

-- Read-only adapter for security partitions (security.c4i).
--
-- Deliberately exposes state only. Arming/disarming (PARTITION_ARM /
-- PARTITION_DISARM) needs the user's alarm code, and the V1 LAN API is
-- plain HTTP with a single shared owner credential; sending alarm codes and
-- allowing remote disarm over that transport should wait for a stronger
-- auth/transport design.
local Security = {}

local VARIABLE_HOME_STATE = 1000
local VARIABLE_AWAY_STATE = 1001
local VARIABLE_DISARMED_STATE = 1002
local VARIABLE_ALARM_STATE = 1003
local VARIABLE_TROUBLE_TEXT = 1005
local VARIABLE_IS_ACTIVE = 1006
local VARIABLE_PARTITION_STATE = 1007
local VARIABLE_DELAY_TIME_TOTAL = 1008
local VARIABLE_DELAY_TIME_REMAINING = 1009
local VARIABLE_OPEN_ZONE_COUNT = 1010
local VARIABLE_ALARM_TYPE = 1011
local VARIABLE_ARMED_TYPE = 1012

local WATCHED = {
    VARIABLE_IS_ACTIVE,
    VARIABLE_HOME_STATE,
    VARIABLE_AWAY_STATE,
    VARIABLE_DISARMED_STATE,
    VARIABLE_ALARM_STATE,
    VARIABLE_TROUBLE_TEXT,
    VARIABLE_PARTITION_STATE,
    VARIABLE_DELAY_TIME_TOTAL,
    VARIABLE_DELAY_TIME_REMAINING,
    VARIABLE_OPEN_ZONE_COUNT,
    VARIABLE_ALARM_TYPE,
    VARIABLE_ARMED_TYPE,
}

local tracked = {}

local function boolValue(value)
    local normalized = string.lower(tostring(value or ""))
    return normalized == "1" or normalized == "true"
end

local function textValue(value)
    local text = tostring(value or "")
    return text ~= "" and text or nil
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
    local armedHome = boolValue(raw[VARIABLE_HOME_STATE])
    local armedAway = boolValue(raw[VARIABLE_AWAY_STATE])

    -- Unused partitions report IS_ACTIVE = 0. At Director startup the panel
    -- driver may not have connected yet, so activity is tracked live rather
    -- than decided once at init.
    device.state.active = raw[VARIABLE_IS_ACTIVE] == nil or boolValue(raw[VARIABLE_IS_ACTIVE])
    device.state.partition_state = textValue(raw[VARIABLE_PARTITION_STATE])
    device.state.armed = armedHome or armedAway
    device.state.armed_mode = armedAway and "away" or (armedHome and "home" or nil)
    device.state.armed_type = textValue(raw[VARIABLE_ARMED_TYPE])
    device.state.disarmed = boolValue(raw[VARIABLE_DISARMED_STATE])
    device.state.alarm = boolValue(raw[VARIABLE_ALARM_STATE])
    device.state.alarm_type = textValue(raw[VARIABLE_ALARM_TYPE])
    device.state.open_zones = tonumber(raw[VARIABLE_OPEN_ZONE_COUNT])
    device.state.delay_remaining = tonumber(raw[VARIABLE_DELAY_TIME_REMAINING])
    device.state.delay_total = tonumber(raw[VARIABLE_DELAY_TIME_TOTAL])
    device.state.trouble = textValue(raw[VARIABLE_TROUBLE_TEXT])
end

function Security.matches(device)
    local driver = string.lower(tostring(device and device.proxy and device.proxy.driver or ""))
    return driver == "security.c4i"
end

function Security.reset()
    tracked = {}
end

function Security.initialize(device)
    local partitionState = safeGetVariable(device.id, VARIABLE_PARTITION_STATE)
    if partitionState == nil then
        return false, "Partition State variable (1007) is unavailable"
    end

    local raw = {}
    for _, variableId in ipairs(WATCHED) do
        raw[variableId] = safeGetVariable(device.id, variableId)
        if raw[variableId] ~= nil then
            local ok = pcall(function()
                C4:RegisterVariableListener(device.id, variableId)
            end)
            if not ok then
                return false, "Unable to watch security variable " .. tostring(variableId)
            end
        end
    end

    tracked[device.id] = { raw = raw }

    device.supported = true
    device.capabilities = { read_only = true }
    device.state = {}
    device.actions = {}
    refresh(device)

    Diagnostics.info("security", "initialized read-only partition", {
        device_id = device.id,
        partition_state = device.state.partition_state,
    })

    return true
end

function Security.onVariableChanged(device, variableId, value)
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

function Security.execute(device, action)
    return false, {
        code = "ACTION_NOT_SUPPORTED",
        message = "Security partitions are read-only in C4Bridge V1 (" .. tostring(action) .. ")",
    }
end

return Security
