FiveEMS = FiveEMS or {}
FiveEMS.PortableMonitors = FiveEMS.PortableMonitors or {}

local PM = FiveEMS.PortableMonitors
local Server = FiveEMS.Server
local F = FiveEMS.Framework
local DB = FiveEMS.DB

PM.active = PM.active or {}
PM.byOwner = PM.byOwner or {}

local function cfg()
    local monitor = Config.Monitor or {}
    return monitor.portable or {}
end

local function portableEnabled()
    return cfg().enabled ~= false
end

local function getEntityFromNet(netId)
    netId = tonumber(netId)
    if not netId or netId <= 0 then return 0 end
    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return 0 end
    return entity
end

local function distance(a, b)
    if not a or not b then return 9999.0 end
    local dx, dy, dz = a.x-b.x, a.y-b.y, a.z-b.z
    return math.sqrt(dx*dx + dy*dy + dz*dz)
end

local function sourceNearEntity(src, entity, maxDist)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return false end
    return distance(GetEntityCoords(ped), GetEntityCoords(entity)) <= (tonumber(maxDist) or 5.0)
end

local function resolvePatientEntity(ref)
    if type(ref) ~= 'table' then return 0 end
    if ref.kind == 'player' then
        local ped = GetPlayerPed(tonumber(ref.serverId) or -1)
        return ped and ped ~= 0 and DoesEntityExist(ped) and ped or 0
    end
    if ref.kind == 'npc' then
        local entity = getEntityFromNet(ref.netId)
        if entity ~= 0 and GetEntityType(entity) == 1 then return entity end
    end
    return 0
end

local function setMonitorState(monitor, ref)
    if not monitor or not monitor.entity or monitor.entity == 0 or not DoesEntityExist(monitor.entity) then return end
    local bag = Entity(monitor.entity).state
    if not bag then return end

    bag:set('fiveems:portableMonitor', true, true)
    bag:set('fiveems:monitorOwner', tonumber(monitor.owner) or 0, true)
    bag:set('fiveems:monitorLabel', tostring(cfg().label or 'LIFEPAK 15'), true)

    if type(ref) == 'table' then
        bag:set('fiveems:monitorPatientKind', tostring(ref.kind or ''), true)
        bag:set('fiveems:monitorPatientId', tonumber(ref.kind == 'player' and ref.serverId or ref.netId) or 0, true)
        bag:set('fiveems:monitorConnected', true, true)
    else
        bag:set('fiveems:monitorPatientKind', '', true)
        bag:set('fiveems:monitorPatientId', 0, true)
        bag:set('fiveems:monitorConnected', false, true)
    end
end

local function detachMonitor(netId, reason)
    netId = tonumber(netId)
    local monitor = netId and PM.active[netId] or nil
    if not monitor then return end
    monitor.patientRef = nil
    setMonitorState(monitor, nil)
    TriggerClientEvent('fiveems:client:portableMonitorDetached', -1, netId, reason or 'Paciente desconectado.')
end

local function deleteMonitor(netId, reason)
    netId = tonumber(netId)
    local monitor = netId and PM.active[netId] or nil
    if not monitor then return false end

    PM.active[netId] = nil
    if monitor.owner and PM.byOwner[monitor.owner] == netId then
        PM.byOwner[monitor.owner] = nil
    end

    TriggerClientEvent('fiveems:client:portableMonitorRemoved', -1, netId, reason or 'Equipamento guardado.')

    if monitor.entity and monitor.entity ~= 0 and DoesEntityExist(monitor.entity) then
        DeleteEntity(monitor.entity)
    end
    return true
end

local function hasPortableItem(src)
    if cfg().requireInventory == false then return true end
    local itemName = tostring(cfg().itemName or 'lifepak15_monitor')
    if F and F.hasExactFiveEMSItem then
        return F.hasExactFiveEMSItem(src, itemName, 1)
    end
    return false
end

local function canBeginPortableUse(src)
    if not portableEnabled() then return false, 'Monitor portatil desativado na configuracao.' end
    if not Server.hasPermission(src, 'monitor.use') then return false, _L('no_permission') end
    if not hasPortableItem(src) then
        return false, 'Retire um LIFEPAK 15 no estoque de equipamentos antes de usa-lo.'
    end
    local existing = PM.byOwner[src]
    if existing and PM.active[existing] then
        return false, 'Voce ja possui um LIFEPAK 15 colocado na cena.'
    end
    return true
end

