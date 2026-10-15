FiveEMS = FiveEMS or {}
FiveEMS.FrameworkClient = FiveEMS.FrameworkClient or {}

local FC = FiveEMS.FrameworkClient
local C = FiveEMS.Client
local cfg = Config.Framework or {}
local resources = cfg.resources or {}

local function res(key, fallback) return tostring(resources[key] or fallback or key) end
local function started(name) return GetResourceState(name) == 'started' end

local function archetypeName(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return '' end
    local ok, value = pcall(GetEntityArchetypeName, entity)
    if ok and value then return tostring(value):lower() end
    return ''
end

local function visualAgeBand(archetype)
    archetype = tostring(archetype or ''):lower()
    local band = archetype:match('_[mf]_([ymo])_')
    if band == 'y' then return 18, 35, 'young' end
    if band == 'm' then return 30, 59, 'middle' end
    if band == 'o' then return 60, 88, 'old' end

    if archetype:find('old', 1, true) or archetype:find('elder', 1, true) then
        return 60, 88, 'old'
    end
    if archetype:find('young', 1, true) then
        return 18, 35, 'young'
    end
    return 21, 65, 'adult'
end

local function deterministicAge(ped, minAge, maxAge)
    minAge, maxAge = tonumber(minAge) or 21, tonumber(maxAge) or 65
    if maxAge < minAge then minAge, maxAge = maxAge, minAge end

    local model = tonumber(GetEntityModel(ped)) or 0
    local netId = 0
    if NetworkGetEntityIsNetworked(ped) then
        netId = tonumber(NetworkGetNetworkIdFromEntity(ped)) or 0
    end

    local span = math.max(1, math.floor(maxAge - minAge + 1))
    local seed = math.abs(model + (netId * 131) + 7919)
    return math.floor(minAge + (seed % span))
end

function FC.getNpcAppearanceHints(ped)
    if not ped or ped == 0 or not DoesEntityExist(ped) or not IsEntityAPed(ped) or IsPedAPlayer(ped) then
        return {}
    end

    local sexo = nil
    local okMale, isMale = pcall(IsPedMale, ped)
    if okMale then sexo = isMale and 'masculino' or 'feminino' end

    local archetype = archetypeName(ped)
    local minAge, maxAge, ageGroup = visualAgeBand(archetype)
    local idade = deterministicAge(ped, minAge, maxAge)

    return {
        sexo = sexo,
        idade = idade,
        idade_min = minAge,
        idade_max = maxAge,
        age_group = ageGroup,
        archetype = archetype,
        model_hash = GetEntityModel(ped),
    }
end

function FC.notify(message, kind)
    if started(res('ui','fivepd_sp_ui')) then
        local ok = pcall(function()
            exports[res('ui','fivepd_sp_ui')]:Notificar({
                tipo = kind or 'info',
                titulo = 'FiveEMS',
                descricao = tostring(message or '')
            })
        end)
        if ok then return true end
    end
    return false
end

local regionMap = {
    head='cabeca', neck='cabeca', chest='torax', abdomen='torax', pelvis='perna',
    left_arm='braco', right_arm='braco', left_leg='perna', right_leg='perna'
}

RegisterNetEvent('fiveems:client:frameworkApplyTreatment', function(region, amount)
    if not started(res('injuries','fivepd_sp_injuries')) then return end
    local mapped = regionMap[tostring(region or '')] or 'todos'
    pcall(function() exports[res('injuries','fivepd_sp_injuries')]:AplicarTratamento(mapped, tonumber(amount) or 10) end)
end)

RegisterNetEvent('fiveems:client:frameworkExternalRevive', function()
    if not started(res('death','fivepd_sp_death')) then return end
    -- O evento server e disparado pelo proprio paciente, preservando o source
    -- esperado pelo fivepd_sp_death. Em seguida normalizamos o ped localmente.
    TriggerServerEvent('fivepd_sp:morte:revividoExterno')
    TriggerEvent('fivepd_sp:morte:reviver', 200)
    TriggerEvent('fivepd_sp:morte:revivido')
end)

AddEventHandler('fivepd_sp:injuries:alterado', function(injuries, bleeding)
    TriggerServerEvent('fiveems:server:frameworkInjuriesSnapshot', injuries or {}, bleeding == true)
end)

AddEventHandler('fivepd_sp:personagem:carregado', function()
    TriggerServerEvent('fiveems:server:frameworkCharacterLoaded')
end)

AddEventHandler('fivepd_sp:personagem:descarregado', function()
    if C and C.uiOpen then C.closeUi() end
    TriggerServerEvent('fiveems:server:frameworkCharacterUnloaded')
end)


RegisterNetEvent('fiveems:client:debugNpcIdentity', function()
    local playerPed = PlayerPedId()
    local pos = GetEntityCoords(playerPed)
    local best, bestDist
    for _, ped in ipairs(GetGamePool('CPed')) do
        if ped ~= playerPed and DoesEntityExist(ped) and not IsPedAPlayer(ped) then
            local dist = #(GetEntityCoords(ped) - pos)
            if dist <= 5.0 and (not bestDist or dist < bestDist) then best, bestDist = ped, dist end
        end
    end
    if not best then return C.notify('Nenhum NPC proximo em ate 5 metros.') end
    if not NetworkGetEntityIsNetworked(best) then
        NetworkRegisterEntityAsNetworked(best)
        Wait(50)
    end
    local netId = NetworkGetNetworkIdFromEntity(best)
    if not netId or netId == 0 then return C.notify('NPC sem Network ID valido.') end
    local hints = FC.getNpcAppearanceHints and FC.getNpcAppearanceHints(best) or {}
    TriggerServerEvent('fiveems:server:testNpcIdentity', netId, hints)
end)


AddEventHandler('fivepd_sp:medical:tratamentoCompleto', function()
    TriggerServerEvent('fiveems:server:frameworkTreatmentComplete')
end)

AddEventHandler('fivepd_sp:injuries:curado', function(reason)
    TriggerServerEvent('fiveems:server:frameworkInjuriesSnapshot', {}, false)
end)

CreateThread(function()
    local lastDeathState = nil
    while true do
        local state = LocalPlayer and LocalPlayer.state and LocalPlayer.state['fivepd_sp:deathState'] or nil
        if state ~= lastDeathState then
            lastDeathState = state
            TriggerServerEvent('fiveems:server:frameworkDeathStateChanged', state or 'alive')
        end
        Wait(750)
    end
end)
