local cinto = false
local ultimoVeiculo = 0
local velocidadeAnterior = 0.0
local velocidadeAnterior2 = 0.0

local alarmeCintoAtivo = false
local alarmePodeIniciarEm = 0

local motorLocal = {}
local travaLocal = {}
local indicadorLocal = {}
local vidrosAbertos = {}
local danoAnterior = {}
local maximaOriginais = {}
local avisouMotor = {}
local quebradoPorDano = {}

local empurrando = 0

local extrasAberto = false
local extrasVeiculo = 0
local extrasLocal = {}
local f10PodeLivery = false

local handlingAberto = false
local handlingVeiculo = 0
local handlingModelo = nil
local handlingPerfis = {}
local handlingPerfisHash = {}
local handlingOriginais = {}
local handlingPreview = nil


local function normalizarBooleanoExtra(valor)
    if valor == true
        or valor == 1
    then
        return true
    end

    if valor == false
        or valor == nil
        or valor == 0
    then
        return false
    end

    if type(valor) == 'string' then
        local texto =
            valor:lower()

        return texto == '1'
            or texto == 'true'
            or texto == 'sim'
            or texto == 'yes'
            or texto == 'on'
    end

    return false
end

local function chaveCacheExtra(
    veiculo,
    extra
)
    local netId = 0

    if veiculo ~= 0
        and DoesEntityExist(
            veiculo
        )
        and NetworkGetEntityIsNetworked(
            veiculo
        )
    then
        netId =
            NetworkGetNetworkIdFromEntity(
                veiculo
            )
            or 0
    end

    if netId > 0 then
        return ('net:%s:%s'):format(
            netId,
            extra
        )
    end

    return ('ent:%s:%s'):format(
        veiculo,
        extra
    )
end


local function limitar(valor, minimo, maximo)
    return math.max(
        minimo,
        math.min(
            maximo,
            tonumber(valor) or minimo
        )
    )
end

local function notificar(tipo, titulo, descricao, duracao)
    exports.fivepd_sp_ui:Notificar({
        tipo = tipo,
        titulo = titulo,
        descricao = descricao,
        duracao = duracao
    })
end

local function ehMotoOuBicicleta(veiculo)
    if veiculo == 0
        or not DoesEntityExist(veiculo)
    then
        return false
    end

    local classe = GetVehicleClass(veiculo)

    -- 8 = motocicletas, 13 = bicicletas. Alguns veículos add-on vêm com a
    -- classe configurada incorretamente, então não dependemos apenas dela.
    if classe == 8 or classe == 13 then
        return true
    end

    local modelo = GetEntityModel(veiculo)

    if type(IsThisModelABike) == 'function' then
        local ok, resultado = pcall(IsThisModelABike, modelo)
        if ok and resultado == true then
            return true
        end
    end

    if type(IsThisModelABicycle) == 'function' then
        local ok, resultado = pcall(IsThisModelABicycle, modelo)
        if ok and resultado == true then
            return true
        end
    end

    -- Fallback importante para motos add-on com vehicleClass errado.
    if type(GetVehicleNumberOfWheels) == 'function' then
        local ok, rodas = pcall(GetVehicleNumberOfWheels, veiculo)
        if ok and tonumber(rodas) and tonumber(rodas) <= 2 then
            return true
        end
    end

    return false
end

local function aceitaCinto(veiculo)
    return veiculo ~= 0
        and DoesEntityExist(veiculo)
        and not ehMotoOuBicicleta(veiculo)
        and FSPVehicle.ClassesComCinto[
            GetVehicleClass(veiculo)
        ] == true
end

local function audioDisponivel()
    return GetResourceState('fivepd_sp_audio') == 'started'
end

local function tocar(tipo)
    if not audioDisponivel() then
        return false
    end

    return exports.fivepd_sp_audio:Tocar(tipo)
end

local function parar(tipo)
    if not audioDisponivel() then
        return false
    end

    return exports.fivepd_sp_audio:Parar(tipo)
end

local function definirStateBag(veiculo, chave, valor)
    if veiculo == 0
        or not DoesEntityExist(veiculo)
        or not NetworkGetEntityIsNetworked(veiculo)
    then
        return
    end

    pcall(function()
        Entity(veiculo).state:set(
            chave,
            valor,
            true
        )
    end)
end

local function pararAlarmeCinto()
    if alarmeCintoAtivo then
        alarmeCintoAtivo = false
    end

    parar('cinto_alerta')
end

local function agendarAlarmeCinto()
    alarmePodeIniciarEm =
        GetGameTimer()
        + (
            FSPVehicle.AlarmeCinto
            and FSPVehicle.AlarmeCinto.AtrasoInicialMs
            or 900
        )
end

local function iniciarAlarmeCinto()
    if alarmeCintoAtivo
        or GetGameTimer() < alarmePodeIniciarEm
    then
        return
    end

    alarmeCintoAtivo = true
    tocar('cinto_alerta')
end

local function definirCinto(estado, silencioso)
    estado = estado == true

    if cinto == estado then
        if estado then
            pararAlarmeCinto()
        end

        return
    end

    cinto = estado

    if cinto then
        pararAlarmeCinto()

        if not silencioso then
            tocar('cinto_colocar')
        end
    else
        if not silencioso then
            tocar('cinto_retirar')
        end

        agendarAlarmeCinto()
    end

    TriggerEvent(
        'fivepd_sp:veiculo:cintoAlterado',
        cinto
    )
end

local function deveTocarAlarme(ped, veiculo)
    local config =
        FSPVehicle.AlarmeCinto
        or {}

    if config.Ativo == false
        or cinto
        or IsEntityDead(ped)
        or not aceitaCinto(veiculo)
    then
        return false
    end

    if config.SomenteComMotorLigado ~= false
        and not GetIsVehicleEngineRunning(veiculo)
    then
        return false
    end

    return true
end

local function jogadorDirige(veiculo)
    local ped = PlayerPedId()

    return veiculo ~= 0
        and DoesEntityExist(veiculo)
        and GetPedInVehicleSeat(
            veiculo,
            -1
        ) == ped
end

local function combustivelDisponivel(veiculo)
    if GetResourceState('fivepd_sp_fuel') ~= 'started' then
        return true
    end

    return exports.fivepd_sp_fuel:ObterCombustivel(
        veiculo
    ) > 0.15
end

local function estadoMotor(veiculo)
    if veiculo == 0
        or not DoesEntityExist(veiculo)
    then
        return false
    end

    local bag =
        Entity(veiculo).state['fivepd_sp:engine']

    if type(bag) == 'boolean' then
        motorLocal[veiculo] = bag
        return bag
    end

    if motorLocal[veiculo] ~= nil then
        return motorLocal[veiculo]
    end

    motorLocal[veiculo] = false
    return false
end

local function definirMotor(veiculo, ligado, avisar)
    if veiculo == 0
        or not DoesEntityExist(veiculo)
    then
        return false
    end

    ligado = ligado == true

    if ligado then
        if GetVehicleEngineHealth(veiculo)
            <= FSPVehicle.SaudeMotorQuebrado
        then
            if avisar then
                notificar(
                    'aviso',
                    'Veículo',
                    'O motor está danificado demais para funcionar.'
                )
            end

            return false
        end

        if not combustivelDisponivel(veiculo) then
            if avisar then
                notificar(
                    'aviso',
                    'Veículo',
                    'Não há combustível suficiente para ligar o motor.'
                )
            end

            return false
        end
    end

    motorLocal[veiculo] = ligado

    definirStateBag(
        veiculo,
        'fivepd_sp:engine',
        ligado
    )

    SetVehicleEngineOn(
        veiculo,
        ligado,
        true,
        true
    )

    if avisar then
        notificar(
            'info',
            'Motor',
            ligado
                and 'Motor ligado.'
                or 'Motor desligado.',
            1800
        )
    end

    return true
end

local function alternarMotor()
    if not exports.fivepd_sp_core:PersonagemCarregado() then
        return
    end

    local ped = PlayerPedId()
    local veiculo =
        GetVehiclePedIsIn(
            ped,
            false
        )

    if not jogadorDirige(veiculo) then
        return
    end

    definirMotor(
        veiculo,
        not estadoMotor(veiculo),
        true
    )
end

local function aplicarTrava(veiculo, travado)
    if veiculo == 0
        or not DoesEntityExist(veiculo)
    then
        return
    end

    travaLocal[veiculo] = travado == true

    SetVehicleDoorsLocked(
        veiculo,
        travado and 2 or 1
    )

    SetVehicleDoorsLockedForAllPlayers(
        veiculo,
        travado == true
    )
end

local function animacaoControleVeiculo()
    local ped =
        PlayerPedId()

    if IsPedInAnyVehicle(
        ped,
        false
    ) then
        return
    end

    local dict =
        'anim@mp_player_intmenu@key_fob@'

    RequestAnimDict(
        dict
    )

    local limite =
        GetGameTimer()
        + 1800

    while not HasAnimDictLoaded(
        dict
    )
        and GetGameTimer()
            < limite
    do
        Wait(20)
    end

    if HasAnimDictLoaded(
        dict
    ) then
        TaskPlayAnim(
            ped,
            dict,
            'fob_click',
            4.0,
            -4.0,
            900,
            48,
            0.0,
            false,
            false,
            false
        )
    end
end

local function piscarFarolTrava(
    veiculo,
    vezes
)
    if veiculo == 0
        or not DoesEntityExist(
            veiculo
        )
    then
        return
    end

    CreateThread(function()
        for _ = 1, vezes do
            SetVehicleLights(
                veiculo,
                2
            )

            Wait(115)

            SetVehicleLights(
                veiculo,
                0
            )

            Wait(115)
        end
    end)
end

local function somTravaVeiculo(
    veiculo,
    travando
)
    if veiculo == 0
        or not DoesEntityExist(
            veiculo
        )
    then
        return
    end

    -- Usa o próprio buzzer do veículo para um retorno espacial,
    -- perceptível também por quem estiver próximo.
    StartVehicleHorn(
        veiculo,
        travando and 55 or 42,
        joaat('NORMAL'),
        false
    )
end

local function alternarTravaVeiculo(veiculo)
    if veiculo == 0
        or not DoesEntityExist(veiculo)
    then
        return
    end

    local estado =
        Entity(veiculo).state['fivepd_sp:locked']

    if type(estado) ~= 'boolean' then
        estado =
            travaLocal[veiculo]
            or false
    end

    local novo =
        not estado

    animacaoControleVeiculo()

    aplicarTrava(
        veiculo,
        novo
    )

    definirStateBag(
        veiculo,
        'fivepd_sp:locked',
        novo
    )

    somTravaVeiculo(
        veiculo,
        novo
    )

    piscarFarolTrava(
        veiculo,
        novo and 1 or 2
    )

    notificar(
        'info',
        'Veículo',
        novo
            and 'Veículo travado.'
            or 'Veículo destravado.',
        1800
    )
end

local function veiculoAtualOuProximo()
    local ped =
        PlayerPedId()

    local atual =
        GetVehiclePedIsIn(
            ped,
            false
        )

    if atual ~= 0 then
        return atual
    end

    local coords =
        GetEntityCoords(
            ped
        )

    local melhor = 0
    local menor = 5.0

    for _, veiculo in ipairs(
        GetGamePool('CVehicle')
    ) do
        local distancia =
            #(
                coords
                - GetEntityCoords(
                    veiculo
                )
            )

        if distancia < menor then
            menor = distancia
            melhor = veiculo
        end
    end

    return melhor
end

local function aplicarIndicadores(veiculo, estado)
    if veiculo == 0
        or not DoesEntityExist(veiculo)
    then
        return
    end

    estado =
        tonumber(estado)
        or 0

    indicadorLocal[veiculo] =
        estado

    local esquerda =
        estado == 1
        or estado == 3

    local direita =
        estado == 2
        or estado == 3

    SetVehicleIndicatorLights(
        veiculo,
        1,
        esquerda
    )

    SetVehicleIndicatorLights(
        veiculo,
        0,
        direita
    )
end

local function definirIndicador(veiculo, estado)
    aplicarIndicadores(
        veiculo,
        estado
    )

    definirStateBag(
        veiculo,
        'fivepd_sp:indicator',
        estado
    )
end

local function alternarIndicador(tipo)
    local ped =
        PlayerPedId()

    local veiculo =
        GetVehiclePedIsIn(
            ped,
            false
        )

    if not jogadorDirige(veiculo) then
        return
    end

    local atual =
        Entity(veiculo).state['fivepd_sp:indicator']

    if type(atual) ~= 'number' then
        atual =
            indicadorLocal[veiculo]
            or 0
    end

    local alvo =
        tipo == 'esquerda'
        and 1
        or tipo == 'direita'
        and 2
        or 3

    definirIndicador(
        veiculo,
        atual == alvo
            and 0
            or alvo
    )
end

local function alternarPorta(veiculo, porta)
    if veiculo == 0
        or not DoesEntityExist(veiculo)
    then
        return
    end

    if GetVehicleDoorAngleRatio(
        veiculo,
        porta
    ) > 0.12
    then
        SetVehicleDoorShut(
            veiculo,
            porta,
            false
        )
    else
        SetVehicleDoorOpen(
            veiculo,
            porta,
            false,
            false
        )
    end
end

local function portaMaisProxima(veiculo)
    local ped =
        PlayerPedId()

    local coords =
        GetEntityCoords(
            ped
        )

    local ossos = {
        { nome = 'door_dside_f', porta = 0 },
        { nome = 'door_pside_f', porta = 1 },
        { nome = 'door_dside_r', porta = 2 },
        { nome = 'door_pside_r', porta = 3 }
    }

    local melhor =
        0

    local menor =
        99.0

    for _, item in ipairs(ossos) do
        local osso =
            GetEntityBoneIndexByName(
                veiculo,
                item.nome
            )

        if osso ~= -1 then
            local pos =
                GetWorldPositionOfEntityBone(
                    veiculo,
                    osso
                )

            local distancia =
                #(coords - pos)

            if distancia < menor then
                menor = distancia
                melhor = item.porta
            end
        end
    end

    return melhor
end

local function aplicarVidros(veiculo, abertos)
    if veiculo == 0
        or not DoesEntityExist(veiculo)
    then
        return
    end

    vidrosAbertos[veiculo] =
        abertos == true

    for janela = 0, 1 do
        if abertos then
            RollDownWindow(
                veiculo,
                janela
            )
        else
            RollUpWindow(
                veiculo,
                janela
            )
        end

        local chave =
            ('%s:%s'):format(
                veiculo,
                janela
            )

        vidrosAbertos[chave] =
            abertos == true

        definirStateBag(
            veiculo,
            ('fivepd_sp:windowOpen:%s'):format(janela),
            abertos == true
        )
    end