RegisterNetEvent('fiveems:server:portableMonitorUseRequest', function()
    local src = source
    local ok, reason = canBeginPortableUse(src)
    if not ok then return Server.notify(src, reason) end
    TriggerClientEvent('fiveems:client:portableMonitorBeginPlacement', src)
end)

RegisterNetEvent('fiveems:server:portableMonitorDeploy', function(payload)
    local src = source
    if not portableEnabled() then return Server.notify(src, 'Monitor portatil desativado na configuracao.') end
    if not Server.hasPermission(src, 'monitor.use') then return Server.notify(src, _L('no_permission')) end
    if not hasPortableItem(src) then
        return Server.notify(src, 'Retire um LIFEPAK 15 no estoque de equipamentos antes de usa-lo.')
    end

    local existing = PM.byOwner[src]
    if existing and PM.active[existing] then
        return Server.notify(src, 'Voce ja possui um LIFEPAK 15 colocado na cena.')
    end

    payload = type(payload) == 'table' and payload or {}
    local x, y, z = tonumber(payload.x), tonumber(payload.y), tonumber(payload.z)
    local heading = tonumber(payload.heading) or 0.0
    if not x or not y or not z then return end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local playerPos = GetEntityCoords(ped)
    if distance(playerPos, vector3(x,y,z)) > 4.5 then
        return Server.notify(src, 'Posicione o monitor mais proximo de voce.')
    end

    local model = joaat(tostring(cfg().model or 'lifepak15'))
    local entity = CreateObject(model, x, y, z, true, true, false)
    if not entity or entity == 0 then
        return Server.notify(src, 'Nao foi possivel criar o LIFEPAK 15. Verifique o model lifepak15.ydr.')
    end

    SetEntityHeading(entity, heading)
    FreezeEntityPosition(entity, true)
    pcall(function() SetEntityOrphanMode(entity, 2) end)

    local timeout = GetGameTimer() + 2500
    local netId = NetworkGetNetworkIdFromEntity(entity)
    while (not netId or netId == 0) and GetGameTimer() < timeout do
        Wait(0)
        netId = NetworkGetNetworkIdFromEntity(entity)
    end
    if not netId or netId == 0 then
        DeleteEntity(entity)
        return Server.notify(src, 'Falha ao sincronizar o LIFEPAK 15 no OneSync.')
    end

    PM.active[netId] = {
        entity = entity,
        owner = src,
        patientRef = nil,
        createdAt = os.time(),
    }
    PM.byOwner[src] = netId
    setMonitorState(PM.active[netId], nil)

    TriggerClientEvent('fiveems:client:portableMonitorDeployed', src, netId)
    Server.notify(src, 'LIFEPAK 15 colocado na cena. Use o ox_target no aparelho.')
end)

RegisterNetEvent('fiveems:server:portableMonitorAttach', function(netId, ref, snapshot, openMode)
    local src = source
    netId = tonumber(netId)
    local monitor = netId and PM.active[netId] or nil
    if not monitor then return Server.notify(src, 'Monitor portatil nao encontrado.') end
    if not Server.hasPermission(src, 'monitor.use') then return Server.notify(src, _L('no_permission')) end
    if not sourceNearEntity(src, monitor.entity, tonumber(cfg().openDistance) or 4.0) then
        return Server.notify(src, 'Aproxime-se do LIFEPAK 15.')
    end

    local patientEntity = resolvePatientEntity(ref)
    if patientEntity == 0 then return Server.notify(src, 'Paciente invalido para o monitor.') end
    local cable = tonumber(cfg().maxCableDistance) or 5.5
    if distance(GetEntityCoords(monitor.entity), GetEntityCoords(patientEntity)) > cable then
        return Server.notify(src, ('Paciente muito longe do monitor. Limite de cabo: %.1fm.'):format(cable))
    end

    monitor.patientRef = {
        kind = tostring(ref.kind),
        serverId = ref.kind == 'player' and tonumber(ref.serverId) or nil,
        netId = ref.kind == 'npc' and tonumber(ref.netId) or nil,
    }
    setMonitorState(monitor, monitor.patientRef)
    TriggerClientEvent('fiveems:client:portableMonitorAttached', -1, netId, monitor.patientRef)
    TriggerClientEvent('fiveems:client:openPortableMonitor', src, netId, monitor.patientRef, snapshot or {}, tostring(openMode or 'full'))
end)

