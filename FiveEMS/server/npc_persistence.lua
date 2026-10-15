FiveEMS = FiveEMS or {}

local Server = FiveEMS.Server
local F = FiveEMS.Framework
local protected = {}

local function entityFromNet(netId)
    netId = tonumber(netId)
    if not netId or netId <= 0 then return 0 end
    local entity = NetworkGetEntityFromNetworkId(netId)
    if entity == 0 or not DoesEntityExist(entity) then return 0 end
    return entity
end

local function isPlayerPed(entity)
    if entity == 0 or GetEntityType(entity) ~= 1 then return false end
    local owner = NetworkGetEntityOwner(entity)
    return owner and owner > 0 and GetPlayerPed(owner) == entity
end

local function protectEntity(entity, netId)
    if SetEntityOrphanMode then
        pcall(SetEntityOrphanMode, entity, 2)
    end

    local state = Entity(entity).state
    state:set('fiveems:patientProtected', true, true)

    -- O fivepd_sp_world ja respeita esta flag e nao remove a entidade.
    state:set('fivepd_sp:protected', true, true)

    local minutes = math.max(1, tonumber((Config.NpcPersistence or {}).persistMinutes) or 20)
    protected[netId] = {
        expiresAt = os.time() + (minutes * 60),
        lastRefresh = os.time(),
    }
end

local function refreshProtectedExpiry(netId)
    local minutes = math.max(1, tonumber((Config.NpcPersistence or {}).persistMinutes) or 20)
    protected[netId] = protected[netId] or {}
    protected[netId].expiresAt = os.time() + (minutes * 60)
    protected[netId].lastRefresh = os.time()
end

local function validateNearSource(src, entity, maxDistance)
    local playerPed = GetPlayerPed(src)
    if playerPed == 0 or not DoesEntityExist(playerPed) then return false end
    return #(GetEntityCoords(playerPed) - GetEntityCoords(entity)) <= (maxDistance or 100.0)
end

RegisterNetEvent('fiveems:server:protectNpcPatient', function(netId, metadata)
    local src = source
    netId = tonumber(netId)
    if not netId or netId <= 0 then return end

    local entity = entityFromNet(netId)
    if entity == 0 or GetEntityType(entity) ~= 1 or isPlayerPed(entity) then return end

    local playerPed = GetPlayerPed(src)
    if playerPed == 0 then return end

    local maxDistance = (tonumber((Config.NpcPersistence or {}).scanRadius) or 70.0) + 20.0
    if #(GetEntityCoords(playerPed) - GetEntityCoords(entity)) > maxDistance then return end

    protectEntity(entity, netId)

    -- Resolve a identidade canônica assim que o NPC passa a ser paciente FiveEMS.
    if F and F.getNpcIdentity then
        pcall(function()
            metadata = type(metadata) == 'table' and metadata or {}
            F.getNpcIdentity(netId, {
                persistir = true,
                source = 'fiveems_patient',
                sexo = metadata.sexo,
                idade = metadata.idade,
                idade_min = metadata.idade_min,
                idade_max = metadata.idade_max,
                age_group = metadata.age_group,
                archetype = metadata.archetype,
                model_hash = metadata.model_hash or metadata.model,
                metadata = metadata,
            })
        end)
    end
end)

RegisterNetEvent('fiveems:server:refreshNpcPatient', function(netId)
    local entity = entityFromNet(netId)
    if entity == 0 or isPlayerPed(entity) then return end
    protectEntity(entity, tonumber(netId))
end)

RegisterNetEvent('fiveems:server:claimNpcTransport', function(netId, stretcherNetId, transform)
    local src = source
    netId = tonumber(netId)
    stretcherNetId = tonumber(stretcherNetId) or 0

    local entity = entityFromNet(netId)
    if entity == 0 or GetEntityType(entity) ~= 1 or isPlayerPed(entity) then return end
    if not validateNearSource(src, entity, 100.0) then return end

    protectEntity(entity, netId)

    local state = Entity(entity).state
    state:set('fiveems:patientOnStretcher', stretcherNetId, true)
    state:set('fiveems:carePointId', 0, true)
    if type(transform) == 'table' then
        state:set('fiveems:stretcherPatientTransform', transform, true)
    end
end)

