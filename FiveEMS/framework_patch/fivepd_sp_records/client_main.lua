local pendentes = {}
local sequencia = 0

local function proximoId()
    sequencia = sequencia + 1
    if sequencia > 999999 then
        sequencia = 1
    end

    return ('%s:%s'):format(GetGameTimer(), sequencia)
end

local function resolverPendente(id, dados)
    local p = pendentes[id]
    if not p then return end

    pendentes[id] = nil
    p:resolve(dados)
end

RegisterNetEvent('fivepd_sp:records:npcResposta', function(id, dados)
    resolverPendente(id, dados)
end)

RegisterNetEvent('fivepd_sp:records:veiculoResposta', function(id, dados)
    resolverPendente(id, dados)
end)

RegisterNetEvent('fivepd_sp:records:bicicletaResposta', function(id, dados)
    resolverPendente(id, dados)
end)

local function garantirRede(entidade)
    if NetworkGetEntityIsNetworked(entidade) then
        local netId = NetworkGetNetworkIdFromEntity(entidade)
        return netId and netId > 0 and netId or nil
    end

    NetworkRegisterEntityAsNetworked(entidade)
    local limite = GetGameTimer() + 900
    while GetGameTimer() < limite and not NetworkGetEntityIsNetworked(entidade) do
        Wait(0)
    end

    if not NetworkGetEntityIsNetworked(entidade) then return nil end
    local netId = NetworkGetNetworkIdFromEntity(entidade)
    return netId and netId > 0 and netId or nil
end

local function aguardarResposta(evento, entidade, dados)
    local netId = garantirRede(entidade)
    if not netId then return nil end

    local id = proximoId()
    local p = promise.new()
    pendentes[id] = p

    TriggerServerEvent(evento, id, netId, dados or {})

    SetTimeout(6000, function()
        if pendentes[id] then
            pendentes[id] = nil
            p:resolve(nil)
        end
    end)

    return Citizen.Await(p)
end

local function faixaEtariaVisualNpc(entidade)
    local arquetipo = ''
    local okArq, value = pcall(GetEntityArchetypeName, entidade)
    if okArq and value then arquetipo = tostring(value):lower() end

    -- GTA freemode/ambient naming commonly carries y/m/o (young/middle/old).
    local faixa = arquetipo:match('_[mf]_([ymo])_')
    if faixa == 'y' then return 18, 35, 'young', arquetipo end
    if faixa == 'm' then return 30, 59, 'middle', arquetipo end
    if faixa == 'o' then return 60, 88, 'old', arquetipo end

    if arquetipo:find('old', 1, true) or arquetipo:find('elder', 1, true) then
        return 60, 88, 'old', arquetipo
    end
    if arquetipo:find('young', 1, true) then
        return 18, 35, 'young', arquetipo
    end
    return 21, 65, 'adult', arquetipo
end

local function idadeVisualDeterministicaNpc(entidade, minAge, maxAge)
    minAge, maxAge = tonumber(minAge) or 21, tonumber(maxAge) or 65
    if maxAge < minAge then minAge, maxAge = maxAge, minAge end

    local model = tonumber(GetEntityModel(entidade)) or 0
    local netId = 0
    if NetworkGetEntityIsNetworked(entidade) then
        netId = tonumber(NetworkGetNetworkIdFromEntity(entidade)) or 0
    end

    local span = math.max(1, math.floor(maxAge - minAge + 1))
    local seed = math.abs(model + (netId * 131) + 7919)
    return math.floor(minAge + (seed % span))
end

local function obterOuCriarNpc(entidade, dados)
    if not entidade or entidade == 0 or not DoesEntityExist(entidade) then
        return nil, 'Entidade inválida.'
    end

    if not IsEntityAPed(entidade) or IsPedAPlayer(entidade) then
        return nil, 'A entidade não é um NPC.'
    end

    dados = type(dados) == 'table' and dados or {}
    dados.modelo = dados.modelo or GetEntityModel(entidade)

    -- A identidade civil do NPC deve respeitar o sexo visual do próprio ped.
    -- Isso também permite ao servidor corrigir registros antigos que tenham
    -- sido criados antes desta validação.
    if dados.sexo == nil or tostring(dados.sexo) == '' then
        local okMale, isMale = pcall(IsPedMale, entidade)
        if okMale then
            dados.sexo = isMale and 'masculino' or 'feminino'
        end
    end

    -- A idade civil também deve ser plausível para a apresentação visual.
    -- Se o chamador já definiu idade explicitamente, ela é preservada.
    if tonumber(dados.idade) == nil then
        local minAge, maxAge, ageGroup, archetype = faixaEtariaVisualNpc(entidade)
        dados.idade_min = tonumber(dados.idade_min) or minAge
        dados.idade_max = tonumber(dados.idade_max) or maxAge
        dados.age_group = dados.age_group or ageGroup
        dados.archetype = dados.archetype or archetype
        dados.idade = idadeVisualDeterministicaNpc(entidade, dados.idade_min, dados.idade_max)
    end

    local resposta = aguardarResposta(
        'fivepd_sp:records:solicitarNpc',
        entidade,
        dados
    )
    return resposta