end


local function alternarVidro(
    veiculo,
    janela
)
    if veiculo == 0
        or not DoesEntityExist(
            veiculo
        )
        or janela == nil
    then
        return
    end

    local chave =
        ('%s:%s'):format(
            veiculo,
            janela
        )

    local state = Entity(veiculo).state
    local stateAberto = state
        and state[('fivepd_sp:windowOpen:%s'):format(janela)]
        or nil

    local aberto =
        type(stateAberto) == 'boolean'
        and stateAberto
        or vidrosAbertos[chave] == true

    if aberto then
        RollUpWindow(
            veiculo,
            janela
        )
    else
        RollDownWindow(
            veiculo,
            janela
        )
    end

    local novo =
        not aberto

    vidrosAbertos[chave] =
        novo

    definirStateBag(
        veiculo,
        ('fivepd_sp:windowOpen:%s'):format(janela),
        novo
    )
end

local function alternarVidros(veiculo)
    local estado =
        Entity(veiculo).state['fivepd_sp:frontWindows']

    if type(estado) ~= 'boolean' then
        estado =
            vidrosAbertos[veiculo]
            or false
    end

    local novo =
        not estado

    aplicarVidros(
        veiculo,
        novo
    )

    definirStateBag(
        veiculo,
        'fivepd_sp:frontWindows',
        novo
    )
end

local function assentoPassageiroLivre(veiculo)
    if veiculo == 0
        or not DoesEntityExist(veiculo)
    then
        return nil
    end

    local maximo =
        GetVehicleMaxNumberOfPassengers(
            veiculo
        )

    for banco = 0, maximo - 1 do
        if IsVehicleSeatFree(
            veiculo,
            banco
        ) then
            return banco
        end
    end

    return nil
end

local function podeInteragirExterno(veiculo)
    if veiculo == 0
        or not DoesEntityExist(veiculo)
    then
        return false
    end

    if GetEntityModel(veiculo) == joaat('strykerpro') then
        return false
    end
    local ok, entityState = pcall(function() return Entity(veiculo).state end)
    if ok and entityState and entityState['fiveems:stretcher'] == true then
        return false
    end

    return GetVehiclePedIsIn(
        PlayerPedId(),
        false
    ) == 0
end


local JANELAS_VEICULO = {
    [0] = { id = 'dianteiro_esquerdo', bones = { 'window_lf', 'door_dside_f' }, porta = 0 },
    [1] = { id = 'dianteiro_direito', bones = { 'window_rf', 'door_pside_f' }, porta = 1 },
    [2] = { id = 'traseiro_esquerdo', bones = { 'window_lr', 'door_dside_r' }, porta = 2 },
    [3] = { id = 'traseiro_direito', bones = { 'window_rr', 'door_pside_r' }, porta = 3 }
}

local function chaveVidroAberto(veiculo, janela)
    return ('%s:%s'):format(veiculo, janela)
end

local function vidroAberto(veiculo, janela)
    janela = tonumber(janela)

    if veiculo == 0 or not DoesEntityExist(veiculo)
        or janela == nil or janela < 0 or janela > 3
    then
        return false
    end

    local state = Entity(veiculo).state
    local bag = state and state[('fivepd_sp:windowOpen:%s'):format(janela)] or nil

    if type(bag) == 'boolean' then
        return bag
    end

    if janela <= 1 then
        local front = state and state['fivepd_sp:frontWindows'] or nil
        if type(front) == 'boolean' then
            return front
        end
    end

    return vidrosAbertos[chaveVidroAberto(veiculo, janela)] == true
end

local function vidroIntegro(veiculo, janela)
    -- Alguns veículos add-on retornam false em IsVehicleWindowIntact mesmo com
    -- o vidro presente. O valor continua sendo enviado apenas como informação
    -- visual; nunca mais bloqueia o botão individual do F10.
    local ok, intacto = pcall(IsVehicleWindowIntact, veiculo, janela)
    if not ok then
        return true
    end
    return intacto == true
end

local function vidroFechado(veiculo, janela)
    return not vidroAberto(veiculo, janela) and vidroIntegro(veiculo, janela)
end

local REGIOES_VEICULO = {
    porta_dianteira_esquerda = {
        osso = 'door_dside_f',
        porta = 0,
        janela = 0,
        titulo = 'Porta dianteira esquerda'
    },
    porta_dianteira_direita = {
        osso = 'door_pside_f',
        porta = 1,
        janela = 1,
        titulo = 'Porta dianteira direita'
    },
    porta_traseira_esquerda = {
        osso = 'door_dside_r',
        porta = 2,
        janela = 2,
        titulo = 'Porta traseira esquerda'
    },
    porta_traseira_direita = {
        osso = 'door_pside_r',
        porta = 3,
        janela = 3,
        titulo = 'Porta traseira direita'
    },
    capo = {
        osso = 'bonnet',
        porta = 4,
        titulo = 'Capô'
    },
    porta_malas = {
        osso = 'boot',
        porta = 5,
        titulo = 'Porta-malas'
    }
}

local function coordenadaOsso(
    veiculo,
    nome
)
    local osso =
        GetEntityBoneIndexByName(
            veiculo,
            nome
        )

    if osso == -1 then
        return nil
    end

    return GetWorldPositionOfEntityBone(
        veiculo,
        osso
    )
end

local function dimensoesVeiculo(
    veiculo
)
    local minimo,
        maximo =
        GetModelDimensions(
            GetEntityModel(
                veiculo
            )
        )

    return minimo,
        maximo
end

local function pontoFallbackRegiao(
    veiculo,
    id
)
    local minimo,
        maximo =
        dimensoesVeiculo(
            veiculo
        )

    local largura =
        math.max(
            1.2,
            maximo.x - minimo.x
        )

    local comprimento =
        math.max(
            2.0,
            maximo.y - minimo.y
        )

    local altura =
        math.max(
            1.0,
            maximo.z - minimo.z
        )

    local lado =
        largura * 0.48

    local frente =
        maximo.y
        - comprimento * 0.28

    local traseira =
        minimo.y
        + comprimento * 0.30

    local zPorta =
        minimo.z
        + altura * 0.50

    if id == 'porta_dianteira_esquerda' then
        return GetOffsetFromEntityInWorldCoords(
            veiculo,
            -lado,
            frente,
            zPorta
        )
    elseif id == 'porta_dianteira_direita' then
        return GetOffsetFromEntityInWorldCoords(
            veiculo,
            lado,
            frente,
            zPorta
        )
    elseif id == 'porta_traseira_esquerda' then
        return GetOffsetFromEntityInWorldCoords(
            veiculo,
            -lado,
            traseira,
            zPorta
        )
    elseif id == 'porta_traseira_direita' then
        return GetOffsetFromEntityInWorldCoords(
            veiculo,
            lado,
            traseira,
            zPorta
        )
    elseif id == 'capo' then
        return GetOffsetFromEntityInWorldCoords(
            veiculo,
            0.0,
            maximo.y - comprimento * 0.10,
            minimo.z + altura * 0.60
        )
    elseif id == 'porta_malas' then
        return GetOffsetFromEntityInWorldCoords(
            veiculo,
            0.0,
            minimo.y + comprimento * 0.08,
            minimo.z + altura * 0.60
        )
    end

    return GetEntityCoords(
        veiculo
    )
end

local function pontoRegiao(
    veiculo,
    id
)
    local regiao =
        REGIOES_VEICULO[id]

    if not regiao then
        return nil
    end

    local osso =
        coordenadaOsso(
            veiculo,
            regiao.osso
        )

    if osso then
        return osso
    end

    return pontoFallbackRegiao(
        veiculo,
        id
    )
end

local function distanciaHitRegiao(
    veiculo,
    contexto,
    id
)
    if veiculo == 0
        or not DoesEntityExist(
            veiculo
        )
        or type(contexto)
            ~= 'table'
        or not contexto.coords
    then
        return 999.0
    end

    local ponto =
        pontoRegiao(
            veiculo,
            id
        )

    if not ponto then
        return 999.0
    end

    return #(
        contexto.coords
        - ponto
    )
end

local function coordsLocaisVeiculo(
    veiculo,
    coords
)
    if not coords
        or type(GetOffsetFromEntityGivenWorldCoords)
            ~= 'function'
    then
        return nil
    end

    local ok,
        localCoords =
        pcall(
            GetOffsetFromEntityGivenWorldCoords,
            veiculo,
            coords.x + 0.0,
            coords.y + 0.0,
            coords.z + 0.0
        )

    if not ok
        or not localCoords
    then
        return nil
    end

    return localCoords
end

local function yLocalOsso(
    veiculo,
    nome
)
    local world =
        coordenadaOsso(
            veiculo,
            nome
        )

    if not world then
        return nil
    end

    local localCoords =
        coordsLocaisVeiculo(
            veiculo,
            world
        )

    return localCoords
        and localCoords.y
        or nil
end

local function pontoEntradaRegiao(
    veiculo,
    id
)
    local regiao =
        REGIOES_VEICULO[id]

    if not regiao then
        return nil
    end

    local porta =
        tonumber(
            regiao.porta
        )

    if porta
        and porta >= 0
        and porta <= 3
        and type(GetEntryPositionOfDoor)
            == 'function'
    then
        local ok,
            ponto =
            pcall(
                GetEntryPositionOfDoor,
                veiculo,
                porta
            )

        if ok
            and ponto
            and ponto.x
            and ponto.y
            and ponto.z
        then
            return ponto
        end
    end

    return pontoRegiao(
        veiculo,
        id
    )
end

local function yLocalRegiao(
    veiculo,
    id
)
    local ponto =
        pontoEntradaRegiao(
            veiculo,
            id
        )

    if not ponto then
        return nil
    end

    local localCoords =
        coordsLocaisVeiculo(
            veiculo,
            ponto
        )

    return localCoords
        and localCoords.y
        or nil
end

local function portaFisicamenteValida(
    veiculo,
    porta,
    osso
)
    if porta == nil
        or veiculo == 0
        or not DoesEntityExist(veiculo)
    then
        return false
    end

    -- GetIsDoorValid não está disponível/consistente em todos os artifacts e
    -- em vários veículos add-on. Quando existir, usamos; caso contrário a
    -- estrutura real de bones do modelo vira a fonte principal.
    if type(GetIsDoorValid) == 'function' then
        local ok,
            valida =
            pcall(
                GetIsDoorValid,
                veiculo,
                porta
            )

        if ok
            and valida == true
        then
            return true
        end
    end

    if type(osso) == 'table' then
        for _, nomeOsso in ipairs(osso) do
            if nomeOsso
                and GetEntityBoneIndexByName(
                    veiculo,
                    nomeOsso
                ) ~= -1
            then
                return true
            end
        end
    elseif osso
        and GetEntityBoneIndexByName(
            veiculo,
            osso
        ) ~= -1
    then
        return true
    end

    -- Último fallback para carros add-on com bones não padronizados.
    -- O número de passageiros ajuda a distinguir 2 e 4 portas sem depender
    -- exclusivamente do nome dos bones. Capô/porta-malas continuam exigindo
    -- bone/nativa válida para não criar controles fantasmas.
    if porta >= 0
        and porta <= 3
    then
        local maxPassageiros =
            math.max(
                0,
                tonumber(
                    GetVehicleMaxNumberOfPassengers(
                        veiculo
                    )
                ) or 0
            )

        if porta == 0 then
            return true
        end

        if porta == 1 then
            return maxPassageiros >= 1
        end

        return maxPassageiros >= 3
    end

    return false
end

local function regiaoMaisProxima(
    veiculo,
    contexto
)
    if veiculo == 0
        or not DoesEntityExist(
            veiculo
        )
        or type(contexto) ~= 'table'
        or not contexto.coords
    then
        return nil,
            999.0
    end

    local hitLocal =
        coordsLocaisVeiculo(
            veiculo,
            contexto.coords
        )

    if hitLocal then
        local minimo,
            maximo =
            dimensoesVeiculo(
                veiculo
            )

        local minX = minimo.x or -0.8
        local maxX = maximo.x or 0.8
        local minY = minimo.y or -1.5
        local maxY = maximo.y or 1.5
        local centroX =
            (minX + maxX) * 0.5
        local centroY =
            (minY + maxY) * 0.5
        local largura =
            math.max(
                1.2,
                maxX - minX
            )
        local comprimento =
            math.max(
                2.0,
                maxY - minY
            )
        local meiaLargura =
            largura * 0.5
        local x =
            hitLocal.x - centroX
        local lateral =
            math.abs(x)
            >= meiaLargura * 0.34
        local esquerda =
            x < 0.0

        -- Classificação geométrica das extremidades antes das portas. Em vários
        -- veículos addon o bone/entry da porta fica adiantado demais e fazia o
        -- capô deixar de ser reconhecido. Usamos a caixa real do modelo e a
        -- altura do ponto atingido para separar capô/porta-malas de para-brisa.
        local altura = math.max(1.0, (maximo.z or 1.0) - (minimo.z or 0.0))
        local limiteZExtremidade = (minimo.z or 0.0) + altura * 0.80
        local frenteGeometrica = centroY + comprimento * 0.17
        local traseiraGeometrica = centroY - comprimento * 0.17

        if hitLocal.z <= limiteZExtremidade
            and math.abs(x) <= meiaLargura * 1.08
        then
            if hitLocal.y >= frenteGeometrica
                and portaFisicamenteValida(veiculo, 4, 'bonnet')
            then
                return 'capo', 0.0
            end

            if hitLocal.y <= traseiraGeometrica
                and portaFisicamenteValida(veiculo, 5, 'boot')
            then
                return 'porta_malas', 0.0
            end
        end

        local idFrente =
            esquerda
            and 'porta_dianteira_esquerda'
            or 'porta_dianteira_direita'
        local idTraseira =
            esquerda
            and 'porta_traseira_esquerda'
            or 'porta_traseira_direita'
        local portaFrente =
            esquerda and 0 or 1
        local portaTraseira =
            esquerda and 2 or 3
        local ossoFrente =
            esquerda
            and 'door_dside_f'
            or 'door_pside_f'
        local ossoTraseira =
            esquerda
            and 'door_dside_r'
            or 'door_pside_r'

        local frenteValida =
            portaFisicamenteValida(
                veiculo,
                portaFrente,
                ossoFrente
            )
        local traseiraValida =
            portaFisicamenteValida(
                veiculo,
                portaTraseira,
                ossoTraseira
            )

        local yFrente =
            frenteValida
            and yLocalRegiao(
                veiculo,
                idFrente
            )
            or nil
        local yTraseira =
            traseiraValida
            and yLocalRegiao(
                veiculo,
                idTraseira
            )
            or nil

        -- As extremidades ganham prioridade antes das laterais. Assim mirar
        -- na quina traseira seleciona porta-malas, não a porta traseira.
        local margemExtremidade =
            math.max(
                0.34,
                comprimento * 0.085
            )

        local limiteFrente =
            yFrente
            and (
                yFrente
                + margemExtremidade
            )
            or (
                centroY
                + comprimento * 0.22
            )

        local limiteTraseira =
            yTraseira
            and (
                yTraseira
                - margemExtremidade
            )
            or (
                centroY
                - comprimento * 0.22
            )

        if hitLocal.y >= limiteFrente
            and portaFisicamenteValida(
                veiculo,
                4,
                'bonnet'
            )
        then
            return 'capo',
                0.0
        end

        if hitLocal.y <= limiteTraseira
            and portaFisicamenteValida(
                veiculo,
                5,
                'boot'
            )
        then
            return 'porta_malas',
                0.0
        end

        if lateral then
            if frenteValida
                and traseiraValida
                and yFrente
                and yTraseira
            then
                local divisor =
                    (yFrente + yTraseira)
                    * 0.5

                -- Pequena zona neutra na coluna B: melhor não oferecer uma
                -- porta do que selecionar a vizinha quando a mira está no meio.
                if math.abs(
                    hitLocal.y - divisor
                ) <= 0.055
                then
                    return nil,
                        0.0
                end

                return (
                    hitLocal.y > divisor
                    and idFrente
                    or idTraseira
                ),
                    0.0
            end

            if frenteValida
                and not traseiraValida
            then
                return idFrente,
                    0.0
            end

            if traseiraValida
                and not frenteValida
            then
                return idTraseira,
                    0.0
            end
        end

        -- No miolo da carroceria não "chutamos" uma porta lateral.
        return nil,
            0.0
    end

    -- Fallback para modelos addon que não aceitam a transformação de
    -- coordenadas. Tolerância curta para não misturar portas vizinhas.
    local melhor = nil
    local menor = 999.0

    for id in pairs(
        REGIOES_VEICULO
    ) do
        local distancia =
            distanciaHitRegiao(
                veiculo,
                contexto,
                id
            )

        if distancia < menor then
            menor = distancia
            melhor = id
        end
    end

    if menor > 0.62 then
        return nil,
            menor
    end

    return melhor,
        menor