RegisterNetEvent('fiveems:server:refreshNpcTransport', function(netId, stretcherNetId)
    local src = source
    netId = tonumber(netId)
    stretcherNetId = tonumber(stretcherNetId) or 0

    local entity = entityFromNet(netId)
    if entity == 0 or GetEntityType(entity) ~= 1 or isPlayerPed(entity) then return end

    -- Durante transicao de MLO, a posicao pode oscilar por alguns frames;
    -- aceita uma margem maior, mas continua exigindo que o solicitante exista.
    if not validateNearSource(src, entity, 180.0) then return end

    protectEntity(entity, netId)
    Entity(entity).state:set('fiveems:patientOnStretcher', stretcherNetId, true)
end)

RegisterNetEvent('fiveems:server:npcPatientGrounded', function(netId)
    netId = tonumber(netId)
    local entity = entityFromNet(netId)
    if entity == 0 or isPlayerPed(entity) then return end

    protectEntity(entity, netId)
    local state = Entity(entity).state
    state:set('fiveems:patientOnStretcher', 0, true)
    state:set('fiveems:carePointId', 0, true)
end)

RegisterNetEvent('fiveems:server:npcPatientAtCarePoint', function(netId, pointId)
    local src = source
    netId = tonumber(netId)
    pointId = tonumber(pointId)
    if not netId or not pointId then return end

    local entity = entityFromNet(netId)
    if entity == 0 or isPlayerPed(entity) then return end
    if not validateNearSource(src, entity, 120.0) then return end

    protectEntity(entity, netId)
    local state = Entity(entity).state
    state:set('fiveems:patientOnStretcher', 0, true)
    state:set('fiveems:carePointId', pointId, true)
end)

RegisterNetEvent('fiveems:server:releaseNpcPatient', function(netId)
    netId = tonumber(netId)
    local entity = entityFromNet(netId)
    protected[netId] = nil
    if entity == 0 then return end

    local state = Entity(entity).state
    state:set('fiveems:patientProtected', false, true)
    state:set('fiveems:patientOnStretcher', 0, true)
    state:set('fiveems:carePointId', 0, true)

    -- Nao retira a protecao generica se outro sistema da base ainda possuir a entidade.
    local usedElsewhere =
        state['fivepd_sp:supportPersistent'] == true
        or state['fivepd_sp:supportJob'] ~= nil
        or state['fivepd_sp:qru:entity'] == true
        or state['fivepd_sp:ambient:entity'] == true
        or state['fivepd_sp:illegal:entity'] == true
        or state['fivepd_sp:partner'] == true
        or state['fivepd_sp:trafficStopOwner'] ~= nil

    if not usedElsewhere then
        state:set('fivepd_sp:protected', false, true)
        if SetEntityOrphanMode then pcall(SetEntityOrphanMode, entity, 0) end
    end
end)

CreateThread(function()
    while true do
        Wait(30000)
        local now = os.time()
        for netId, info in pairs(protected) do
            if now >= (info.expiresAt or 0) then
                local entity = entityFromNet(netId)
                protected[netId] = nil
                if entity ~= 0 then
                    local state = Entity(entity).state
                    state:set('fiveems:patientProtected', false, true)

                    local usedElsewhere =
                        state['fivepd_sp:supportPersistent'] == true
                        or state['fivepd_sp:supportJob'] ~= nil
                        or state['fivepd_sp:qru:entity'] == true
                        or state['fivepd_sp:ambient:entity'] == true
                        or state['fivepd_sp:illegal:entity'] == true
                        or state['fivepd_sp:partner'] == true
                        or state['fivepd_sp:trafficStopOwner'] ~= nil

                    if not usedElsewhere then
                        state:set('fivepd_sp:protected', false, true)
                        if SetEntityOrphanMode then pcall(SetEntityOrphanMode, entity, 0) end
                    end
                end
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    for netId, _ in pairs(protected) do
        local entity = entityFromNet(netId)
        if entity ~= 0 then
            local state = Entity(entity).state
            state:set('fiveems:patientProtected', false, true)
            if state['fivepd_sp:supportPersistent'] ~= true and state['fivepd_sp:supportJob'] == nil then
                state:set('fivepd_sp:protected', false, true)
                if SetEntityOrphanMode then pcall(SetEntityOrphanMode, entity, 0) end
            end
        end
    end
end)