RegisterNetEvent('fiveems:server:portableMonitorRequestOpen', function(netId, mode)
    local src = source
    netId = tonumber(netId)
    local monitor = netId and PM.active[netId] or nil
    if not monitor then return Server.notify(src, 'Monitor portatil nao encontrado.') end
    if not Server.hasPermission(src, 'monitor.use') then return Server.notify(src, _L('no_permission')) end
    if not sourceNearEntity(src, monitor.entity, tonumber(cfg().openDistance) or 4.0) then
        return Server.notify(src, 'Aproxime-se do LIFEPAK 15.')
    end
    if not monitor.patientRef then
        return Server.notify(src, 'Conecte o LIFEPAK 15 a um paciente primeiro.')
    end
    TriggerClientEvent('fiveems:client:openPortableMonitor', src, netId, monitor.patientRef, {}, tostring(mode or 'full'))
end)

RegisterNetEvent('fiveems:server:portableMonitorDetach', function(netId)
    local src = source
    netId = tonumber(netId)
    local monitor = netId and PM.active[netId] or nil
    if not monitor then return end
    if not Server.hasPermission(src, 'monitor.use') then return end
    if not sourceNearEntity(src, monitor.entity, tonumber(cfg().openDistance) or 4.0) then return end
    detachMonitor(netId, 'Cabos/eletrodos desconectados.')
end)

RegisterNetEvent('fiveems:server:portableMonitorStore', function(netId)
    local src = source
    netId = tonumber(netId)
    local monitor = netId and PM.active[netId] or nil
    if not monitor then return end
    if not Server.hasPermission(src, 'monitor.use') then return end
    if not sourceNearEntity(src, monitor.entity, tonumber(cfg().openDistance) or 4.0) then return end
    deleteMonitor(netId, 'LIFEPAK 15 guardado.')
    Server.notify(src, 'LIFEPAK 15 recolhido da cena.')
end)

RegisterNetEvent('fiveems:server:portableMonitorMoved', function(netId, coords, heading)
    local src = source
    netId = tonumber(netId)
    local monitor = netId and PM.active[netId] or nil
    if not monitor or not Server.hasPermission(src, 'monitor.use') then return end
    if type(coords) ~= 'table' then return end
    if not sourceNearEntity(src, monitor.entity, 5.5) then return end
    local x,y,z = tonumber(coords.x),tonumber(coords.y),tonumber(coords.z)
    if not x or not y or not z then return end
    SetEntityCoords(monitor.entity, x,y,z, false,false,false,false)
    SetEntityHeading(monitor.entity, tonumber(heading) or GetEntityHeading(monitor.entity))
    FreezeEntityPosition(monitor.entity, true)
end)

CreateThread(function()
    while true do
        Wait(1500)
        local cable = tonumber(cfg().maxCableDistance) or 5.5
        local detachList, deleteList = {}, {}
        for netId, monitor in pairs(PM.active) do
            if not monitor.entity or monitor.entity == 0 or not DoesEntityExist(monitor.entity) then
                deleteList[#deleteList+1] = netId
            elseif monitor.patientRef then
                local patientEntity = resolvePatientEntity(monitor.patientRef)
                if patientEntity == 0 then
                    detachList[#detachList+1] = {netId=netId, reason='Sinal do paciente perdido.'}
                else
                    local d = distance(GetEntityCoords(monitor.entity), GetEntityCoords(patientEntity))
                    if d > cable then
                        detachList[#detachList+1] = {netId=netId, reason='ELETRODOS DESCONECTADOS: paciente fora do alcance dos cabos.'}
                    end
                end
            end
        end
        for _, data in ipairs(detachList) do detachMonitor(data.netId, data.reason) end
        for _, netId in ipairs(deleteList) do deleteMonitor(netId, 'Monitor removido da cena.') end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    local netId = PM.byOwner[src]
    if netId then deleteMonitor(netId, 'Proprietario desconectou.') end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    local ids = {}
    for netId in pairs(PM.active) do ids[#ids+1] = netId end
    for _, netId in ipairs(ids) do deleteMonitor(netId, 'FiveEMS reiniciado.') end
end)

-- Existing hospitals/EMS departments also receive the new catalog item automatically.
CreateThread(function()
    Wait(1500)
    local deadline = GetGameTimer() + 30000
    while (not DB or not DB._ready) and GetGameTimer() < deadline do Wait(500) end
    if not DB or not DB._ready or not FiveEMS.Departments or not FiveEMS.Departments.seedSupplies then return end
    local rows = DB.query('SELECT id, type FROM fiveems_departments') or {}
    for _, row in ipairs(rows) do
        if row.type ~= FiveEMS.DepartmentTypes.CSI then
            FiveEMS.Departments.seedSupplies(row.id, row.type)
        end
    end
end)