end

local function olhandoRegiao(
    veiculo,
    contexto,
    id
)
    local regiao =
        regiaoMaisProxima(
            veiculo,
            contexto
        )

    return regiao == id
end

local function portaDaRegiao(
    id
)
    local regiao =
        REGIOES_VEICULO[id]

    return regiao
        and regiao.porta
        or nil
end

local function janelaAlvo(veiculo, coords)
    if veiculo == 0 or not DoesEntityExist(veiculo) or not coords then
        return nil, nil
    end

    -- Prioriza bones reais do vidro, seguindo a mesma filosofia do ox_target.
    local melhorJanela, melhorDistancia = nil, nil

    for janela, dados in pairs(JANELAS_VEICULO) do
        local boneNome = dados.bones[1]
        local boneId = GetEntityBoneIndexByName(veiculo, boneNome)

        if boneId ~= -1 then
            local bonePos = GetWorldPositionOfEntityBone(veiculo, boneId)
            local d = #(coords - bonePos)

            if not melhorDistancia or d < melhorDistancia then
                melhorJanela = janela
                melhorDistancia = d
            end
        end
    end

    if melhorJanela ~= nil and melhorDistancia and melhorDistancia <= 0.86 then
        return melhorJanela, JANELAS_VEICULO[melhorJanela]
    end

    -- Fallback para add-ons sem window_*: exige a metade superior da porta.
    local regiao = regiaoMaisProxima(veiculo, { coords = coords })
    local mapa = {
        porta_dianteira_esquerda = 0,
        porta_dianteira_direita = 1,
        porta_traseira_esquerda = 2,
        porta_traseira_direita = 3
    }
    local janela = mapa[regiao]
    if janela == nil then return nil, nil end

    local localCoords = coordsLocaisVeiculo(veiculo, coords)
    if not localCoords then return nil, nil end

    local minimo, maximo = dimensoesVeiculo(veiculo)
    local altura = math.max(1.0, maximo.z - minimo.z)
    local limiteInferior = minimo.z + altura * 0.38
    local limiteSuperior = maximo.z + altura * 0.10

    if localCoords.z < limiteInferior or localCoords.z > limiteSuperior then
        return nil, nil
    end

    return janela, JANELAS_VEICULO[janela]
end

local function janelaDaRegiao(
    id
)
    local regiao =
        REGIOES_VEICULO[id]

    return regiao
        and regiao.janela
        or nil
end

local function portaOlhada(
    veiculo,
    contexto
)
    local id =
        regiaoMaisProxima(
            veiculo,
            contexto
        )

    if not id
        or id == 'capo'
        or id == 'porta_malas'
    then
        return nil,
            nil
    end

    return portaDaRegiao(id),
        id
end

local function janelaOlhada(
    veiculo,
    contexto
)
    local porta,
        id =
        portaOlhada(
            veiculo,
            contexto
        )

    if porta == nil then
        return nil,
            nil
    end

    return janelaDaRegiao(id),
        id
end

local function podeInteragirRegiao(
    veiculo,
    distancia,
    contexto,
    id
)
    if not podeInteragirExterno(veiculo) then
        return false
    end

    if not olhandoRegiao(veiculo, contexto, id) then
        return false
    end

    -- Quando a retícula está na área envidraçada, a janela tem prioridade sobre
    -- a chapa da porta. Isso evita mostrar "porta" ao mirar diretamente no vidro.
    local regiao = REGIOES_VEICULO[id]
    if regiao and regiao.janela ~= nil and contexto and contexto.coords then
        local janela = janelaAlvo(veiculo, contexto.coords)
        if janela == regiao.janela then
            return false
        end
    end

    return true
end


local function podeEntrarPassageiro(veiculo)
    if not podeInteragirExterno(
        veiculo
    ) then
        return false
    end

    if GetEntitySpeed(veiculo)
        > 1.5
    then
        return false
    end

    return assentoPassageiroLivre(
        veiculo
    ) ~= nil
end

local function entrarPassageiro(veiculo)
    local banco =
        assentoPassageiroLivre(
            veiculo
        )

    if banco == nil then
        notificar(
            'aviso',
            'Veículo',
            'Não há assento de passageiro disponível.'
        )

        return
    end

    local ped =
        PlayerPedId()

    SetPedConfigFlag(
        ped,
        184,
        true
    )

    TaskEnterVehicle(
        ped,
        veiculo,
        8000,
        banco,
        1.0,
        1,
        0
    )
end


local PORTAS_ENTRADA = {
    {
        regiao = 'porta_dianteira_esquerda',
        banco = -1,
        motorista = true
    },
    {
        regiao = 'porta_dianteira_direita',
        banco = 0
    },
    {
        regiao = 'porta_traseira_esquerda',
        banco = 1
    },
    {
        regiao = 'porta_traseira_direita',
        banco = 2
    }
}

local function pontoEntradaPorta(
    veiculo,
    entrada
)
    if type(entrada) ~= 'table' then
        return nil
    end

    local regiao =
        entrada.regiao

    if regiao then
        local ponto =
            pontoEntradaRegiao(
                veiculo,
                regiao
            )

        if ponto then
            return ponto
        end
    end

    return nil
end

local function portaEntradaMaisProxima(
    veiculo,
    coords
)
    if veiculo == 0
        or not DoesEntityExist(
            veiculo
        )
    then
        return nil
    end

    local localPed =
        coordsLocaisVeiculo(
            veiculo,
            coords
        )

    if not localPed then
        return nil
    end

    local minimo,
        maximo =
        dimensoesVeiculo(
            veiculo
        )

    local centroX =
        ((minimo.x or -0.8)
        + (maximo.x or 0.8))
        * 0.5
    local meiaLargura =
        math.max(
            0.65,
            ((maximo.x or 0.8)
            - (minimo.x or -0.8))
            * 0.5
        )

    -- Só escolhemos banco quando o jogador está realmente ao lado do carro.
    -- Isso evita apertar F perto do capô/porta-malas e entrar em um banco
    -- vizinho porque o bone daquela porta ficou mais próximo.
    if math.abs(
        localPed.x - centroX
    ) < meiaLargura * 0.72
    then
        return nil
    end

    local esquerda =
        localPed.x < centroX

    local frente =
        PORTAS_ENTRADA[
            esquerda and 1 or 2
        ]
    local traseira =
        PORTAS_ENTRADA[
            esquerda and 3 or 4
        ]

    local pontoFrente =
        pontoEntradaPorta(
            veiculo,
            frente
        )
    local pontoTraseira =
        pontoEntradaPorta(
            veiculo,
            traseira
        )

    local yFrente =
        pontoFrente
        and coordsLocaisVeiculo(
            veiculo,
            pontoFrente
        )
        or nil
    local yTraseira =
        pontoTraseira
        and coordsLocaisVeiculo(
            veiculo,
            pontoTraseira
        )
        or nil

    yFrente =
        yFrente
        and yFrente.y
        or nil

    yTraseira =
        yTraseira
        and yTraseira.y
        or nil

    local escolhida = nil

    if yFrente
        and yTraseira
    then
        local divisor =
            (yFrente + yTraseira)
            * 0.5

        escolhida =
            localPed.y > divisor
            and frente
            or traseira
    elseif yFrente then
        escolhida = frente
    elseif yTraseira then
        escolhida = traseira
    end

    if not escolhida then
        return nil
    end

    local ponto =
        pontoEntradaPorta(
            veiculo,
            escolhida
        )

    if not ponto then
        return nil
    end

    local distancia =
        #(coords - ponto)

    if distancia > 1.55 then
        return nil
    end

    return {
        regiao = escolhida.regiao,
        banco = escolhida.banco,
        motorista =
            escolhida.motorista
            == true,
        distancia = distancia
    }
end

local function veiculoComPortaPassageiroProxima()
    local ped =
        PlayerPedId()

    local coords =
        GetEntityCoords(
            ped
        )

    local melhorVeiculo = 0
    local melhorEntrada = nil
    local menor = 999.0

    for _, veiculo in ipairs(
        GetGamePool('CVehicle')
    ) do
        if DoesEntityExist(
            veiculo
        )
            and GetEntitySpeed(
                veiculo
            ) < 3.0
        then
            local distanciaCentro =
                #(
                    coords
                    - GetEntityCoords(
                        veiculo
                    )
                )

            if distanciaCentro <= 4.5 then
                local entrada =
                    portaEntradaMaisProxima(
                        veiculo,
                        coords
                    )

                if entrada
                    and entrada.distancia < menor
                then
                    menor =
                        entrada.distancia

                    melhorVeiculo =
                        veiculo

                    melhorEntrada =
                        entrada
                end
            end
        end
    end

    return melhorVeiculo,
        melhorEntrada
end

local function entrarPelaPortaPassageiro(
    veiculo,
    banco
)
    if veiculo == 0
        or not DoesEntityExist(
            veiculo
        )
        or banco == nil
        or banco < -1
    then
        return false
    end

    if not IsVehicleSeatFree(
        veiculo,
        banco
    ) then
        notificar(
            'aviso',
            'Veículo',
            'Este assento está ocupado.',
            1800
        )

        return false
    end

    local ped =
        PlayerPedId()

    -- O banco é escolhido pela porta física mais próxima. Interceptamos
    -- inclusive a porta do motorista para impedir o GTA de escolher o banco
    -- traseiro quando o jogador está junto da porta dianteira.
    SetPedConfigFlag(
        ped,
        184,
        true
    )

    ClearPedTasks(
        ped
    )

    TaskEnterVehicle(
        ped,
        veiculo,
        8000,
        banco,
        1.0,
        1,
        0
    )

    return true
end

local function pneuAleatorio()
    local pneus = {
        0,
        1,
        4,
        5
    }

    return pneus[
        math.random(
            1,
            #pneus
        )
    ]
end

local function processarDano(veiculo, velocidade)
    if veiculo == 0
        or not DoesEntityExist(veiculo)
    then
        return
    end

    local corpo =
        GetVehicleBodyHealth(
            veiculo
        )

    local motor =
        GetVehicleEngineHealth(
            veiculo
        )

    local anterior =
        danoAnterior[veiculo]

    if not anterior then
        danoAnterior[veiculo] = {
            corpo = corpo,
            motor = motor
        }

        maximaOriginais[veiculo] =
            math.max(
                1.0,
                GetVehicleEstimatedMaxSpeed(
                    veiculo
                )
            )

        return
    end

    local perda =
        anterior.corpo - corpo

    if perda
        >= FSPVehicle.Dano.PerdaMinimaCarroceria
    then
        local novoMotor =
            motor
            - (
                perda
                * FSPVehicle.Dano.MultiplicadorMotor
            )

        SetVehicleEngineHealth(
            veiculo,
            math.max(
                -4000.0,
                novoMotor
            )
        )

        if perda
            >= FSPVehicle.Dano.ImpactoPneu
            and velocidade
                >= FSPVehicle.Dano.VelocidadeMinimaPneuKmh
            and math.random()
                <= FSPVehicle.Dano.ChancePneu
        then
            SetVehicleTyreBurst(
                veiculo,
                pneuAleatorio(),
                true,
                1000.0
            )
        end
    end

    motor =
        GetVehicleEngineHealth(
            veiculo
        )

    if motor
        <= FSPVehicle.SaudeMotorQuebrado
    then
        quebradoPorDano[veiculo] =
            true

        definirMotor(
            veiculo,
            false,
            false
        )

        SetVehicleUndriveable(
            veiculo,
            true
        )
    elseif quebradoPorDano[veiculo] then
        quebradoPorDano[veiculo] =
            nil

        SetVehicleUndriveable(
            veiculo,
            false
        )
    end

    if motor
        <= FSPVehicle.SaudeMotorCritica
        and motor
            > FSPVehicle.SaudeMotorQuebrado
    then
        local maxima =
            maximaOriginais[veiculo]
            or GetVehicleEstimatedMaxSpeed(
                veiculo
            )

        SetEntityMaxSpeed(
            veiculo,
            math.min(
                maxima,
                FSPVehicle.VelocidadeMotorCriticoKmh
                    / 3.6
            )
        )

        if not avisouMotor[veiculo] then
            avisouMotor[veiculo] =
                true

            notificar(
                'aviso',
                'Veículo',
                'O motor está seriamente danificado.'
            )
        end
    elseif avisouMotor[veiculo]
        and motor > FSPVehicle.SaudeMotorCritica
    then
        avisouMotor[veiculo] =
            nil

        SetEntityMaxSpeed(
            veiculo,
            maximaOriginais[veiculo]
            or 999.0
        )
    end

    anterior.corpo = corpo
    anterior.motor = motor
