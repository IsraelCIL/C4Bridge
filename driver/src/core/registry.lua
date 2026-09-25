local Registry = {
    rooms = {},
    devices = {},
    refreshedAt = nil,
}

function Registry.reset()
    Registry.rooms = {}
    Registry.devices = {}
    Registry.refreshedAt = nil
end

function Registry.putRoom(room)
    if room and room.id then
        Registry.rooms[tonumber(room.id)] = room
    end
end

function Registry.putDevice(device)
    if device and device.id then
        Registry.devices[tonumber(device.id)] = device
    end
end

function Registry.getDevice(id)
    return Registry.devices[tonumber(id)]
end

function Registry.snapshot()
    return {
        rooms = Registry.rooms,
        devices = Registry.devices,
        refreshedAt = Registry.refreshedAt,
    }
end

return Registry
