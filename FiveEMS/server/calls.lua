FiveEMS = FiveEMS or {}
FiveEMS.Calls = FiveEMS.Calls or {}

local Calls = FiveEMS.Calls
local Server = FiveEMS.Server
local DB = FiveEMS.DB
local nextId = 1

local function broadcastCall(call)
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        local member = Server.getMember(src)
        if member and member.on_duty and member.department_type ~= FiveEMS.DepartmentTypes.CSI then
            TriggerClientEvent('fiveems:client:newCall', src, call)
        end
    end
end

function Calls.create(payload, creator)
    payload = payload or {}
    local call = {
        id = nextId,
        title = payload.title or 'Emergencia medica',
        description = payload.description or '',
        x = tonumber(payload.x), y = tonumber(payload.y), z = tonumber(payload.z),
        priority = tonumber(payload.priority) or 2,
        createdAt = os.time(),
        creator = creator,
        status = 'open'
    }
    nextId = nextId + 1
    FiveEMS.Cache.calls[call.id] = call
    DB.insert('INSERT INTO fiveems_calls (external_id, title, description, x, y, z, priority, status, payload) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)', {
        tostring(call.id), call.title, call.description, call.x, call.y, call.z, call.priority, call.status, DB.jsonEncode(payload)
    })
    broadcastCall(call)
    return call
end

RegisterNetEvent('fiveems:server:create911', function(payload)
    local src = source
    payload = payload or {}
    Calls.create(payload, Server.getPrimaryIdentifier(src))
end)

RegisterNetEvent('fiveems:server:acceptCall', function(callId)
    local src = source
    local member = Server.getMember(src)
    if not member or not member.on_duty then return end
    local call = FiveEMS.Cache.calls[tonumber(callId)]
    if not call then return end
    call.assignedTo = Server.getPrimaryIdentifier(src)
    call.status = 'assigned'
    DB.update('UPDATE fiveems_calls SET status=?, assigned_identifier=? WHERE external_id=?', {'assigned', call.assignedTo, tostring(call.id)})
end)

function Calls.createFromPlayer(src, args, commandName)
    src = tonumber(src)
    if not src or src <= 0 then return nil end
    local ped = GetPlayerPed(src)
    if ped == 0 then return nil end
    local coords = GetEntityCoords(ped)
    local label = tostring(commandName or 'EMS'):upper()
    return Calls.create({
        title = ('Chamado %s'):format(label),
        description = table.concat(args or {}, ' '),
        x = coords.x, y = coords.y, z = coords.z,
        priority = 2
    }, Server.getPrimaryIdentifier(src))
end

exports('CreateCall', function(payload) return Calls.create(payload, 'export') end)