end

local function podeEmpurrar(veiculo)
    if not podeInteragirExterno(
        veiculo
    ) then
        return false
    end

    if GetEntitySpeed(veiculo)
        * 3.6
        > 3.0
    then
        return false
    end

    if GetVehicleEngineHealth(
        veiculo
    ) <= FSPVehicle.SaudeMotorEmpurrar
    then
        return true
    end

    if GetResourceState(
        'fivepd_sp_fuel'
    ) == 'started'
    then
        return exports.fivepd_sp_fuel:ObterCombustivel(
            veiculo
        ) <= 0.1
    end

    return false
end

local function carregarAnim(dict)
    RequestAnimDict(dict)

    local limite =
        GetGameTimer()
        + 3000

    while not HasAnimDictLoaded(
        dict
    )
        and GetGameTimer() < limite
    do
        Wait(20)
    end

    return HasAnimDictLoaded(dict)
end

local function pararEmpurrar()
    if empurrando == 0 then
        return
    end

    local ped =
        PlayerPedId()

    DetachEntity(
        ped,
        true,
        false
    )

    ClearPedTasks(
        ped
    )

    SetPedCanRagdoll(
        ped,
        true
    )

    if DoesEntityExist(
        empurrando
    ) then
        SetVehicleSteeringAngle(
            empurrando,
            0.0
        )
    end

    empurrando = 0
end

local function empurrarVeiculo(veiculo)
    if empurrando ~= 0 then
        pararEmpurrar()
        return
    end

    if not podeEmpurrar(
        veiculo
    ) then
        return
    end

    local ped =
        PlayerPedId()

    if not carregarAnim(
        'missfinale_c2ig_11'
    ) then
        return
    end

    empurrando =
        veiculo

    SetPedConfigFlag(
        ped,
        184,
        true
    )

    SetPedCanRagdoll(
        ped,
        false
    )

    AttachEntityToEntity(
        ped,
        veiculo,
        0,
        0.0,
        -2.18,
        0.45,
        0.0,
        0.0,
        0.0,
        false,
        false,
        false,
        false,
        20,
        true
    )

    TaskPlayAnim(
        ped,
        'missfinale_c2ig_11',
        'pushcar_offcliff_m',
        2.0,
        -2.0,
        -1,
        35,
        0.0,
        false,
        false,
        false
    )

    CreateThread(function()
        while empurrando == veiculo
            and DoesEntityExist(
                veiculo
            )
        do
            Wait(0)

            DisableControlAction(
                0,
                23,
                true
            )

            DisableControlAction(
                0,
                75,
                true
            )

            if IsControlJustPressed(
                0,
                73
            )
            then
                break
            end

            if GetEntitySpeed(
                veiculo
            ) * 3.6
                > FSPVehicle.Empurrar.VelocidadeMaximaKmh
            then
                break
            end

            local direcao = 0.0

            if IsControlPressed(
                0,
                32
            ) then
                direcao =
                    FSPVehicle.Empurrar.Forca
            elseif IsControlPressed(
                0,
                33
            ) then
                direcao =
                    -FSPVehicle.Empurrar.Forca
            end

            if direcao ~= 0.0 then
                ApplyForceToEntityCenterOfMass(
                    veiculo,
                    1,
                    0.0,
                    direcao,
                    0.0,
                    true,
                    true,
                    true,
                    true
                )
            end

            if IsControlPressed(
                0,
                34
            ) then
                SetVehicleSteeringAngle(
                    veiculo,
                    24.0
                )
            elseif IsControlPressed(
                0,
                35
            ) then
                SetVehicleSteeringAngle(
                    veiculo,
                    -24.0
                )
            else
                SetVehicleSteeringAngle(
                    veiculo,
                    0.0
                )
            end
        end

        pararEmpurrar()
    end)
end


local function nomeVeiculo(veiculo)
    if veiculo == 0
        or not DoesEntityExist(veiculo)
    then
        return 'Veículo'
    end

    local chave =
        GetDisplayNameFromVehicleModel(
            GetEntityModel(
                veiculo
            )
        )

    local traduzido =
        GetLabelText(
            chave
        )

    if traduzido
        and traduzido ~= 'NULL'
        and traduzido ~= ''
    then
        return traduzido
    end

    if chave
        and chave ~= ''
    then
        return chave
    end

    return 'Veículo'
end

local function estadoExtraAtual(
    veiculo,
    extra
)
    local stateBag = nil

    pcall(function()
        stateBag =
            Entity(veiculo).state[
                ('fivepd_sp:extra:%s'):format(
                    extra
                )
            ]
    end)

    if stateBag ~= nil then
        return normalizarBooleanoExtra(
            stateBag
        )
    end

    local chave =
        chaveCacheExtra(
            veiculo,
            extra
        )

    local cache =
        extrasLocal[chave]

    if type(cache) == 'table'
        and (
            tonumber(cache.expiraEm)
            or 0
        ) >= GetGameTimer()
    then
        return normalizarBooleanoExtra(
            cache.ativo
        )
    end

    extrasLocal[chave] = nil

    return normalizarBooleanoExtra(
        IsVehicleExtraTurnedOn(
            veiculo,
            extra
        )
    )
end

local function extrasDoVeiculo(
    veiculo
)
    local lista = {}

    if veiculo == 0
        or not DoesEntityExist(
            veiculo
        )
    then
        return lista
    end

    for extra = 0, 20 do
        if DoesExtraExist(
            veiculo,
            extra
        ) then
            lista[#lista + 1] = {
                id = extra,
                ativo =
                    estadoExtraAtual(
                        veiculo,
                        extra
                    )
            }
        end
    end

    return lista
end

local function textoLivery(veiculo, tipo, indice)
    if indice < 0 then
        return 'Padrão / sem livery'
    end

    local chave = nil

    pcall(function()
        if tipo == 'mod' then
            chave = GetModTextLabel(veiculo, 48, indice)
        else
            chave = GetLiveryName(veiculo, indice)
        end
    end)

    if chave and chave ~= '' and chave ~= 'NULL' then
        local traduzido = GetLabelText(chave)
        if traduzido and traduzido ~= '' and traduzido ~= 'NULL' then
            return traduzido
        end
    end

    return ('Livery %02d'):format(indice + 1)
end

local function liveriesDoVeiculo(veiculo)
    local retorno = {
        tipo = nil,
        atual = -1,
        opcoes = {}
    }

    if veiculo == 0 or not DoesEntityExist(veiculo) then
        return retorno
    end

    local modCount = 0
    local legacyCount = 0

    pcall(function()
        SetVehicleModKit(veiculo, 0)
        modCount = math.max(0, tonumber(GetNumVehicleMods(veiculo, 48)) or 0)
    end)

    pcall(function()
        legacyCount = math.max(0, tonumber(GetVehicleLiveryCount(veiculo)) or 0)
    end)

    -- Muitos veículos add-on usam VMT_LIVERY_MOD (mod 48). Quando ele existe,
    -- é a fonte preferida. O modo legacy cobre os veículos que usam
    -- Get/SetVehicleLivery.
    if modCount > 0 then
        retorno.tipo = 'mod'
        retorno.atual = tonumber(GetVehicleMod(veiculo, 48)) or -1

        retorno.opcoes[#retorno.opcoes + 1] = {
            id = -1,
            nome = 'Padrão / sem livery',
            ativo = retorno.atual == -1
        }

        for indice = 0, modCount - 1 do
            retorno.opcoes[#retorno.opcoes + 1] = {
                id = indice,
                nome = textoLivery(veiculo, 'mod', indice),
                ativo = retorno.atual == indice
            }
        end
    elseif legacyCount > 0 then
        retorno.tipo = 'legacy'
        retorno.atual = tonumber(GetVehicleLivery(veiculo)) or -1

        retorno.opcoes[#retorno.opcoes + 1] = {
            id = -1,
            nome = 'Padrão / sem livery',
            ativo = retorno.atual == -1
        }

        for indice = 0, legacyCount - 1 do
            retorno.opcoes[#retorno.opcoes + 1] = {
                id = indice,
                nome = textoLivery(veiculo, 'legacy', indice),
                ativo = retorno.atual == indice
            }
        end
    end

    return retorno
end

local function aplicarLiveryLocal(veiculo, tipo, indice)
    if veiculo == 0 or not DoesEntityExist(veiculo) then
        return false
    end

    indice = math.floor(tonumber(indice) or -2)
    tipo = tostring(tipo or '')

    if indice < -1 or indice > 255 then
        return false
    end

    if tipo == 'mod' then
        local ok = pcall(function()
            SetVehicleModKit(veiculo, 0)
            SetVehicleMod(veiculo, 48, indice, false)
        end)
        return ok
    elseif tipo == 'legacy' then
        local ok = pcall(function()
            SetVehicleLivery(veiculo, indice)
        end)
        return ok
    end

    return false
end

local function estadoPainelVeiculo(veiculo)
    local vidros = {}
    local portas = {}

    local nomesVidros = {
        [0] = 'Dianteiro esquerdo',
        [1] = 'Dianteiro direito',
        [2] = 'Traseiro esquerdo',
        [3] = 'Traseiro direito'
    }

    local nomesPortas = {
        [0] = 'Dianteira esquerda',
        [1] = 'Dianteira direita',
        [2] = 'Traseira esquerda',
        [3] = 'Traseira direita',
        [4] = 'Capô',
        [5] = 'Porta-malas'
    }

    for janela = 0, 3 do
        local dadosJanela = JANELAS_VEICULO[janela]
        local janelaValida =
            portaFisicamenteValida(
                veiculo,
                janela,
                dadosJanela
                    and dadosJanela.bones
                    or nil
            )

        if janelaValida then
            vidros[#vidros + 1] = {
                id = janela,
                nome = nomesVidros[janela],
                aberto = vidroAberto(veiculo, janela),
                integro = vidroIntegro(veiculo, janela)
            }
        end
    end

    local ossosPortas = {
        [0] = 'door_dside_f',
        [1] = 'door_pside_f',
        [2] = 'door_dside_r',
        [3] = 'door_pside_r',
        [4] = 'bonnet',
        [5] = 'boot'
    }

    for porta = 0, 5 do
        local valida =
            portaFisicamenteValida(
                veiculo,
                porta,
                ossosPortas[porta]
            )

        if valida then
            local bag = nil

            pcall(function()
                bag = Entity(veiculo).state[
                    ('fivepd_sp:doorOpen:%s'):format(porta)
                ]
            end)

            local aberta = type(bag) == 'boolean'
                and bag
                or GetVehicleDoorAngleRatio(veiculo, porta) > 0.12

            portas[#portas + 1] = {
                id = porta,
                nome = nomesPortas[porta],
                aberta = aberta
            }
        end
    end

    local luzInterna = false

    pcall(function()
        local valor = Entity(veiculo).state['fivepd_sp:interiorLight']

        if type(valor) == 'boolean' then
            luzInterna = valor
        end
    end)

    return {
        extras = extrasDoVeiculo(veiculo),
        vidros = vidros,
        portas = portas,
        luzInterna = luzInterna,
        livery = liveriesDoVeiculo(veiculo)
    }
end

local function enviarEstadoExtras()
    if not extrasAberto
        or extrasVeiculo == 0
        or not DoesEntityExist(
            extrasVeiculo
        )
    then
        return
    end

    SendNUIMessage({
        acao = 'veiculo:estado',
        veiculo = nomeVeiculo(extrasVeiculo),
        controles = estadoPainelVeiculo(extrasVeiculo)
    })
end

local function fecharExtras()
    if not extrasAberto then
        return
    end

    extrasAberto = false
    extrasVeiculo = 0
    f10PodeLivery = false

    SetNuiFocus(
        false,
        false
    )

    SetNuiFocusKeepInput(
        false
    )

    SendNUIMessage({
        acao = 'veiculo:fechar'
    })
end

local function abrirExtras()
    if handlingAberto then
        return
    end

    if extrasAberto then
        fecharExtras()
        return
    end

    if not exports.fivepd_sp_core:PersonagemCarregado() then
        return
    end

    local ped =
        PlayerPedId()

    local veiculo =
        GetVehiclePedIsIn(
            ped,
            false
        )

    if veiculo == 0
        or not jogadorDirige(
            veiculo
        )
    then
        notificar(
            'aviso',
            'Gerenciamento do veículo',
            'Você precisa estar dirigindo para gerenciar o veículo.',
            2200
        )

        return
    end

    extrasVeiculo =
        veiculo

    extrasAberto =
        true

    SetNuiFocus(
        true,
        true
    )

    SetNuiFocusKeepInput(
        false
    )

    SetCursorLocation(
        0.82,
        0.50
    )

    SendNUIMessage({
        acao = 'veiculo:abrir',
        veiculo = nomeVeiculo(veiculo),
        controles = estadoPainelVeiculo(veiculo)
    })

    f10PodeLivery = false
    TriggerServerEvent('fivepd_sp:vehicle:f10:permissoes')

    CreateThread(function()
        while extrasAberto do
            Wait(250)

            if extrasVeiculo == 0
                or not DoesEntityExist(
                    extrasVeiculo
                )
                or not jogadorDirige(
                    extrasVeiculo
                )
            then
                fecharExtras()
                break
            end
        end
    end)
end


local function aplicarExtraLocal(
    veiculo,
    extra,
    ativo
)
    if veiculo == 0
        or not DoesEntityExist(
            veiculo
        )
        or not DoesExtraExist(
            veiculo,
            extra
        )
    then
        return false
    end

    local desejado =
        normalizarBooleanoExtra(
            ativo
        )

    SetVehicleExtra(
        veiculo,
        extra,
        desejado
            and 0
            or 1
    )

    extrasLocal[
        chaveCacheExtra(
            veiculo,
            extra
        )
    ] = {
        ativo = desejado,
        expiraEm =
            GetGameTimer()
            + 3000
    }

    return true
