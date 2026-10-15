FiveEMS = FiveEMS or {}
local C = FiveEMS.Client

local protected = {}
local lastProtectRequest = {}

local function requestControl(entity, timeoutMs)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return false end
    if not NetworkGetEntityIsNetworked(entity) then
        NetworkRegisterEntityAsNetworked(entity)
    end
    if not NetworkGetEntityIsNetworked(entity) then return false end
    if NetworkHasControlOfEntity(entity) then return true end

    local untilAt = GetGameTimer() + (timeoutMs or 700)
    NetworkRequestControlOfEntity(entity)
    while not NetworkHasControlOfEntity(entity) and GetGameTimer() < untilAt do
        Wait(0)
        NetworkRequestControlOfEntity(entity)
    end
    return NetworkHasControlOfEntity(entity)
end

local function promoteLocal(ped)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return end
    if not IsEntityAMissionEntity(ped) then
        -- Igual ao padrao usado pelo fivepd_sp_support:
        -- promove localmente para impedir cleanup da populacao.
        SetEntityAsMissionEntity(ped, true, false)
    end
    SetPedKeepTask(ped, true)
end

local function releaseLocal(ped)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return end
    SetPedKeepTask(ped, false)
    if IsEntityAMissionEntity(ped) then
        SetEntityAsNoLongerNeeded(ped)
    end
end

local function isNpcCasualty(ped)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return false end
    if IsPedAPlayer(ped) or not IsPedHuman(ped) then return false end
    if Entity(ped).state['fivepd_sp:qru:entity'] == true then return false end

    if IsEntityDead(ped) or IsPedFatallyInjured(ped) then return true end

    local health = GetEntityHealth(ped)
    local maxHealth = math.max(1, GetEntityMaxHealth(ped))
    local cfg = Config.NpcPersistence or {}
    local ratio = tonumber(cfg.injuredHealthRatio) or 0.92

    if health < math.floor(maxHealth * ratio) then return true end
    if IsPedInjured(ped) and (IsPedRagdoll(ped) or health < maxHealth) then return true end

    return false
end

local function protectNpc(ped)
    promoteLocal(ped)

    if not NetworkGetEntityIsNetworked(ped) then
        requestControl(ped, 700)
        NetworkRegisterEntityAsNetworked(ped)
    end

    if not NetworkGetEntityIsNetworked(ped) then return end

    local netId = PedToNet(ped)
    if not netId or netId <= 0 then return end

    protected[netId] = ped

    local now = GetGameTimer()
    -- Refresca no maximo a cada 10s; o servidor renova o TTL.
    if now - (lastProtectRequest[netId] or 0) < 10000 then return end
    lastProtectRequest[netId] = now

    local hints = FiveEMS.FrameworkClient and FiveEMS.FrameworkClient.getNpcAppearanceHints
        and FiveEMS.FrameworkClient.getNpcAppearanceHints(ped) or {}

    TriggerServerEvent('fiveems:server:protectNpcPatient', netId, {
        model = GetEntityModel(ped),
        model_hash = hints.model_hash or GetEntityModel(ped),
        health = GetEntityHealth(ped),
        dead = IsEntityDead(ped),
        sexo = hints.sexo,
        idade = hints.idade,
        idade_min = hints.idade_min,
        idade_max = hints.idade_max,
        age_group = hints.age_group,
        archetype = hints.archetype,
    })
end

if AddStateBagChangeHandler and GetEntityFromStateBagName then
    AddStateBagChangeHandler('fiveems:patientProtected', nil, function(bagName, _, value)
        local entity = GetEntityFromStateBagName(bagName)
        if entity == 0 or not DoesEntityExist(entity) or not IsEntityAPed(entity) then return end
        if value == true then
            promoteLocal(entity)
            local netId = NetworkGetEntityIsNetworked(entity) and PedToNet(entity) or 0
            if netId > 0 then protected[netId] = entity end
        else
            local netId = NetworkGetEntityIsNetworked(entity) and PedToNet(entity) or 0
            if netId > 0 then
                protected[netId] = nil
                lastProtectRequest[netId] = nil
            end
            releaseLocal(entity)
        end
    end)
end

CreateThread(function()
    while true do
        local cfg = Config.NpcPersistence or {}
        if cfg.enabled == false then
            Wait(3000)
        else
            local playerPed = PlayerPedId()
            local origin = GetEntityCoords(playerPed)
            local radius = tonumber(cfg.scanRadius) or 70.0
            local maxCount = math.max(1, tonumber(cfg.maxProtectedPerClient) or 24)
            local found = 0

            for _, ped in ipairs(GetGamePool('CPed')) do
                if found >= maxCount then break end
                if ped ~= playerPed and DoesEntityExist(ped) and isNpcCasualty(ped) then
                    local coords = GetEntityCoords(ped)
                    if #(coords - origin) <= radius then
                        found = found + 1
                        protectNpc(ped)
                    end
                end
            end

            -- Se uma entidade protegida voltar a streamar, reforca mission entity.
            for netId, ped in pairs(protected) do
                if not ped or not DoesEntityExist(ped) then
                    local streamed = NetworkGetEntityFromNetworkId(netId)
                    if streamed ~= 0 and DoesEntityExist(streamed) then
                        protected[netId] = streamed
                        promoteLocal(streamed)
                    end
                else
                    promoteLocal(ped)
                end
            end

            Wait(math.max(500, tonumber(cfg.scanIntervalMs) or 1500))
        end
    end
end)

RegisterNetEvent('fiveems:client:applyNpcPersistenceConfig', function(value)
    if type(value) ~= 'table' then return end
    Config.NpcPersistence = Config.NpcPersistence or {}
    for k, v in pairs(value) do Config.NpcPersistence[k] = v end
end)