end

local function obterOuCriarVeiculo(entidade, dados)
    if not entidade or entidade == 0 or not DoesEntityExist(entidade) or not IsEntityAVehicle(entidade) then
        return nil, 'Veículo inválido.'
    end

    dados = type(dados) == 'table' and dados or {}
    local placa = (GetVehicleNumberPlateText(entidade) or ''):gsub('^%s+', ''):gsub('%s+$', '')
    dados.plate = dados.plate or placa
    local modelHash = GetEntityModel(entidade)
    dados.model = dados.model or tostring(modelHash)
    dados.vehicle_class = dados.vehicle_class or GetVehicleClass(entidade)

    local make = GetMakeNameFromVehicleModel(modelHash)
    if make and make ~= '' and make ~= 'NULL' then
        local makeLabel = GetLabelText(make)
        if not makeLabel or makeLabel == '' or makeLabel == 'NULL' then makeLabel = make end
        dados.make_name = dados.make_name or makeLabel
    end

    local display = GetDisplayNameFromVehicleModel(modelHash)
    local label = GetLabelText(display)
    if not label or label == '' or label == 'NULL' then label = display end
    dados.display_name = dados.display_name or label or display

    local primary, secondary = GetVehicleColours(entidade)
    dados.color_primary = dados.color_primary or primary
    dados.color_secondary = dados.color_secondary or secondary

    local resposta = aguardarResposta(
        'fivepd_sp:records:solicitarVeiculo',
        entidade,
        dados
    )
    return resposta
end


local function obterOuCriarBicicleta(entidade, dados)
    if not entidade or entidade == 0 or not DoesEntityExist(entidade) or not IsEntityAVehicle(entidade) then
        return nil, 'Bicicleta inválida.'
    end
    if GetVehicleClass(entidade) ~= 13 then return nil, 'O veículo não é uma bicicleta.' end

    dados = type(dados) == 'table' and dados or {}
    local modelHash = GetEntityModel(entidade)
    dados.model = dados.model or tostring(modelHash)
    local display = GetDisplayNameFromVehicleModel(modelHash)
    local label = GetLabelText(display)
    if not label or label == '' or label == 'NULL' then label = display end
    dados.display_name = dados.display_name or label or display
    local primary, secondary = GetVehicleColours(entidade)
    dados.color_primary = dados.color_primary or primary
    dados.color_secondary = dados.color_secondary or secondary

    return aguardarResposta('fivepd_sp:records:solicitarBicicleta', entidade, dados)
end

-- Bicicletas não possuem placa útil. Ao entrar na área de streaming de uma,
-- garantimos silenciosamente o número de registro que será consultável no
-- Terminal Embarcado e visível na inspeção por ALT.
local bicicletaPendente = {}
CreateThread(function()
    while true do
        Wait(2600)
        local me = PlayerPedId()
        if me ~= 0 and DoesEntityExist(me) then
            local origin = GetEntityCoords(me)
            local now = GetGameTimer()
            for _, vehicle in ipairs(GetGamePool('CVehicle')) do
                if vehicle ~= 0 and DoesEntityExist(vehicle) and GetVehicleClass(vehicle) == 13 then
                    local coords = GetEntityCoords(vehicle)
                    if #(coords - origin) <= 48.0 then
                        local state = Entity(vehicle).state
                        local reg = state and state['fivepd_sp:records:bicycleRegistration'] or nil
                        local nextTry = tonumber(bicicletaPendente[vehicle]) or 0
                        if (not reg or tostring(reg) == '') and now >= nextTry then
                            bicicletaPendente[vehicle] = now + 15000
                            CreateThread(function()
                                obterOuCriarBicicleta(vehicle, {})
                            end)
                        end
                    end
                end
            end
        end
    end
end)

exports('ObterOuCriarNPC', obterOuCriarNpc)
exports('ObterOuCriarVeiculo', obterOuCriarVeiculo)
exports('ObterOuCriarBicicleta', obterOuCriarBicicleta)