end

local function veiculoPorNetId(
    netId
)
    netId =
        tonumber(netId)
        or 0

    if netId > 0 then
        local entidade =
            NetworkGetEntityFromNetworkId(
                netId
            )

        if entidade ~= 0
            and DoesEntityExist(
                entidade
            )
            and IsEntityAVehicle(
                entidade
            )
        then
            return entidade
        end
    end

    if extrasAberto
        and extrasVeiculo ~= 0
        and DoesEntityExist(
            extrasVeiculo
        )
    then
        return extrasVeiculo
    end

    return 0
end

RegisterNetEvent(
    'fivepd_sp:vehicle:extra:sync',
    function(
        netId,
        extra,
        ativo
    )
        extra =
            math.floor(
                tonumber(extra)
                or -1
            )

        if extra < 0
            or extra > 20
        then
            return
        end

        local veiculo =
            veiculoPorNetId(
                netId
            )

        if veiculo == 0
            or not DoesExtraExist(
                veiculo,
                extra
            )
        then
            return
        end

        local desejado =
            normalizarBooleanoExtra(
                ativo
            )

        -- Aplicação imediata + algumas repetições curtas.
        -- A primeira atualização de rede do veículo pode chegar no mesmo
        -- frame da mudança e restaurar temporariamente o estado anterior.
        CreateThread(function()
            for tentativa = 1, 6 do
                if not DoesEntityExist(
                    veiculo
                ) then
                    break
                end

                aplicarExtraLocal(
                    veiculo,
                    extra,
                    desejado
                )

                if tentativa < 6 then
                    Wait(80)
                end
            end

            if extrasAberto
                and extrasVeiculo
                    == veiculo
            then
                enviarEstadoExtras()
            end
        end)
    end
)

RegisterNetEvent(
    'fivepd_sp:vehicle:extra:resultado',
    function(
        extra,
        ativo,
        ok,
        motivo
    )
        if not ok then
            if extrasAberto then
                enviarEstadoExtras()
            end

            notificar(
                'aviso',
                'Gerenciamento do veículo',
                tostring(
                    motivo
                    or 'Não foi possível alterar este extra agora.'
                ),
                2400
            )

            return
        end

        if extrasAberto
            and extrasVeiculo ~= 0
            and DoesEntityExist(
                extrasVeiculo
            )
        then
            aplicarExtraLocal(
                extrasVeiculo,
                math.floor(
                    tonumber(extra)
                    or -1
                ),
                normalizarBooleanoExtra(
                    ativo
                )
            )

            enviarEstadoExtras()
        end
    end
)

RegisterNUICallback(
    'alternarExtra',
    function(data, cb)
        local extra =
            math.floor(
                tonumber(
                    data
                    and data.id
                )
                or -1
            )

        if not extrasAberto
            or extrasVeiculo == 0
            or not jogadorDirige(
                extrasVeiculo
            )
            or extra < 0
            or extra > 20
            or not DoesExtraExist(
                extrasVeiculo,
                extra
            )
        then
            cb({
                ok = false
            })

            return
        end

        local atual =
            estadoExtraAtual(
                extrasVeiculo,
                extra
            )

        local desejado =
            not atual

        -- Atualiza localmente de imediato para o clique ter resposta visual,
        -- mas a autoridade final é o servidor.
        aplicarExtraLocal(
            extrasVeiculo,
            extra,
            desejado
        )

        TriggerServerEvent(
            'fivepd_sp:vehicle:extra:set',
            extra,
            desejado
        )

        cb({
            ok = true,
            id = extra,
            ativo = desejado
        })
    end
)

RegisterNUICallback(
    'alternarVidroPainel',
    function(data, cb)
        local janela = math.floor(tonumber(data and data.id) or -1)

        if not extrasAberto
            or extrasVeiculo == 0
            or not jogadorDirige(extrasVeiculo)
            or janela < 0
            or janela > 3
        then
            cb({ ok = false })
            return
        end

        local dadosJanela = JANELAS_VEICULO[janela]
        local portaValida =
            portaFisicamenteValida(
                extrasVeiculo,
                janela,
                dadosJanela
                    and dadosJanela.bones
                    or nil
            )

        if not portaValida then
            cb({ ok = false })
            return
        end

        local novoEstado = not vidroAberto(extrasVeiculo, janela)

        -- Define explicitamente o estado do vidro individual. Isso evita que
        -- veículos add-on com retorno inconsistente das natives de integridade
        -- deixem o botão visível, porém sem responder ao clique.
        if novoEstado then
            RollDownWindow(extrasVeiculo, janela)
        else
            RollUpWindow(extrasVeiculo, janela)
        end

        vidrosAbertos[chaveVidroAberto(extrasVeiculo, janela)] = novoEstado
        definirStateBag(
            extrasVeiculo,
            ('fivepd_sp:windowOpen:%s'):format(janela),
            novoEstado
        )

        TriggerServerEvent(
            'fivepd_sp:vehicle:controle:set',
            'window',
            janela,
            novoEstado
        )

        enviarEstadoExtras()

        cb({
            ok = true,
            id = janela,
            aberto = novoEstado
        })
    end
)

RegisterNUICallback(
    'alternarPortaPainel',
    function(data, cb)
        local porta = math.floor(tonumber(data and data.id) or -1)

        if not extrasAberto
            or extrasVeiculo == 0
            or not jogadorDirige(extrasVeiculo)
            or porta < 0
            or porta > 5
        then
            cb({ ok = false })
            return
        end

        local osso =
            porta == 0 and 'door_dside_f'
            or porta == 1 and 'door_pside_f'
            or porta == 2 and 'door_dside_r'
            or porta == 3 and 'door_pside_r'
            or porta == 4 and 'bonnet'
            or porta == 5 and 'boot'
            or nil

        local valida =
            portaFisicamenteValida(
                extrasVeiculo,
                porta,
                osso
            )

        if not valida then
            cb({ ok = false })
            return
        end

        local aberta = GetVehicleDoorAngleRatio(extrasVeiculo, porta) > 0.12
        local novoEstado = not aberta

        if novoEstado then
            SetVehicleDoorOpen(extrasVeiculo, porta, false, false)
        else
            SetVehicleDoorShut(extrasVeiculo, porta, false)
        end

        definirStateBag(
            extrasVeiculo,
            ('fivepd_sp:doorOpen:%s'):format(porta),
            novoEstado
        )

        TriggerServerEvent(
            'fivepd_sp:vehicle:controle:set',
            'door',
            porta,
            novoEstado
        )

        enviarEstadoExtras()

        cb({
            ok = true,
            id = porta,
            aberta = novoEstado
        })
    end
)

RegisterNUICallback(
    'alternarLuzInternaPainel',
    function(_, cb)
        if not extrasAberto
            or extrasVeiculo == 0
            or not jogadorDirige(extrasVeiculo)
        then
            cb({ ok = false })
            return
        end

        local atual = false

        pcall(function()
            local bag = Entity(extrasVeiculo).state['fivepd_sp:interiorLight']
            if type(bag) == 'boolean' then
                atual = bag
            end
        end)

        local novoEstado = not atual

        SetVehicleInteriorlight(extrasVeiculo, novoEstado)
        definirStateBag(extrasVeiculo, 'fivepd_sp:interiorLight', novoEstado)

        TriggerServerEvent(
            'fivepd_sp:vehicle:controle:set',
            'interior',
            -1,
            novoEstado
        )

        enviarEstadoExtras()

        cb({
            ok = true,
            ativo = novoEstado
        })
    end
)

RegisterNUICallback(
    'acaoGrupoVeiculo',
    function(data, cb)
        local acao = tostring(data and data.acao or '')

        if not extrasAberto
            or extrasVeiculo == 0
            or not jogadorDirige(extrasVeiculo)
        then
            cb({ ok = false })
            return
        end

        if acao == 'abrir_vidros' or acao == 'fechar_vidros' then
            local abrir = acao == 'abrir_vidros'

            for janela = 0, 3 do
                local dadosJanela = JANELAS_VEICULO[janela]
                local valida =
                    portaFisicamenteValida(
                        extrasVeiculo,
                        janela,
                        dadosJanela
                            and dadosJanela.bones
                            or nil
                    )

                if valida then
                    if abrir then
                        RollDownWindow(extrasVeiculo, janela)
                    else
                        RollUpWindow(extrasVeiculo, janela)
                    end

                    vidrosAbertos[chaveVidroAberto(extrasVeiculo, janela)] = abrir
                    definirStateBag(
                        extrasVeiculo,
                        ('fivepd_sp:windowOpen:%s'):format(janela),
                        abrir
                    )

                    TriggerServerEvent(
                        'fivepd_sp:vehicle:controle:set',
                        'window',
                        janela,
                        abrir
                    )
                end
            end
        elseif acao == 'fechar_portas' then
            for porta = 0, 5 do
                local osso =
                    porta == 0 and 'door_dside_f'
                    or porta == 1 and 'door_pside_f'
                    or porta == 2 and 'door_dside_r'
                    or porta == 3 and 'door_pside_r'
                    or porta == 4 and 'bonnet'
                    or porta == 5 and 'boot'
                    or nil

                local valida =
                    portaFisicamenteValida(
                        extrasVeiculo,
                        porta,
                        osso
                    )

                if valida then
                    SetVehicleDoorShut(extrasVeiculo, porta, false)
                    definirStateBag(
                        extrasVeiculo,
                        ('fivepd_sp:doorOpen:%s'):format(porta),
                        false
                    )

                    TriggerServerEvent(
                        'fivepd_sp:vehicle:controle:set',
                        'door',
                        porta,
                        false
                    )
                end
            end
        else
            cb({ ok = false })
            return
        end

        enviarEstadoExtras()
        cb({ ok = true })
    end
)

RegisterNetEvent(
    'fivepd_sp:vehicle:f10:permissoes',
    function(podeLivery)
        f10PodeLivery = podeLivery == true

        if extrasAberto
            and extrasVeiculo ~= 0
            and DoesEntityExist(extrasVeiculo)
        then
            SendNUIMessage({
                acao = 'veiculo:permissoes',
                podeLivery = f10PodeLivery,
                livery = liveriesDoVeiculo(extrasVeiculo)
            })
        end
    end
)

RegisterNetEvent(
    'fivepd_sp:vehicle:livery:sync',
    function(netId, tipo, indice)
        local veiculo = veiculoPorNetId(netId)
        if veiculo == 0 then
            return
        end

        CreateThread(function()
            for tentativa = 1, 5 do
                if not DoesEntityExist(veiculo) then
                    break
                end

                aplicarLiveryLocal(veiculo, tipo, indice)

                if tentativa < 5 then
                    Wait(100)
                end
            end

            if extrasAberto and extrasVeiculo == veiculo then
                enviarEstadoExtras()
            end
        end)
    end
)

RegisterNetEvent(
    'fivepd_sp:vehicle:livery:resultado',
    function(ok, motivo)
        if not ok then
            notificar(
                'aviso',
                'Livery',
                tostring(motivo or 'Não foi possível alterar a livery.'),
                2600
            )
        end

        if extrasAberto
            and extrasVeiculo ~= 0
            and DoesEntityExist(extrasVeiculo)
        then
            enviarEstadoExtras()
        end
    end
)

RegisterNUICallback(
    'selecionarLivery',
    function(data, cb)
        local tipo = tostring(data and data.tipo or '')
        local indice = math.floor(tonumber(data and data.id) or -2)

        if not extrasAberto
            or not f10PodeLivery
            or extrasVeiculo == 0
            or not jogadorDirige(extrasVeiculo)
            or (tipo ~= 'mod' and tipo ~= 'legacy')
            or indice < -1
            or indice > 255
        then
            cb({ ok = false })
            return
        end

        local encontrado = false
        local dados = liveriesDoVeiculo(extrasVeiculo)

        if dados.tipo == tipo then
            for _, item in ipairs(dados.opcoes or {}) do
                if tonumber(item.id) == indice then
                    encontrado = true
                    break
                end
            end
        end

        if not encontrado then
            cb({ ok = false })
            return
        end

        TriggerServerEvent(
            'fivepd_sp:vehicle:livery:set',
            tipo,
            indice
        )

        cb({ ok = true, pending = true })
    end
)

RegisterNUICallback(
    'fecharExtras',
    function(_, cb)
        fecharExtras()

        cb({
            ok = true
        })
    end
)

RegisterCommand(
    '+fivepd_sp_extras',
    abrirExtras,
    false
)

RegisterCommand(
    '-fivepd_sp_extras',
    function()
    end,
    false
)

RegisterKeyMapping(
    '+fivepd_sp_extras',
    'Gerenciar veículo',
    'keyboard',
    FSPVehicle.TeclaExtras
)

for extra = 0, 20 do
    AddStateBagChangeHandler(
        ('fivepd_sp:extra:%s'):format(
            extra
        ),
        nil,
        function(
            bagName,
            _,
            valor
        )
            if valor == nil then
                return
            end

            local estado =
                normalizarBooleanoExtra(
                    valor
                )

            local entidade =
                GetEntityFromStateBagName(
                    bagName
                )

            if entidade == 0
                or not DoesEntityExist(
                    entidade
                )
                or not IsEntityAVehicle(
                    entidade
                )
                or not DoesExtraExist(
                    entidade,
                    extra
                )
            then
                return
            end

            CreateThread(function()
                for tentativa = 1, 4 do
                    if not DoesEntityExist(
                        entidade
                    ) then
                        break
                    end

                    aplicarExtraLocal(
                        entidade,
                        extra,
                        estado
                    )

                    if tentativa < 4 then
                        Wait(100)
                    end
                end
            end)
        end
    )
end

RegisterCommand(
    '+fivepd_sp_cinto',
    function()
        if not exports.fivepd_sp_core:PersonagemCarregado() then
            return
        end

        local veiculo =
            GetVehiclePedIsIn(
                PlayerPedId(),
                false
            )

        if not aceitaCinto(
            veiculo
        ) then
            return
        end

        definirCinto(
            not cinto,
            false
        )

        notificar(
            'info',
            'Cinto de segurança',
            cinto
                and 'Cinto afivelado.'
                or 'Cinto desafivelado.',
            2200
        )
    end,
    false
)

RegisterCommand(
    '-fivepd_sp_cinto',
    function()
    end,
    false
)

RegisterKeyMapping(
    '+fivepd_sp_cinto',
    'Afivelar ou desafivelar o cinto',
    'keyboard',
    FSPVehicle.TeclaCinto
)

