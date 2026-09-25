local Version = require("src.core.version")
local Registry = require("src.core.registry")
local Discovery = require("src.control4.discovery")

local STATE = {
    directorVersion = nil,
    supported = false,
}

local function log(message)
    print("[C4Bridge] " .. tostring(message))
end

local function readDirectorVersion()
    local info = C4:GetVersionInfo()
    if type(info) ~= "table" then
        return nil
    end
    return info.version
end

function OnDriverInit(driverInitType)
    STATE.directorVersion = readDirectorVersion()
    STATE.supported = Version.isSupported(STATE.directorVersion)

    log("loading " .. Version.BRIDGE_VERSION .. " (" .. tostring(driverInitType) .. ")")
    log("Director OS: " .. tostring(STATE.directorVersion))

    if not STATE.supported then
        log("unsupported Director OS; C4Bridge requires 3.3.0+")
    end
end

function OnDriverLateInit(driverInitType)
    log("late init (" .. tostring(driverInitType) .. ")")

    if not STATE.supported then
        return
    end

    -- Project-wide discovery belongs here, after Director has loaded the project.
    local ok, raw = pcall(Discovery.collectRaw)
    if not ok then
        log("discovery failed: " .. tostring(raw))
        return
    end

    Registry.reset()

    -- Milestone 0: prove Director returns the project data we need.
    -- XML parsing and normalization is the next implementation step.
    log("project XML bytes: " .. tostring(raw.projectXml and #raw.projectXml or 0))
    log("location XML bytes: " .. tostring(raw.locationsXml and #raw.locationsXml or 0))
    log("device/proxy XML bytes: " .. tostring(raw.devicesXml and #raw.devicesXml or 0))
end

function OnDriverDestroyed(driverInitType)
    log("destroyed (" .. tostring(driverInitType) .. ")")
end
