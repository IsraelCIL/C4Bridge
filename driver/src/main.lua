local Version = require("core.version")
local Registry = require("core.registry")
local Discovery = require("control4.discovery")

local function log(message)
    print("[C4Bridge] " .. tostring(message))
end

function OnDriverInit(driverInitType)
    log("loading " .. Version.BRIDGE_VERSION .. " (" .. tostring(driverInitType) .. ")")
end

function OnDriverLateInit(driverInitType)
    log("late init (" .. tostring(driverInitType) .. ")")

    -- Milestone 0 only: prove project discovery safely after Director startup.
    local ok, raw = pcall(Discovery.collectRaw)
    if not ok then
        log("discovery failed: " .. tostring(raw))
        return
    end

    Registry.reset()

    -- Parsing/normalization is intentionally the next implementation step.
    -- For now we only prove that Director returns the expected project XML.
    log("project XML bytes: " .. tostring(raw.projectXml and #raw.projectXml or 0))
    log("location XML bytes: " .. tostring(raw.locationsXml and #raw.locationsXml or 0))
    log("device/proxy XML bytes: " .. tostring(raw.devicesXml and #raw.devicesXml or 0))
end

function OnDriverDestroyed(driverInitType)
    log("destroyed (" .. tostring(driverInitType) .. ")")
end