RegisterCommand(
    '+fivepd_sp_motor',
    alternarMotor,
    false
)

RegisterCommand(
    '-fivepd_sp_motor',
    function()
    end,
    false
)

RegisterKeyMapping(
    '+fivepd_sp_motor',
    'Ligar ou desligar o motor',
    'keyboard',
    FSPVehicle.TeclaMotor
)

RegisterCommand(
    '+fivepd_sp_seta_esquerda',
    function()
        alternarIndicador(
            'esquerda'
        )
    end,
    false
)

RegisterCommand(
    '-fivepd_sp_seta_esquerda',
    function()
    end,
    false
)

RegisterKeyMapping(
    '+fivepd_sp_seta_esquerda',
    'Seta esquerda',
    'keyboard',
    FSPVehicle.TeclaSetaEsquerda
)

RegisterCommand(
    '+fivepd_sp_seta_direita',
    function()
        alternarIndicador(
            'direita'
        )
    end,
    false
)

RegisterCommand(
    '-fivepd_sp_seta_direita',
    function()
    end,
    false
)

RegisterKeyMapping(
    '+fivepd_sp_seta_direita',
    'Seta direita',
    'keyboard',
    FSPVehicle.TeclaSetaDireita
)

RegisterCommand(
    '+fivepd_sp_pisca_alerta',
    function()
        alternarIndicador(
            'alerta'
        )
    end,
    false
)

RegisterCommand(
    '-fivepd_sp_pisca_alerta',
    function()
    end,
    false
)

RegisterKeyMapping(
    '+fivepd_sp_pisca_alerta',
    'Pisca-alerta',
    'keyboard',
    FSPVehicle.TeclaPiscaAlerta
)


local function podePortaDE(
    veiculo,
    distancia,
    contexto
)
    return podeInteragirRegiao(
        veiculo,
        distancia,
        contexto,
        'porta_dianteira_esquerda'
    )
end

local function podePortaDD(
    veiculo,
    distancia,
    contexto
)
    return podeInteragirRegiao(
        veiculo,
        distancia,
        contexto,
        'porta_dianteira_direita'
    )
end

local function podePortaTE(
    veiculo,
    distancia,
    contexto
)
    return podeInteragirRegiao(
        veiculo,
        distancia,
        contexto,
        'porta_traseira_esquerda'
    )
end

local function podePortaTD(
    veiculo,
    distancia,
    contexto
)
    return podeInteragirRegiao(
        veiculo,
        distancia,
        contexto,
        'porta_traseira_direita'
    )
end

local function podeCapo(
    veiculo,
    distancia,
    contexto
)
    return podeInteragirRegiao(
        veiculo,
        distancia,
        contexto,
        'capo'
    )
end

local function podePortaMalas(
    veiculo,
    distancia,
    contexto
)
    return podeInteragirRegiao(
        veiculo,
        distancia,
        contexto,
        'porta_malas'
    )
end

local function podeTravarNaPorta(
    veiculo,
    distancia,
    contexto
)
    if not podeInteragirExterno(
        veiculo
    ) then
        return false
    end

    local porta =
        portaOlhada(
            veiculo,
            contexto
        )

    return porta ~= nil
end

local function podeVidroNaPorta(
    veiculo,
    distancia,
    contexto
)
    if ehMotoOuBicicleta(veiculo) then
        return false
    end
    if not podeInteragirExterno(
        veiculo
    ) then
        return false
    end

    local janela = janelaAlvo(
        veiculo,
        contexto and contexto.coords
    )

    return janela ~= nil
end

local function podeVidroEspecifico(
    veiculo,
    distancia,
    contexto,
    esperado
)
    if ehMotoOuBicicleta(veiculo)
        or not podeInteragirExterno(veiculo)
        or type(contexto) ~= 'table'
        or not contexto.coords
    then
        return false
    end

    local janela = janelaAlvo(
        veiculo,
        contexto.coords
    )

    return janela == esperado
end

local function podeVidroDE(veiculo, distancia, contexto)
    return podeVidroEspecifico(veiculo, distancia, contexto, 0)
end

local function podeVidroDD(veiculo, distancia, contexto)
    return podeVidroEspecifico(veiculo, distancia, contexto, 1)
end

local function podeVidroTE(veiculo, distancia, contexto)
    return podeVidroEspecifico(veiculo, distancia, contexto, 2)
end

local function podeVidroTD(veiculo, distancia, contexto)
    return podeVidroEspecifico(veiculo, distancia, contexto, 3)
end

local function olhandoCapoOuCofreMotor(veiculo, contexto)
    if olhandoRegiao(veiculo, contexto, 'capo') then
        return true
    end

    if type(contexto) ~= 'table' or not contexto.coords then
        return false
    end

    local localCoords = coordsLocaisVeiculo(veiculo, contexto.coords)
    if not localCoords then return false end

    local minimo, maximo = dimensoesVeiculo(veiculo)
    local largura = math.max(1.2, maximo.x - minimo.x)
    local comprimento = math.max(2.0, maximo.y - minimo.y)
    local altura = math.max(1.0, maximo.z - minimo.z)
    local centroY = (minimo.y + maximo.y) * 0.5

    -- Com o capô aberto é comum o raycast acertar o bloco do motor e não a
    -- tampa. O cofre inteiro passa a contar, mas só na metade dianteira baixa.
    return localCoords.y >= (centroY + comprimento * 0.06)
        and math.abs(localCoords.x) <= largura * 0.52
        and localCoords.z <= (minimo.z + altura * 0.82)
end

local function podeInspecionarCapoAberto(
    veiculo,
    distancia,
    contexto
)
    if not podeInteragirExterno(veiculo)
        or type(contexto) ~= 'table'
        or not contexto.coords
        or not olhandoCapoOuCofreMotor(
            veiculo,
            contexto
        )
    then
        return false
    end

    local ok, valida = pcall(
        GetIsDoorValid,
        veiculo,
        4
    )

    if ok and valida == false then
        return false
    end

    return GetVehicleDoorAngleRatio(
        veiculo,
        4
    ) > 0.16
end

local function podeInspecionarVidroFechado(
    veiculo,
    distancia,
    contexto
)
    if ehMotoOuBicicleta(veiculo) then
        return false
    end
    if not podeInteragirExterno(veiculo)
        or type(contexto) ~= 'table'
        or not contexto.coords
    then
        return false
    end

    local janela = janelaAlvo(
        veiculo,
        contexto.coords
    )

    if janela == nil then
        return false
    end

    return vidroFechado(
        veiculo,
        janela
    )
end

RegisterNetEvent(
    'fivepd_sp:vehicle:interaction:passageiro',
    function(contexto)
        local veiculo =
            contexto
            and contexto.entidade
            or 0

        if podeEntrarPassageiro(
            veiculo
        ) then
            entrarPassageiro(
                veiculo
            )
        end
    end
)

RegisterNetEvent(
    'fivepd_sp:vehicle:interaction:porta',
    function(contexto)
        local veiculo =
            contexto
            and contexto.entidade
            or 0

        local porta =
            contexto
            and contexto.args
            and contexto.args.porta

        porta =
            tonumber(
                porta
            )

        if podeInteragirExterno(
            veiculo
        )
            and porta
            and porta >= 0
            and porta <= 3
        then
            alternarPorta(
                veiculo,
                porta
            )
        end
    end
)

RegisterNetEvent(
    'fivepd_sp:vehicle:interaction:capo',
    function(contexto)
        local veiculo =
            contexto
            and contexto.entidade
            or 0

        if podeInteragirExterno(
            veiculo
        ) then
            alternarPorta(
                veiculo,
                4
            )
        end
    end
)

RegisterNetEvent(
    'fivepd_sp:vehicle:interaction:portaMalas',
    function(contexto)
        local veiculo =
            contexto
            and contexto.entidade
            or 0

        if podeInteragirExterno(
            veiculo
        ) then
            alternarPorta(
                veiculo,
                5
            )
        end
    end
)

RegisterNetEvent(
    'fivepd_sp:vehicle:interaction:vidro',
    function(contexto)
        local veiculo =
            contexto
            and contexto.entidade
            or 0

        local janela =
            contexto
            and contexto.args
            and contexto.args.janela

        janela =
            tonumber(
                janela
            )

        if podeInteragirExterno(
            veiculo
        )
            and janela
            and janela >= 0
            and janela <= 3
        then
            alternarVidro(
                veiculo,
                janela
            )
        end
    end
)

RegisterNetEvent(
    'fivepd_sp:vehicle:interaction:trava',
    function(contexto)
        local veiculo =
            contexto
            and contexto.entidade
            or 0

        if podeInteragirExterno(
            veiculo
        ) then
            alternarTravaVeiculo(
                veiculo
            )
        end
    end
)

RegisterNetEvent(
    'fivepd_sp:vehicle:interaction:empurrar',
    function(contexto)
        local veiculo =
            contexto
            and contexto.entidade
            or 0

        if podeEmpurrar(
            veiculo
        ) then
            empurrarVeiculo(
                veiculo
            )
        end
    end
)

local function registrarInteracoesVeiculo()
    if GetResourceState(
        'ox_target'
    ) ~= 'started'
    then
        return false
    end

    FSPTarget.RemoveGlobal(
        'vehicle',
        'fivepd_sp_vehicle:global'
    )

    local id =
        FSPTarget.RegisterGlobal(
            'vehicle',
            {
                id = 'fivepd_sp_vehicle:global',
                nome = 'Veículo',
                distancia = 3.2,
                opcoes = {
                    {
                        id = 'porta_de',
                        titulo = 'Abrir/fechar porta dianteira esquerda',
                        evento = 'fivepd_sp:vehicle:interaction:porta',
                        args = {
                            porta = 0
                        },
                        podeInteragir = podePortaDE
                    },
                    {
                        id = 'vidro_de',
                        titulo = 'Subir/descer vidro dianteiro esquerdo',
                        evento = 'fivepd_sp:vehicle:interaction:vidro',
                        args = {
                            janela = 0
                        },
                        podeInteragir = podeVidroDE
                    },
                    {
                        id = 'porta_dd',
                        titulo = 'Abrir/fechar porta dianteira direita',
                        evento = 'fivepd_sp:vehicle:interaction:porta',
                        args = {
                            porta = 1
                        },
                        podeInteragir = podePortaDD
                    },
                    {
                        id = 'vidro_dd',
                        titulo = 'Subir/descer vidro dianteiro direito',
                        evento = 'fivepd_sp:vehicle:interaction:vidro',
                        args = {
                            janela = 1
                        },
                        podeInteragir = podeVidroDD
                    },
                    {
                        id = 'porta_te',
                        titulo = 'Abrir/fechar porta traseira esquerda',
                        evento = 'fivepd_sp:vehicle:interaction:porta',
                        args = {
                            porta = 2
                        },
                        podeInteragir = podePortaTE
                    },
                    {
                        id = 'vidro_te',
                        titulo = 'Subir/descer vidro traseiro esquerdo',
                        evento = 'fivepd_sp:vehicle:interaction:vidro',
                        args = {
                            janela = 2
                        },
                        podeInteragir = podeVidroTE
                    },
                    {
                        id = 'porta_td',
                        titulo = 'Abrir/fechar porta traseira direita',
                        evento = 'fivepd_sp:vehicle:interaction:porta',
                        args = {
                            porta = 3
                        },
                        podeInteragir = podePortaTD
                    },
                    {
                        id = 'vidro_td',
                        titulo = 'Subir/descer vidro traseiro direito',
                        evento = 'fivepd_sp:vehicle:interaction:vidro',
                        args = {
                            janela = 3
                        },
                        podeInteragir = podeVidroTD
                    },
                    {
                        id = 'capo',
                        titulo = 'Abrir/fechar capô',
                        evento = 'fivepd_sp:vehicle:interaction:capo',
                        podeInteragir = podeCapo
                    },
                    {
                        id = 'porta_malas',
                        titulo = 'Abrir/fechar porta-malas',
                        evento = 'fivepd_sp:vehicle:interaction:portaMalas',
                        podeInteragir = podePortaMalas
                    },
                    {
                        id = 'trava',
                        titulo = 'Travar/destravar veículo',
                        descricao = 'Usar o controle do veículo',
                        evento = 'fivepd_sp:vehicle:interaction:trava',
                        podeInteragir = podeTravarNaPorta
                    },
                    {
                        id = 'empurrar',
                        titulo = 'Empurrar veículo',
                        descricao = 'Mover um veículo quebrado',
                        evento = 'fivepd_sp:vehicle:interaction:empurrar',
                        podeInteragir = podeEmpurrar
                    }
                }
            }
        )

    return id ~= false
end

CreateThread(function()
    while GetResourceState(
        'ox_target'
    ) ~= 'started'
    do
        Wait(500)
    end

    registrarInteracoesVeiculo()
end)

AddEventHandler(
    'onClientResourceStart',
    function(resource)
        if resource == 'ox_target' then
            CreateThread(function()
                Wait(500)
                registrarInteracoesVeiculo()
            end)
        end
    end
)

-- Autocura dos registros globais do ALT. RegistrarGlobal sobrescreve o mesmo
-- ID, então esta atualização periódica é segura e evita perder interações de
-- veículos após restart isolado/ordem de start dos resources.
CreateThread(function()
    while true do
        Wait(5000)
        if GetResourceState('ox_target') == 'started' then
            registrarInteracoesVeiculo()
        end
    end
end)


CreateThread(function()
    while true do
        local espera = 350

        if exports.fivepd_sp_core:PersonagemCarregado() then
            local ped =
                PlayerPedId()

            if not IsEntityDead(
                ped
            )
                and GetVehiclePedIsIn(
                    ped,
                    false
                ) == 0
            then
                local veiculo,
                    entrada =
                    veiculoComPortaPassageiroProxima()

                if veiculo ~= 0
                    and entrada
                then
                    espera = 0

                    -- Intercepta o F somente junto de uma porta real e envia
                    -- o ped diretamente ao banco daquela porta, inclusive motorista.
                    DisableControlAction(
                        0,
                        23,
                        true
                    )

                    if IsDisabledControlJustPressed(
                        0,
                        23
                    ) then
                        entrarPelaPortaPassageiro(
                            veiculo,
                            entrada.banco
                        )
                    end
                end
            end
        end

        Wait(
            espera
        )
    end
end)

