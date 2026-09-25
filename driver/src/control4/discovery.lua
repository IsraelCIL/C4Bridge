local Discovery = {}

-- Discovery deliberately runs after Director has loaded the full project.
-- Do not call project-wide discovery APIs from OnDriverInit.

function Discovery.readProjectXml()
    return C4:GetProjectItems("ALL")
end

function Discovery.readLocationsXml()
    return C4:GetProjectItems("LOCATIONS", "LIMIT_DEVICE_DATA")
end

function Discovery.readDevicesXml()
    return C4:GetProjectItems("DEVICES", "PROXIES")
end

function Discovery.collectRaw()
    return {
        projectXml = Discovery.readProjectXml(),
        locationsXml = Discovery.readLocationsXml(),
        devicesXml = Discovery.readDevicesXml(),
    }
end

return Discovery