CreateThread(function()
    while true do
        local espera = 450

        if exports.fivepd_sp_core:PersonagemCarregado() then
            local ped =
                PlayerPedId()

            local veiculo =
                GetVehiclePedIsIn(
                    ped,
                    false
                )

            if veiculo ~= 0 then
                local estaComoPassageiro =
                    GetPedInVehicleSeat(
                        veiculo,
                        -1
                    ) ~= ped

                if estaComoPassageiro then
                    SetPedConfigFlag(
                        ped,
                        184,
                        true
                    )
                end

                espera =
                    cinto
                    and 0
                    or 100

                if ultimoVeiculo ~= veiculo then
                    pararAlarmeCinto()

                    ultimoVeiculo =
                        veiculo

                    velocidadeAnterior =
                        0.0

                    velocidadeAnterior2 =
                        0.0

                    definirCinto(
                        false,
                        true
                    )

                    agendarAlarmeCinto()

                    local bagMotor =
                        Entity(veiculo).state['fivepd_sp:engine']

                    if type(bagMotor) ~= 'boolean'
                        and jogadorDirige(
                            veiculo
                        )
                    then
                        definirMotor(
                            veiculo,
                            false,
                            false
                        )
                    end
                end

                if deveTocarAlarme(
                    ped,
                    veiculo
                ) then
                    iniciarAlarmeCinto()
                else
                    pararAlarmeCinto()
                end

                if cinto
                    and aceitaCinto(
                        veiculo
                    )
                then
                    DisableControlAction(
                        0,
                        75,
                        true
                    )
                end

                local velocidade =
                    GetEntitySpeed(
                        veiculo
                    ) * 3.6

                if not cinto
                    and velocidadeAnterior2
                        > FSPVehicle.VelocidadeEjecaoKmh
                    and (
                        velocidadeAnterior2
                        - velocidade
                    ) > FSPVehicle.QuedaVelocidadeEjecaoKmh
                    and HasEntityCollidedWithAnything(
                        veiculo
                    )
                then
                    local coords =
                        GetEntityCoords(
                            ped
                        )

                    local frente =
                        GetEntityForwardVector(
                            veiculo
                        )

                    SetEntityCoords(
                        ped,
                        coords.x
                            + frente.x * 1.4,
                        coords.y
                            + frente.y * 1.4,
                        coords.z + 0.3,
                        true,
                        true,
                        true,
                        false
                    )

                    SetPedToRagdoll(
                        ped,
                        1800,
                        2600,
                        0,
                        true,
                        true,
                        false
                    )

                    ApplyDamageToPed(
                        ped,
                        18,
                        false
                    )
                end

                velocidadeAnterior2 =
                    velocidadeAnterior

                velocidadeAnterior =
                    velocidade

                if jogadorDirige(
                    veiculo
                ) then
                    local desejado =
                        estadoMotor(
                            veiculo
                        )

                    if not desejado then
                        SetVehicleEngineOn(
                            veiculo,
                            false,
                            true,
                            true
                        )
                    elseif combustivelDisponivel(
                        veiculo
                    )
                        and GetVehicleEngineHealth(
                            veiculo
                        ) > FSPVehicle.SaudeMotorQuebrado
                    then
                        SetVehicleEngineOn(
                            veiculo,
                            true,
                            true,
                            true
                        )
                    else
                        definirMotor(
                            veiculo,
                            false,
                            false
                        )
                    end

                    processarDano(
                        veiculo,
                        velocidade
                    )
                end
            else
                if ultimoVeiculo ~= 0
                    or alarmeCintoAtivo
                then
                    pararAlarmeCinto()

                    ultimoVeiculo = 0
                    velocidadeAnterior = 0.0
                    velocidadeAnterior2 = 0.0

                    definirCinto(
                        false,
                        true
                    )
                end
            end
        else
            if ultimoVeiculo ~= 0
                or alarmeCintoAtivo
            then
                pararAlarmeCinto()

                ultimoVeiculo = 0

                definirCinto(
                    false,
                    true
                )
            end

            if empurrando ~= 0 then
                pararEmpurrar()
            end
        end

        Wait(espera)
    end
end)

AddStateBagChangeHandler(
    'fivepd_sp:engine',
    nil,
    function(bagName, _, valor)
        local entidade =
            GetEntityFromStateBagName(
                bagName
            )

        if entidade ~= 0
            and DoesEntityExist(
                entidade
            )
            and type(valor) == 'boolean'
        then
            motorLocal[entidade] =
                valor

            SetVehicleEngineOn(
                entidade,
                valor,
                true,
                true
            )
        end
    end
)

AddStateBagChangeHandler(
    'fivepd_sp:locked',
    nil,
    function(bagName, _, valor)
        local entidade =
            GetEntityFromStateBagName(
                bagName
            )

        if entidade ~= 0
            and DoesEntityExist(
                entidade
            )
            and type(valor) == 'boolean'
        then
            aplicarTrava(
                entidade,
                valor
            )
        end
    end
)

AddStateBagChangeHandler(
    'fivepd_sp:indicator',
    nil,
    function(bagName, _, valor)
        local entidade =
            GetEntityFromStateBagName(
                bagName
            )

        if entidade ~= 0
            and DoesEntityExist(
                entidade
            )
        then
            aplicarIndicadores(
                entidade,
                tonumber(valor) or 0
            )
        end
    end
)

AddStateBagChangeHandler(
    'fivepd_sp:frontWindows',
    nil,
    function(bagName, _, valor)
        local entidade =
            GetEntityFromStateBagName(
                bagName
            )

        if entidade ~= 0
            and DoesEntityExist(
                entidade
            )
            and type(valor) == 'boolean'
        then
            aplicarVidros(
                entidade,
                valor
            )
        end
    end
)

for janelaPainel = 0, 3 do
    local indiceJanela = janelaPainel

    AddStateBagChangeHandler(
        ('fivepd_sp:windowOpen:%s'):format(indiceJanela),
        nil,
        function(bagName, _, valor)
            if type(valor) ~= 'boolean' then
                return
            end

            local entidade = GetEntityFromStateBagName(bagName)

            if entidade == 0
                or not DoesEntityExist(entidade)
                or not IsEntityAVehicle(entidade)
            then
                return
            end

            if valor then
                RollDownWindow(entidade, indiceJanela)
            else
                RollUpWindow(entidade, indiceJanela)
            end

            vidrosAbertos[chaveVidroAberto(entidade, indiceJanela)] = valor

            if extrasAberto and extrasVeiculo == entidade then
                enviarEstadoExtras()
            end
        end
    )
end

for portaPainel = 0, 5 do
    local indicePorta = portaPainel

    AddStateBagChangeHandler(
        ('fivepd_sp:doorOpen:%s'):format(indicePorta),
        nil,
        function(bagName, _, valor)
            if type(valor) ~= 'boolean' then
                return
            end

            local entidade = GetEntityFromStateBagName(bagName)

            if entidade == 0
                or not DoesEntityExist(entidade)
                or not IsEntityAVehicle(entidade)
            then
                return
            end

            if valor then
                SetVehicleDoorOpen(entidade, indicePorta, false, false)
            else
                SetVehicleDoorShut(entidade, indicePorta, false)
            end

            if extrasAberto and extrasVeiculo == entidade then
                enviarEstadoExtras()
            end
        end
    )
end

AddStateBagChangeHandler(
    'fivepd_sp:interiorLight',
    nil,
    function(bagName, _, valor)
        if type(valor) ~= 'boolean' then
            return
        end

        local entidade = GetEntityFromStateBagName(bagName)

        if entidade == 0
            or not DoesEntityExist(entidade)
            or not IsEntityAVehicle(entidade)
        then
            return
        end

        SetVehicleInteriorlight(entidade, valor)

        if extrasAberto and extrasVeiculo == entidade then
            enviarEstadoExtras()
        end
    end
)

AddEventHandler(
    'fivepd_sp:personagem:descarregado',
    function()
        pararAlarmeCinto()
        pararEmpurrar()

        ultimoVeiculo = 0

        definirCinto(
            false,
            true
        )
    end
)

AddEventHandler(
    'onResourceStop',
    function(resource)
        if resource ~= GetCurrentResourceName() then
            return
        end

        if extrasAberto or handlingAberto then
            SetNuiFocus(
                false,
                false
            )

            SetNuiFocusKeepInput(
                false
            )
        end
    end
)

AddEventHandler(
    'onResourceStop',
    function(resource)
        if resource ~= GetCurrentResourceName() then
            return
        end

        pararAlarmeCinto()
        pararEmpurrar()
    end
)

exports(
    'CintoAfivelado',
    function()
        return cinto
    end
)

exports(
    'VeiculoAceitaCinto',
    function(veiculo)
        veiculo =
            tonumber(veiculo)
            or GetVehiclePedIsIn(
                PlayerPedId(),
                false
            )

        return aceitaCinto(
            veiculo
        )
    end
)

exports(
    'AlarmeCintoAtivo',
    function()
        return alarmeCintoAtivo
    end
)

exports(
    'RegiaoAlvo',
    function(veiculo, coords)
        if veiculo == 0
            or not DoesEntityExist(
                veiculo
            )
            or not coords
        then
            return nil
        end

        local id =
            regiaoMaisProxima(
                veiculo,
                {
                    coords = coords
                }
            )

        return id
    end
)

exports(
    'JanelaAlvo',
    function(veiculo, coords)
        local janela, dados = janelaAlvo(
            veiculo,
            coords
        )

        return janela,
            dados and dados.id or nil
    end
)

exports(
    'VidroAberto',
    vidroAberto
)

exports(
    'VidroFechado',
    vidroFechado
)

exports(
    'PodeInspecionarCapoAberto',
    podeInspecionarCapoAberto
)

exports(
    'PodeInspecionarVidroFechado',
    podeInspecionarVidroFechado
)

exports(
    'PodeInteragirExterno',
    podeInteragirExterno
)

exports(
    'PodeEntrarPassageiro',
    podeEntrarPassageiro
)

exports(
    'PodeEmpurrar',
    podeEmpurrar
)


exports(
    'PodePortaDE',
    podePortaDE
)

exports(
    'PodePortaDD',
    podePortaDD
)

exports(
    'PodePortaTE',
    podePortaTE
)

exports(
    'PodePortaTD',
    podePortaTD
)

exports(
    'PodeCapo',
    podeCapo
)

exports(
    'PodePortaMalas',
    podePortaMalas
)

exports(
    'PodeTravarNaPorta',
    podeTravarNaPorta
)

exports(
    'PodeVidroDE',
    podeVidroDE
)

exports(
    'PodeVidroDD',
    podeVidroDD
)

exports(
    'PodeVidroTE',
    podeVidroTE
)

exports(
    'PodeVidroTD',
    podeVidroTD
)

exports(
    'PodeVidroNaPorta',
    podeVidroNaPorta
)

-- ==========================================================================
-- /handling2 - editor compacto de dirigibilidade em runtime
-- Perfis são salvos por modelo no fivepd_sp_vehicle. Nenhum .meta é alterado.
-- ==========================================================================
local function clampHandling(value, minValue, maxValue)
    value = tonumber(value) or minValue
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function handlingDefaults()
    local defaults = (FSPVehicle.Handling and FSPVehicle.Handling.Defaults) or {}
    return {
        arrancada = clampHandling(defaults.arrancada or 50, 0, 100),
        rolagem = clampHandling(defaults.rolagem or 50, 0, 100),
        antiCapotagem = clampHandling(defaults.antiCapotagem or 0, 0, 100),
        potencia = clampHandling(defaults.potencia or 50, 0, 100)
    }
end

local function normalizeHandlingProfile(profile)
    local defaults = handlingDefaults()
    profile = type(profile) == 'table' and profile or {}
    return {
        arrancada = clampHandling(profile.arrancada ~= nil and profile.arrancada or defaults.arrancada, 0, 100),
        rolagem = clampHandling(profile.rolagem ~= nil and profile.rolagem or defaults.rolagem, 0, 100),
        antiCapotagem = clampHandling(profile.antiCapotagem ~= nil and profile.antiCapotagem or defaults.antiCapotagem, 0, 100),
        potencia = clampHandling(profile.potencia ~= nil and profile.potencia or defaults.potencia, 0, 100)
    }
end

local function vehicleModelName(vehicle)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return nil end
    local name = nil
    pcall(function()
        name = tostring(GetEntityArchetypeName(vehicle) or ''):lower()
    end)
    if not name or name == '' or name == '0' then return nil end
    return name
end

local function requestVehicleControl(vehicle)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return false end
    if not NetworkGetEntityIsNetworked(vehicle) or NetworkHasControlOfEntity(vehicle) then return true end

    NetworkRequestControlOfEntity(vehicle)
    local deadline = GetGameTimer() + 450
    while GetGameTimer() < deadline and not NetworkHasControlOfEntity(vehicle) do
        Wait(0)
        NetworkRequestControlOfEntity(vehicle)
    end

    return NetworkHasControlOfEntity(vehicle)
end

local function safeHandlingFloat(vehicle, field, fallback)
    local ok, value = pcall(GetVehicleHandlingFloat, vehicle, 'CHandlingData', field)
    value = ok and tonumber(value) or nil
    if value == nil or value ~= value then return fallback or 0.0 end
    return value
end

local function captureHandlingOriginal(vehicle)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return nil end
    local model = GetEntityModel(vehicle)
    local cached = handlingOriginais[vehicle]
    if cached and cached.model == model then return cached end

    local com = GetVehicleHandlingVector(vehicle, 'CHandlingData', 'vecCentreOfMassOffset')
    local original = {
        model = model,
        lowSpeedTractionLoss = safeHandlingFloat(vehicle, 'fLowSpeedTractionLossMult', 1.0),
        tractionCurveMin = safeHandlingFloat(vehicle, 'fTractionCurveMin', 1.8),
        tractionCurveMax = safeHandlingFloat(vehicle, 'fTractionCurveMax', 2.0),
        tractionLossMult = safeHandlingFloat(vehicle, 'fTractionLossMult', 1.0),
        initialDriveForce = safeHandlingFloat(vehicle, 'fInitialDriveForce', 0.30),
        antiRollBarForce = safeHandlingFloat(vehicle, 'fAntiRollBarForce', 0.0),
        rollCentreFront = safeHandlingFloat(vehicle, 'fRollCentreHeightFront', 0.0),
        rollCentreRear = safeHandlingFloat(vehicle, 'fRollCentreHeightRear', 0.0),
        centreOfMass = vector3(com.x, com.y, com.z)
    }
    handlingOriginais[vehicle] = original
    return original
end

local function applyFloat(vehicle, field, value)
    local ok = pcall(SetVehicleHandlingFloat, vehicle, 'CHandlingData', field, value + 0.0)
    return ok
end

local function applyHandlingProfile(vehicle, profile)
    if vehicle == 0 or not DoesEntityExist(vehicle) or not IsEntityAVehicle(vehicle) then return false end
    requestVehicleControl(vehicle)

    local original = captureHandlingOriginal(vehicle)
    if not original then return false end
    profile = normalizeHandlingProfile(profile)

    -- 0) POTÊNCIA DO MOTOR
    -- 50 = força original do handling. O slider altera somente a força de
    -- tração do motor, sem aumentar artificialmente a velocidade máxima.
    local powerValue = profile.potencia / 100.0
    local minPower = tonumber(FSPVehicle.Handling and FSPVehicle.Handling.PotenciaMinMultiplicador) or 0.70
    local maxPower = tonumber(FSPVehicle.Handling and FSPVehicle.Handling.PotenciaMaxMultiplicador) or 1.80
    local powerFactor
    if powerValue <= 0.5 then
        powerFactor = minPower + ((powerValue / 0.5) * (1.0 - minPower))
    else
        powerFactor = 1.0 + (((powerValue - 0.5) / 0.5) * (maxPower - 1.0))
    end
    applyFloat(vehicle, 'fInitialDriveForce', math.max(0.02, original.initialDriveForce * powerFactor))

    -- 1) ARRANCADA / PATINAÇÃO
    -- 50 = original. Para a direita, aumenta a aderência mecânica e reduz
    -- a perda de tração em baixa velocidade. Para a esquerda faz o inverso.
    local tractionT = (profile.arrancada - 50.0) / 50.0
    local curveFactor
    local lowLossFactor
    local generalLossFactor

    if tractionT >= 0.0 then
        curveFactor = 1.0 + (tractionT * 0.55)
        lowLossFactor = 1.0 - (tractionT * 0.90)
        generalLossFactor = 1.0 - (tractionT * 0.35)
    else
        local loose = -tractionT
        curveFactor = 1.0 - (loose * 0.30)
        lowLossFactor = 1.0 + (loose * 1.75)
        generalLossFactor = 1.0 + (loose * 0.45)
    end

    local curveMin = math.max(0.15, original.tractionCurveMin * curveFactor)
    local curveMax = math.max(curveMin + 0.05, original.tractionCurveMax * curveFactor)
    local lowLoss = math.max(0.0, original.lowSpeedTractionLoss * lowLossFactor)
    local tractionLoss = math.max(0.05, original.tractionLossMult * generalLossFactor)

    applyFloat(vehicle, 'fTractionCurveMin', curveMin)
    applyFloat(vehicle, 'fTractionCurveMax', curveMax)
    applyFloat(vehicle, 'fLowSpeedTractionLossMult', lowLoss)
    applyFloat(vehicle, 'fTractionLossMult', tractionLoss)

    -- 2) ROLAGEM LATERAL
    -- Slider: 0 = mais firme, 50 = original, 100 = mais inclinação.
    local rollT = (profile.rolagem - 50.0) / 50.0
    local antiRoll
    if rollT < 0.0 then
        local firm = -rollT
        local firmTarget = math.max(original.antiRollBarForce * 2.75, 0.85)
        antiRoll = original.antiRollBarForce + ((firmTarget - original.antiRollBarForce) * firm)
    else
        antiRoll = original.antiRollBarForce * (1.0 - (rollT * 0.90))
    end

    -- 3) ANTI-CAPOTAGEM
    -- Além de baixar o centro de massa, adiciona estabilização progressiva.
    local antiFlip = profile.antiCapotagem / 100.0
    local maxDrop = tonumber(FSPVehicle.Handling and FSPVehicle.Handling.AntiCapotagemMaxMetros) or 0.65
    local extraAntiRoll = antiFlip * math.max(0.90, original.antiRollBarForce * 1.40)
    local finalAntiRoll = math.max(0.0, antiRoll + extraAntiRoll)

    applyFloat(vehicle, 'fAntiRollBarForce', finalAntiRoll)

    -- Pequeno ajuste de roll centre junto do anti-capotagem para tornar o efeito
    -- perceptível também em SUVs/viaturas altas com COM muito elevado.
    local rollCentreLift = antiFlip * 0.10
    applyFloat(vehicle, 'fRollCentreHeightFront', original.rollCentreFront + rollCentreLift)
    applyFloat(vehicle, 'fRollCentreHeightRear', original.rollCentreRear + rollCentreLift)

    local drop = antiFlip * maxDrop
    local com = original.centreOfMass
    pcall(SetVehicleHandlingVector, vehicle, 'CHandlingData', 'vecCentreOfMassOffset', vector3(com.x, com.y, com.z - drop))

    -- Força o jogo a reavaliar o handling sem reiniciar o veículo/resource.
    pcall(ModifyVehicleTopSpeed, vehicle, 1.0)

    return true
end

local function restoreHandlingOriginal(vehicle)
    local original = handlingOriginais[vehicle]
    if not original or vehicle == 0 or not DoesEntityExist(vehicle) then return false end
    requestVehicleControl(vehicle)
    applyFloat(vehicle, 'fLowSpeedTractionLossMult', original.lowSpeedTractionLoss)
    applyFloat(vehicle, 'fTractionCurveMin', original.tractionCurveMin)
    applyFloat(vehicle, 'fTractionCurveMax', original.tractionCurveMax)
    applyFloat(vehicle, 'fTractionLossMult', original.tractionLossMult)
    applyFloat(vehicle, 'fInitialDriveForce', original.initialDriveForce)
    applyFloat(vehicle, 'fAntiRollBarForce', original.antiRollBarForce)
    applyFloat(vehicle, 'fRollCentreHeightFront', original.rollCentreFront)
    applyFloat(vehicle, 'fRollCentreHeightRear', original.rollCentreRear)
    pcall(SetVehicleHandlingVector, vehicle, 'CHandlingData', 'vecCentreOfMassOffset', original.centreOfMass)
    pcall(ModifyVehicleTopSpeed, vehicle, 1.0)
    return true
end

local function rebuildHandlingHash()
    handlingPerfisHash = {}
    for model, profile in pairs(handlingPerfis or {}) do
        handlingPerfisHash[joaat(model)] = normalizeHandlingProfile(profile)
    end
end

local function applySavedProfileToVehicle(vehicle)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return end
    local profile = handlingPerfisHash[GetEntityModel(vehicle)]
    if profile then applyHandlingProfile(vehicle, profile) end
end

local function closeHandlingPanel(revertPreview)
    if not handlingAberto then return end
    if revertPreview and handlingVeiculo ~= 0 and DoesEntityExist(handlingVeiculo) then
        local saved = handlingModelo and handlingPerfis[handlingModelo] or nil
        if saved then applyHandlingProfile(handlingVeiculo, saved) else restoreHandlingOriginal(handlingVeiculo) end
    end
    handlingAberto = false
    handlingVeiculo = 0
    handlingModelo = nil
    handlingPreview = nil
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ acao = 'handling:fechar' })
end

RegisterNetEvent('fivepd_sp:vehicle:handling:sync', function(profiles)
    local previous = handlingPerfis
    handlingPerfis = type(profiles) == 'table' and profiles or {}
    rebuildHandlingHash()

    -- Sincronização também reaplica o estado efetivo. Isso evita que uma
    -- prévia local fique diferente do perfil salvo no banco.
    for model in pairs(previous or {}) do
        if not handlingPerfis[model] then
            local hash = joaat(model)
            for _, vehicle in ipairs(GetGamePool('CVehicle')) do
                if DoesEntityExist(vehicle) and GetEntityModel(vehicle) == hash then
                    restoreHandlingOriginal(vehicle)
                end
            end
        end
    end

    for model, profile in pairs(handlingPerfis or {}) do
        local hash = joaat(model)
        for _, vehicle in ipairs(GetGamePool('CVehicle')) do
            if DoesEntityExist(vehicle) and GetEntityModel(vehicle) == hash then
                applyHandlingProfile(vehicle, profile)
            end
        end
    end
end)

RegisterNetEvent('fivepd_sp:vehicle:handling:abrir', function(data)
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 or GetPedInVehicleSeat(vehicle, -1) ~= ped then return end

    local model = tostring(data and data.model or ''):lower()
    if model == '' or GetEntityModel(vehicle) ~= joaat(model) then return end

    if extrasAberto then fecharExtras() end
    handlingAberto = true
    handlingVeiculo = vehicle
    handlingModelo = model
    handlingPreview = normalizeHandlingProfile(data and data.profile or nil)
    captureHandlingOriginal(vehicle)
    applyHandlingProfile(vehicle, handlingPreview)

    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    SetCursorLocation(0.82, 0.50)
    SendNUIMessage({
        acao = 'handling:abrir',
        model = model,
        profile = handlingPreview,
        hasProfile = data and data.hasProfile == true,
        presets = (FSPVehicle.Handling and FSPVehicle.Handling.Presets) or {}
    })

    CreateThread(function()
        while handlingAberto do
            Wait(300)
            if handlingVeiculo == 0 or not DoesEntityExist(handlingVeiculo) or not jogadorDirige(handlingVeiculo) then
                closeHandlingPanel(true)
                break
            end
        end
    end)
end)

RegisterNetEvent('fivepd_sp:vehicle:handling:salvo', function(model, profile)
    model = tostring(model or ''):lower()
    handlingPerfis[model] = normalizeHandlingProfile(profile)
    rebuildHandlingHash()
    if handlingAberto and handlingModelo == model then
        handlingPreview = normalizeHandlingProfile(profile)
        if handlingVeiculo ~= 0 and DoesEntityExist(handlingVeiculo) then
            applyHandlingProfile(handlingVeiculo, handlingPreview)
        end
        SendNUIMessage({ acao = 'handling:salvo', profile = handlingPreview })
    end
end)

RegisterNetEvent('fivepd_sp:vehicle:handling:restaurado', function(model, defaults)
    model = tostring(model or ''):lower()
    handlingPerfis[model] = nil
    rebuildHandlingHash()
    if handlingVeiculo ~= 0 and DoesEntityExist(handlingVeiculo) and handlingModelo == model then
        restoreHandlingOriginal(handlingVeiculo)
        handlingPreview = normalizeHandlingProfile(defaults)
        SendNUIMessage({ acao = 'handling:restaurado', profile = handlingPreview })
    end
end)

RegisterNetEvent('fivepd_sp:vehicle:handling:resultado', function(ok, titulo, mensagem)
    notificar(ok and 'sucesso' or 'erro', titulo or 'Handling', mensagem or 'Operação concluída.', ok and 4200 or 6200)
end)

RegisterNUICallback('previewHandling', function(data, cb)
    if not handlingAberto or handlingVeiculo == 0 or not jogadorDirige(handlingVeiculo) then
        cb({ok=false})
        return
    end
    handlingPreview = normalizeHandlingProfile(data and data.profile or nil)
    applyHandlingProfile(handlingVeiculo, handlingPreview)
    cb({ok=true})
end)

RegisterNUICallback('aplicarPresetHandling', function(data, cb)
    if not handlingAberto or handlingVeiculo == 0 or not jogadorDirige(handlingVeiculo) or not handlingModelo then
        cb({ok=false})
        return
    end

    local profile = normalizeHandlingProfile(data and data.profile or nil)
    handlingPreview = profile

    if not applyHandlingProfile(handlingVeiculo, profile) then
        cb({ok=false})
        return
    end

    -- Mantém o preset ativo mesmo se o painel for fechado antes do round-trip
    -- com o banco. Se o banco falhar, o servidor reenvia o perfil verdadeiro.
    handlingPerfis[handlingModelo] = profile
    rebuildHandlingHash()
    TriggerServerEvent('fivepd_sp:vehicle:handling:salvar', handlingModelo, profile)
    cb({ok=true})
end)

RegisterNUICallback('salvarHandling', function(data, cb)
    if not handlingAberto or handlingVeiculo == 0 or not jogadorDirige(handlingVeiculo) or not handlingModelo then
        cb({ok=false})
        return
    end
    handlingPreview = normalizeHandlingProfile(data and data.profile or handlingPreview)
    applyHandlingProfile(handlingVeiculo, handlingPreview)
    handlingPerfis[handlingModelo] = handlingPreview
    rebuildHandlingHash()
    TriggerServerEvent('fivepd_sp:vehicle:handling:salvar', handlingModelo, handlingPreview)
    cb({ok=true})
end)

RegisterNUICallback('restaurarHandling', function(_, cb)
    if not handlingAberto or handlingVeiculo == 0 or not jogadorDirige(handlingVeiculo) or not handlingModelo then
        cb({ok=false})
        return
    end
    TriggerServerEvent('fivepd_sp:vehicle:handling:restaurar', handlingModelo)
    cb({ok=true})
end)

RegisterNUICallback('fecharHandling', function(_, cb)
    closeHandlingPanel(true)
    cb({ok=true})
end)

RegisterCommand(
    (FSPVehicle.Handling and FSPVehicle.Handling.Comando) or 'handling2',
    function()
        if not exports.fivepd_sp_core:PersonagemCarregado() then return end
        local ped = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)
        if vehicle == 0 or not DoesEntityExist(vehicle) then
            notificar('erro', 'Handling', 'Entre na viatura que deseja configurar.', 3500)
            return
        end
        if GetPedInVehicleSeat(vehicle, -1) ~= ped then
            notificar('erro', 'Handling', 'Você precisa estar no banco do motorista.', 3500)
            return
        end
        local model = vehicleModelName(vehicle)
        if not model then
            notificar('erro', 'Handling', 'Não consegui identificar o spawn name desta viatura.', 4500)
            return
        end
        TriggerServerEvent('fivepd_sp:vehicle:handling:abrirRequest', model)
    end,
    false
)

CreateThread(function()
    Wait(1500)
    TriggerServerEvent('fivepd_sp:vehicle:handling:syncRequest')
    local interval = tonumber(FSPVehicle.Handling and FSPVehicle.Handling.IntervaloAplicacaoMs) or 1500
    if interval < 500 then interval = 500 end
    while true do
        Wait(interval)
        if next(handlingPerfisHash) then
            for _, vehicle in ipairs(GetGamePool('CVehicle')) do
                if DoesEntityExist(vehicle) then
                    local profile = handlingPerfisHash[GetEntityModel(vehicle)]
                    if profile then applyHandlingProfile(vehicle, profile) end
                end
            end
        end
    end
end)

