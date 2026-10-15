local pedStates = {}
local playerInfractionStates = {}
local currentPed = nil
local radialOpen = false
local radialMode = nil
local radialContext = nil
local interactionRegistered = false
local vehicleIdentificationInteractionRegistered = false
local primaryPedInteractionRegistered = false
local escortedPed = nil
local escortRequestSeq = 0
local pendingEscortRequests = {}
local escortHelpVisible = false
local escortHelpRefreshAt = 0
local placementActive = false
local placementPed = nil
local placementPoint = nil
local placementHelpVisible = false
local pedDocumentFallback = {}
local openPostSearchRadial
local searchClaimSeq = 0
local pendingSearchClaims = {}
local armedNpcThreats = {}
local armedNpcKillClaims = {}

local CUFF_DICT = 'mp_arresting'
local CUFF_ANIM = 'idle'
local DIALOG_DICT = 'gestures@m@standing@casual'
local CUFF_PAIR_DICT = 'mp_arrest_paired'
local CUFF_OFFICER_ANIM = 'cop_p2_back_left'
local CUFF_SUSPECT_ANIM = 'crook_p2_back_left'
local UNCUFF_DICT = 'mp_arresting'
local UNCUFF_ANIM = 'a_uncuff'
local SEARCH_OFFICER_DICT = 'custom@police'
local SEARCH_OFFICER_ANIM = 'police'
local SEARCH_FALLBACK_DICT = 'random@shop_robbery'
local SEARCH_FALLBACK_ANIM = 'robbery_action_b'
local HANDSUP_DICT = 'missminuteman_1ig_2'
local HANDSUP_ANIM = 'handsup_base'
local PLAYER_KNEEL_DICT = 'random@arrests'
local PLAYER_KNEEL_ANIM = 'kneeling_arrest_idle'
local RELEASE_ESCORT_CONTROL = 20 -- Z / INPUT_MULTIPLAYER_INFO
local ESCORT_PLAYER_DICT = 'amb@world_human_drinking@coffee@male@base'
local ESCORT_PLAYER_ANIM = 'base'

local function onDuty()
    local state = LocalPlayer and LocalPlayer.state or nil
    local characterType = state and tostring(state['fivepd_sp:personagemTipo'] or '') or ''

    -- Desde o fluxo de serviço automático, todo personagem policial é
    -- considerado operacional enquanto estiver carregado. A antiga flag
    -- pmEmServico continua existindo para sincronização de unidade/roster,
    -- mas não pode mais esconder as interações básicas do policial.
    if characterType == 'policial' then return true end
    if characterType == 'ilegal' then return false end

    if state and state['fivepd_sp:pmEmServico'] == true then return true end

    if GetResourceState('fivepd_sp_pm') == 'started' then
        local ok, duty = pcall(function()
            return exports.fivepd_sp_pm:EmServicoLocal()
        end)
        if ok and duty == true then return true end
    end

    return false
end

local function rememberArmedNpcThreat(ped)
    if not onDuty() or not ped or ped == 0 or not DoesEntityExist(ped) or not IsEntityAPed(ped) or IsPedAPlayer(ped) then return end
    if not NetworkGetEntityIsNetworked(ped) then return end

    local weapon = GetSelectedPedWeapon(ped)
    local armed = IsPedArmed(ped, 7) or (weapon and weapon ~= 0 and weapon ~= joaat('WEAPON_UNARMED'))
    if not armed then return end

    local playerPed = PlayerPedId()
    local relationship = GetRelationshipBetweenPeds(ped, playerPed)
    local threat = IsPedInCombat(ped, playerPed) or IsPedShooting(ped) or (tonumber(relationship) or 0) >= 4
    if not threat then return end

    local netId = NetworkGetNetworkIdFromEntity(ped)
    if netId and netId > 0 then
        armedNpcThreats[netId] = {
            seenAt = GetGameTimer(),
            weapon = tonumber(weapon) or 0
        }
    end
end

AddEventHandler('gameEventTriggered', function(name, args)
    if name ~= 'CEventNetworkEntityDamage' or not onDuty() or type(args) ~= 'table' then return end
    local victim = tonumber(args[1]) or 0
    local attacker = tonumber(args[2]) or 0
    local playerPed = PlayerPedId()

    if victim ~= 0 and DoesEntityExist(victim) and IsEntityAPed(victim) and not IsPedAPlayer(victim) then
        rememberArmedNpcThreat(victim)
    end
    if attacker ~= 0 and attacker ~= playerPed and DoesEntityExist(attacker) and IsEntityAPed(attacker) and not IsPedAPlayer(attacker) then
        rememberArmedNpcThreat(attacker)
    end

    if attacker ~= playerPed or victim == 0 or not DoesEntityExist(victim) or not IsEntityAPed(victim) or IsPedAPlayer(victim) then return end
    if not NetworkGetEntityIsNetworked(victim) then return end

    local netId = NetworkGetNetworkIdFromEntity(victim)
    if not netId or netId <= 0 or armedNpcKillClaims[netId] then return end
    local threat = armedNpcThreats[netId]
    if not threat or GetGameTimer() - (threat.seenAt or 0) > 45000 then return end

    CreateThread(function()
        Wait(80)
        if not DoesEntityExist(victim) or not IsEntityDead(victim) then return end
        if armedNpcKillClaims[netId] then return end
        armedNpcKillClaims[netId] = GetGameTimer()
        TriggerServerEvent('fivepd_sp:police:armedNpcNeutralized', netId, {
            armed = true,
            threat = true,
            weapon = threat.weapon
        })
        CreateThread(function()
            Wait(15 * 60 * 1000)
            armedNpcKillClaims[netId] = nil
            armedNpcThreats[netId] = nil
        end)
    end)
end)

local function notify(kind, title, description)
    TriggerEvent('fivepd_sp:ui:notificar', {
        tipo = kind or 'info',
        titulo = title or 'Abordagem',
        descricao = description or '',
        duracao = 4200
    })
end

local function showEscortHelp(force)
    local now = GetGameTimer()
    if not force and escortHelpVisible and now < escortHelpRefreshAt then return end
    escortHelpVisible = true
    escortHelpRefreshAt = now + 650
    TriggerEvent('fivepd_sp:ui:ajuda:mostrar', {
        tecla = 'Z',
        texto = 'Soltar pessoa',
        detalhe = 'Condução policial'
    })
end

local function hideEscortHelp()
    if not escortHelpVisible then return end
    escortHelpVisible = false
    escortHelpRefreshAt = 0
    TriggerEvent('fivepd_sp:ui:ajuda:ocultar')
end

local function showPlacementHelp()
    if placementHelpVisible then return end
    placementHelpVisible = true
    TriggerEvent('fivepd_sp:ui:ajuda:mostrar', {
        tecla = 'E',
        texto = 'Confirmar local',
        detalhe = 'Z • Cancelar'
    })
end

local function hidePlacementHelp()
    if not placementHelpVisible then return end
    placementHelpVisible = false
    TriggerEvent('fivepd_sp:ui:ajuda:ocultar')
end

local function startProgress(title, description, duration, onTick)
    if GetResourceState('fivepd_sp_ui') ~= 'started' then return nil end
    local ok, id = pcall(function()
        return exports.fivepd_sp_ui:IniciarProgresso({
            titulo = title or 'Aguarde',
            descricao = description or '',
            dica = '',
            progresso = 0
        })
    end)
    if not ok then return nil end
    local startedAt = GetGameTimer()
    duration = math.max(1, tonumber(duration) or 1000)
    while GetGameTimer() - startedAt < duration do
        local elapsed = GetGameTimer() - startedAt
        local percent = math.min(100, math.floor((elapsed / duration) * 100))
        if onTick then pcall(onTick, elapsed, percent) end
        pcall(function() exports.fivepd_sp_ui:AtualizarProgresso(id, percent, {}) end)
        Wait(20)
    end
    pcall(function() exports.fivepd_sp_ui:AtualizarProgresso(id, 100, {}) end)
    pcall(function() exports.fivepd_sp_ui:FinalizarProgresso(id, true, description or '') end)
    return id
end

local function rotationToDirection(rotation)
    local rx = math.rad(rotation.x + 0.0)
    local rz = math.rad(rotation.z + 0.0)
    local cosX = math.abs(math.cos(rx))
    return vector3(-math.sin(rz) * cosX, math.cos(rz) * cosX, math.sin(rx))
end

local function placementCandidate(maxDistance)
    local camPos = GetGameplayCamCoord()
    local direction = rotationToDirection(GetGameplayCamRot(2))
    local distance = maxDistance or (Config.Interaction.placeMaxDistance or 12.0)
    local destination = camPos + direction * distance
    local handle = StartShapeTestRay(camPos.x, camPos.y, camPos.z, destination.x, destination.y, destination.z, 17, PlayerPedId(), 7)
    local _, hit, endCoords = GetShapeTestResult(handle)
    local point = hit == 1 and endCoords or destination

    local probeZ = point.z + 8.0
    local foundGround, groundZ = GetGroundZFor_3dCoord(point.x, point.y, probeZ, false)
    if foundGround then
        point = vector3(point.x, point.y, groundZ)
    end

    local playerCoords = GetEntityCoords(PlayerPedId())
    if #(point - playerCoords) > distance + 1.0 then return nil end
    return point
end

local function requestControl(entity, timeout)
    if entity == 0 or not DoesEntityExist(entity) then return false end
    if not NetworkGetEntityIsNetworked(entity) then return true end
    timeout = timeout or 1300
    local untilAt = GetGameTimer() + timeout
    NetworkRequestControlOfEntity(entity)
    while not NetworkHasControlOfEntity(entity) and GetGameTimer() < untilAt do
        NetworkRequestControlOfEntity(entity)
        Wait(0)
    end
    return NetworkHasControlOfEntity(entity)
end

local function requestAnim(dict)
    RequestAnimDict(dict)
    local untilAt = GetGameTimer() + 2500
    while not HasAnimDictLoaded(dict) and GetGameTimer() < untilAt do Wait(15) end
    return HasAnimDictLoaded(dict)
end

local escortPlayerAnimActive = false
local playerEscortOfficerActive = false

local function stopEscortPlayerAnim()
    local player = PlayerPedId()
    if player ~= 0 and DoesEntityExist(player) then
        -- Nunca use ClearPedSecondaryTask aqui. A animação de condução pelo
        -- braço usa a camada secondary e esse native também apagava rádio,
        -- emotes e qualquer outra animação upper-body do jogador.
        -- Paramos exclusivamente o clipe pertencente à condução.
        if escortPlayerAnimActive or IsEntityPlayingAnim(player, ESCORT_PLAYER_DICT, ESCORT_PLAYER_ANIM, 3) then
            StopAnimTask(player, ESCORT_PLAYER_DICT, ESCORT_PLAYER_ANIM, 2.0)
        end
    end
    escortPlayerAnimActive = false
end

local function ensureEscortPlayerAnim()
    local player = PlayerPedId()
    if player == 0 or not DoesEntityExist(player) or IsEntityDead(player) then
        escortPlayerAnimActive = false
        return false
    end
    if IsPedInAnyVehicle(player, false) or radialOpen then
        stopEscortPlayerAnim()
        return false
    end
    if requestAnim(ESCORT_PLAYER_DICT) then
        if not IsEntityPlayingAnim(player, ESCORT_PLAYER_DICT, ESCORT_PLAYER_ANIM, 3) then
            TaskPlayAnim(player, ESCORT_PLAYER_DICT, ESCORT_PLAYER_ANIM, 3.0, -3.0, -1, 49, 0.0, false, false, false)
        end
        escortPlayerAnimActive = true
        return true
    end
    escortPlayerAnimActive = false
    return false
end

local function stopEscortPrisonerAnim(ped)
    -- A condução não possui animação própria no conduzido. Mantemos exatamente
    -- o mesmo idle de algemado usado fora da condução.
end

local function ensureEscortPrisonerAnim(ped, officer)
    if ped == 0 or not DoesEntityExist(ped) or officer == 0 or not DoesEntityExist(officer) then return false end
    if IsPedInAnyVehicle(ped, false) or IsPedInAnyVehicle(officer, false) then return false end
    SetEnableHandcuffs(ped, true)
    SetPedCanPlayGestureAnims(ped, false)
    if requestAnim(CUFF_DICT) and not IsEntityPlayingAnim(ped, CUFF_DICT, CUFF_ANIM, 3) then
        TaskPlayAnim(ped, CUFF_DICT, CUFF_ANIM, 4.0, -4.0, -1, 49, 0.0, false, false, false)
    end
    return true
end

local function faceSameHeading(entity, heading)
    if entity ~= 0 and DoesEntityExist(entity) then
        SetEntityHeading(entity, heading + 0.0)
    end
end

local function headingDelta(a, b)
    local delta = (b - a + 180.0) % 360.0 - 180.0
    return math.abs(delta)
end

local function desiredHeadingToEntity(fromEntity, toEntity)
    local from = GetEntityCoords(fromEntity)
    local to = GetEntityCoords(toEntity)
    return GetHeadingFromVector_2d(to.x - from.x, to.y - from.y)
end

local function alignForCuffAnimation(ped)
    local officer = PlayerPedId()
    if not DoesEntityExist(officer) or not DoesEntityExist(ped) then return end
    local heading = GetEntityHeading(officer)
    local target = GetOffsetFromEntityInWorldCoords(officer, 0.0, 0.72, 0.0)
    TaskGoStraightToCoord(ped, target.x, target.y, target.z, 1.0, 1200, heading, 0.18)
    local untilAt = GetGameTimer() + 1100
    while DoesEntityExist(ped) and not IsEntityDead(ped) and #(GetEntityCoords(ped) - target) > 0.28 and GetGameTimer() < untilAt do
        Wait(25)
    end
    if DoesEntityExist(ped) then
        SetEntityCoordsNoOffset(ped, target.x, target.y, target.z, false, false, false)
        faceSameHeading(ped, heading)
    end
end

local function playCuffTransition(ped, cuffing)
    local officer = PlayerPedId()
    if not DoesEntityExist(officer) or not DoesEntityExist(ped) then return false end
    ClearPedSecondaryTask(officer)

    if cuffing then
        if not requestAnim(CUFF_PAIR_DICT) then return false end
        alignForCuffAnimation(ped)
        local heading = GetEntityHeading(officer)
        faceSameHeading(ped, heading)

        -- A animação pareada precisa tocar como animação primária até o fim.
        -- Flags 32/33 a colocavam como secondary/looping e o GTA podia
        -- interromper o suspeito antes da conclusão, causando o passo/slide
        -- visto antes de entrar no idle algemado.
        TaskPlayAnim(officer, CUFF_PAIR_DICT, CUFF_OFFICER_ANIM, 8.0, -8.0, 3750, 2, 0.0, false, false, false)
        TaskPlayAnim(ped, CUFF_PAIR_DICT, CUFF_SUSPECT_ANIM, 8.0, -8.0, 3750, 2, 0.0, false, false, false)

        local timeoutAt = GetGameTimer() + 4100
        local started = false
        while DoesEntityExist(ped) and not IsEntityDead(ped) and GetGameTimer() < timeoutAt do
            local playing = IsEntityPlayingAnim(ped, CUFF_PAIR_DICT, CUFF_SUSPECT_ANIM, 3)
            if playing then
                started = true
                if GetEntityAnimCurrentTime(ped, CUFF_PAIR_DICT, CUFF_SUSPECT_ANIM) >= 0.96 then break end
            elseif started then
                break
            end
            Wait(0)
        end

        ClearPedSecondaryTask(officer)
        return true
    end

    if not requestAnim(UNCUFF_DICT) then return false end
    TaskTurnPedToFaceEntity(officer, ped, 450)
    Wait(250)
    TaskPlayAnim(officer, UNCUFF_DICT, UNCUFF_ANIM, 8.0, -8.0, 2400, 48, 0.0, false, false, false)
    Wait(2300)
    ClearPedSecondaryTask(officer)
    return true
end

local function playSearchOfficer(officer)
    if requestAnim(SEARCH_OFFICER_DICT) then
        -- Loop contínuo durante toda a revista. A animação só é removida
        -- depois que a barra de progresso termina.
        TaskPlayAnim(officer, SEARCH_OFFICER_DICT, SEARCH_OFFICER_ANIM, 6.0, -6.0, -1, 49, 0.0, false, false, false)
        return SEARCH_OFFICER_DICT, SEARCH_OFFICER_ANIM
    end
    if requestAnim(SEARCH_FALLBACK_DICT) then
        TaskPlayAnim(officer, SEARCH_FALLBACK_DICT, SEARCH_FALLBACK_ANIM, 6.0, -6.0, -1, 49, 0.0, false, false, false)
        return SEARCH_FALLBACK_DICT, SEARCH_FALLBACK_ANIM
    end
    return nil, nil
end

local function isValidNpc(ped)
    -- IMPORTANTE: não validar o handle com type(ped) == 'number'.
    -- O fluxo do ox_target já entrega um handle válido para as natives e essa
    -- checagem extra já bloqueou todos os NPCs no passado. Mantemos aqui a
    -- lógica simples e comprovada que funcionava antes.
    return ped and ped ~= 0
        and DoesEntityExist(ped)
        and IsEntityAPed(ped)
        and not IsPedAPlayer(ped)
        and not IsEntityDead(ped)
        and IsPedHuman(ped)
end

local function isValidHumanPed(ped)
    return ped and ped ~= 0
        and DoesEntityExist(ped)
        and IsEntityAPed(ped)
        and not IsEntityDead(ped)
        and IsPedHuman(ped)
end

local function bagValue(ped, key)
    if not NetworkGetEntityIsNetworked(ped) then return nil end
    local ok, value = pcall(function()
        return Entity(ped).state[('fivepd_sp:police:%s'):format(key)]
    end)
    return ok and value or nil
end

local function bagNumber(ped, key)
    local value = bagValue(ped, key)
    value = tonumber(value)
    return value
end

local function localServerId()
    return GetPlayerServerId(PlayerId())
end

local function stateFor(ped)
    local st = pedStates[ped]
    if st then return st end

    local targetX = bagNumber(ped, 'targetX')
    local targetY = bagNumber(ped, 'targetY')
    local targetZ = bagNumber(ped, 'targetZ')
    local hasTarget = targetX and targetY and targetZ
        and (math.abs(targetX) > 0.0001 or math.abs(targetY) > 0.0001 or math.abs(targetZ) > 0.0001)

    st = {
        approached = bagValue(ped, 'approached') == true,
        cuffed = bagValue(ped, 'cuffed') == true,
        seated = bagValue(ped, 'seated') == true,
        following = bagValue(ped, 'following') == true,
        held = bagValue(ped, 'held') == true,
        insideVehicle = bagValue(ped, 'insideVehicle') == true,
        preventive = bagValue(ped, 'preventive') == true,
        movingToPoint = bagValue(ped, 'movingToPoint') == true,
        placedAtPoint = bagValue(ped, 'placedAtPoint') == true,
        searching = bagValue(ped, 'searching') == true,
        handsUp = bagValue(ped, 'handsUp') == true,
        kneeling = bagValue(ped, 'kneeling') == true,
        searchOwner = bagNumber(ped, 'searchOwner') or 0,
        controller = bagNumber(ped, 'controller') or 0,
        stateOwner = bagNumber(ped, 'stateOwner') or 0,
        vehicleNetId = bagNumber(ped, 'vehicleNetId') or 0,
        vehicleSeat = bagNumber(ped, 'vehicleSeat') or 0,
        escortAnchorNetId = bagNumber(ped, 'escortAnchorNetId') or 0,
        enteringVehicle = false,
        lastFollowTask = 0,
        lastHoldPositionTask = 0,
        lastFaceTask = 0,
        busyUntil = 0,
        dialogueToken = 0,
        dialogueFrozen = false,
        targetPoint = hasTarget and vector3(targetX, targetY, targetZ) or nil,
        positionLocked = false,
        moveUntil = 0,
        lastPointHoldTask = 0,
        placementNetId = nil,
        placementMigrationLocked = false,
        customSearchActive = false,
        inventorySearchToken = 0,
        sharedRefreshAt = 0,
        sharedAppliedAt = 0,
        preventiveApplied = false
    }
    pedStates[ped] = st
    return st
end

local function refreshSharedState(ped, st)
    if not st or not NetworkGetEntityIsNetworked(ped) then return st end
    st.approached = bagValue(ped, 'approached') == true
    st.cuffed = bagValue(ped, 'cuffed') == true
    st.seated = bagValue(ped, 'seated') == true
    st.following = bagValue(ped, 'following') == true
    st.held = bagValue(ped, 'held') == true
    st.insideVehicle = bagValue(ped, 'insideVehicle') == true
    st.preventive = bagValue(ped, 'preventive') == true
    st.movingToPoint = bagValue(ped, 'movingToPoint') == true
    st.placedAtPoint = bagValue(ped, 'placedAtPoint') == true
    st.searching = bagValue(ped, 'searching') == true
    st.handsUp = bagValue(ped, 'handsUp') == true
    st.kneeling = bagValue(ped, 'kneeling') == true
    st.searchOwner = bagNumber(ped, 'searchOwner') or 0
    st.controller = bagNumber(ped, 'controller') or 0
    st.stateOwner = bagNumber(ped, 'stateOwner') or 0
    st.vehicleNetId = bagNumber(ped, 'vehicleNetId') or 0
    st.vehicleSeat = bagNumber(ped, 'vehicleSeat') or 0
    st.escortAnchorNetId = bagNumber(ped, 'escortAnchorNetId') or 0

    local x = bagNumber(ped, 'targetX')
    local y = bagNumber(ped, 'targetY')
    local z = bagNumber(ped, 'targetZ')
    if x and y and z and (math.abs(x) > 0.0001 or math.abs(y) > 0.0001 or math.abs(z) > 0.0001) then
        st.targetPoint = vector3(x, y, z)
    elseif not st.placedAtPoint and not st.movingToPoint then
        st.targetPoint = nil
    end
    st.sharedRefreshAt = GetGameTimer()
    return st
end

local function hasSharedPoliceState(ped)
    return bagValue(ped, 'approached') == true
        or bagValue(ped, 'cuffed') == true
        or bagValue(ped, 'seated') == true
        or bagValue(ped, 'following') == true
        or bagValue(ped, 'held') == true
        or bagValue(ped, 'insideVehicle') == true
        or bagValue(ped, 'preventive') == true
        or bagValue(ped, 'placedAtPoint') == true
        or bagValue(ped, 'movingToPoint') == true
        or bagValue(ped, 'searching') == true
        or bagValue(ped, 'handsUp') == true
        or bagValue(ped, 'kneeling') == true
end

local function sharedStateActive(st)
    return st and (
        st.approached == true
        or st.cuffed == true
        or st.seated == true
        or st.following == true
        or st.held == true
        or st.insideVehicle == true
        or st.preventive == true
        or st.placedAtPoint == true
        or st.movingToPoint == true
        or st.searching == true
        or st.handsUp == true
        or st.kneeling == true
    )
end

local function canDriveSharedPed(ped)
    return not NetworkGetEntityIsNetworked(ped) or NetworkHasControlOfEntity(ped)
end

local function controllerPed(st)
    if not st then return 0 end
    local serverId = tonumber(st.controller) or 0
    if serverId <= 0 then return 0 end
    if serverId == localServerId() then return PlayerPedId() end
    local player = GetPlayerFromServerId(serverId)
    if not player or player < 0 then return 0 end
    local ped = GetPlayerPed(player)
    if ped == 0 or not DoesEntityExist(ped) then return 0 end
    return ped
end

local function stateOwnerPed(st)
    if not st then return 0 end
    local serverId = tonumber(st.stateOwner) or 0
    if serverId <= 0 then return 0 end
    if serverId == localServerId() then return PlayerPedId() end
    local player = GetPlayerFromServerId(serverId)
    if not player or player < 0 then return 0 end
    local ped = GetPlayerPed(player)
    if ped == 0 or not DoesEntityExist(ped) then return 0 end
    return ped
end

-- NPCs ambientes nem sempre chegam como net objects. Qualquer estado de
-- custódia que precise ser visto por outros jogadores deve primeiro promover o
-- ped para uma entidade networked, para que as state bags do servidor existam.
function FivePD_EnsureCustodyNpcNetworked(ped)
    if ped == 0 or not DoesEntityExist(ped) or IsPedAPlayer(ped) then return 0 end
    if NetworkGetEntityIsNetworked(ped) then
        local existing = NetworkGetNetworkIdFromEntity(ped)
        return existing and existing > 0 and existing or 0
    end

    requestControl(ped, 900)
    NetworkRegisterEntityAsNetworked(ped)
    local untilAt = GetGameTimer() + 900
    while not NetworkGetEntityIsNetworked(ped) and GetGameTimer() < untilAt do Wait(0) end
    if not NetworkGetEntityIsNetworked(ped) then return 0 end

    local netId = NetworkGetNetworkIdFromEntity(ped)
    if netId and netId > 0 then
        SetNetworkIdCanMigrate(netId, true)
        SetEntityAsMissionEntity(ped, true, false)
        return netId
    end
    return 0
end

local function syncState(ped, patch)
    local st = stateFor(ped)
    if not NetworkGetEntityIsNetworked(ped) then
        local wantsShared = patch.cuffed == true or patch.held == true or patch.following == true
            or patch.approached == true or patch.handsUp == true or patch.kneeling == true
            or patch.insideVehicle == true or patch.searching == true
        if wantsShared then FivePD_EnsureCustodyNpcNetworked(ped) end
    end
    st.sharedRefreshAt = GetGameTimer()

    local takesPrimaryLocal = false
    for key, value in pairs(patch) do
        if key ~= 'searching'
            and key ~= 'targetX' and key ~= 'targetY' and key ~= 'targetZ'
            and key ~= 'vehicleNetId' and key ~= 'vehicleSeat'
            and value == true and st[key] ~= true then
            takesPrimaryLocal = true
            break
        end
    end

    for key, value in pairs(patch) do
        if key == 'targetX' or key == 'targetY' or key == 'targetZ' then
            -- As coordenadas são reconstituídas abaixo para evitar guardar
            -- componentes parciais como estado local.
        else
            st[key] = value
        end
    end

    local tx = patch.targetX
    local ty = patch.targetY
    local tz = patch.targetZ
    if tx ~= nil or ty ~= nil or tz ~= nil then
        tx = tonumber(tx) or (st.targetPoint and st.targetPoint.x) or 0.0
        ty = tonumber(ty) or (st.targetPoint and st.targetPoint.y) or 0.0
        tz = tonumber(tz) or (st.targetPoint and st.targetPoint.z) or 0.0
        if math.abs(tx) > 0.0001 or math.abs(ty) > 0.0001 or math.abs(tz) > 0.0001 then
            st.targetPoint = vector3(tx, ty, tz)
        elseif patch.placedAtPoint == false and patch.movingToPoint == false then
            st.targetPoint = nil
        end
    end

    if patch.following == true or patch.held == true then
        st.controller = localServerId()
    elseif (patch.following ~= nil or patch.held ~= nil)
        and st.following ~= true and st.held ~= true
        and (tonumber(st.controller) or 0) == localServerId() then
        st.controller = 0
    end

    if patch.searching == true then
        st.searchOwner = localServerId()
    elseif patch.searching == false and (tonumber(st.searchOwner) or 0) == localServerId() then
        st.searchOwner = 0
    end

    if patch.following == true or patch.held == true then
        takesPrimaryLocal = true
    end
    if takesPrimaryLocal then st.stateOwner = localServerId() end

    if NetworkGetEntityIsNetworked(ped) then
        local netId = NetworkGetNetworkIdFromEntity(ped)
        if netId and netId > 0 then TriggerServerEvent('fivepd_sp:police:ped:state', netId, patch) end
    end
end


-- ---------------------------------------------------------------------------
-- Props locais de algema
-- ---------------------------------------------------------------------------
-- Cada cliente cria uma cópia local do prop para qualquer ped algemado que
-- esteja próximo. O estado de "cuffed" continua sendo o estado de rede já
-- usado pelo FivePD; portanto não criamos uma entidade networked extra para
-- cada par de algemas e evitamos duplicações/ownership disputado entre players.
local cuffProps = {}
local resolvedCuffPropHash = nil
local resolvedCuffPropName = nil

local function cuffPropConfig()
    return type(Config.CuffProp) == 'table' and Config.CuffProp or {}
end

local function requestCuffPropModel(hash, timeoutMs)
    if not hash or hash == 0 then return false end
    if HasModelLoaded(hash) then return true end
    RequestModel(hash)
    local untilAt = GetGameTimer() + (tonumber(timeoutMs) or 1800)
    while not HasModelLoaded(hash) and GetGameTimer() < untilAt do
        Wait(20)
    end
    return HasModelLoaded(hash)
end

local function resolveCuffPropModel()
    local cfg = cuffPropConfig()
    if cfg.enabled == false then return nil end

    if resolvedCuffPropHash and requestCuffPropModel(resolvedCuffPropHash, 450) then
        return resolvedCuffPropHash
    end

    local models = type(cfg.models) == 'table' and cfg.models or { 'prop_cs_cuffs_01', 'p_cs_cuffs_02_s' }
    for _, name in ipairs(models) do
        name = tostring(name or '')
        if name ~= '' then
            local hash = joaat(name)
            if requestCuffPropModel(hash, 1200) then
                resolvedCuffPropHash = hash
                resolvedCuffPropName = name
                return hash
            end
        end
    end

    return nil
end

local function removeCuffProp(ped)
    local entry = cuffProps[ped]
    if not entry then return end
    local object = type(entry) == 'table' and entry.object or entry
    -- A tabela de props é local e normalmente só contém objetos. Ainda assim,
    -- validamos o tipo antes de apagar para nunca correr o risco de remover um
    -- ped caso um handle antigo seja reutilizado pelo jogo.
    if object and object ~= 0 and DoesEntityExist(object) and GetEntityType(object) == 3 then
        DetachEntity(object, true, true)
        SetEntityAsMissionEntity(object, true, true)
        DeleteEntity(object)
    end
    cuffProps[ped] = nil
end

local function pedIsCuffedForProp(ped)
    if not ped or ped == 0 or not DoesEntityExist(ped) or not IsEntityAPed(ped) then return false end
    local st = pedStates[ped]

    -- Quando este cliente é quem está dirigindo o estado daquele NPC, o valor
    -- local muda no mesmo frame da ação. Para entidades controladas por outros
    -- clientes, a state bag é a fonte de verdade e evita manter um prop antigo
    -- depois que outra pessoa remove as algemas.
    if st and ((tonumber(st.stateOwner) or 0) == localServerId() or not NetworkGetEntityIsNetworked(ped)) then
        return st.cuffed == true
    end

    local shared = bagValue(ped, 'cuffed')
    if shared ~= nil then return shared == true end
    return st and st.cuffed == true or false
end

local function ensureCuffProp(ped)
    local cfg = cuffPropConfig()
    if cfg.enabled == false or not pedIsCuffedForProp(ped) then
        removeCuffProp(ped)
        return false
    end

    local current = cuffProps[ped]
    if current and current.object and DoesEntityExist(current.object) then
        if IsEntityAttachedToEntity(current.object, ped) then return true end
        removeCuffProp(ped)
    end

    local hash = resolveCuffPropModel()
    if not hash then return false end

    local coords = GetEntityCoords(ped)
    local object = CreateObjectNoOffset(hash, coords.x, coords.y, coords.z, false, false, false)
    if not object or object == 0 or not DoesEntityExist(object) then return false end

    SetEntityAsMissionEntity(object, true, true)
    SetEntityCollision(object, false, false)
    SetEntityInvincible(object, true)
    SetEntityVisible(object, true, false)
    local off = type(cfg.rear) == 'table' and cfg.rear or {}
    local bone = GetPedBoneIndex(ped, tonumber(cfg.bone) or 60309)
    AttachEntityToEntity(
        object, ped, bone,
        tonumber(off.x) or -0.055, tonumber(off.y) or 0.060, tonumber(off.z) or 0.040,
        tonumber(off.rx) or 265.0, tonumber(off.ry) or 155.0, tonumber(off.rz) or 80.0,
        true, false, false, false, 0, true
    )

    -- Se o attachment falhar, o prop não deve ficar largado no chão. Além de
    -- ser visualmente incorreto, isso mascarava o problema fazendo parecer que
    -- o ped tinha sido substituído pelo objeto.
    if not IsEntityAttachedToEntity(object, ped) then
        SetEntityAsMissionEntity(object, true, true)
        DeleteEntity(object)
        SetModelAsNoLongerNeeded(hash)
        return false
    end

    cuffProps[ped] = { object = object, model = hash }
    SetModelAsNoLongerNeeded(hash)
    return true
end

local function clearAllCuffProps()
    local peds = {}
    for ped in pairs(cuffProps) do peds[#peds + 1] = ped end
    for _, ped in ipairs(peds) do removeCuffProp(ped) end
end

CreateThread(function()
    while true do
        local cfg = cuffPropConfig()
        if cfg.enabled == false then
            if next(cuffProps) then clearAllCuffProps() end
            Wait(1500)
        else
            local playerPed = PlayerPedId()
            local origin = GetEntityCoords(playerPed)
            local maxDistance = math.max(25.0, tonumber(cfg.maxRenderDistance) or 110.0)
            local maxDistanceSq = maxDistance * maxDistance
            local seen = {}

            for _, ped in ipairs(GetGamePool('CPed')) do
                if ped and ped ~= 0 and DoesEntityExist(ped) and IsEntityAPed(ped) and IsPedHuman(ped) then
                    local p = GetEntityCoords(ped)
                    local dx, dy, dz = p.x - origin.x, p.y - origin.y, p.z - origin.z
                    local closeEnough = (dx * dx + dy * dy + dz * dz) <= maxDistanceSq
                    if closeEnough and pedIsCuffedForProp(ped) then
                        seen[ped] = true
                        ensureCuffProp(ped)
                    elseif cuffProps[ped] then
                        removeCuffProp(ped)
                    end
                end
            end

            local stale = {}
            for ped in pairs(cuffProps) do
                if not seen[ped] or not DoesEntityExist(ped) or not pedIsCuffedForProp(ped) then
                    stale[#stale + 1] = ped
                end
            end
            for _, ped in ipairs(stale) do removeCuffProp(ped) end
            Wait(650)
        end
    end
end)

RegisterNetEvent('fivepd_sp:police:ped:searchClaimResult', function(requestId, granted)
    requestId = tonumber(requestId)
    local pending = requestId and pendingSearchClaims[requestId] or nil
    if not pending then return end
    pending.done = true
    pending.granted = granted == true
end)

local function claimSearchLock(ped)
    if not NetworkGetEntityIsNetworked(ped) then return true end
    local netId = NetworkGetNetworkIdFromEntity(ped)
    if not netId or netId <= 0 then return false end

    searchClaimSeq = searchClaimSeq + 1
    if searchClaimSeq > 2000000000 then searchClaimSeq = 1 end
    local requestId = searchClaimSeq
    local pending = { done = false, granted = false }
    pendingSearchClaims[requestId] = pending

    TriggerServerEvent('fivepd_sp:police:ped:searchClaim', netId, requestId)
    local timeoutAt = GetGameTimer() + 1800
    while not pending.done and GetGameTimer() < timeoutAt do Wait(10) end

    pendingSearchClaims[requestId] = nil
    if not pending.done or pending.granted ~= true then
        -- Se a resposta se perder depois de o servidor conceder a trava,
        -- esta limpeza só terá efeito caso a trava realmente pertença a nós.
        TriggerServerEvent('fivepd_sp:police:ped:state', netId, { searching = false })
        return false
    end
    return true
end

local function ensureCuffVisual(ped, st)
    if not st.cuffed or not isValidNpc(ped) then
        removeCuffProp(ped)
        return
    end

    -- Um ped sob custódia deixa de ser apenas população ambiente. Mantê-lo
    -- como mission entity impede o population manager de recolhê-lo durante
    -- trocas de task/animação, que era uma das situações em que o NPC podia
    -- desaparecer logo após a algemação.
    SetEntityAsMissionEntity(ped, true, false)
    -- Não use NetworkFadeInEntity aqui. Esta rotina é chamada continuamente
    -- enquanto o suspeito está algemado; reiniciar o fade a cada atualização
    -- fazia o ped alternar alpha e aparentar estar piscando.
    if not IsEntityVisible(ped) then SetEntityVisible(ped, true, false) end
    if GetEntityAlpha(ped) < 250 then ResetEntityAlpha(ped) end
    SetEntityCollision(ped, true, true)

    ensureCuffProp(ped)
    if st.customSearchActive then return end
    SetEnableHandcuffs(ped, true)
    SetPedCanPlayGestureAnims(ped, false)
    SetPedCanRagdoll(ped, false)
    -- Mesmo durante a condução o abordado mantém a animação original de
    -- algemado; o vínculo físico cuida somente da posição/orientação.
    if requestAnim(CUFF_DICT) and not IsEntityPlayingAnim(ped, CUFF_DICT, CUFF_ANIM, 3) then
        TaskPlayAnim(ped, CUFF_DICT, CUFF_ANIM, 4.0, -4.0, -1, 49, 0.0, false, false, false)
    end
end

local function stopCuffVisual(ped)
    removeCuffProp(ped)
    if ped == 0 or not DoesEntityExist(ped) then return end
    SetEnableHandcuffs(ped, false)
    SetPedCanPlayGestureAnims(ped, true)
    SetPedCanRagdoll(ped, true)
    StopAnimTask(ped, CUFF_DICT, CUFF_ANIM, 2.0)
end

local function acquirePlacedPedControl(ped, st, timeout)
    if ped == 0 or not DoesEntityExist(ped) or not st then return false end
    timeout = timeout or 900

    SetEntityAsMissionEntity(ped, true, true)
    local controlled = requestControl(ped, timeout)

    if NetworkGetEntityIsNetworked(ped) then
        local netId = NetworkGetNetworkIdFromEntity(ped)
        if netId and netId > 0 then
            st.placementNetId = netId
            NetworkRequestControlOfNetworkId(netId)
            -- Não bloqueamos a migração do network id. O estado do ponto é
            -- replicado pelo servidor e o próximo owner reaplica a trava.
            st.placementMigrationLocked = false
        end
    end

    return controlled or not NetworkGetEntityIsNetworked(ped)
end

local function releasePlacedPedControl(ped, st)
    if not st then return end
    st.placementMigrationLocked = false
    st.placementNetId = nil
end

local function setPlacedPositionLock(ped, st, enabled, snapToTarget)
    if ped == 0 or not DoesEntityExist(ped) or not st then return end
    if enabled then
        -- V32: reabrir o radial ou executar o mantenedor nao pode reiniciar a
        -- trava a cada frame. O ped precisa continuar processando seu idle.
        if st.positionLocked then
            local target = st.targetPoint
            if target and not st.searching and not st.seated and not st.held
                and not st.enteringVehicle and #(GetEntityCoords(ped) - target) > 0.90 then
                -- Corrige somente deslocamentos reais (ex.: migracao OneSync).
                SetEntityCoordsNoOffset(ped, target.x, target.y, target.z, false, false, false)
                SetEntityVelocity(ped, 0.0, 0.0, 0.0)
                FreezeEntityPosition(ped, true)
            end
            return
        end
        acquirePlacedPedControl(ped, st, 700)
        local target = st.targetPoint
        if target then
            local current = GetEntityCoords(ped)

            -- O ponto escolhido pelo raycast usa o Z do chão. Já a coordenada
            -- raiz do ped fica acima desse Z. Reutilizar o Z do chão em
            -- SetEntityCoordsNoOffset fazia a raiz do ped ser colocada dentro
            -- do piso ao reabrir a abordagem. Na primeira trava, preservamos o
            -- Z em que o navmesh deixou o ped naturalmente em pé.
            if not st.positionLocked and math.abs((current.z or 0.0) - (target.z or 0.0)) > 0.20 then
                target = vector3(target.x, target.y, current.z)
                st.targetPoint = target
            end

            if snapToTarget or #(current - target) > 0.035 then
                SetEntityCoordsNoOffset(ped, target.x, target.y, target.z, false, false, false)
            end
        end
        SetEntityVelocity(ped, 0.0, 0.0, 0.0)
        SetBlockingOfNonTemporaryEvents(ped, true)
        SetPedKeepTask(ped, true)
        SetPedFleeAttributes(ped, 0, false)
        FreezeEntityPosition(ped, true)
        st.positionLocked = true
    else
        if st.positionLocked then
            FreezeEntityPosition(ped, false)
        end
        st.positionLocked = false
        releasePlacedPedControl(ped, st)
    end
end

local function clearPlacedPoint(ped, st)
    if not st then return end
    local hadSharedPlacement = st.placedAtPoint == true or st.movingToPoint == true or st.targetPoint ~= nil
    setPlacedPositionLock(ped, st, false, false)
    st.placedAtPoint = false
    st.targetPoint = nil
    st.movingToPoint = false
    st.moveUntil = 0
    st.lastPointHoldTask = 0
    if hadSharedPlacement then
        syncState(ped, {
            placedAtPoint = false,
            movingToPoint = false,
            targetX = 0.0,
            targetY = 0.0,
            targetZ = 0.0
        })
    end
end

local function rotatePlacedPedToward(ped, desired)
    local current = GetEntityHeading(ped)
    local delta = (desired - current + 540.0) % 360.0 - 180.0
    if math.abs(delta) < 1.5 then return end
    local maxStep = 8.0
    local step = math.max(-maxStep, math.min(maxStep, delta))
    SetEntityHeading(ped, (current + step + 360.0) % 360.0)
end

local function turnApproachedPedNaturally(ped, st)
    if not isValidNpc(ped) or not st or not st.approached then return end
    -- Rendição é uma pose exclusiva. Não empilhamos TaskTurnPedToFaceEntity/
    -- TaskStandStill enquanto o NPC está com as mãos para cima/ajoelhado, pois
    -- isso disputa o task tree com a animação e causa o efeito de ficar
    -- virando/baixando os braços repetidamente.
    if st.handsUp or st.kneeling then return end
    if st.held or st.following or st.seated or st.insideVehicle or st.enteringVehicle or st.movingToPoint then return end
    if GetGameTimer() < (st.busyUntil or 0) then return end

    local player = stateOwnerPed(st)
    if player == 0 or not DoesEntityExist(player) or IsEntityDead(player) then return end
    local desired = desiredHeadingToEntity(ped, player)

    -- Quando a pessoa foi mandada permanecer em um ponto, a posição fica
    -- fisicamente travada para impedir a IA ambiente de reassumir a locomoção.
    -- O heading, porém, é interpolado em pequenos passos para ela continuar
    -- olhando naturalmente para o policial enquanto o radial está aberto.
    if st.placedAtPoint and st.targetPoint then
        setPlacedPositionLock(ped, st, true, false)
        rotatePlacedPedToward(ped, desired)
        return
    end

    if headingDelta(GetEntityHeading(ped), desired) < 11.0 then return end

    local now = GetGameTimer()
    if now - (st.lastFaceTask or 0) < 900 then return end
    st.lastFaceTask = now
    requestControl(ped, 250)
    TaskTurnPedToFaceEntity(ped, player, 700)
    CreateThread(function()
        Wait(720)
        if isValidNpc(ped) then
            local current = stateFor(ped)
            if current.approached and not current.held and not current.following and not current.seated and not current.insideVehicle and GetGameTimer() >= (current.busyUntil or 0) then
                TaskStandStill(ped, -1)
                current.lastHoldPositionTask = GetGameTimer()
                if current.cuffed then ensureCuffVisual(ped, current) end
            end
        end
    end)
end

local function turnPedBackToOfficerForSearch(ped, st)
    local officer = PlayerPedId()
    if not isValidNpc(ped) or officer == 0 or not DoesEntityExist(officer) then return false end

    requestControl(ped, 500)
    SetPedKeepTask(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)

    local desiredPedHeading = desiredHeadingToEntity(officer, ped)
    local untilAt = GetGameTimer() + 1450
    TaskAchieveHeading(ped, desiredPedHeading, 1200)
    TaskTurnPedToFaceEntity(officer, ped, 850)

    while isValidNpc(ped) and GetGameTimer() < untilAt do
        if headingDelta(GetEntityHeading(ped), desiredPedHeading) <= 9.0 then break end
        Wait(25)
    end

    TaskStandStill(ped, -1)
    st.lastHoldPositionTask = GetGameTimer()
    return true
end

function FivePD_DeleteEscortAnchor(anchor)
    anchor = tonumber(anchor) or 0
    if anchor ~= 0 and DoesEntityExist(anchor) then
        if IsEntityAttached(anchor) then DetachEntity(anchor, true, false) end
        SetEntityAsMissionEntity(anchor, true, true)
        DeleteEntity(anchor)
    end
end

function FivePD_ResolveEscortAnchor(st)
    if not st then return 0 end
    local localAnchor = tonumber(st.escortAnchor) or 0
    if localAnchor ~= 0 and DoesEntityExist(localAnchor) then return localAnchor end

    local netId = tonumber(st.escortAnchorNetId) or 0
    if netId > 0 and NetworkDoesNetworkIdExist(netId) then
        local anchor = NetworkGetEntityFromNetworkId(netId)
        if anchor and anchor ~= 0 and DoesEntityExist(anchor) then
            st.escortAnchor = anchor
            SetEntityVisible(anchor, false, false)
            SetEntityCollision(anchor, false, false)
            SetEntityAlpha(anchor, 0, false)
            return anchor
        end
    end
    return 0
end

function FivePD_UpdateEscortAnchor(anchor, officer)
    if anchor == 0 or not DoesEntityExist(anchor) or officer == 0 or not DoesEntityExist(officer) then return false end
    local boneId = tonumber(Config.Interaction.escortAttachBone) or 11816
    local boneIndex = GetPedBoneIndex(officer, boneId)
    local anchorPos
    if boneIndex and boneIndex >= 0 then anchorPos = GetWorldPositionOfEntityBone(officer, boneIndex) end
    if not anchorPos then anchorPos = GetEntityCoords(officer) end

    SetEntityCoordsNoOffset(anchor, anchorPos.x, anchorPos.y, anchorPos.z, false, false, false)
    SetEntityRotation(anchor, 0.0, 0.0, GetEntityHeading(officer), 2, true)
    SetEntityVisible(anchor, false, false)
    SetEntityCollision(anchor, false, false)
    SetEntityAlpha(anchor, 0, false)
    return true
end

function FivePD_CreateEscortAnchor(officer, currentAnchor)
    if officer == 0 or not DoesEntityExist(officer) then
        FivePD_DeleteEscortAnchor(currentAnchor)
        return 0
    end

    currentAnchor = tonumber(currentAnchor) or 0
    if currentAnchor ~= 0 and not DoesEntityExist(currentAnchor) then currentAnchor = 0 end

    if currentAnchor == 0 then
        local model = joaat('prop_cs_cardbox_01')
        RequestModel(model)
        local timeout = GetGameTimer() + 1500
        while not HasModelLoaded(model) and GetGameTimer() < timeout do Wait(0) end
        if not HasModelLoaded(model) then return 0 end

        local pos = GetEntityCoords(officer)
        -- Networked de propósito: o ped conduzido fica anexado ao MESMO anchor
        -- em todos os clientes, eliminando o efeito de follow/teleporte visto
        -- por observadores quando o anchor existia apenas no client do policial.
        currentAnchor = CreateObjectNoOffset(model, pos.x, pos.y, pos.z, true, true, false)
        SetModelAsNoLongerNeeded(model)
        if currentAnchor == 0 or not DoesEntityExist(currentAnchor) then return 0 end

        SetEntityAsMissionEntity(currentAnchor, true, true)
        SetEntityVisible(currentAnchor, false, false)
        SetEntityCollision(currentAnchor, false, false)
        SetEntityInvincible(currentAnchor, true)
        SetEntityAlpha(currentAnchor, 0, false)
        if NetworkGetEntityIsNetworked(currentAnchor) then
            local netId = NetworkGetNetworkIdFromEntity(currentAnchor)
            if netId and netId > 0 then
                SetNetworkIdCanMigrate(netId, true)
                Entity(currentAnchor).state:set('fivepd_sp:police:escortAnchor', true, true)
            end
        end
    elseif IsEntityAttached(currentAnchor) then
        DetachEntity(currentAnchor, true, false)
    end

    FivePD_UpdateEscortAnchor(currentAnchor, officer)
    return currentAnchor
end

-- V38: a ancora visual de NPC e local a CADA cliente. A referencia compartilhada
-- e exclusivamente o networked ped do policial + controller na state bag do NPC.
-- Mover um prop networked com SetEntityCoordsNoOffset todo frame fazia os demais
-- clientes receberem posicoes em saltos, mesmo que o condutor visse fluidez.
function FivePD_EnsureLocalNpcEscortAnchor(officer, anchor)
    if officer == 0 or not DoesEntityExist(officer) then return 0 end
    anchor = tonumber(anchor) or 0
    if anchor ~= 0 and DoesEntityExist(anchor) and not NetworkGetEntityIsNetworked(anchor) then
        FivePD_UpdateEscortAnchor(anchor, officer)
        return anchor
    end

    local model = joaat('prop_cs_cardbox_01')
    RequestModel(model)
    local deadline = GetGameTimer() + 1500
    while not HasModelLoaded(model) and GetGameTimer() < deadline do Wait(0) end
    if not HasModelLoaded(model) then return 0 end

    local coords = GetEntityCoords(officer)
    -- false: NAO registrar a ancora no OneSync. Observadores usam o policial
    -- interpolado localmente para posicionar o conduzido sem jitter de rede.
    anchor = CreateObjectNoOffset(model, coords.x, coords.y, coords.z, false, false, false)
    SetModelAsNoLongerNeeded(model)
    if anchor == 0 or not DoesEntityExist(anchor) then return 0 end
    SetEntityAsMissionEntity(anchor, true, false)
    SetEntityVisible(anchor, false, false)
    SetEntityCollision(anchor, false, false)
    SetEntityInvincible(anchor, true)
    SetEntityAlpha(anchor, 0, false)
    FivePD_UpdateEscortAnchor(anchor, officer)
    return anchor
end

function FivePD_AttachEscortPedToAnchor(ped, officer, anchor)
    if ped == 0 or not DoesEntityExist(ped) or anchor == 0 or not DoesEntityExist(anchor) then return false end
    local off = Config.Interaction.escortAttachOffset or { x = 0.20, y = 0.45, z = 0.0, rx = 0.0, ry = 0.0, rz = 0.0 }

    if not IsEntityAttachedToEntity(ped, anchor) then
        if IsEntityAttached(ped) then DetachEntity(ped, true, false) end
        -- Somente o network owner ajusta o heading inicial do NPC.
        -- Espectadores nao sobrescrevem transformacao de uma entidade remota.
        if canDriveSharedPed(ped) then
            SetEntityRotation(ped, 0.0, 0.0, GetEntityHeading(officer), 2, true)
        end
        AttachEntityToEntity(
            ped, anchor, 0,
            (tonumber(off.x) or 0.20) + 0.0,
            (tonumber(off.y) or 0.45) + 0.0,
            (tonumber(off.z) or 0.0) + 0.0,
            (tonumber(off.rx) or 0.0) + 0.0,
            (tonumber(off.ry) or 0.0) + 0.0,
            (tonumber(off.rz) or 0.0) + 0.0,
            false, false, false, true, 2, true
        )
    end

    -- A rotacao posterior vem do anchor local seguindo o policial. Reaplicar
    -- SetEntityRotation aqui a cada frame disputava a sincronizacao OneSync.
    return true
end

local function detachEscort(ped)
    if ped == 0 or not DoesEntityExist(ped) then return end
    if IsEntityAttached(ped) then
        DetachEntity(ped, true, false)
    end
    local st = pedStates[ped]
    if st and st.escortAnchor then
        local anchor = st.escortAnchor
        if not NetworkGetEntityIsNetworked(anchor) or NetworkHasControlOfEntity(anchor) then
            FivePD_DeleteEscortAnchor(anchor)
        end
        st.escortAnchor = nil
    end
    if st then st.escortAnchorNetId = 0 end
    stopEscortPrisonerAnim(ped)
    SetEntityCollision(ped, true, true)
end

local function clearEscortOwner(ped)
    if escortedPed == ped then
        escortedPed = nil
        hideEscortHelp()
        stopEscortPlayerAnim()
    end
end

local function escortOffset()
    local off = Config.Interaction.escortAttachOffset or { x = 0.44, y = 0.12, z = 0.0 }
    return tonumber(off.x) or 0.44, tonumber(off.y) or 0.12, tonumber(off.z) or 0.0
end

local function applyEscortAttachment(ped, st)
    if not isValidNpc(ped) or not st.cuffed or not st.held then return false end
    local player = controllerPed(st)
    if player == 0 or not DoesEntityExist(player) or IsEntityDead(player) or IsPedInAnyVehicle(player, false) then
        return false
    end

    local x, y, z = escortOffset()
    local soft = Config.Interaction.escortSoft ~= false

    if soft then
        -- Follow task altera a task tree do NPC e por isso exige network control.
        if not canDriveSharedPed(ped) and not requestControl(ped, 500) then return false end
        -- Hard-attach de peds ao esqueleto de outro ped costuma produzir
        -- jitter/rotação diferente entre network owners. No modo soft o owner
        -- da entidade executa um follow task bem curto, mantendo o conduzido
        -- realmente caminhando ao lado do policial.
        if IsEntityAttached(ped) then DetachEntity(ped, true, false) end
        SetEntityCollision(ped, true, true)
        local dist = #(GetEntityCoords(ped) - GetEntityCoords(player))
        local maxSep = tonumber(Config.Interaction.escortMaxSeparation) or 4.5
        if dist <= maxSep then
            TaskFollowToOffsetOfEntity(
                ped, player, x, y, z,
                tonumber(Config.Interaction.escortFollowSpeed) or 1.05,
                -1,
                tonumber(Config.Interaction.escortStopRange) or 0.34,
                true
            )
            st.lastEscortFollowTask = GetGameTimer()
        end
    else
        -- Cada cliente acompanha os ossos do policial que ELE recebeu de rede.
        -- O servidor replica apenas o vinculo (controller/held), nunca um objeto
        -- intermediario que pula entre amostras de posicao no observador.
        st.escortAnchor = FivePD_EnsureLocalNpcEscortAnchor(player, st.escortAnchor)
        if st.escortAnchor == 0 then return false end
        FivePD_AttachEscortPedToAnchor(ped, player, st.escortAnchor)

        SetEntityNoCollisionEntity(ped, player, true)
        SetEntityNoCollisionEntity(player, ped, true)
    end

    SetPedKeepTask(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanRagdoll(ped, false)
    ensureCuffVisual(ped, st)
    ensureEscortPrisonerAnim(ped, player)
    if player == PlayerPedId() then ensureEscortPlayerAnim() end
    return true
end

local function restoreApproachState(ped, st)
    if not isValidNpc(ped) or not st.approached then return end
    -- Enquanto houver rendição ativa, o mantenedor dedicado abaixo é o único
    -- responsável pela task do NPC. Isso impede dois Task* concorrentes.
    if st.handsUp or st.kneeling then return end
    SetPedKeepTask(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    if st.insideVehicle or st.enteringVehicle then
        if st.cuffed then ensureCuffVisual(ped, st) end
        return
    end
    if st.movingToPoint then
        if st.cuffed then ensureCuffVisual(ped, st) end
        return
    end
    if st.placedAtPoint and st.targetPoint then
        setPlacedPositionLock(ped, st, true, true)
        if st.cuffed then ensureCuffVisual(ped, st) end
        return
    end
    if st.held then
        applyEscortAttachment(ped, st)
        return
    end
    if st.following then
        local player = controllerPed(st)
        if player ~= 0 and DoesEntityExist(player) and not IsEntityDead(player) then
            local off = Config.Interaction.followOffset
            TaskFollowToOffsetOfEntity(ped, player, off.x + 0.0, off.y + 0.0, off.z + 0.0, 1.15, -1, 1.25, true)
            st.lastFollowTask = GetGameTimer()
        end
        if st.cuffed then ensureCuffVisual(ped, st) end
        return
    end
    if st.seated then
        if st.cuffed then ensureCuffVisual(ped, st) end
        return
    end

    requestControl(ped, 450)
    SetBlockingOfNonTemporaryEvents(ped, true)
    TaskStandStill(ped, -1)
    st.lastHoldPositionTask = GetGameTimer()
    if st.cuffed then ensureCuffVisual(ped, st) end
end

local function clearFollowState(ped, st)
    if st.held then detachEscort(ped) end
    clearEscortOwner(ped)
    st.following = false
    st.held = false
    st.lastFollowTask = 0
    syncState(ped, { following = false, held = false })
end

local function setStandStill(ped, st)
    requestControl(ped)
    ClearPedTasks(ped)
    TaskStandStill(ped, -1)
    if st.cuffed then ensureCuffVisual(ped, st) end
end

local function closeInteraction()
    if GetResourceState('ox_target') == 'started' then
        pcall(function() FSPTarget.Close() end)
    end
end

local function copyInteractionValue(value)
    value = tostring(value or '')
    value = value:gsub('^%s+', ''):gsub('%s+$', '')
    if value == '' or value == '—' then return false end
    if GetResourceState('ox_target') ~= 'started' then return false end

    local ok, copied = pcall(function()
        return FSPTarget.Copy(value)
    end)
    return ok and copied ~= false
end

local function closeRadial()
    if not radialOpen then return end
    radialOpen = false
    radialMode = nil
    radialContext = nil
    currentPed = nil
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'close' })
end

local function openRadial(title, subtitle, options, mode, context, canBack)
    if not onDuty() then return end
    closeInteraction()
    radialOpen = true
    radialMode = mode or 'main'
    radialContext = context
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    SetCursorLocation(0.5, 0.5)
    SendNUIMessage({
        action = 'open',
        data = {
            title = title or 'Abordagem',
            subtitle = subtitle or 'INTERAÇÃO POLICIAL',
            options = options or {},
            canBack = canBack == true
        }
    })
end

RegisterNetEvent('fivepd_sp:police:trafficstop:openTypeChooser', function(data)
    data = type(data) == 'table' and data or {}
    local requestId = tonumber(data.requestId)
    if not requestId then return end
    if not onDuty() then
        TriggerEvent('fivepd_sp:trafficstop:typeChooserClosed', requestId)
        return
    end

    local vehicle = tostring(data.vehicle or 'Veículo abordado')
    local plate = tostring(data.plate or '')
    local subtitle = plate ~= '' and ('ABORDAGEM VEICULAR • ' .. plate) or 'ABORDAGEM VEICULAR'

    openRadial('Escolha o tipo de abordagem', subtitle, {
        {
            id = 'trafficstop:traffic',
            icon = 'TR',
            title = 'Abordagem de trânsito',
            description = ('Contato pela janela • %s'):format(vehicle)
        },
        {
            id = 'trafficstop:preventive',
            icon = 'AP',
            title = 'Abordagem preventiva',
            description = 'Desembarque de todos os ocupantes e busca individual'
        }
    }, 'trafficstop_type', { requestId = requestId }, false)
end)

RegisterNetEvent('fivepd_sp:police:trafficstop:closeTypeChooser', function(requestId)
    requestId = tonumber(requestId)
    if not radialOpen or radialMode ~= 'trafficstop_type' then return end
    local context = radialContext or {}
    if requestId and tonumber(context.requestId) ~= requestId then return end
    closeRadial()
end)

local function nearestVehicle(ped, maxDistance)
    local origin = GetEntityCoords(ped)
    local best, bestDistance = 0, maxDistance or Config.Interaction.vehicleSearchDistance or 5.0
    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if DoesEntityExist(vehicle) then
            local d = #(origin - GetEntityCoords(vehicle))
            if d < bestDistance then
                best = vehicle
                bestDistance = d
            end
        end
    end
    return best, bestDistance
end

local function seatDoorIndex(seat)
    if seat == -1 then return 0 end
    if seat == 0 then return 1 end
    if seat == 1 then return 2 end
    if seat == 2 then return 3 end
    return math.min(5, seat + 1)
end

local function doorIsOpen(vehicle, door)
    if not DoesEntityExist(vehicle) then return false end
    if IsVehicleDoorDamaged(vehicle, door) then return true end
    local cfg = Config.Interaction and Config.Interaction.custodyVehicleSeats or nil
    return GetVehicleDoorAngleRatio(vehicle, door) > (tonumber(cfg and cfg.openRatio) or 0.12)
end

-- Mapeamento de bancos de custódia para viaturas customizadas.
-- Não presumimos mais que seat + 1 seja a porta correta. Em veículos que usam
-- bancos extras/celas no compartimento traseiro isso fazia seat 3 apontar para
-- o capô (door 4) e outros bancos abrirem a porta lateral errada.
function FivePD_CustodySeatSettings()
    return Config.Interaction and Config.Interaction.custodyVehicleSeats or {}
end

function FivePD_CustodyMaxPassengerSeat(vehicle)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return -1 end
    local seats = GetVehicleModelNumberOfSeats(GetEntityModel(vehicle)) or 0
    local cfg = FivePD_CustodySeatSettings()
    local cap = tonumber(cfg.maxPassengerSeatIndex) or 8
    return math.min(cap, seats - 2)
end

function FivePD_CustodySeatBoneNames(seat)
    seat = tonumber(seat)
    if seat == 0 then return { 'seat_pside_f' } end
    if seat == 1 then return { 'seat_dside_r', 'seat_dside_r0' } end
    if seat == 2 then return { 'seat_pside_r', 'seat_pside_r0' } end
    if not seat or seat < 3 then return {} end
    local extra = seat - 3
    local row = math.floor(extra / 2) + 1
    local side = (extra % 2 == 0) and 'dside' or 'pside'
    return {
        ('seat_%s_r%d'):format(side, row),
        ('seat_%s_r_%d'):format(side, row),
        ('seat_%s_extra_%d'):format(side, row)
    }
end

function FivePD_CustodySeatPosition(vehicle, seat)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return nil end
    for _, boneName in ipairs(FivePD_CustodySeatBoneNames(seat)) do
        local bone = GetEntityBoneIndexByName(vehicle, boneName)
        if bone and bone ~= -1 then
            return GetWorldPositionOfEntityBone(vehicle, bone)
        end
    end
    return nil
end

function FivePD_CustodyDoorBoneNames(door)
    if door == 0 then return { 'door_dside_f' } end
    if door == 1 then return { 'door_pside_f' } end
    if door == 2 then return { 'door_dside_r' } end
    if door == 3 then return { 'door_pside_r' } end
    if door == 5 then return { 'boot', 'boot_l', 'boot_r', 'door_hatch_r', 'door_hatch_l', 'door_rear' } end
    return {}
end

function FivePD_CustodyDoorPosition(vehicle, door)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return nil end
    for _, boneName in ipairs(FivePD_CustodyDoorBoneNames(door)) do
        local bone = GetEntityBoneIndexByName(vehicle, boneName)
        if bone and bone ~= -1 then
            return GetWorldPositionOfEntityBone(vehicle, bone)
        end
    end
    local pos = GetEntryPositionOfDoor(vehicle, door)
    if pos and pos.x and (math.abs(pos.x) + math.abs(pos.y) + math.abs(pos.z)) > 0.01 then
        return pos
    end
    return nil
end

function FivePD_CustodySeatOverride(vehicle, seat)
    local cfg = FivePD_CustodySeatSettings()
    local profiles = cfg.modelOverrides
    if type(profiles) ~= 'table' or vehicle == 0 or not DoesEntityExist(vehicle) then return nil end
    local model = GetEntityModel(vehicle)
    for modelName, profile in pairs(profiles) do
        local hash = type(modelName) == 'number' and modelName or GetHashKey(tostring(modelName))
        if model == hash and type(profile) == 'table' then
            return profile[seat] or profile[tostring(seat)]
        end
    end
    return nil
end

function FivePD_ResolveCustodySeatAccess(vehicle, seat)
    seat = math.floor(tonumber(seat) or -99)
    local override = FivePD_CustodySeatOverride(vehicle, seat)
    if type(override) == 'table' then
        local door = math.floor(tonumber(override.door) or seatDoorIndex(seat))
        return {
            door = door,
            trunk = override.trunk == true or door == 5,
            warp = override.warp == true or door == 5,
            label = override.label
        }
    end

    local canonical = seatDoorIndex(seat)
    local cfg = FivePD_CustodySeatSettings()
    if cfg.enabled == false or cfg.autoDetect == false then
        local door = seat >= 3 and 5 or canonical
        return { door = door, trunk = door == 5, warp = door == 5 }
    end

    -- O passageiro dianteiro é sempre atendido pela porta dianteira direita.
    if seat == 0 then return { door = 1, trunk = false, warp = false } end

    local seatPos = FivePD_CustodySeatPosition(vehicle, seat)
    if not seatPos then
        local door = seat >= 3 and 5 or canonical
        return { door = door, trunk = door == 5, warp = door == 5 }
    end

    local candidates = seat >= 3 and { 2, 3, 5 } or { canonical, canonical == 2 and 3 or 2, 5 }
    local bestDoor, bestScore = canonical, math.huge
    local canonicalBias = tonumber(cfg.canonicalDoorBias) or 0.22
    local extraBootBias = tonumber(cfg.extraSeatBootBias) or 0.12
    for _, door in ipairs(candidates) do
        local doorPos = FivePD_CustodyDoorPosition(vehicle, door)
        if doorPos then
            local score = #(seatPos - doorPos)
            if door == canonical then score = score - canonicalBias end
            if door == 5 and seat >= 3 then score = score - extraBootBias end
            if score < bestScore then
                bestDoor, bestScore = door, score
            end
        end
    end

    if bestScore == math.huge then
        bestDoor = seat >= 3 and 5 or canonical
    end
    return { door = bestDoor, trunk = bestDoor == 5, warp = bestDoor == 5 }
end

function FivePD_CustodySeatLabel(vehicle, seat, access)
    access = access or FivePD_ResolveCustodySeatAccess(vehicle, seat)
    if access and access.label and access.label ~= '' then return tostring(access.label) end
    if access and access.trunk then return ('Custódia traseira • banco %d'):format(seat + 2) end
    if seat == 0 then return 'Dianteiro direito' end
    if seat == 1 then return 'Traseiro esquerdo' end
    if seat == 2 then return 'Traseiro direito' end
    return ('Banco adicional %d'):format(seat + 2)
end

function FivePD_CustodyEntryPosition(vehicle, door, ped)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return nil end
    if door ~= 5 then
        local pos = GetEntryPositionOfDoor(vehicle, door)
        if pos and pos.x then return pos end
    end

    local doorPos = FivePD_CustodyDoorPosition(vehicle, door)
    if not doorPos then return GetEntityCoords(vehicle) end
    if door == 5 then
        local forward = GetEntityForwardVector(vehicle)
        local z = doorPos.z
        if ped and ped ~= 0 and DoesEntityExist(ped) then z = GetEntityCoords(ped).z end
        return vector3(doorPos.x - forward.x * 0.85, doorPos.y - forward.y * 0.85, z)
    end
    return doorPos
end

function FivePD_CustodyAccessDescription(access, open, free)
    if not free then return 'Banco ocupado' end
    if access and access.trunk then
        return open and 'Porta-malas aberto • banco de custódia livre' or 'Abra o porta-malas para usar este banco'
    end
    return open and 'Porta aberta • banco livre' or 'Abra a porta correspondente'
end

local function availableSeatOptions(ped, vehicle)
    local options = {}
    local maxSeat = FivePD_CustodyMaxPassengerSeat(vehicle)
    for seat = 0, maxSeat do
        local free = IsVehicleSeatFree(vehicle, seat)
        local access = FivePD_ResolveCustodySeatAccess(vehicle, seat)
        local open = doorIsOpen(vehicle, access.door)
        options[#options + 1] = {
            id = ('seat:%d'):format(seat),
            title = FivePD_CustodySeatLabel(vehicle, seat, access),
            icon = access.trunk and 'VTR' or 'CAR',
            description = FivePD_CustodyAccessDescription(access, open, free),
            disabled = not free or not open
        }
    end
    return options
end

local function findCuffedOccupants(vehicle)
    local out = {}
    local maxSeat = FivePD_CustodyMaxPassengerSeat(vehicle)
    for seat = 0, maxSeat do
        local ped = GetPedInVehicleSeat(vehicle, seat)
        if isValidNpc(ped) and stateFor(ped).cuffed then
            local access = FivePD_ResolveCustodySeatAccess(vehicle, seat)
            out[#out + 1] = { ped = ped, seat = seat, door = access.door, access = access }
        end
    end
    return out
end

local function cancelPlacement(showNotice)
    local ped = placementPed
    placementActive = false
    placementPed = nil
    placementPoint = nil
    hidePlacementHelp()
    if isValidNpc(ped) then
        local st = stateFor(ped)
        st.busyUntil = 0
        if showNotice then notify('info', 'Abordagem', 'Seleção de local cancelada.') end
        if showNotice then restoreApproachState(ped, st) end
    end
end

local function sendPedToPoint(ped, point)
    if not onDuty() or not isValidNpc(ped) or not point then return false end
    local st = stateFor(ped)
    if not acquirePlacedPedControl(ped, st, 1200) then return false end

    if st.held then
        detachEscort(ped)
        clearEscortOwner(ped)
    end
    setPlacedPositionLock(ped, st, false, false)
    st.seated = false
    st.following = false
    st.held = false
    st.placedAtPoint = false
    st.movingToPoint = true
    st.targetPoint = point
    st.moveUntil = GetGameTimer() + 12000
    st.lastPointHoldTask = 0
    syncState(ped, {
        seated = false,
        following = false,
        held = false,
        placedAtPoint = false,
        movingToPoint = true,
        targetX = point.x + 0.0,
        targetY = point.y + 0.0,
        targetZ = point.z + 0.0
    })

    SetPedKeepTask(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    ClearPedTasks(ped)
    TaskFollowNavMeshToCoord(ped, point.x, point.y, point.z, 1.0, 11000, 0.35, false, 0.0)
    if st.cuffed then ensureCuffVisual(ped, st) end
    return true
end

local function holdPedAtPlacedPoint(ped, st, force)
    if not isValidNpc(ped) or not st or not st.placedAtPoint or not st.targetPoint then return end
    if st.held or st.following or st.seated or st.insideVehicle or st.enteringVehicle or st.movingToPoint then return end

    local now = GetGameTimer()
    if not force and now < (st.busyUntil or 0) then return end

    -- V32: a chegada deve produzir UMA transicao para o idle. Na V31 o loop
    -- chamava esta funcao com force=true em todo frame, cancelando a animacao
    -- incessantemente e deixando o NPC na postura T.
    if not st.positionLocked then
        if not acquirePlacedPedControl(ped, st, 900) then return end
        SetPedKeepTask(ped, true)
        SetBlockingOfNonTemporaryEvents(ped, true)
        SetPedFleeAttributes(ped, 0, false)
        -- ClearPedTasks (sem Immediately) deixa o motor de animacao completar
        -- a transicao de caminhar para parado.
        ClearPedTasks(ped)
        TaskStandStill(ped, -1)
        if not st.cuffed then
            if SetPedCanPlayAmbientAnims then SetPedCanPlayAmbientAnims(ped, true) end
            if SetPedCanPlayAmbientBaseAnims then SetPedCanPlayAmbientBaseAnims(ped, true) end
        end
        setPlacedPositionLock(ped, st, true, false)
        st.lastPointHoldTask = now
        st.lastHoldPositionTask = now
    elseif now - (st.lastPointHoldTask or 0) >= 2500 then
        -- Apenas conferir eventual deriva; nunca sobrescrever a task de idle.
        setPlacedPositionLock(ped, st, true, false)
        st.lastPointHoldTask = now
    end

    if st.cuffed then ensureCuffVisual(ped, st) end
end

local function beginPlacement(ped)
    if not onDuty() or not isValidNpc(ped) then return end
    local st = stateFor(ped)
    if st.held or st.seated or st.insideVehicle or st.enteringVehicle then
        notify('aviso', 'Abordagem', 'A pessoa precisa estar em pé e fora do veículo para ir até outro local.')
        return
    end
    closeRadial()
    if st.following then
        st.following = false
        syncState(ped, { following = false })
    end
    placementActive = true
    placementPed = ped
    placementPoint = placementCandidate()
    st.busyUntil = GetGameTimer() + 600000
    ClearPedTasks(ped)
    TaskStandStill(ped, -1)
    if st.cuffed then ensureCuffVisual(ped, st) end
    showPlacementHelp()
end

local function infractionDefinitions()
    local cfg = Config.Infractions or {}
    return cfg.groups or {}, cfg.items or {}
end

local function infractionStateFor(ped)
    if ped and ped ~= 0 and DoesEntityExist(ped) and IsPedAPlayer(ped) then
        local playerIndex = NetworkGetPlayerIndexFromPed(ped)
        local key = playerIndex ~= -1 and GetPlayerServerId(playerIndex) or nil
        if key and key > 0 then
            playerInfractionStates[key] = playerInfractionStates[key] or {}
            return playerInfractionStates[key]
        end
        return {}
    end
    local st = stateFor(ped)
    st.infractions = st.infractions or {}
    return st.infractions
end

local function infractionCount(ped)
    local selected = infractionStateFor(ped)
    local count = 0
    for _, enabled in pairs(selected) do
        if enabled then count = count + 1 end
    end
    return count
end

local function findInfraction(id)
    local _, items = infractionDefinitions()
    for _, item in ipairs(items) do
        if item.id == id then return item end
    end
    return nil
end

local function toggleInfraction(ped, id)
    if not onDuty() or not isValidHumanPed(ped) then return false end
    local item = findInfraction(id)
    if not item then return false end
    local selected = infractionStateFor(ped)
    local adding = selected[id] ~= true
    selected[id] = adding or nil
    if adding then
        notify('sucesso', 'Infração registrada', item.label)
    else
        notify('info', 'Infração removida', item.label)
    end
    TriggerEvent('fivepd_sp:police:infracaoAlterada', ped, id, adding, item)
    return true
end

local function mainOptions(ped)
    return {
        { id = 'category:identification', title = 'Identificação', icon = 'ID', description = 'Documentos, diálogo e revista pessoal.' },
        { id = 'category:control', title = 'Controle', icon = 'CTL', description = 'Algemas, posição e permanência.' },
        { id = 'category:conduction', title = 'Condução', icon = 'CON', description = 'Seguir, segurar e colocar no veículo.' },
        { id = 'category:finish', title = 'Encerrar', icon = 'FIM', description = 'Liberar ou dispensar a pessoa abordada.' }
    }
end

local function openMainRadial(ped)
    if not onDuty() or not isValidNpc(ped) then return end
    currentPed = ped
    openRadial('Pessoa abordada', 'INTERAÇÃO POLICIAL', mainOptions(ped), 'main', { ped = ped }, false)
end

local function identificationOptions(ped)
    return {
        { id = 'search', title = 'Revistar', icon = 'REV', description = 'Realizar busca pessoal.' },
        { id = 'documents', title = 'Solicitar documentos', icon = 'DOC', description = 'Solicitar identificação e habilitação quando aplicável.' },
        { id = 'dialogue', title = 'Dialogar', icon = 'FAL', description = 'Fazer perguntas durante a abordagem.' }
    }
end

local function controlOptions(ped)
    local st = stateFor(ped)
    return {
        { id = 'cuff', title = st.cuffed and 'Desalgemar' or 'Algemar', icon = 'ALG', description = st.cuffed and 'Retirar as algemas.' or 'Conter a pessoa abordada.' },
        { id = 'sit', title = st.seated and 'Levantar' or 'Sentar no chão', icon = 'SEN', description = st.seated and 'Mandar levantar.' or 'Mandar sentar no chão.' },
        { id = 'place', title = 'Ficar naquele lugar', icon = 'POS', description = 'Escolher um ponto para a pessoa permanecer.', disabled = st.held or st.seated or st.insideVehicle or st.enteringVehicle }
    }
end

local function conductionOptions(ped)
    local st = stateFor(ped)
    local vehicle = nearestVehicle(ped, Config.Interaction.vehicleSearchDistance)
    local canVehicle = st.cuffed and vehicle ~= 0 and not IsPedInAnyVehicle(ped, false)
    return {
        { id = 'follow', title = st.following and 'Parar de seguir' or 'Seguir', icon = 'SEG', description = st.following and 'Permanecer no local.' or 'Acompanhar o policial.' },
        { id = 'hold', title = st.held and 'Soltar' or 'Segurar', icon = 'CON', description = st.cuffed and 'Condução próxima do policial.' or 'Disponível somente algemado.', disabled = not st.cuffed },
        { id = 'vehicle', title = 'Colocar no veículo', icon = 'VTR', description = canVehicle and 'Escolher banco com a porta ou porta-malas de acesso já aberto.' or 'Algeme e aproxime-se de um veículo.', disabled = not canVehicle }
    }
end

local function trafficStopContextForPed(ped)
    if GetResourceState('fivepd_sp_trafficstop') ~= 'started' then return nil end
    local ok, context = pcall(function()
        return exports.fivepd_sp_trafficstop:ObterContextoPedAbordagem(ped)
    end)
    if ok and type(context) == 'table' and context.active == true then return context end
    return nil
end

local function finishOptions(ped)
    local st = stateFor(ped)
    local traffic = trafficStopContextForPed(ped)
    if traffic then
        local blocked = traffic.hasCuffedOccupant == true
        return {
            { id = 'traffic_release_foot', title = 'Liberar a pé', icon = 'APE', description = blocked and 'Desalgeme todos os ocupantes antes de liberar.' or 'Encerrar a abordagem e liberar os ocupantes a pé.', disabled = blocked },
            { id = 'traffic_release_vehicle', title = 'Liberar com veículo', icon = 'VEI', description = blocked and 'Desalgeme todos os ocupantes antes de liberar.' or 'Retornar os ocupantes aos assentos originais e liberar o veículo.', disabled = blocked }
        }
    end

    return {
        { id = 'release', title = 'Liberar', icon = 'LIB', description = st.cuffed and 'Desalgeme a pessoa antes de liberar.' or 'Encerrar a abordagem.', disabled = st.cuffed },
        { id = 'dismiss', title = 'Mandar sair do local', icon = 'SAI', description = st.cuffed and 'Desalgeme a pessoa antes de dispensá-la.' or 'Orientar a pessoa a deixar a área.', disabled = st.cuffed }
    }
end

local function openCategoryRadial(ped, category)
    if not onDuty() or not isValidNpc(ped) then return end
    if category == 'identification' then
        openRadial('Identificação', 'INTERAÇÃO POLICIAL', identificationOptions(ped), 'category:identification', { ped = ped }, true)
    elseif category == 'control' then
        openRadial('Controle', 'INTERAÇÃO POLICIAL', controlOptions(ped), 'category:control', { ped = ped }, true)
    elseif category == 'conduction' then
        openRadial('Condução', 'INTERAÇÃO POLICIAL', conductionOptions(ped), 'category:conduction', { ped = ped }, true)
    elseif category == 'finish' then
        openRadial('Encerrar abordagem', 'INTERAÇÃO POLICIAL', finishOptions(ped), 'category:finish', { ped = ped }, true)
    end
end

local function openInfractionsRoot(ped, origin)
    if not onDuty() or not isValidHumanPed(ped) then return false end
    local groups, items = infractionDefinitions()
    local selected = infractionStateFor(ped)
    local options = {}
    for _, group in ipairs(groups) do
        local registered = 0
        for _, item in ipairs(items) do
            if item.group == group.id and selected[item.id] then registered = registered + 1 end
        end
        options[#options + 1] = {
            id = 'infgroup:' .. tostring(group.id),
            title = group.label or group.id,
            icon = group.icon or 'INF',
            description = registered > 0 and (('%d registrada(s) • abrir categoria'):format(registered)) or (group.description or 'Abrir categoria')
        }
    end
    openRadial('Infrações', 'REGISTRO DA ABORDAGEM', options, 'infractions_root', { ped = ped, origin = origin or 'person' }, true)
    return true
end

local function openInfractionsGroup(ped, groupId, origin)
    if not onDuty() or not isValidHumanPed(ped) then return false end
    local groups, items = infractionDefinitions()
    local groupLabel = 'Infrações'
    for _, group in ipairs(groups) do
        if group.id == groupId then
            groupLabel = group.label or groupLabel
            break
        end
    end
    local selected = infractionStateFor(ped)
    local options = {}
    for _, item in ipairs(items) do
        if item.group == groupId then
            local active = selected[item.id] == true
            options[#options + 1] = {
                id = 'infraction:' .. tostring(item.id),
                title = active and ('✓ ' .. item.label) or item.label,
                icon = active and '✓' or 'INF',
                description = active and 'Registrada • selecionar novamente para remover.' or (item.description or 'Registrar infração.')
            }
        end
    end
    openRadial(groupLabel, 'INFRAÇÕES', options, 'infractions_group', { ped = ped, group = groupId, origin = origin or 'person' }, true)
    return true
end

exports('AbrirMenuInfracoes', function(ped, origin)
    if not onDuty() or not isValidHumanPed(ped) then return false end
    return openInfractionsRoot(ped, origin or 'external')
end)

exports('ObterInfracoesPed', function(ped)
    if not isValidHumanPed(ped) then return {} end
    local selected = infractionStateFor(ped)
    local out = {}
    local _, items = infractionDefinitions()
    for _, item in ipairs(items) do
        if selected[item.id] then
            out[#out + 1] = { id = item.id, group = item.group, label = item.label, description = item.description }
        end
    end
    return out
end)

local function fallbackDocumentsFor(ped)
    if pedDocumentFallback[ped] then return pedDocumentFallback[ped] end

    if GetResourceState('fivepd_sp_records') == 'started' then
        local ok, registro = pcall(function()
            return exports.fivepd_sp_records:ObterOuCriarNPC(ped, { persistir = true })
        end)
        if ok and type(registro) == 'table' and registro.encontrado ~= false then
            local status = registro.cnh and tostring(registro.cnh.status or ''):lower() or ''
            local labels = {
                regular = 'Válida', vencida = 'Vencida', suspensa = 'Suspensa',
                cassada = 'Cassada', nao_emitida = 'Não habilitado'
            }
            local data = {
                record_id = registro.record_id,
                npc_key = registro.npc_key,
                rg = registro.rg,
                name = registro.nome_completo or ((tostring(registro.nome or '') .. ' ' .. tostring(registro.sobrenome or '')):gsub('^%s+', ''):gsub('%s+$', '')),
                age = tonumber(registro.idade) or 0,
                birth = registro.nascimento,
                license = labels[status] or status,
                cnh = registro.cnh
            }
            pedDocumentFallback[ped] = data
            return data
        end
    end

    local first = ({ 'Gabriel', 'Lucas', 'Rafael', 'Marcos', 'Bruno', 'Carlos', 'Ana', 'Mariana', 'Camila', 'Juliana', 'Fernanda', 'Bianca' })[math.random(1, 12)]
    local last = ({ 'Silva', 'Santos', 'Oliveira', 'Souza', 'Lima', 'Pereira', 'Costa', 'Almeida', 'Ribeiro', 'Carvalho' })[math.random(1, 10)]
    local data = {
        name = first .. ' ' .. last,
        age = math.random(18, 72),
        license = ({ 'Válida', 'Válida', 'Válida', 'Válida', 'Vencida', 'Suspensa' })[math.random(1, 6)]
    }
    pedDocumentFallback[ped] = data
    return data
end

local function requestPedDocuments(ped)
    if not onDuty() or not isValidNpc(ped) then return false end
    closeRadial()
    local st = stateFor(ped)
    st.busyUntil = GetGameTimer() + 2400
    requestControl(ped, 700)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedKeepTask(ped, true)

    local data
    if GetResourceState('fivepd_sp_trafficstop') == 'started' then
        local ok, result = pcall(function()
            return exports.fivepd_sp_trafficstop:ObterDocumentosPed(ped)
        end)
        if ok and type(result) == 'table' then data = result end
    end
    data = data or fallbackDocumentsFor(ped)

    local player = PlayerPedId()
    if requestAnim(DIALOG_DICT) then
        TaskPlayAnim(player, DIALOG_DICT, 'gesture_point', 4.0, -4.0, 1500, 48, 0.0, false, false, false)
        if not st.cuffed and not st.seated then
            TaskPlayAnim(ped, DIALOG_DICT, 'gesture_nod_yes_soft', 4.0, -4.0, 1500, 48, 0.0, false, false, false)
        end
    end
    Wait(650)

    local rgCopied = data.rg and copyInteractionValue(data.rg) or false
    local text = ('%s • %d anos'):format(data.name or 'Identificação apresentada', tonumber(data.age) or 0)
    if data.rg then text = text .. ('\nRG: %s%s'):format(data.rg, rgCopied and ' • copiado' or '') end
    if data.birth then text = text .. ('\nNascimento: %s'):format(data.birth) end
    if data.license then text = text .. ('\nCNH: %s'):format(data.license) end
    if data.plate then text = text .. ('\nPlaca: %s'):format(data.plate) end
    notify('info', 'Documentos apresentados', text)

    Wait(900)
    ClearPedSecondaryTask(player)
    if isValidNpc(ped) then
        if not st.cuffed then ClearPedSecondaryTask(ped) end
        st.busyUntil = 0
        restoreApproachState(ped, st)
        openCategoryRadial(ped, 'identification')
    end
    return true
end

openPostSearchRadial = function(ped)
    if not onDuty() or not isValidNpc(ped) then return end
    openRadial('Revista concluída', 'ABORDAGEM PREVENTIVA', {
        { id = 'post:cuff', title = 'Algemar', icon = 'ALG', description = 'Conter a pessoa após a revista.', disabled = stateFor(ped).cuffed == true },
        { id = 'post:continue', title = 'Continuar abordagem', icon = '▶', description = 'Abrir todas as opções da abordagem pessoal.' }
    }, 'post_search', { ped = ped })
end

local function applyFollowTask(ped, st, held)
    if not isValidNpc(ped) then return end
    if held then
        applyEscortAttachment(ped, st)
        st.lastFollowTask = GetGameTimer()
        return
    end
    local player = controllerPed(st)
    if player == 0 or not DoesEntityExist(player) or IsEntityDead(player) then return end
    if not canDriveSharedPed(ped) and not requestControl(ped) then return end
    detachEscort(ped)
    local off = Config.Interaction.followOffset
    TaskFollowToOffsetOfEntity(ped, player, off.x + 0.0, off.y + 0.0, off.z + 0.0, 1.15, -1, 1.25, true)
    st.lastFollowTask = GetGameTimer()
    if st.cuffed then ensureCuffVisual(ped, st) end
end

local function setCuffed(ped, enabled)
    if not onDuty() then return false end
    local st = stateFor(ped)
    if not requestControl(ped) then return end
    FivePD_EnsureCustodyNpcNetworked(ped)
    local cuffing = enabled == true
    if cuffing == st.cuffed then return end

    closeRadial()
    local wasPlaced = st.placedAtPoint == true
    if wasPlaced then setPlacedPositionLock(ped, st, false, false) end
    st.busyUntil = GetGameTimer() + (cuffing and 4400 or 3200)
    SetPedKeepTask(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetCurrentPedWeapon(ped, joaat('WEAPON_UNARMED'), true)

    if cuffing then
        -- A partir daqui o NPC está sob custódia policial e não deve mais ser
        -- tratado pelo GTA como ped ambiente descartável.
        SetEntityAsMissionEntity(ped, true, false)
        SetEntityVisible(ped, true, false)
        if GetEntityAlpha(ped) < 250 then ResetEntityAlpha(ped) end
        SetEntityCollision(ped, true, true)
        -- Não iniciamos fade de rede ao algemar. O ped já está visível e esse
        -- native disputa o alpha com a replicação/prop de algema, gerando o
        -- efeito de piscar observado tanto em NPCs quanto em jogadores.

        if st.held then
            detachEscort(ped)
            clearEscortOwner(ped)
        end
        st.held = false
        st.following = false
        st.seated = false
        st.preventive = false
        st.preventiveApplied = false
        st.handsUp = false
        st.kneeling = false
        FreezeEntityPosition(ped, false)
        syncState(ped, { held = false, following = false, seated = false, preventive = false, handsUp = false, kneeling = false })
        ClearPedTasks(ped)
        playCuffTransition(ped, true)

        st.cuffed = true
        local arrestCoords = GetEntityCoords(ped)
        local weatherHash = 0
        local okWeather, currentWeather = pcall(GetPrevWeatherTypeHashName)
        if okWeather then weatherHash = tonumber(currentWeather) or 0 end
        local interior = 0
        local okInterior, interiorId = pcall(GetInteriorFromEntity, ped)
        if okInterior and tonumber(interiorId) and tonumber(interiorId) ~= 0 then interior = 1 end
        syncState(ped, {
            cuffed = true,
            arrestX = arrestCoords.x, arrestY = arrestCoords.y, arrestZ = arrestCoords.z,
            arrestHour = GetClockHours(), arrestWeather = weatherHash, arrestInterior = interior
        })
        -- Troca diretamente da animação pareada para o idle algemado, sem
        -- entregar um frame de locomoção/IA ambiente entre as duas tarefas.
        ClearPedTasksImmediately(ped)

        -- A animação pareada possui root motion. Em alguns peds/solos o frame
        -- final pode deixar a raiz alguns centímetros (ou, raramente, mais)
        -- abaixo do piso. Corrigimos apenas desvios grandes para não criar snap
        -- em escadas, calçadas ou interiores válidos.
        if DoesEntityExist(ped) and not IsPedInAnyVehicle(ped, false) then
            local afterCuff = GetEntityCoords(ped)
            local foundGround, groundZ = GetGroundZFor_3dCoord(afterCuff.x, afterCuff.y, afterCuff.z + 3.0, false)
            if foundGround and (afterCuff.z < groundZ - 0.70 or afterCuff.z > groundZ + 2.20) then
                SetEntityCoordsNoOffset(ped, afterCuff.x, afterCuff.y, groundZ + 0.03, false, false, false)
            end
            SetEntityVisible(ped, true, false)
            if GetEntityAlpha(ped) < 250 then ResetEntityAlpha(ped) end
            SetEntityCollision(ped, true, true)
        end

        ensureCuffVisual(ped, st)
        st.lastHoldPositionTask = GetGameTimer()
        if wasPlaced then
            st.targetPoint = GetEntityCoords(ped)
            st.placedAtPoint = true
            st.busyUntil = 0
            holdPedAtPlacedPoint(ped, st, true)
        end
        notify('sucesso', 'Abordagem', 'Pessoa algemada.')
        return
    end

    -- O ped permanece visualmente algemado até o fim da animação de retirada.
    detachEscort(ped)
    clearEscortOwner(ped)
    st.held = false
    st.following = false
    syncState(ped, { held = false, following = false })
    ensureCuffVisual(ped, st)
    playCuffTransition(ped, false)

    st.cuffed = false
    syncState(ped, { cuffed = false, held = false })
    stopCuffVisual(ped)
    ClearPedTasks(ped)
    TaskStandStill(ped, -1)
    st.lastHoldPositionTask = GetGameTimer()
    if wasPlaced then
        st.targetPoint = GetEntityCoords(ped)
        st.placedAtPoint = true
        st.busyUntil = 0
        holdPedAtPlacedPoint(ped, st, true)
    end
    notify('sucesso', 'Abordagem', 'Pessoa desalgemada.')
end

local function toggleSit(ped)
    if not onDuty() then return false end
    local st = stateFor(ped)
    requestControl(ped)
    clearPlacedPoint(ped, st)
    if st.held then
        detachEscort(ped)
        clearEscortOwner(ped)
    end
    if st.seated then
        st.seated = false
        syncState(ped, { seated = false })
        ClearPedTasks(ped)
        TaskStandStill(ped, -1)
        if st.cuffed then ensureCuffVisual(ped, st) end
    else
        clearFollowState(ped, st)
        st.seated = true
        syncState(ped, { seated = true, following = false, held = false })
        ClearPedTasks(ped)
        TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_PICNIC', 0, true)
        if st.cuffed then
            CreateThread(function()
                Wait(450)
                if isValidNpc(ped) and stateFor(ped).cuffed then ensureCuffVisual(ped, stateFor(ped)) end
            end)
        end
    end
end

local function toggleFollow(ped)
    if not onDuty() then return false end
    local st = stateFor(ped)
    requestControl(ped)
    clearPlacedPoint(ped, st)
    if st.held then
        detachEscort(ped)
        clearEscortOwner(ped)
    end
    if st.following then
        st.following = false
        st.held = false
        syncState(ped, { following = false, held = false })
        ClearPedTasks(ped)
        TaskStandStill(ped, -1)
        if st.cuffed then ensureCuffVisual(ped, st) end
        return
    end
    st.seated = false
    st.held = false
    st.following = true
    syncState(ped, { seated = false, held = false, following = true })
    ClearPedTasks(ped)
    applyFollowTask(ped, st, false)
end

local function toggleHold(ped)
    if not onDuty() then return false end
    if not isValidNpc(ped) then return false end

    local st = stateFor(ped)
    clearPlacedPoint(ped, st)
    if not st.cuffed then
        notify('aviso', 'Condução', 'A pessoa precisa estar algemada para ser segurada.')
        return false
    end

    local netId = FivePD_EnsureCustodyNpcNetworked(ped)
    if not netId or netId <= 0 then
        notify('aviso', 'Condução', 'Não foi possível sincronizar essa pessoa com o servidor.')
        return false
    end

    escortRequestSeq = escortRequestSeq + 1
    local requestId = escortRequestSeq
    pendingEscortRequests[requestId] = { ped = ped, netId = netId, requestedAt = GetGameTimer() }
    TriggerServerEvent('fivepd_sp:police:ped:escortToggleRequest', netId, requestId)

    CreateThread(function()
        Wait(4000)
        if pendingEscortRequests[requestId] then
            pendingEscortRequests[requestId] = nil
            notify('aviso', 'Condução', 'O servidor não confirmou a condução a tempo.')
        end
    end)
    return true
end

RegisterNetEvent('fivepd_sp:police:ped:escortToggleResult', function(requestId, netId, ok, held, message)
    requestId = tonumber(requestId) or 0
    netId = tonumber(netId) or 0
    local pending = pendingEscortRequests[requestId]
    pendingEscortRequests[requestId] = nil

    local ped = pending and pending.ped or 0
    if (ped == 0 or not DoesEntityExist(ped)) and netId > 0 and NetworkDoesNetworkIdExist(netId) then
        ped = NetworkGetEntityFromNetworkId(netId)
    end

    if ok ~= true then
        if ped ~= 0 and DoesEntityExist(ped) then refreshSharedState(ped, stateFor(ped)) end
        notify('aviso', 'Condução', tostring(message or 'Não foi possível iniciar a condução.'))
        return
    end

    if ped == 0 or not DoesEntityExist(ped) then return end
    local st = stateFor(ped)
    st.held = held == true
    st.following = false
    st.controller = held == true and localServerId() or 0
    -- Não lê a state bag imediatamente após o ACK: o evento de rede pode chegar
    -- alguns ms antes da replicação da bag e reverter temporariamente held=false.
    st.sharedRefreshAt = GetGameTimer()

    if held == true then
        requestControl(ped, 350)
        ClearPedTasksImmediately(ped)
        SetPedKeepTask(ped, true)
        SetBlockingOfNonTemporaryEvents(ped, true)
        applyEscortAttachment(ped, st)
        escortedPed = ped
        ensureEscortPlayerAnim()
        showEscortHelp(true)
        notify('sucesso', 'Condução', tostring(message or 'Você está conduzindo a pessoa pelo braço.'))
    else
        detachEscort(ped)
        clearEscortOwner(ped)
        stopEscortPlayerAnim()
        requestControl(ped, 250)
        SetPedKeepTask(ped, true)
        SetBlockingOfNonTemporaryEvents(ped, true)
        TaskStandStill(ped, -1)
        st.lastHoldPositionTask = GetGameTimer()
        if st.cuffed then ensureCuffVisual(ped, st) end
        notify('info', 'Condução', tostring(message or 'Você soltou o braço da pessoa.'))
    end
end)

local function alignOfficerBehindForSearch(ped)
    local officer = PlayerPedId()
    if officer == 0 or not DoesEntityExist(officer) or not isValidNpc(ped) then return false end

    local off = Config.Interaction.searchOfficerOffset or { x = 0.0, y = -0.66, z = 0.0 }
    local target = GetOffsetFromEntityInWorldCoords(ped, off.x + 0.0, off.y + 0.0, off.z + 0.0)
    local heading = GetEntityHeading(ped)

    -- Enquanto o policial se posiciona atrás do abordado, desativamos a
    -- colisão entre os dois somente neste frame. Sem isso, o capsule collision
    -- do GTA pode fazer o TaskGoStraightToCoord contornar o NPC e terminar ao
    -- lado dele, mesmo com o alvo calculado exatamente atrás.
    ClearPedTasks(officer)
    TaskGoStraightToCoord(officer, target.x, target.y, target.z, 0.85, 2100, heading, 0.04)

    local untilAt = GetGameTimer() + 2100
    while DoesEntityExist(officer) and isValidNpc(ped) and GetGameTimer() < untilAt do
        SetEntityNoCollisionEntity(officer, ped, true)
        SetEntityNoCollisionEntity(ped, officer, true)
        if #(GetEntityCoords(officer) - target) <= 0.11 then break end
        Wait(0)
    end

    -- Faz apenas a correção final de poucos centímetros depois do deslocamento
    -- natural. Assim a animação começa centralizada nas costas do NPC e não
    -- depende do pathfinding ter acertado o ponto com precisão absoluta.
    if DoesEntityExist(officer) and isValidNpc(ped) then
        target = GetOffsetFromEntityInWorldCoords(ped, off.x + 0.0, off.y + 0.0, off.z + 0.0)
        SetEntityCoordsNoOffset(officer, target.x, target.y, target.z, false, false, false)
        SetEntityHeading(officer, GetEntityHeading(ped))
    end

    return true
end

local function customSearchConfig()
    local cfg = Config.Interaction and Config.Interaction.customSearchAnimation or {}
    return {
        enabled = cfg.enabled ~= false,
        officerDict = tostring(cfg.officerDict or 'cpdrevistandopolicial@animations'),
        officerClip = tostring(cfg.officerClip or 'gndrevistandopolicial_clip'),
        suspectDict = tostring(cfg.suspectDict or 'cpdanimacaomaonacabeca@animations'),
        suspectClip = tostring(cfg.suspectClip or 'gndanimacaomaonacabeca_clip'),
        durationMs = tonumber(cfg.durationMs) or 8500
    }
end

local function playCustomSearchPair(ped, st)
    local cfg = customSearchConfig()
    if not cfg.enabled then return false end

    local player = PlayerPedId()
    if not isValidNpc(ped) or player == 0 or not DoesEntityExist(player) then return false end
    if IsPedInAnyVehicle(ped, false) or IsPedInAnyVehicle(player, false) then return false end
    if not requestAnim(cfg.officerDict) or not requestAnim(cfg.suspectDict) then return false end
    if not requestControl(ped, 1800) then return false end

    local durationMs = cfg.durationMs
    if durationMs <= 0 then
        local seconds = GetAnimDuration(cfg.officerDict, cfg.officerClip)
        if seconds and seconds > 0.05 then
            durationMs = math.floor((seconds * 1000.0) + 0.5)
        end
    end
    if durationMs <= 0 then durationMs = 8500 end

    local suspectStart = GetEntityCoords(ped)
    local suspectStartHeading = GetEntityHeading(ped)
    local origin = GetEntityCoords(player)
    local heading = GetEntityHeading(player)
    local wasCuffed = st.cuffed == true

    -- Este par de YCD foi criado para comecar com os dois atores na mesma
    -- origem/heading. O jogador e sempre a ancora: somente o NPC e trazido ate
    -- ele. A v22 mantinha o NPC anexado ao policial durante toda a revista;
    -- isso segurava a root entity, mas deformava o pareamento visual do clip.
    -- Aqui o attach foi removido completamente.
    st.customSearchActive = true
    st.busyUntil = GetGameTimer() + durationMs + 1200

    ClearPedTasks(player)
    ClearPedTasksImmediately(ped)
    ClearPedSecondaryTask(ped)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedKeepTask(ped, true)
    SetPedCanRagdoll(ped, false)
    SetPedCanRagdoll(player, false)
    SetEnableHandcuffs(ped, false)
    if SetPedCanPlayGestureAnims then SetPedCanPlayGestureAnims(ped, false) end
    if SetPedCanPlayAmbientAnims then SetPedCanPlayAmbientAnims(ped, false) end
    if SetPedCanPlayAmbientBaseAnims then SetPedCanPlayAmbientBaseAnims(ped, false) end

    SetEntityNoCollisionEntity(player, ped, true)
    SetEntityNoCollisionEntity(ped, player, true)

    -- Teleporta somente o NPC para a ancora do policial. Congelamos ambos
    -- apenas durante os poucos frames de inicializacao para impedir que um clip
    -- ganhe root-motion antes do outro e produza aquele "deslizar" de entrada.
    SetEntityCoordsNoOffset(ped, origin.x, origin.y, origin.z, false, false, false)
    SetEntityHeading(ped, heading)
    SetEntityHeading(player, heading)
    FreezeEntityPosition(player, true)
    FreezeEntityPosition(ped, true)

    local pairStarted = false
    for attempt = 1, 3 do
        if attempt > 1 then
            ClearPedTasks(player)
            ClearPedTasksImmediately(ped)
            ClearPedSecondaryTask(ped)
            SetBlockingOfNonTemporaryEvents(ped, true)
            SetPedCanRagdoll(ped, false)
            SetEnableHandcuffs(ped, false)
            SetEntityCoordsNoOffset(ped, origin.x, origin.y, origin.z, false, false, false)
            SetEntityHeading(ped, heading)
            SetEntityHeading(player, heading)
            Wait(25)
        end

        -- Os dois clips sao enviados no MESMO tick. Nao confirmamos o NPC e
        -- depois iniciamos o policial; isso era a origem da defasagem visual.
        TaskPlayAnim(ped, cfg.suspectDict, cfg.suspectClip, 8.0, -8.0, durationMs, 1, 0.0, false, false, false)
        TaskPlayAnim(player, cfg.officerDict, cfg.officerClip, 8.0, -8.0, durationMs, 0, 0.0, false, false, false)
        SetPedKeepTask(ped, true)

        -- Mantemos a raiz parada durante a primeira troca de frame e soltamos
        -- os dois juntos. A partir daqui os YCDs fazem o pareamento sozinhos.
        Wait(0)
        FreezeEntityPosition(player, false)
        FreezeEntityPosition(ped, false)

        local confirmUntil = GetGameTimer() + 420
        local suspectStarted, officerStarted = false, false
        while GetGameTimer() < confirmUntil do
            SetEntityNoCollisionEntity(player, ped, true)
            SetEntityNoCollisionEntity(ped, player, true)
            suspectStarted = suspectStarted or IsEntityPlayingAnim(ped, cfg.suspectDict, cfg.suspectClip, 3)
            officerStarted = officerStarted or IsEntityPlayingAnim(player, cfg.officerDict, cfg.officerClip, 3)
            if suspectStarted and officerStarted then
                pairStarted = true
                break
            end
            Wait(10)
        end
        if pairStarted then break end

        -- So congela novamente se realmente houver uma nova tentativa.
        FreezeEntityPosition(player, true)
        FreezeEntityPosition(ped, true)
    end

    FreezeEntityPosition(player, false)
    FreezeEntityPosition(ped, false)

    if not pairStarted then
        ClearPedTasks(player)
        ClearPedTasks(ped)
        SetPedCanRagdoll(player, true)
        SetPedCanRagdoll(ped, true)
        SetEnableHandcuffs(ped, wasCuffed)
        if SetPedCanPlayGestureAnims then SetPedCanPlayGestureAnims(ped, not wasCuffed) end
        if SetPedCanPlayAmbientAnims then SetPedCanPlayAmbientAnims(ped, true) end
        if SetPedCanPlayAmbientBaseAnims then SetPedCanPlayAmbientBaseAnims(ped, true) end
        if DoesEntityExist(ped) then
            SetEntityCoordsNoOffset(ped, suspectStart.x, suspectStart.y, suspectStart.z, false, false, false)
            SetEntityHeading(ped, suspectStartHeading)
        end
        st.customSearchActive = false
        return false
    end

    startProgress('Revista pessoal', 'Realizando busca pessoal...', durationMs, function()
        if DoesEntityExist(player) and isValidNpc(ped) then
            SetEntityNoCollisionEntity(player, ped, true)
            SetEntityNoCollisionEntity(ped, player, true)
            SetBlockingOfNonTemporaryEvents(ped, true)
            SetPedKeepTask(ped, true)
            SetPedCanRagdoll(ped, false)
            SetEnableHandcuffs(ped, false)
            -- Nao existe attach e nao reiniciamos nenhum clip aqui. Reiniciar
            -- ou reposicionar no meio da janela quebra a root-motion pareada.
        end
    end)

    -- Encerra somente o primeiro ciclo da animação. NÃO devolvemos mais o NPC
    -- para a posição em que ele estava antes da revista: logo em seguida a NUI
    -- pode abrir e o par de animações será mantido. Restaurar suspectStart aqui
    -- fazia o abordado "pular" para trás e voltar à animação longe do policial.
    -- Mantemos a posição final do pareamento até sabermos se o painel abriu.
    ClearPedTasks(player)
    ClearPedTasks(ped)
    SetPedCanRagdoll(player, true)
    SetPedCanRagdoll(ped, true)

    if isValidNpc(ped) then
        SetEntityAsMissionEntity(ped, true, false)
        SetEntityVelocity(ped, 0.0, 0.0, 0.0)
        SetEntityVisible(ped, true, false)
        if GetEntityAlpha(ped) < 250 then ResetEntityAlpha(ped) end
        SetEntityCollision(ped, true, true)
        SetEnableHandcuffs(ped, wasCuffed)
        if SetPedCanPlayGestureAnims then SetPedCanPlayGestureAnims(ped, not wasCuffed) end
        if SetPedCanPlayAmbientAnims then SetPedCanPlayAmbientAnims(ped, true) end
        if SetPedCanPlayAmbientBaseAnims then SetPedCanPlayAmbientBaseAnims(ped, true) end
    end

    st.customSearchActive = false
    if wasCuffed and isValidNpc(ped) then ensureCuffVisual(ped, st) end
    return true
end

local function inventorySearchOpenFor(ped)
    if GetResourceState('fivepd_sp_inventory') ~= 'started' then return false end
    local ok, opened = pcall(function()
        return exports.fivepd_sp_inventory:RevistaAbertaPara(ped)
    end)
    return ok and opened == true
end

local function keepSearchAnimationWhileInventoryOpen(ped, st, wasPlaced, postSearchChoice)
    if not isValidNpc(ped) then return end
    local player = PlayerPedId()
    if player == 0 or not DoesEntityExist(player) then return end

    st.inventorySearchToken = (st.inventorySearchToken or 0) + 1
    local token = st.inventorySearchToken
    local wasCuffed = st.cuffed == true
    local holdCoords = GetEntityCoords(ped)
    local holdHeading = GetEntityHeading(ped)
    local wasMissionEntity = IsEntityAMissionEntity and IsEntityAMissionEntity(ped) or false

    CreateThread(function()
        st.customSearchActive = true
        st.busyUntil = GetGameTimer() + 3600000
        requestControl(ped, 1200)

        -- Decide o par ANTES de fixar a posição. Os YCDs customizados foram
        -- feitos para policial e abordado compartilharem a mesma raiz. Ao abrir
        -- o painel usamos a posição ATUAL do policial como essa raiz; assim o
        -- NPC continua alinhado com ele e nunca volta para suspectStart.
        local cfg = customSearchConfig()
        local useCustomPair = cfg.enabled
            and requestAnim(cfg.officerDict)
            and requestAnim(cfg.suspectDict)

        if useCustomPair then
            holdCoords = GetEntityCoords(player)
            holdHeading = GetEntityHeading(player)
        end

        -- Enquanto a NUI está aberta o NPC real continua no mundo. No par
        -- customizado fazemos uma única correção para a raiz atual do policial
        -- antes de reiniciar os clips; depois disso ambos permanecem congelados
        -- nessa raiz durante todo o painel.
        SetEntityAsMissionEntity(ped, true, false)
        ClearPedTasks(player)
        ClearPedTasksImmediately(ped)
        ClearPedSecondaryTask(ped)
        SetBlockingOfNonTemporaryEvents(ped, true)
        SetPedKeepTask(ped, true)
        SetPedCanRagdoll(ped, false)
        SetEntityVisible(ped, true, false)
        if GetEntityAlpha(ped) < 250 then ResetEntityAlpha(ped) end
        SetEntityCollision(ped, true, true)
        SetEntityCoordsNoOffset(ped, holdCoords.x, holdCoords.y, holdCoords.z, false, false, false)
        SetEntityHeading(ped, holdHeading)
        SetEntityVelocity(ped, 0.0, 0.0, 0.0)

        local officerDict, officerAnim = nil, nil
        local suspectDict, suspectAnim = nil, nil

        if useCustomPair then
            officerDict, officerAnim = cfg.officerDict, cfg.officerClip
            suspectDict, suspectAnim = cfg.suspectDict, cfg.suspectClip
            SetEnableHandcuffs(ped, false)
            SetEntityHeading(player, holdHeading)
            TaskPlayAnim(player, officerDict, officerAnim, 8.0, -8.0, -1, 1, 0.0, false, false, false)
            TaskPlayAnim(ped, suspectDict, suspectAnim, 8.0, -8.0, -1, 1, 0.0, false, false, false)
        else
            officerDict, officerAnim = playSearchOfficer(player)
            if wasCuffed then
                SetEnableHandcuffs(ped, true)
                ensureCuffVisual(ped, st)
            elseif requestAnim(HANDSUP_DICT) then
                suspectDict, suspectAnim = HANDSUP_DICT, HANDSUP_ANIM
                TaskPlayAnim(ped, suspectDict, suspectAnim, 4.0, -4.0, -1, 49, 0.0, false, false, false)
            else
                TaskStandStill(ped, -1)
            end
        end

        FreezeEntityPosition(player, true)
        FreezeEntityPosition(ped, true)

        while token == st.inventorySearchToken
            and isValidNpc(ped)
            and DoesEntityExist(player)
            and onDuty()
            and inventorySearchOpenFor(ped) do

            SetBlockingOfNonTemporaryEvents(ped, true)
            SetPedKeepTask(ped, true)
            SetEntityVisible(ped, true, false)
            if GetEntityAlpha(ped) < 250 then ResetEntityAlpha(ped) end
            SetEntityCollision(ped, true, true)
            SetEntityVelocity(ped, 0.0, 0.0, 0.0)
            FreezeEntityPosition(player, true)
            FreezeEntityPosition(ped, true)

            local now = GetEntityCoords(ped)
            if #(now - holdCoords) > 0.08 then
                SetEntityCoordsNoOffset(ped, holdCoords.x, holdCoords.y, holdCoords.z, false, false, false)
            end
            if math.abs(GetEntityHeading(ped) - holdHeading) > 0.5 then
                SetEntityHeading(ped, holdHeading)
            end

            if officerDict and officerAnim and not IsEntityPlayingAnim(player, officerDict, officerAnim, 3) then
                TaskPlayAnim(player, officerDict, officerAnim, 8.0, -8.0, -1, useCustomPair and 1 or 49, 0.0, false, false, false)
            end
            if suspectDict and suspectAnim and not IsEntityPlayingAnim(ped, suspectDict, suspectAnim, 3) then
                TaskPlayAnim(ped, suspectDict, suspectAnim, 8.0, -8.0, -1, useCustomPair and 1 or 49, 0.0, false, false, false)
            elseif not suspectDict and wasCuffed then
                SetEnableHandcuffs(ped, true)
                ensureCuffVisual(ped, st)
            end

            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 37, true)
            DisablePlayerFiring(PlayerId(), true)
            Wait(120)
        end

        FreezeEntityPosition(player, false)
        if DoesEntityExist(ped) then FreezeEntityPosition(ped, false) end

        if officerDict and officerAnim and DoesEntityExist(player) then
            StopAnimTask(player, officerDict, officerAnim, 2.0)
        else
            ClearPedSecondaryTask(player)
        end

        if isValidNpc(ped) then
            if suspectDict and suspectAnim then
                StopAnimTask(ped, suspectDict, suspectAnim, 2.0)
            end
            SetEntityCoordsNoOffset(ped, holdCoords.x, holdCoords.y, holdCoords.z, false, false, false)
            SetEntityHeading(ped, holdHeading)
            SetEntityVisible(ped, true, false)
            if GetEntityAlpha(ped) < 250 then ResetEntityAlpha(ped) end
            SetEntityCollision(ped, true, true)
            SetPedCanRagdoll(ped, true)
            SetEnableHandcuffs(ped, wasCuffed)
            if SetPedCanPlayGestureAnims then SetPedCanPlayGestureAnims(ped, not wasCuffed) end
            if SetPedCanPlayAmbientAnims then SetPedCanPlayAmbientAnims(ped, true) end
            if SetPedCanPlayAmbientBaseAnims then SetPedCanPlayAmbientBaseAnims(ped, true) end
        end

        if token ~= st.inventorySearchToken then return end
        st.customSearchActive = false
        st.busyUntil = 0
        st.searching = false
        if isValidNpc(ped) then syncState(ped, { searching = false }) end
        if wasCuffed and isValidNpc(ped) then ensureCuffVisual(ped, st) end

        if isValidNpc(ped) then
            if wasPlaced then
                local landed = GetEntityCoords(ped)
                st.targetPoint = vector3(landed.x, landed.y, landed.z)
                st.placedAtPoint = true
                syncState(ped, {
                    placedAtPoint = true,
                    movingToPoint = false,
                    targetX = landed.x + 0.0,
                    targetY = landed.y + 0.0,
                    targetZ = landed.z + 0.0
                })
                holdPedAtPlacedPoint(ped, st, true)
            else
                restoreApproachState(ped, st)
            end

            if not wasMissionEntity and not wasCuffed and not wasPlaced and SetEntityAsNoLongerNeeded then
                pcall(SetEntityAsNoLongerNeeded, ped)
            end

            if postSearchChoice and openPostSearchRadial then
                openPostSearchRadial(ped)
            end
        end
    end)
end

local function searchPed(ped, postSearchChoice)
    if not onDuty() then return false end
    local st = stateFor(ped)
    refreshSharedState(ped, st)
    if st.searching and tonumber(st.searchOwner or 0) ~= localServerId() then
        notify('aviso', 'Revista pessoal', 'Outro policial já está revistando esta pessoa.')
        return false
    end

    if not claimSearchLock(ped) then
        refreshSharedState(ped, st)
        notify('aviso', 'Revista pessoal', 'Outro policial já está revistando esta pessoa.')
        return false
    end

    local player = PlayerPedId()
    if not requestControl(ped) then
        st.searching = false
        st.searchOwner = 0
        syncState(ped, { searching = false })
        return false
    end

    -- A partir daqui o ped participa de uma interação longa controlada por script.
    -- Segurá-lo como mission entity evita que o ambient population manager o remova
    -- no meio da animação/NUI.
    SetEntityAsMissionEntity(ped, true, false)

    st.preventive = false
    st.preventiveApplied = false
    st.handsUp = false
    st.kneeling = false
    st.searching = true
    FreezeEntityPosition(ped, false)
    syncState(ped, { searching = true, preventive = false, handsUp = false, kneeling = false })

    closeRadial()
    local wasPlaced = st.placedAtPoint == true
    if wasPlaced then setPlacedPositionLock(ped, st, false, false) end
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedKeepTask(ped, true)

    -- Primeiro o abordado gira naturalmente e fica de costas para o policial.
    turnPedBackToOfficerForSearch(ped, st)

    local customCfg = customSearchConfig()
    local expectedDuration = customCfg.enabled and customCfg.durationMs or (Config.Interaction.searchDuration or 3000)
    if expectedDuration <= 0 then expectedDuration = 8500 end
    st.busyUntil = GetGameTimer() + expectedDuration + 1800

    -- A animação do script de referência é um par customizado: policial e NPC
    -- compartilham origem/heading e os próprios YCDs fazem o encaixe da revista.
    -- Se o asset não carregar, preservamos a revista nativa anterior como fallback.
    local usedCustom = playCustomSearchPair(ped, st)

    if not usedCustom then
        FreezeEntityPosition(ped, true)
        alignOfficerBehindForSearch(ped)

        if st.cuffed then
            ensureCuffVisual(ped, st)
        elseif requestAnim(HANDSUP_DICT) then
            TaskPlayAnim(ped, HANDSUP_DICT, HANDSUP_ANIM, 4.0, -4.0, -1, 49, 0.0, false, false, false)
        else
            TaskStandStill(ped, 4000)
        end

        FreezeEntityPosition(player, true)
        local searchDict, searchAnim = playSearchOfficer(player)
        local searchDuration = Config.Interaction.searchDuration or 3000
        startProgress('Revista pessoal', 'Realizando busca pessoal...', searchDuration)
        if searchDict and searchAnim then
            StopAnimTask(player, searchDict, searchAnim, 2.0)
        else
            ClearPedSecondaryTask(player)
        end
        FreezeEntityPosition(player, false)
        if isValidNpc(ped) then
            if not st.cuffed then ClearPedSecondaryTask(ped) end
            FreezeEntityPosition(ped, false)
        end
    end

    if isValidNpc(ped) then
        st.customSearchActive = false
        local inventoryOpened = false
        if GetResourceState('fivepd_sp_inventory') == 'started' then
            local okInventory, resultInventory = pcall(function()
                return exports.fivepd_sp_inventory:AbrirRevistaNpc(ped)
            end)
            inventoryOpened = okInventory and resultInventory == true
        end
        if inventoryOpened then
            -- Não reabre o radial enquanto o painel de resultados estiver ativo.
            -- A animação de revista continua em loop até o jogador fechar a NUI.
            keepSearchAnimationWhileInventoryOpen(ped, st, wasPlaced, postSearchChoice == true)
            return true
        end

        st.searching = false
        syncState(ped, { searching = false })

        local cash = math.random(12, 460)
        local extras = ({ 'chaves e um celular', 'carteira e um celular', 'carteira, chaves e um isqueiro', 'documentos e um celular' })[math.random(1, 4)]
        notify('info', 'Revista pessoal', ('Encontrado: %s • R$ %d.'):format(extras, cash))
        if wasPlaced then
            local landed = GetEntityCoords(ped)
            st.targetPoint = vector3(landed.x, landed.y, landed.z)
            st.placedAtPoint = true
            st.busyUntil = 0
            syncState(ped, {
                placedAtPoint = true,
                movingToPoint = false,
                targetX = landed.x + 0.0,
                targetY = landed.y + 0.0,
                targetZ = landed.z + 0.0
            })
            holdPedAtPlacedPoint(ped, st, true)
        else
            restoreApproachState(ped, st)
        end
        if postSearchChoice and openPostSearchRadial then
            openPostSearchRadial(ped)
        end
    end
    return false
end

exports('RevistarPreventiva', function(ped)
    if not onDuty() or not isValidNpc(ped) then return false end
    local st = stateFor(ped)
    requestControl(ped, 1000)
    st.approached = true
    st.seated = false
    st.following = false
    st.held = false
    st.insideVehicle = false
    st.enteringVehicle = false
    st.preventive = false
    st.preventiveApplied = false
    FreezeEntityPosition(ped, false)
    syncState(ped, {
        approached = true,
        seated = false,
        following = false,
        held = false,
        insideVehicle = false,
        preventive = false
    })
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedKeepTask(ped, true)
    return searchPed(ped, true)
end)

local function releasePed(ped)
    if not onDuty() then return false end
    local st = stateFor(ped)
    if st.cuffed then
        notify('aviso', 'Abordagem', 'Desalgeme a pessoa antes de liberá-la.')
        return false
    end

    requestControl(ped)
    setPlacedPositionLock(ped, st, false, false)
    detachEscort(ped)
    if escortedPed == ped then escortedPed = nil end
    hideEscortHelp()
    st.dialogueToken = (st.dialogueToken or 0) + 1
    if st.dialogueFrozen then
        FreezeEntityPosition(ped, false)
        st.dialogueFrozen = false
    end
    st.approached = false
    st.seated = false
    clearPlacedPoint(ped, st)
    st.following = false
    st.held = false
    st.insideVehicle = IsPedInAnyVehicle(ped, false)
    syncState(ped, {
        approached = false,
        seated = false,
        following = false,
        held = false,
        insideVehicle = st.insideVehicle,
        preventive = false
    })
    SetPedKeepTask(ped, false)
    SetBlockingOfNonTemporaryEvents(ped, false)
    ClearPedTasks(ped)
    if not IsPedInAnyVehicle(ped, false) then TaskWanderStandard(ped, 10.0, 10) end
    notify('sucesso', 'Abordagem', 'Pessoa liberada.')
    return true
end

local function openDialogue(ped)
    if not onDuty() then return false end

    -- NPCs criados por uma QRU podem ter diálogos próprios. Eles substituem
    -- as falas genéricas da abordagem, mas somente para aquele ator.
    local qruDialogues = {}
    if GetResourceState('fivepd_sp_qru') == 'started' then
        local ok, rows = pcall(function()
            return exports.fivepd_sp_qru:GetQruDialoguesForPed(ped)
        end)
        if ok and type(rows) == 'table' then qruDialogues = rows end
    end
    if #qruDialogues == 1 then
        closeRadial()
        local ok, opened = pcall(function()
            return exports.fivepd_sp_qru:OpenQruDialogueForPed(ped, qruDialogues[1].id)
        end)
        if ok and opened == true then return true end
        -- Se a ocorrência encerrou exatamente entre a consulta e a abertura,
        -- cai com segurança para o diálogo padrão abaixo.
    elseif #qruDialogues > 1 then
        local options = {}
        for index, dialogue in ipairs(qruDialogues) do
            local lines = tonumber(dialogue.line_count) or 0
            local choices = tonumber(dialogue.choice_count) or 0
            local description = ('%d fala(s) • %d escolha(s)'):format(lines, choices)
            if dialogue.attendance == true then description = description .. ' • atendimento' end
            options[#options + 1] = {
                id = ('qdlg:%d'):format(index),
                title = tostring(dialogue.title or dialogue.label or ('Conversa ' .. index)),
                icon = 'FAL',
                description = description
            }
        end
        openRadial('Dialogar', 'DIÁLOGOS DA OCORRÊNCIA', options, 'qru_dialogue', { ped = ped, dialogues = qruDialogues }, true)
        return true
    end

    openRadial('Dialogar', 'ESCOLHA UMA FALA', {
        { id = 'dlg:id', title = 'Solicitar identificação', icon = 'RG', description = 'Peça documento e identificação.' },
        { id = 'dlg:reason', title = 'Perguntar o que aconteceu', icon = '?', description = 'Pergunte o motivo da situação.' },
        { id = 'dlg:illegal', title = 'Questionar sobre ilícitos', icon = '!', description = 'Pergunte se porta algo ilegal.' },
        { id = 'dlg:wait', title = 'Mandar aguardar', icon = '...', description = 'Oriente a pessoa a permanecer no local.' }
    }, 'dialogue', { ped = ped }, true)
    return true
end

local function doDialogue(ped, id)
    if not onDuty() then return false end
    local replies = {
        ['dlg:id'] = { 'Certo, policial. Meu documento está comigo.', 'Tudo bem, posso me identificar.' },
        ['dlg:reason'] = { 'Eu estava apenas passando por aqui.', 'Não aconteceu nada comigo, estava indo embora.' },
        ['dlg:illegal'] = { 'Não, não tenho nada ilegal comigo.', 'Não, senhor. Pode verificar.' },
        ['dlg:wait'] = { 'Tudo bem, vou aguardar aqui.', 'Certo, policial.' }
    }
    if id == 'dlg:reason' and NetworkGetEntityIsNetworked(ped) then
        local okAmbient, ambientReason = pcall(function()
            return Entity(ped).state['fivepd_sp:ambient:dialogueReason']
        end)
        if okAmbient and type(ambientReason) == 'string' and ambientReason ~= '' then
            replies['dlg:reason'] = { ambientReason }
        end
    end
    local anims = {
        ['dlg:id'] = { officer = 'gesture_point', npc = 'gesture_nod_yes_soft' },
        ['dlg:reason'] = { officer = 'gesture_why', npc = 'gesture_shrug_soft' },
        ['dlg:illegal'] = { officer = 'gesture_point', npc = 'gesture_nod_no_soft' },
        ['dlg:wait'] = { officer = 'gesture_easy_now', npc = 'gesture_nod_yes_soft' }
    }
    local pool = replies[id] or { 'Entendido.' }
    local choice = anims[id] or { officer = 'gesture_easy_now', npc = 'gesture_nod_yes_soft' }
    local st = stateFor(ped)
    local player = PlayerPedId()
    requestControl(ped)
    SetPedKeepTask(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)

    st.dialogueToken = (st.dialogueToken or 0) + 1
    local token = st.dialogueToken
    st.busyUntil = GetGameTimer() + 2600

    CreateThread(function()
        if not isValidNpc(ped) or not DoesEntityExist(player) then return end

        -- O FivePD original mantém o ped sob uma tarefa permanente e bloqueia
        -- eventos ambiente. Aqui fazemos o mesmo, mas sem deixar o ped dar
        -- aqueles pequenos passos de reposicionamento durante a conversa.
        local pc = GetEntityCoords(player)
        local nc = GetEntityCoords(ped)
        SetEntityHeading(ped, GetHeadingFromVector_2d(pc.x - nc.x, pc.y - nc.y))
        SetEntityHeading(player, GetHeadingFromVector_2d(nc.x - pc.x, nc.y - pc.y))

        if not st.seated and not st.held and not st.following and not st.insideVehicle then
            ClearPedTasks(ped)
            TaskStandStill(ped, 2600)
            FreezeEntityPosition(ped, true)
            st.dialogueFrozen = true
        end

        if requestAnim(DIALOG_DICT) then
            TaskPlayAnim(player, DIALOG_DICT, choice.officer, 4.0, -4.0, 1750, 48, 0.0, false, false, false)
            if not st.cuffed and not st.seated and not st.insideVehicle then
                TaskPlayAnim(ped, DIALOG_DICT, choice.npc, 4.0, -4.0, 1750, 48, 0.0, false, false, false)
            end
        end
        if st.cuffed then ensureCuffVisual(ped, st) end

        Wait(450)
        if isValidNpc(ped) and st.dialogueToken == token then
            notify('info', 'Pessoa abordada', pool[math.random(1, #pool)])
        end

        Wait(1450)
        ClearPedSecondaryTask(player)
        if not isValidNpc(ped) or st.dialogueToken ~= token then return end
        if not st.cuffed then ClearPedSecondaryTask(ped) end
        if st.dialogueFrozen then
            FreezeEntityPosition(ped, false)
            st.dialogueFrozen = false
        end
        restoreApproachState(ped, st)
    end)
end

local function openVehicleSeats(ped)
    if not onDuty() then return false end
    local st = stateFor(ped)
    if not st.cuffed then return notify('aviso', 'Custódia', 'A pessoa precisa estar algemada.') end
    local vehicle = nearestVehicle(ped, Config.Interaction.vehicleSearchDistance)
    if vehicle == 0 then return notify('aviso', 'Custódia', 'Nenhum veículo próximo.') end
    local options = availableSeatOptions(ped, vehicle)
    local anyEnabled = false
    for _, opt in ipairs(options) do if not opt.disabled then anyEnabled = true break end end
    if not anyEnabled then
        notify('aviso', 'Custódia', 'Abra manualmente a porta ou o porta-malas correspondente ao banco de custódia.')
        return
    end
    openRadial('Colocar na viatura', 'SELECIONE O BANCO', options, 'vehicle_enter', { ped = ped, vehicle = vehicle }, true)
end

local function enterVehicle(ped, vehicle, seat)
    if not onDuty() then return false end
    if not isValidNpc(ped) or vehicle == 0 or not DoesEntityExist(vehicle) then return end
    local st = stateFor(ped)
    if not st.cuffed then return end
    local access = FivePD_ResolveCustodySeatAccess(vehicle, seat)
    local door = access.door
    if not IsVehicleSeatFree(vehicle, seat) then return notify('aviso', 'Custódia', 'Esse banco está ocupado.') end
    if not doorIsOpen(vehicle, door) then
        return notify('aviso', 'Custódia', access.trunk and 'Abra o porta-malas antes de colocar a pessoa neste banco.' or 'Abra a porta correspondente antes de colocar a pessoa no veículo.')
    end

    requestControl(ped)
    setPlacedPositionLock(ped, st, false, false)
    requestControl(vehicle)
    detachEscort(ped)
    clearEscortOwner(ped)
    st.seated = false
    st.following = false
    st.held = false
    clearPlacedPoint(ped, st)
    st.enteringVehicle = true
    syncState(ped, { seated = false, following = false, held = false })
    ClearPedTasks(ped)

    local entry = FivePD_CustodyEntryPosition(vehicle, door, ped)
    if entry and entry.x then
        TaskGoStraightToCoord(ped, entry.x, entry.y, entry.z, 1.0, 4500, GetEntityHeading(vehicle), 0.25)
        local untilAt = GetGameTimer() + 4500
        while isValidNpc(ped) and #(GetEntityCoords(ped) - entry) > 1.35 and GetGameTimer() < untilAt do
            if st.cuffed then ensureCuffVisual(ped, st) end
            Wait(80)
        end
    end

    if not doorIsOpen(vehicle, door) then
        st.enteringVehicle = false
        TaskStandStill(ped, -1)
        ensureCuffVisual(ped, st)
        return notify('aviso', 'Custódia', access.trunk and 'O porta-malas foi fechado. Abra novamente para a entrada.' or 'A porta foi fechada. Abra novamente para a entrada.')
    end

    if access.warp then
        -- Bancos físicos de cela/porta-malas muitas vezes usam um EntryPoint
        -- lateral incorreto no vehiclelayout. Caminhamos até o compartimento
        -- certo e fazemos somente a etapa final de acomodação por warp.
        TaskTurnPedToFaceEntity(ped, vehicle, 350)
        Wait(380)
        TaskWarpPedIntoVehicle(ped, vehicle, seat)
    else
        TaskEnterVehicle(ped, vehicle, 12000, seat, 1.0, 1, 0)
    end

    local untilAt = GetGameTimer() + (access.warp and 2500 or 12500)
    CreateThread(function()
        while isValidNpc(ped) and not IsPedInVehicle(ped, vehicle, false) and GetGameTimer() < untilAt do
            if st.cuffed then ensureCuffVisual(ped, st) end
            Wait(access.warp and 80 or 180)
        end
        st.enteringVehicle = false
        if IsPedInVehicle(ped, vehicle, false) then
            st.insideVehicle = true
            local vehicleNetId = NetworkGetEntityIsNetworked(vehicle) and NetworkGetNetworkIdFromEntity(vehicle) or 0
            st.vehicleNetId = vehicleNetId or 0
            st.vehicleSeat = seat
            syncState(ped, {
                insideVehicle = true,
                vehicleNetId = st.vehicleNetId,
                vehicleSeat = seat
            })
            ensureCuffVisual(ped, st)
            notify('sucesso', 'Custódia', ('Pessoa acomodada em %s.'):format(FivePD_CustodySeatLabel(vehicle, seat, access)))
        else
            TaskStandStill(ped, -1)
            ensureCuffVisual(ped, st)
            notify('aviso', 'Custódia', 'A pessoa não conseguiu entrar no veículo.')
        end
    end)
end

local function openExitRadial(vehicle)
    if not onDuty() then return false end
    local occupants = findCuffedOccupants(vehicle)
    if #occupants == 0 then return notify('info', 'Custódia', 'Não há pessoa algemada neste veículo.') end
    local options = {}
    for i, item in ipairs(occupants) do
        local access = item.access or FivePD_ResolveCustodySeatAccess(vehicle, item.seat)
        local open = doorIsOpen(vehicle, access.door)
        options[#options + 1] = {
            id = ('exit:%d'):format(i),
            title = FivePD_CustodySeatLabel(vehicle, item.seat, access),
            icon = 'SAI',
            description = open and (access.trunk and 'Porta-malas aberto • retirar pessoa' or 'Porta aberta • retirar pessoa') or (access.trunk and 'Abra o porta-malas primeiro' or 'Abra esta porta primeiro'),
            disabled = not open
        }
    end
    openRadial('Retirar da viatura', 'SELECIONE A PESSOA', options, 'vehicle_exit', { vehicle = vehicle, occupants = occupants })
end

local function exitVehicle(vehicle, item)
    if not onDuty() then return false end
    if not item or not isValidNpc(item.ped) or not DoesEntityExist(vehicle) then return end
    local access = item.access or FivePD_ResolveCustodySeatAccess(vehicle, item.seat)
    if not doorIsOpen(vehicle, access.door) then
        return notify('aviso', 'Custódia', access.trunk and 'Abra o porta-malas antes de retirar a pessoa.' or 'Abra a porta correspondente antes de retirar a pessoa.')
    end
    local ped = item.ped
    local st = stateFor(ped)
    requestControl(ped)
    requestControl(vehicle)
    if access.trunk then
        TaskLeaveVehicle(ped, vehicle, 16)
    else
        TaskLeaveVehicle(ped, vehicle, 0)
    end
    CreateThread(function()
        local untilAt = GetGameTimer() + (access.trunk and 3000 or 8000)
        while isValidNpc(ped) and IsPedInVehicle(ped, vehicle, false) and GetGameTimer() < untilAt do Wait(100) end
        if isValidNpc(ped) and not IsPedInAnyVehicle(ped, false) then
            if access.trunk then
                local entry = FivePD_CustodyEntryPosition(vehicle, access.door, ped)
                if entry and entry.x then
                    SetEntityCoordsNoOffset(ped, entry.x, entry.y, entry.z, false, false, false)
                    SetEntityHeading(ped, GetEntityHeading(vehicle))
                end
            end
            st.insideVehicle = false
            st.vehicleNetId = 0
            st.vehicleSeat = 0
            syncState(ped, { insideVehicle = false, vehicleNetId = 0, vehicleSeat = 0 })
            TaskStandStill(ped, -1)
            ensureCuffVisual(ped, st)
            notify('sucesso', 'Custódia', 'Pessoa retirada do veículo.')
        end
    end)
end

local function approachPed(ped)
    if not isValidNpc(ped) or not onDuty() then return end
    closeInteraction()
    requestControl(ped)
    local st = stateFor(ped)
    st.approached = true
    syncState(ped, { approached = true })
    SetPedKeepTask(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedFleeAttributes(ped, 0, false)

    -- Se a pessoa foi mandada permanecer em um ponto, não limpamos a trava nem
    -- executamos uma nova task de locomoção ao reabrir a abordagem. O radial já
    -- possui a rotação suave que faz o ped olhar para o policial sem sair do lugar.
    if st.placedAtPoint and st.targetPoint then
        st.busyUntil = 0
        holdPedAtPlacedPoint(ped, st, true)
        if st.cuffed then ensureCuffVisual(ped, st) end
        openMainRadial(ped)
        return
    end

    ClearPedTasks(ped)
    st.busyUntil = GetGameTimer() + 850
    TaskTurnPedToFaceEntity(ped, PlayerPedId(), 700)
    Wait(350)
    TaskStandStill(ped, -1)
    if st.cuffed then ensureCuffVisual(ped, st) end
    openMainRadial(ped)
end

local function dismissPed(ped)
    if not isValidNpc(ped) or not onDuty() then return end
    closeInteraction()
    requestControl(ped)
    local st = stateFor(ped)
    setPlacedPositionLock(ped, st, false, false)
    if st.cuffed then return notify('aviso', 'Abordagem', 'Desalgeme a pessoa antes de mandá-la sair do local.') end
    clearFollowState(ped, st)
    st.approached = false
    st.seated = false
    clearPlacedPoint(ped, st)
    syncState(ped, { approached = false, seated = false, following = false, held = false })
    st.dialogueToken = (st.dialogueToken or 0) + 1
    if st.dialogueFrozen then
        FreezeEntityPosition(ped, false)
        st.dialogueFrozen = false
    end
    SetPedKeepTask(ped, false)
    SetBlockingOfNonTemporaryEvents(ped, false)
    ClearPedTasks(ped)

    local officer = PlayerPedId()
    local pc = GetEntityCoords(officer)
    local nc = GetEntityCoords(ped)
    local dx, dy = nc.x - pc.x, nc.y - pc.y
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.05 then
        local heading = math.rad(GetEntityHeading(officer))
        dx, dy = -math.sin(heading), math.cos(heading)
        len = 1.0
    end
    dx, dy = dx / len, dy / len
    local distance = Config.Interaction.walkAwayDistance or 28.0
    local tx, ty = nc.x + dx * distance, nc.y + dy * distance
    TaskGoStraightToCoord(ped, tx, ty, nc.z, 1.0, 18000, GetEntityHeading(ped), 0.4)
    CreateThread(function()
        Wait(9000)
        if isValidNpc(ped) and not IsPedInAnyVehicle(ped, false) then TaskWanderStandard(ped, 10.0, 10) end
    end)
end

local localJailState = nil
local playerCustodyLastCuffed = false
local playerCustodyWasAttached = false
local playerCustodyLastFollowAt = 0
local playerCustodyPairAnimUntil = 0
local playerInteractionSearchToken = 0
local localPlayerHandsUpApplied = false
local localPlayerKneelingApplied = false

local function isOtherPlayerPed(ped)
    -- Condições do sistema de interaction são avaliadas enquanto entidades podem
    -- entrar/sair do streaming. Também rejeitamos explicitamente qualquer valor
    -- que não seja um handle numérico antes de tocar em natives.
    if type(ped) ~= 'number' or ped <= 0 or ped == PlayerPedId() then
        return false
    end

    local ok, valido = pcall(function()
        return DoesEntityExist(ped)
            and IsEntityAPed(ped)
            and IsPedAPlayer(ped)
            and not IsEntityDead(ped)
            and IsPedHuman(ped)
    end)

    return ok and not not valido
end

local function serverIdForPlayerPed(ped)
    if not isOtherPlayerPed(ped) then return nil end
    local playerIndex = NetworkGetPlayerIndexFromPed(ped)
    if playerIndex == -1 then return nil end
    local serverId = GetPlayerServerId(playerIndex)
    return serverId and serverId > 0 and serverId or nil
end

local function playerPedCharacterType(ped)
    local serverId = serverIdForPlayerPed(ped)
    if not serverId then return nil end
    local ok, value = pcall(function()
        return Player(serverId).state['fivepd_sp:personagemTipo']
    end)
    value = ok and tostring(value or ''):lower() or ''
    if value == 'policial' or value == 'ilegal' then return value end
    return nil
end

local function playerPedIsJailed(ped)
    if type(ped) ~= 'number' or ped <= 0 then return false end
    local okExiste, existe = pcall(DoesEntityExist, ped)
    if not okExiste or existe ~= true then return false end
    local ok, value = pcall(function() return Entity(ped).state['fivepd_sp:police:jailed'] end)
    if ok and value == true then return true end
    local serverId = serverIdForPlayerPed(ped)
    if serverId then
        local okPlayer, playerValue = pcall(function() return Player(serverId).state['fivepd_sp:police:jailed'] end)
        if okPlayer and playerValue == true then return true end
    end
    return false
end

local function canPoliceInteractWithPlayerPed(ped)
    return onDuty()
        and isOtherPlayerPed(ped)
        and playerPedCharacterType(ped) == 'ilegal'
        and not playerPedIsJailed(ped)
end

local function cuffedPlayerOccupants(vehicle)
    local out = {}
    if vehicle == 0 or not DoesEntityExist(vehicle) then return out end
    local maxSeat = FivePD_CustodyMaxPassengerSeat(vehicle)
    for seat = 0, maxSeat do
        local ped = GetPedInVehicleSeat(vehicle, seat)
        if canPoliceInteractWithPlayerPed(ped) and bagValue(ped, 'cuffed') == true then
            local serverId = serverIdForPlayerPed(ped)
            if serverId then
                local access = FivePD_ResolveCustodySeatAccess(vehicle, seat)
                out[#out + 1] = { ped = ped, serverId = serverId, seat = seat, door = access.door, access = access }
            end
        end
    end
    return out
end

local function firstFreePlayerCustodySeat(vehicle)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return nil end
    local maxSeat = FivePD_CustodyMaxPassengerSeat(vehicle)

    -- Para presos, prioriza os bancos cujo acesso físico é pelo porta-malas/cela.
    for seat = 0, maxSeat do
        local access = FivePD_ResolveCustodySeatAccess(vehicle, seat)
        if access.trunk and IsVehicleSeatFree(vehicle, seat) and doorIsOpen(vehicle, access.door) then
            return seat
        end
    end

    -- Depois usa bancos traseiros/laterais com a porta realmente aberta.
    for seat = 1, maxSeat do
        local access = FivePD_ResolveCustodySeatAccess(vehicle, seat)
        if not access.trunk and IsVehicleSeatFree(vehicle, seat) and doorIsOpen(vehicle, access.door) then
            return seat
        end
    end

    -- Passageiro dianteiro apenas como último recurso.
    if maxSeat >= 0 and IsVehicleSeatFree(vehicle, 0) then
        local access = FivePD_ResolveCustodySeatAccess(vehicle, 0)
        if doorIsOpen(vehicle, access.door) then return 0 end
    end
    return nil
end

local function playOfficerCuffOnly(targetPed, cuffing)
    local officer = PlayerPedId()
    if targetPed and targetPed ~= 0 and DoesEntityExist(targetPed) then TaskTurnPedToFaceEntity(officer, targetPed, 350) end
    if cuffing then
        if requestAnim(CUFF_PAIR_DICT) then
            TaskPlayAnim(officer, CUFF_PAIR_DICT, CUFF_OFFICER_ANIM, 8.0, -8.0, 3750, 2, 0.0, false, false, false)
            CreateThread(function() Wait(3850); if DoesEntityExist(officer) then StopAnimTask(officer, CUFF_PAIR_DICT, CUFF_OFFICER_ANIM, 2.0) end end)
        end
    else
        if requestAnim(UNCUFF_DICT) then
            TaskPlayAnim(officer, UNCUFF_DICT, UNCUFF_ANIM, 8.0, -8.0, 2400, 48, 0.0, false, false, false)
            CreateThread(function() Wait(2350); if DoesEntityExist(officer) then StopAnimTask(officer, UNCUFF_DICT, UNCUFF_ANIM, 2.0) end end)
        end
    end
end

FivePD_PlayerCustodyEscortAnchor = FivePD_PlayerCustodyEscortAnchor or 0

local function detachLocalCustodyEscort()
    local ped = PlayerPedId()
    if IsEntityAttached(ped) then DetachEntity(ped, true, false) end
    if FivePD_PlayerCustodyEscortAnchor and FivePD_PlayerCustodyEscortAnchor ~= 0 then
        FivePD_DeleteEscortAnchor(FivePD_PlayerCustodyEscortAnchor)
        FivePD_PlayerCustodyEscortAnchor = 0
    end
    stopEscortPrisonerAnim(ped)
    SetEntityCollision(ped, true, true)
    if playerCustodyWasAttached and not IsPedInAnyVehicle(ped, false) then
        -- Cancela somente a locomoção automática; a animação de algemado é
        -- reaplicada imediatamente pelo loop de custódia.
        ClearPedTasks(ped)
    end
    playerCustodyWasAttached = false
    playerCustodyLastFollowAt = 0
end

local function ensureLocalCustodyEscort(controllerServerId)
    local ped = PlayerPedId()
    local index = GetPlayerFromServerId(tonumber(controllerServerId) or -1)
    if index == -1 then detachLocalCustodyEscort(); return false end
    local officer = GetPlayerPed(index)
    if officer == 0 or not DoesEntityExist(officer) or IsEntityDead(officer) or IsPedInAnyVehicle(officer, false) then
        detachLocalCustodyEscort()
        return false
    end

    local x, y, z = escortOffset()
    if Config.Interaction.escortSoft ~= false then
        if IsEntityAttached(ped) then DetachEntity(ped, true, false) end
        SetEntityCollision(ped, true, true)
        local dist = #(GetEntityCoords(ped) - GetEntityCoords(officer))
        local maxSep = tonumber(Config.Interaction.escortMaxSeparation) or 4.5
        if dist > maxSep then
            -- Não teleporta jogador real. Se a sincronização se perder demais,
            -- o servidor encerrará a condução pela validação de distância.
            return false
        end
        local now = GetGameTimer()
        if now - (playerCustodyLastFollowAt or 0) >= 400 then
            TaskFollowToOffsetOfEntity(
                ped, officer, x, y, z,
                tonumber(Config.Interaction.escortFollowSpeed) or 1.05,
                -1,
                tonumber(Config.Interaction.escortStopRange) or 0.34,
                true
            )
            playerCustodyLastFollowAt = now
        end
    else
        FivePD_PlayerCustodyEscortAnchor = FivePD_CreateEscortAnchor(officer, FivePD_PlayerCustodyEscortAnchor)
        if FivePD_PlayerCustodyEscortAnchor ~= 0 then
            FivePD_AttachEscortPedToAnchor(ped, officer, FivePD_PlayerCustodyEscortAnchor)
        end
        SetEntityNoCollisionEntity(ped, officer, true)
        ensureEscortPrisonerAnim(ped, officer)
    end
    playerCustodyWasAttached = true
    return true
end

local function ensureLocalPlayerCuffedVisual()
    local ped = PlayerPedId()
    if not IsEntityVisible(ped) then SetEntityVisible(ped, true, false) end
    if GetEntityAlpha(ped) < 250 then ResetEntityAlpha(ped) end
    SetEntityCollision(ped, true, true)
    -- O próprio cliente já possui o ped local; iniciar NetworkFadeInEntity a
    -- cada frame criava o mesmo efeito de piscar em jogadores algemados.
    ensureCuffProp(ped)
    SetEnableHandcuffs(ped, true)
    SetPedCanPlayGestureAnims(ped, false)
    if not IsPedInAnyVehicle(ped, false) then
        if requestAnim(CUFF_DICT) and not IsEntityPlayingAnim(ped, CUFF_DICT, CUFF_ANIM, 3) then
            TaskPlayAnim(ped, CUFF_DICT, CUFF_ANIM, 4.0, -4.0, -1, 49, 0.0, false, false, false)
        end
    end
end

local function clearLocalPlayerCuffedVisual()
    local ped = PlayerPedId()
    removeCuffProp(ped)
    SetEnableHandcuffs(ped, false)
    SetPedCanPlayGestureAnims(ped, true)
    StopAnimTask(ped, CUFF_DICT, CUFF_ANIM, 2.0)
    detachLocalCustodyEscort()
end

local function playerDisplayName(ped)
    if not isOtherPlayerPed(ped) then return 'Jogador abordado' end
    local playerIndex = NetworkGetPlayerIndexFromPed(ped)
    local name = playerIndex ~= -1 and GetPlayerName(playerIndex) or nil
    name = tostring(name or '')
    return name ~= '' and name or 'Jogador abordado'
end

local function playerSearchAllowed(ped)
    return canPoliceInteractWithPlayerPed(ped)
        and (bagValue(ped, 'cuffed') == true or bagValue(ped, 'handsUp') == true or bagValue(ped, 'kneeling') == true)
        and not IsPedInAnyVehicle(ped, false)
end

local function playerMainOptions(ped)
    return {
        { id = 'pcategory:identification', title = 'Identificação', icon = 'ID', description = 'Documentos e revista pessoal.' },
        { id = 'pcategory:control', title = 'Custódia', icon = 'ALG', description = 'Algemar ou retirar as algemas.' },
        { id = 'pcategory:conduction', title = 'Condução', icon = 'CON', description = 'Conduzir e colocar na viatura.' },
        { id = 'pcategory:finish', title = 'Encerrar', icon = 'FIM', description = 'Encerrar a abordagem do jogador.' }
    }
end

local function openPlayerMainRadial(ped)
    if not canPoliceInteractWithPlayerPed(ped) then return false end
    currentPed = ped
    openRadial(playerDisplayName(ped), 'INTERAÇÃO COM JOGADOR', playerMainOptions(ped), 'player_main', { ped = ped }, false)
    return true
end

local function playerIdentificationOptions(ped)
    local canSearch = playerSearchAllowed(ped)
    return {
        {
            id = 'player:search', title = 'Revistar jogador', icon = 'REV',
            description = canSearch and 'Abrir a revista pessoal e apreender objetos quando necessário.' or 'A pessoa precisa estar algemada ou ter aceitado uma ordem de rendição.',
            disabled = not canSearch
        },
        { id = 'player:documents', title = 'Solicitar documentos', icon = 'DOC', description = 'Consultar os documentos apresentados pelo personagem.' }
    }
end

local function playerControlOptions(ped)
    local cuffed = bagValue(ped, 'cuffed') == true
    return {
        {
            id = 'player:cuff', title = cuffed and 'Desalgemar' or 'Algemar', icon = 'ALG',
            description = cuffed and 'Retirar as algemas do jogador.' or 'Aplicar algemas e iniciar custódia.'
        }
    }
end

local function playerConductionOptions(ped)
    local cuffed = bagValue(ped, 'cuffed') == true
    local held = bagValue(ped, 'held') == true
    local inVehicle = IsPedInAnyVehicle(ped, false)
    local vehicle = not inVehicle and nearestVehicle(ped, Config.Interaction.vehicleSearchDistance) or 0
    local seat = vehicle ~= 0 and firstFreePlayerCustodySeat(vehicle) or nil
    return {
        {
            id = 'player:hold', title = held and 'Soltar jogador' or 'Conduzir pelo braço', icon = 'CON',
            description = cuffed and (held and 'Encerrar a condução.' or 'Conduzir o jogador algemado junto ao policial.') or 'Disponível somente para jogador algemado.',
            disabled = not cuffed or inVehicle
        },
        {
            id = 'player:vehicle', title = 'Colocar na viatura', icon = 'VTR',
            description = (cuffed and seat ~= nil) and (FivePD_ResolveCustodySeatAccess(vehicle, seat).trunk and 'Colocar no compartimento de custódia com o porta-malas aberto.' or 'Colocar no banco com a porta correspondente aberta.') or 'Algeme o jogador e aproxime-se de uma viatura com acesso de custódia aberto.',
            disabled = not cuffed or inVehicle or seat == nil
        }
    }
end

local function playerFinishOptions(ped)
    local cuffed = bagValue(ped, 'cuffed') == true
    local held = bagValue(ped, 'held') == true
    local inVehicle = IsPedInAnyVehicle(ped, false)
    return {
        {
            id = 'player:release', title = 'Liberar abordagem', icon = 'LIB',
            description = cuffed and 'Desalgeme o jogador antes de liberar.' or (held and 'Solte a condução antes de liberar.' or 'Limpar ordens de rendição e encerrar a abordagem.'),
            disabled = cuffed or held or inVehicle
        }
    }
end

local function openPlayerCategoryRadial(ped, category)
    if not canPoliceInteractWithPlayerPed(ped) then return false end
    if category == 'identification' then
        openRadial('Identificação', 'JOGADOR ABORDADO', playerIdentificationOptions(ped), 'player_category:identification', { ped = ped }, true)
    elseif category == 'control' then
        openRadial('Custódia', 'JOGADOR ABORDADO', playerControlOptions(ped), 'player_category:control', { ped = ped }, true)
    elseif category == 'conduction' then
        openRadial('Condução', 'JOGADOR ABORDADO', playerConductionOptions(ped), 'player_category:conduction', { ped = ped }, true)
    elseif category == 'finish' then
        openRadial('Encerrar abordagem', 'JOGADOR ABORDADO', playerFinishOptions(ped), 'player_category:finish', { ped = ped }, true)
    else
        return false
    end
    return true
end

local function triggerPlayerCustodyAction(ped, action)
    local serverId = serverIdForPlayerPed(ped)
    if not serverId then return false end
    if action == 'cuff' then
        TriggerServerEvent('fivepd_sp:police:playerCustody:toggleCuff', serverId)
    elseif action == 'hold' then
        TriggerServerEvent('fivepd_sp:police:playerCustody:toggleEscort', serverId)
    elseif action == 'release' then
        TriggerServerEvent('fivepd_sp:police:playerInteraction:release', serverId)
    else
        return false
    end
    return true
end

local function putPlayerInNearestVehicle(ped)
    local serverId = serverIdForPlayerPed(ped)
    if not serverId then return false end
    local vehicle = nearestVehicle(ped, Config.Interaction.vehicleSearchDistance)
    local seat = firstFreePlayerCustodySeat(vehicle)
    if vehicle == 0 or seat == nil then
        notify('aviso', 'Custódia', 'Não há banco disponível com o acesso aberto. Abra a porta ou o porta-malas correspondente.')
        return false
    end
    local netId = NetworkGetEntityIsNetworked(vehicle) and NetworkGetNetworkIdFromEntity(vehicle) or 0
    if netId <= 0 then
        notify('aviso', 'Custódia', 'A viatura não possui entidade de rede válida.')
        return false
    end
    TriggerServerEvent('fivepd_sp:police:playerCustody:enterVehicle', serverId, netId, seat)
    return true
end

local function requestPlayerDocuments(ped)
    local serverId = serverIdForPlayerPed(ped)
    if not serverId then return false end
    closeRadial()
    TriggerServerEvent('fivepd_sp:police:playerInteraction:requestDocuments', serverId)
    return true
end

local function searchPlayerPed(ped)
    if not onDuty() or not playerSearchAllowed(ped) then
        notify('aviso', 'Revista pessoal', 'O jogador precisa estar algemado, com as mãos para cima ou ajoelhado.')
        return false
    end
    if GetResourceState('fivepd_sp_inventory') ~= 'started' then
        notify('erro', 'Revista pessoal', 'O inventário não está disponível.')
        return false
    end
    closeRadial()
    local ok, opened = pcall(function()
        return exports.fivepd_sp_inventory:AbrirRevistaPessoa(ped)
    end)
    if not ok or opened ~= true then
        notify('erro', 'Revista pessoal', 'Não foi possível abrir a revista desse jogador.')
        return false
    end

    playerInteractionSearchToken = playerInteractionSearchToken + 1
    local token = playerInteractionSearchToken
    local targetServerId = serverIdForPlayerPed(ped)
    local officer = PlayerPedId()
    local searchCfg = customSearchConfig()
    local dict, anim = nil, nil
    if searchCfg.enabled and requestAnim(searchCfg.officerDict) then
        dict, anim = searchCfg.officerDict, searchCfg.officerClip
        TaskPlayAnim(officer, dict, anim, 8.0, -8.0, -1, 1, 0.0, false, false, false)
    else
        dict, anim = playSearchOfficer(officer)
    end
    if targetServerId then
        TriggerServerEvent('fivepd_sp:police:playerSearch:setVisual', targetServerId, true)
    end
    CreateThread(function()
        while token == playerInteractionSearchToken and inventorySearchOpenFor(ped) do
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 37, true)
            DisablePlayerFiring(PlayerId(), true)
            if dict and anim and not IsEntityPlayingAnim(officer, dict, anim, 3) then
                TaskPlayAnim(officer, dict, anim, 8.0, -8.0, -1, searchCfg.enabled and 1 or 49, 0.0, false, false, false)
            end
            Wait(0)
        end
        if targetServerId then
            TriggerServerEvent('fivepd_sp:police:playerSearch:setVisual', targetServerId, false)
        end
        if token == playerInteractionSearchToken then
            if dict and anim and DoesEntityExist(officer) then
                StopAnimTask(officer, dict, anim, 2.0)
            end
            if targetServerId then
                TriggerServerEvent('fivepd_sp:police:surrender:searched', targetServerId)
            end
        end
    end)
    return true
end

FSPPlayerSearchVisual = FSPPlayerSearchVisual or { token = 0 }

RegisterNetEvent('fivepd_sp:police:playerSearch:visual', function(active, officerServerId)
    FSPPlayerSearchVisual.token = (tonumber(FSPPlayerSearchVisual.token) or 0) + 1
    local token = FSPPlayerSearchVisual.token
    local ped = PlayerPedId()
    local cfg = customSearchConfig()

    if active ~= true then
        if ped ~= 0 and DoesEntityExist(ped) and cfg.suspectDict ~= '' and cfg.suspectClip ~= '' then
            StopAnimTask(ped, cfg.suspectDict, cfg.suspectClip, 2.0)
        end
        return
    end

    if ped == 0 or not DoesEntityExist(ped) or not cfg.enabled or not requestAnim(cfg.suspectDict) then return end
    local officerIndex = GetPlayerFromServerId(tonumber(officerServerId) or -1)
    local officerPed = officerIndex ~= -1 and GetPlayerPed(officerIndex) or 0
    if officerPed ~= 0 and DoesEntityExist(officerPed) then
        TaskTurnPedToFaceEntity(ped, officerPed, 350)
    end
    TaskPlayAnim(ped, cfg.suspectDict, cfg.suspectClip, 8.0, -8.0, -1, 1, 0.0, false, false, false)

    CreateThread(function()
        while FSPPlayerSearchVisual.token == token do
            DisableControlAction(0, 21, true)
            DisableControlAction(0, 22, true)
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 37, true)
            DisablePlayerFiring(PlayerId(), true)
            if not IsEntityPlayingAnim(ped, cfg.suspectDict, cfg.suspectClip, 3) then
                TaskPlayAnim(ped, cfg.suspectDict, cfg.suspectClip, 8.0, -8.0, -1, 1, 0.0, false, false, false)
            end
            Wait(0)
        end
    end)
end)

RegisterNetEvent('fivepd_sp:police:playerInteraction:documents', function(targetServerId, data)
    data = type(data) == 'table' and data or {}
    local targetPlayer = GetPlayerFromServerId(tonumber(targetServerId) or -1)
    local ped = targetPlayer ~= -1 and GetPlayerPed(targetPlayer) or 0
    local cnh = type(data.cnh) == 'table' and data.cnh or {}
    local statusLabels = {
        valida = 'Válida', regular = 'Regular', vencida = 'Vencida', suspensa = 'Suspensa',
        cassada = 'Cassada', nao_emitida = 'Não emitida'
    }
    local status = tostring(cnh.status or 'nao_emitida')
    local categories = type(cnh.categories) == 'table' and table.concat(cnh.categories, ', ') or ''
    local rgCopied = data.rg and copyInteractionValue(data.rg) or false
    local lines = {
        tostring(data.nome_completo or 'Identificação apresentada'),
        ('RG: %s%s'):format(tostring(data.rg or '—'), rgCopied and ' • copiado' or ''),
        ('Nascimento: %s • %s anos'):format(tostring(data.nascimento or '—'), tostring(data.idade or '—')),
        ('Sexo: %s'):format(tostring(data.sexo or '—')),
        ('CNH: %s%s'):format(statusLabels[status] or status, categories ~= '' and (' • ' .. categories) or '')
    }
    notify('info', 'Documentos apresentados', table.concat(lines, '\n'))
    if isOtherPlayerPed(ped) then
        CreateThread(function()
            Wait(350)
            if isOtherPlayerPed(ped) and not radialOpen then openPlayerCategoryRadial(ped, 'identification') end
        end)
    end
end)

local VEHICLE_IDENTIFIER_DEFS = {
    chassis = {
        label = 'Chassi',
        stateKey = 'fivepd_sp:records:chassisPhysical',
        recordKey = 'chassi'
    },
    engine = {
        label = 'Motor',
        stateKey = 'fivepd_sp:records:enginePhysical',
        recordKey = 'motor'
    },
    glass = {
        label = 'Vidros',
        stateKey = 'fivepd_sp:records:glassPhysical',
        recordKey = 'vidros'
    },
    plate = {
        label = 'Placa',
        recordKey = 'placa'
    }
}

function inspectVehicleIdentifier(vehicle, identifier)
    if not onDuty() or vehicle == 0 or not DoesEntityExist(vehicle) then return false end
    local def = VEHICLE_IDENTIFIER_DEFS[identifier]
    if not def then return false end

    if GetResourceState('fivepd_sp_records') ~= 'started' then
        notify('erro', def.label, 'Sistema de registros indisponível.')
        return false
    end

    local ok, record = pcall(function()
        return exports.fivepd_sp_records:ObterOuCriarVeiculo(vehicle, { persistir = true })
    end)
    if not ok or type(record) ~= 'table' or record.encontrado == false then
        notify('erro', def.label, 'Não foi possível obter a identificação deste veículo.')
        return false
    end

    local state = Entity(vehicle).state
    local physical = def.stateKey and state and state[def.stateKey] or nil
    local value = tostring(physical or record[def.recordKey] or 'NÃO LOCALIZADO')
    local copied = copyInteractionValue(value)

    local details = {}
    details[#details + 1] = ('%s: %s'):format(def.label, value)

    if identifier == 'chassis' and value:upper() == 'RASPADO' and type(record.chassi) == 'string' and #record.chassi >= 5 then
        details[#details + 1] = ('Trecho parcialmente recuperável: %s????'):format(record.chassi:sub(1, -5))
    end

    details[#details + 1] = copied
        and 'Copiado automaticamente para consulta no aplicativo.'
        or 'Não foi possível copiar automaticamente; a leitura continua visível acima.'

    TriggerEvent('fivepd_sp:ui:notificar', {
        tipo = value:upper() == 'RASPADO' and 'aviso' or 'info',
        titulo = ('Verificação de %s'):format(def.label:lower()),
        descricao = table.concat(details, '\n'),
        duracao = 7500
    })
    return true
end

function podeIdentificarVeiculo(vehicle)
    if vehicle == 0 or not DoesEntityExist(vehicle) or not IsEntityAVehicle(vehicle) then return false end

    -- Integração FiveEMS: a Stryker Pro usa um veículo como entidade técnica,
    -- mas operacionalmente é uma maca. Não deve receber ações policiais de
    -- identificação de placa/chassi/motor/moto no ox_target.
    if GetEntityModel(vehicle) == joaat('strykerpro') then return false end
    local ok, entityState = pcall(function() return Entity(vehicle).state end)
    if ok and entityState and entityState['fiveems:stretcher'] == true then return false end

    return onDuty()
end

local function ehBicicletaIdentificacao(vehicle)
    if not podeIdentificarVeiculo(vehicle) then return false end
    if GetVehicleClass(vehicle) == 13 then return true end
    local model = GetEntityModel(vehicle)
    if type(IsThisModelABicycle) == 'function' then
        local ok, result = pcall(IsThisModelABicycle, model)
        if ok and result == true then return true end
    end
    return false
end

local function ehMotocicletaIdentificacao(vehicle)
    if not podeIdentificarVeiculo(vehicle) or ehBicicletaIdentificacao(vehicle) then return false end
    if GetVehicleClass(vehicle) == 8 then return true end
    local model = GetEntityModel(vehicle)
    if type(IsThisModelABike) == 'function' then
        local ok, result = pcall(IsThisModelABike, model)
        if ok and result == true then return true end
    end
    -- Fallback para motos add-on que foram configuradas com vehicleClass incorreto.
    if type(GetVehicleNumberOfWheels) == 'function' then
        local ok, wheels = pcall(GetVehicleNumberOfWheels, vehicle)
        if ok and tonumber(wheels) and tonumber(wheels) <= 2 then return true end
    end
    return false
end

local function ehDuasRodasIdentificacao(vehicle)
    return ehMotocicletaIdentificacao(vehicle) or ehBicicletaIdentificacao(vehicle)
end

local function podeIdentificarMotoRegiao(vehicle, distance, contexto, identifier)
    if not ehMotocicletaIdentificacao(vehicle) then return false end
    if tonumber(distance) and tonumber(distance) > 3.2 then return false end
    if type(contexto) ~= 'table' or not contexto.coords then return true end

    local c = contexto.coords
    local okLocal, localCoords = pcall(GetOffsetFromEntityGivenWorldCoords, vehicle, c.x, c.y, c.z)
    if not okLocal or not localCoords then return true end

    local okDims, minDim, maxDim = pcall(GetModelDimensions, GetEntityModel(vehicle))
    if not okDims or not minDim or not maxDim then return true end

    local width = math.max(0.55, maxDim.x - minDim.x)
    local length = math.max(1.45, maxDim.y - minDim.y)
    local height = math.max(0.75, maxDim.z - minDim.z)
    local centerY = (minDim.y + maxDim.y) * 0.5
    local xLimit = math.max(0.45, width * 0.72)

    if identifier == 'plate' then
        -- Placa da motocicleta: região traseira, próxima ao paralama/suporte
        -- da placa. Não dependemos de bones de carro (boot/bumper_r), pois a
        -- maioria das motos não possui esses bones e o ox_target não oferecia
        -- a interação.
        return math.abs(localCoords.x) <= math.max(0.50, width * 0.90)
            and localCoords.y >= (minDim.y - length * 0.12)
            and localCoords.y <= (minDim.y + length * 0.38)
            and localCoords.z >= (minDim.z + height * 0.10)
            and localCoords.z <= (maxDim.z + height * 0.22)
    end

    if identifier == 'engine' then
        -- Bloco do motor: região central e baixa da motocicleta.
        return math.abs(localCoords.x) <= xLimit
            and math.abs(localCoords.y - centerY) <= length * 0.34
            and localCoords.z <= (minDim.z + height * 0.72)
    end

    -- Numeração de chassi/quadro: região central-dianteira do quadro, próxima
    -- à coluna de direção. A área é propositalmente um pouco generosa para
    -- funcionar também em motos add-on com dimensões/bones diferentes.
    return math.abs(localCoords.x) <= xLimit
        and localCoords.y >= (centerY - length * 0.08)
        and localCoords.y <= (maxDim.y + length * 0.08)
        and localCoords.z >= (minDim.z + height * 0.18)
        and localCoords.z <= (maxDim.z + height * 0.10)
end

function podeIdentificarCapo(vehicle, distance, contexto)
    if not podeIdentificarVeiculo(vehicle)
        or GetResourceState('fivepd_sp_vehicle') ~= 'started'
    then
        return false
    end

    local ok, permitido = pcall(function()
        return exports.fivepd_sp_vehicle:PodeInspecionarCapoAberto(
            vehicle,
            distance,
            contexto
        )
    end)

    return ok and permitido == true
end

function podeIdentificarVidro(vehicle, distance, contexto)
    if not podeIdentificarVeiculo(vehicle)
        or ehDuasRodasIdentificacao(vehicle)
        or GetResourceState('fivepd_sp_vehicle') ~= 'started'
    then
        return false
    end

    local ok, permitido = pcall(function()
        return exports.fivepd_sp_vehicle:PodeInspecionarVidroFechado(
            vehicle,
            distance,
            contexto
        )
    end)

    return ok and permitido == true
end

exports('PodeIdentificarVeiculo', podeIdentificarVeiculo)
exports('PodeIdentificarCapo', podeIdentificarCapo)
exports('PodeIdentificarVidro', podeIdentificarVidro)

function podeIdentificarBicicleta(vehicle)
    return ehBicicletaIdentificacao(vehicle)
end

function inspectBicycleRegistration(vehicle)
    if not podeIdentificarBicicleta(vehicle) then return false end
    if GetResourceState('fivepd_sp_records') ~= 'started' then
        notify('erro', 'Registro da bicicleta', 'Sistema de registros indisponível.')
        return false
    end
    local ok, record = pcall(function()
        return exports.fivepd_sp_records:ObterOuCriarBicicleta(vehicle, {})
    end)
    if not ok or type(record) ~= 'table' or record.encontrado == false then
        notify('erro', 'Registro da bicicleta', 'Não foi possível obter a numeração desta bicicleta.')
        return false
    end
    local registration = tostring(record.registro or 'NÃO LOCALIZADO')
    local copied = copyInteractionValue(registration)
    notify('info', 'Registro da bicicleta', ('Registro: %s\n%s'):format(registration, copied and 'Copiado para consulta no Terminal Embarcado.' or 'Anote o número para consulta.'))
    return true
end

exports('PodeIdentificarBicicleta', podeIdentificarBicicleta)

function registerVehicleIdentificationInteraction(force)
    if GetResourceState('ox_target') ~= 'started' then return false end
    if vehicleIdentificationInteractionRegistered and force ~= true then return true end

    local names = {
        'fivepd_police:bicycle_registration',
        'fivepd_police:chassis',
        'fivepd_police:engine',
        'fivepd_police:plate_front',
        'fivepd_police:plate_rear',
        'fivepd_police:glass',
        'fivepd_police:motorcycle_chassis',
        'fivepd_police:motorcycle_engine',
        'fivepd_police:motorcycle_plate'
    }
    pcall(function() exports.ox_target:removeGlobalVehicle(names) end)

    local function ctxFrom(data)
        return {
            entidade = tonumber(data and data.entity) or 0,
            coords = data and data.coords or nil,
            distancia = data and data.distance or nil,
            osso = data and data.bone or nil
        }
    end

    exports.ox_target:addGlobalVehicle({
        {
            name = names[1],
            icon = 'fa-solid fa-bicycle',
            label = 'Verificar registro da bicicleta',
            distance = 3.4,
            canInteract = function(vehicle) return podeIdentificarBicicleta(vehicle) end,
            onSelect = function(data) TriggerEvent('fivepd_sp:police:interaction:bicycleRegistration', ctxFrom(data)) end
        },
        {
            name = names[2],
            icon = 'fa-solid fa-fingerprint',
            label = 'Verificar chassi',
            distance = 3.2,
            bones = { 'bonnet', 'engine' },
            canInteract = function(vehicle, distance, coords, _, bone)
                return not ehDuasRodasIdentificacao(vehicle)
                    and podeIdentificarCapo(vehicle, distance, { entidade = vehicle, coords = coords, distancia = distance, osso = bone })
            end,
            onSelect = function(data) TriggerEvent('fivepd_sp:police:interaction:vehicleIdentificationChassis', ctxFrom(data)) end
        },
        {
            name = names[3],
            icon = 'fa-solid fa-gears',
            label = 'Verificar motor',
            distance = 3.2,
            bones = { 'bonnet', 'engine' },
            canInteract = function(vehicle, distance, coords, _, bone)
                return not ehDuasRodasIdentificacao(vehicle)
                    and podeIdentificarCapo(vehicle, distance, { entidade = vehicle, coords = coords, distancia = distance, osso = bone })
            end,
            onSelect = function(data) TriggerEvent('fivepd_sp:police:interaction:vehicleIdentificationEngine', ctxFrom(data)) end
        },
        {
            name = names[4],
            icon = 'fa-solid fa-id-card',
            label = 'Verificar placa',
            distance = 3.2,
            bones = { 'bonnet', 'bumper_f' },
            canInteract = function(vehicle, distance, coords, _, bone)
                return podeIdentificarCapo(vehicle, distance, { entidade = vehicle, coords = coords, distancia = distance, osso = bone })
            end,
            onSelect = function(data) TriggerEvent('fivepd_sp:police:interaction:vehicleIdentificationPlate', ctxFrom(data)) end
        },
        {
            name = names[5],
            icon = 'fa-solid fa-id-card',
            label = 'Verificar placa',
            distance = 3.2,
            bones = { 'boot', 'bumper_r' },
            canInteract = function(vehicle)
                return not ehDuasRodasIdentificacao(vehicle)
                    and podeIdentificarVeiculo(vehicle)
                    and GetVehicleClass(vehicle) ~= 13
            end,
            onSelect = function(data) TriggerEvent('fivepd_sp:police:interaction:vehicleIdentificationPlate', ctxFrom(data)) end
        },
        {
            name = names[6],
            icon = 'fa-solid fa-car-side',
            label = 'Verificar código dos vidros',
            distance = 3.0,
            bones = {
                'window_lf', 'window_rf', 'window_lr', 'window_rr',
                'door_dside_f', 'door_pside_f', 'door_dside_r', 'door_pside_r'
            },
            canInteract = function(vehicle, distance, coords, _, bone)
                return not ehDuasRodasIdentificacao(vehicle)
                    and podeIdentificarVidro(vehicle, distance, { entidade = vehicle, coords = coords, distancia = distance, osso = bone })
            end,
            onSelect = function(data) TriggerEvent('fivepd_sp:police:interaction:vehicleIdentificationGlass', ctxFrom(data)) end
        },
        {
            name = names[7],
            icon = 'fa-solid fa-fingerprint',
            label = 'Verificar chassi da moto',
            distance = 3.2,
            canInteract = function(vehicle, distance, coords)
                return podeIdentificarMotoRegiao(vehicle, distance, { entidade = vehicle, coords = coords, distancia = distance }, 'chassis')
            end,
            onSelect = function(data) TriggerEvent('fivepd_sp:police:interaction:vehicleIdentificationChassis', ctxFrom(data)) end
        },
        {
            name = names[8],
            icon = 'fa-solid fa-gears',
            label = 'Verificar número do motor',
            distance = 3.2,
            canInteract = function(vehicle, distance, coords)
                return podeIdentificarMotoRegiao(vehicle, distance, { entidade = vehicle, coords = coords, distancia = distance }, 'engine')
            end,
            onSelect = function(data) TriggerEvent('fivepd_sp:police:interaction:vehicleIdentificationEngine', ctxFrom(data)) end
        },
        {
            name = names[9],
            icon = 'fa-solid fa-id-card',
            label = 'Verificar placa da moto',
            distance = 3.2,
            canInteract = function(vehicle, distance, coords)
                return podeIdentificarMotoRegiao(vehicle, distance, { entidade = vehicle, coords = coords, distancia = distance }, 'plate')
            end,
            onSelect = function(data) TriggerEvent('fivepd_sp:police:interaction:vehicleIdentificationPlate', ctxFrom(data)) end
        }
    })

    vehicleIdentificationInteractionRegistered = true
    return true
end

function podeAbordarPedInteraction(ped)
    return onDuty()
        and isValidNpc(ped)
        and not stateFor(ped).cuffed
        and not IsPedInAnyVehicle(ped, false)
end

function podeDispensarPedInteraction(ped)
    return onDuty()
        and isValidNpc(ped)
        and not stateFor(ped).cuffed
        and not IsPedInAnyVehicle(ped, false)
end

function podeSegurarPedInteraction(ped)
    return onDuty()
        and isValidNpc(ped)
        and stateFor(ped).cuffed
        and not IsPedInAnyVehicle(ped, false)
end

function podeColocarPedVeiculoInteraction(ped)
    if not onDuty() or not isValidNpc(ped) or not stateFor(ped).cuffed or IsPedInAnyVehicle(ped, false) then return false end
    return nearestVehicle(ped, Config.Interaction.vehicleSearchDistance) ~= 0
end

-- Exposto também ao módulo client/ped_target.lua. Mantemos esta condição no
-- main porque stateFor() contém o estado local dos NPCs não-networked e é a
-- fonte correta para saber se o ped realmente se rendeu.
function podeAlgemarPedInteraction(ped)
    if not onDuty() or not isValidNpc(ped) or IsPedInAnyVehicle(ped, false) then return false end
    local st = stateFor(ped)
    return not st.cuffed and (st.handsUp == true or st.kneeling == true)
end

function podeInteragirJogadorInteraction(ped)
    return canPoliceInteractWithPlayerPed(ped)
end

exports('PodeAbordarPedInteraction', podeAbordarPedInteraction)
exports('PodeDispensarPedInteraction', podeDispensarPedInteraction)
exports('PodeSegurarPedInteraction', podeSegurarPedInteraction)
exports('PodeColocarPedVeiculoInteraction', podeColocarPedVeiculoInteraction)
exports('PodeInteragirJogadorInteraction', podeInteragirJogadorInteraction)

policePedNames = {
    'fivepd_police:approach', 'fivepd_police:dismiss', 'fivepd_police:interact_cuffed',
    'fivepd_police:uncuff_npc', 'fivepd_police:hold_npc', 'fivepd_police:vehicle_npc',
    'fivepd_police:cuff_surrendered_npc'
}
policePlayerNames = {
    'fivepd_police:player_interact', 'fivepd_police:player_uncuff', 'fivepd_police:player_hold',
    'fivepd_police:player_vehicle', 'fivepd_police:player_cuff_surrendered',
    'fivepd_police:return_bopm_to_civil', 'fivepd_police:return_tcopm_to_civil'
}
policeVehicleNames = {
    'fivepd_police:remove_detainee', 'fivepd_police:remove_player_detainee'
}

function targetCtx(data)
    return {
        entidade = tonumber(data and data.entity) or 0,
        coords = data and data.coords or nil,
        distancia = data and data.distance or nil,
        osso = data and data.bone or nil
    }
end

function registerPrimaryPedInteraction(force)
    if GetResourceState('ox_target') ~= 'started' then return false end
    if primaryPedInteractionRegistered and force ~= true then return true end
    pcall(function() exports.ox_target:removeGlobalPed(policePedNames) end)

    local maxDist = Config.Interaction.maxPedDistance or 3.2
    exports.ox_target:addGlobalPed({
        {
            name = policePedNames[1], icon = 'fa-solid fa-person-circle-question', label = 'Abordar', distance = maxDist,
            canInteract = function(ped) return podeAbordarPedInteraction(ped) end,
            onSelect = function(data) TriggerEvent('fivepd_sp:police:interaction:approach', targetCtx(data)) end
        },
        {
            name = policePedNames[2], icon = 'fa-solid fa-person-walking-arrow-right', label = 'Mandar sair do local', distance = maxDist,
            canInteract = function(ped) return podeDispensarPedInteraction(ped) end,
            onSelect = function(data) TriggerEvent('fivepd_sp:police:interaction:dismiss', targetCtx(data)) end
        },
        {
            name = policePedNames[3], icon = 'fa-solid fa-hand', label = 'Interagir', distance = maxDist,
            canInteract = function(ped) return onDuty() and isValidNpc(ped) and stateFor(ped).cuffed and not IsPedInAnyVehicle(ped, false) end,
            onSelect = function(data) TriggerEvent('fivepd_sp:police:interaction:approach', targetCtx(data)) end
        },
        {
            name = policePedNames[7], icon = 'fa-solid fa-link', label = 'Algemar', distance = maxDist,
            canInteract = function(ped) return podeAlgemarPedInteraction(ped) end,
            onSelect = function(data) TriggerEvent('fivepd_sp:police:interaction:npcCuff', targetCtx(data)) end
        },
        {
            name = policePedNames[4], icon = 'fa-solid fa-link-slash', label = 'Desalgemar', distance = maxDist,
            canInteract = function(ped) return onDuty() and isValidNpc(ped) and stateFor(ped).cuffed and not IsPedInAnyVehicle(ped, false) end,
            onSelect = function(data) TriggerEvent('fivepd_sp:police:interaction:npcUncuff', targetCtx(data)) end
        },
        {
            name = policePedNames[5], icon = 'fa-solid fa-hand-holding-hand', label = 'Segurar / Soltar', distance = maxDist,
            canInteract = function(ped) return podeSegurarPedInteraction(ped) end,
            onSelect = function(data) TriggerEvent('fivepd_sp:police:interaction:hold', targetCtx(data)) end
        },
        {
            name = policePedNames[6], icon = 'fa-solid fa-car-side', label = 'Colocar no veículo', distance = maxDist,
            canInteract = function(ped) return podeColocarPedVeiculoInteraction(ped) end,
            onSelect = function(data) TriggerEvent('fivepd_sp:police:interaction:vehicle', targetCtx(data)) end
        }
    })
    primaryPedInteractionRegistered = true
    return true
end

function registerInteraction(force)
    if GetResourceState('ox_target') ~= 'started' then return false end
    if interactionRegistered and force ~= true then return true end

    pcall(function() exports.ox_target:removeGlobalPlayer(policePlayerNames) end)
    pcall(function() exports.ox_target:removeGlobalVehicle(policeVehicleNames) end)

    local maxDist = Config.Interaction.maxPedDistance or 3.2
    exports.ox_target:addGlobalPlayer({
        {
            name = policePlayerNames[1], icon = 'fa-solid fa-user-shield', label = 'Interagir', distance = maxDist,
            canInteract = function(ped) return podeInteragirJogadorInteraction(ped) end,
            onSelect = function(data) TriggerEvent('fivepd_sp:police:interaction:playerOpen', targetCtx(data)) end
        },
        {
            name = policePlayerNames[5], icon = 'fa-solid fa-link', label = 'Algemar', distance = maxDist,
            canInteract = function(ped)
                return podeInteragirJogadorInteraction(ped)
                    and bagValue(ped, 'cuffed') ~= true
                    and (bagValue(ped, 'handsUp') == true or bagValue(ped, 'kneeling') == true)
                    and not IsPedInAnyVehicle(ped, false)
            end,
            onSelect = function(data) TriggerEvent('fivepd_sp:police:interaction:playerCuff', targetCtx(data)) end
        },
        {
            name = policePlayerNames[2], icon = 'fa-solid fa-link-slash', label = 'Desalgemar', distance = maxDist,
            canInteract = function(ped) return podeInteragirJogadorInteraction(ped) and bagValue(ped, 'cuffed') == true end,
            onSelect = function(data) TriggerEvent('fivepd_sp:police:interaction:playerCuff', targetCtx(data)) end
        },
        {
            name = policePlayerNames[3], icon = 'fa-solid fa-hand-holding-hand', label = 'Segurar / Soltar', distance = maxDist,
            canInteract = function(ped) return podeInteragirJogadorInteraction(ped) and bagValue(ped, 'cuffed') == true and not IsPedInAnyVehicle(ped, false) end,
            onSelect = function(data) TriggerEvent('fivepd_sp:police:interaction:playerHold', targetCtx(data)) end
        },
        {
            name = policePlayerNames[4], icon = 'fa-solid fa-car-side', label = 'Colocar no veículo', distance = maxDist,
            canInteract = function(ped) return podeInteragirJogadorInteraction(ped) and bagValue(ped, 'cuffed') == true and not IsPedInAnyVehicle(ped, false) end,
            onSelect = function(data) TriggerEvent('fivepd_sp:police:interaction:playerVehicle', targetCtx(data)) end
        },
        {
            name = policePlayerNames[6], icon = 'fa-solid fa-file-arrow-up', label = 'Entregar documento BOPM', distance = 3.2,
            canInteract = function(ped)
                return pcespCustodyDocument and pcespCustodyDocument.finalized == true
                    and tostring(pcespCustodyDocument.documentType or '') == 'bopm'
                    and tonumber(serverIdForPlayerPed(ped)) == tonumber(pcespCustodyDocument.civilSource)
            end,
            onSelect = function(data)
                if pcespCustodyDocument then TriggerServerEvent('fivepd_sp:police:custody:returnCivilDocument', pcespCustodyDocument.requestId, pcespCustodyDocument.civilSource) end
            end
        },
        {
            name = policePlayerNames[7], icon = 'fa-solid fa-file-arrow-up', label = 'Entregar documento TCOPM', distance = 3.2,
            canInteract = function(ped)
                return pcespCustodyDocument and pcespCustodyDocument.finalized == true
                    and tostring(pcespCustodyDocument.documentType or '') == 'tcopm'
                    and tonumber(serverIdForPlayerPed(ped)) == tonumber(pcespCustodyDocument.civilSource)
            end,
            onSelect = function(data)
                if pcespCustodyDocument then TriggerServerEvent('fivepd_sp:police:custody:returnCivilDocument', pcespCustodyDocument.requestId, pcespCustodyDocument.civilSource) end
            end
        }
        })

    exports.ox_target:addGlobalVehicle({
        {
            name = policeVehicleNames[1], icon = 'fa-solid fa-person-walking-arrow-right', label = 'Retirar pessoa algemada', distance = 3.4,
            canInteract = function(vehicle) return onDuty() and DoesEntityExist(vehicle) and #findCuffedOccupants(vehicle) > 0 end,
            onSelect = function(data) TriggerEvent('fivepd_sp:police:interaction:vehicleExit', targetCtx(data)) end
        },
        {
            name = policeVehicleNames[2], icon = 'fa-solid fa-person-walking-arrow-right', label = 'Retirar jogador algemado', distance = 3.4,
            canInteract = function(vehicle) return onDuty() and DoesEntityExist(vehicle) and #cuffedPlayerOccupants(vehicle) > 0 end,
            onSelect = function(data) TriggerEvent('fivepd_sp:police:interaction:playerVehicleExit', targetCtx(data)) end
        }
    })

    interactionRegistered = true
    return true
end

function unregisterInteraction()
    if GetResourceState('ox_target') == 'started' then
        pcall(function() exports.ox_target:removeGlobalPed(policePedNames) end)
    pcall(function() exports.ox_target:removeGlobalPed('fivepd_police:debug_ped') end)
        pcall(function() exports.ox_target:removeGlobalPlayer(policePlayerNames) end)
        pcall(function() exports.ox_target:removeGlobalVehicle(policeVehicleNames) end)
        FSPTarget.Close()
    end
    interactionRegistered = false
    primaryPedInteractionRegistered = false
end

function unregisterVehicleIdentificationInteraction()
    if GetResourceState('ox_target') == 'started' then
        pcall(function()
            exports.ox_target:removeGlobalVehicle({
                'fivepd_police:bicycle_registration', 'fivepd_police:chassis', 'fivepd_police:engine',
                'fivepd_police:plate_front', 'fivepd_police:plate_rear', 'fivepd_police:glass'
            })
        end)
    end
    vehicleIdentificationInteractionRegistered = false
end


RegisterNetEvent('fivepd_sp:police:interaction:approach', function(ctx)
    if not onDuty() then return end
    local ped = ctx and ctx.entidade or 0
    CreateThread(function() approachPed(ped) end)
end)
RegisterNetEvent('fivepd_sp:police:interaction:dismiss', function(ctx) if not onDuty() then return end; dismissPed(ctx and ctx.entidade or 0) end)
RegisterNetEvent('fivepd_sp:police:interaction:hold', function(ctx)
    if not onDuty() then return end
    local ped = ctx and ctx.entidade or 0
    if isValidNpc(ped) then closeInteraction(); toggleHold(ped) end
end)
RegisterNetEvent('fivepd_sp:police:interaction:npcCuff', function(ctx)
    if not onDuty() then return end
    local ped = ctx and ctx.entidade or 0
    if not isValidNpc(ped) or IsPedInAnyVehicle(ped, false) then return end
    local st = stateFor(ped)
    if not st.cuffed and (st.handsUp == true or st.kneeling == true) then
        closeInteraction()
        setCuffed(ped, true)
    end
end)
RegisterNetEvent('fivepd_sp:police:interaction:npcUncuff', function(ctx)
    if not onDuty() then return end
    local ped = ctx and ctx.entidade or 0
    if isValidNpc(ped) and stateFor(ped).cuffed then closeInteraction(); setCuffed(ped, false) end
end)
RegisterNetEvent('fivepd_sp:police:interaction:vehicle', function(ctx)
    if not onDuty() then return end
    local ped = ctx and ctx.entidade or 0
    if isValidNpc(ped) then closeInteraction(); openVehicleSeats(ped) end
end)
function handleVehicleIdentifierInteraction(ctx, identifier)
    if not onDuty() then return end
    local vehicle = ctx and ctx.entidade or 0
    if vehicle == 0 or not DoesEntityExist(vehicle) then return end

    local permitido = false

    if identifier == 'chassis' or identifier == 'engine' then
        if ehMotocicletaIdentificacao(vehicle) then
            permitido = podeIdentificarMotoRegiao(
                vehicle,
                ctx and ctx.distancia or 0.0,
                ctx,
                identifier
            )
            if not permitido then
                local alvo = identifier == 'engine' and 'bloco central/inferior do motor' or 'região dianteira do quadro/chassi'
                notify('aviso', 'Identificação veicular', ('Mire na %s da motocicleta para fazer essa verificação.'):format(alvo))
                return
            end
        else
            permitido = podeIdentificarCapo(
                vehicle,
                ctx and ctx.distancia or 0.0,
                ctx
            )
            if not permitido then
                notify('aviso', 'Identificação veicular', 'Abra o capô e mire na região do motor para fazer essa verificação.')
                return
            end
        end
    elseif identifier == 'glass' then
        if ehDuasRodasIdentificacao(vehicle) then return end
        permitido = podeIdentificarVidro(
            vehicle,
            ctx and ctx.distancia or 0.0,
            ctx
        )

        if not permitido then
            notify('aviso', 'Identificação veicular', 'Mire diretamente em um vidro fechado e intacto.')
            return
        end
    end

    CreateThread(function()
        inspectVehicleIdentifier(vehicle, identifier)
        -- Dá ao CEF da interação um instante para concluir a cópia antes de perder o foco.
        Wait(80)
        closeInteraction()
    end)
end

RegisterNetEvent('fivepd_sp:police:interaction:bicycleRegistration', function(ctx)
    if not onDuty() then return end
    local vehicle = ctx and ctx.entidade or 0
    if not podeIdentificarBicicleta(vehicle) then return end
    CreateThread(function()
        inspectBicycleRegistration(vehicle)
        Wait(80)
        closeInteraction()
    end)
end)

RegisterNetEvent('fivepd_sp:police:interaction:vehicleIdentificationChassis', function(ctx)
    handleVehicleIdentifierInteraction(ctx, 'chassis')
end)

RegisterNetEvent('fivepd_sp:police:interaction:vehicleIdentificationEngine', function(ctx)
    handleVehicleIdentifierInteraction(ctx, 'engine')
end)

RegisterNetEvent('fivepd_sp:police:interaction:vehicleIdentificationPlate', function(ctx)
    handleVehicleIdentifierInteraction(ctx, 'plate')
end)

RegisterNetEvent('fivepd_sp:police:interaction:vehicleIdentificationGlass', function(ctx)
    handleVehicleIdentifierInteraction(ctx, 'glass')
end)

RegisterNetEvent('fivepd_sp:police:interaction:vehicleExit', function(ctx)
    if not onDuty() then return end
    local vehicle = ctx and ctx.entidade or 0
    if vehicle ~= 0 and DoesEntityExist(vehicle) then closeInteraction(); openExitRadial(vehicle) end
end)

RegisterNetEvent('fivepd_sp:police:interaction:playerOpen', function(ctx)
    if not onDuty() then return end
    local ped = ctx and ctx.entidade or 0
    if not canPoliceInteractWithPlayerPed(ped) then return end
    closeInteraction()
    openPlayerMainRadial(ped)
end)

RegisterNetEvent('fivepd_sp:police:interaction:playerCuff', function(ctx)
    if not onDuty() then return end
    local ped = ctx and ctx.entidade or 0
    if not isOtherPlayerPed(ped) then return end
    closeInteraction()
    triggerPlayerCustodyAction(ped, 'cuff')
end)

RegisterNetEvent('fivepd_sp:police:interaction:playerHold', function(ctx)
    if not onDuty() then return end
    local ped = ctx and ctx.entidade or 0
    if not isOtherPlayerPed(ped) then return end
    closeInteraction()
    triggerPlayerCustodyAction(ped, 'hold')
end)

RegisterNetEvent('fivepd_sp:police:interaction:playerVehicle', function(ctx)
    if not onDuty() then return end
    local ped = ctx and ctx.entidade or 0
    if not isOtherPlayerPed(ped) then return end
    closeInteraction()
    putPlayerInNearestVehicle(ped)
end)

RegisterNetEvent('fivepd_sp:police:interaction:playerVehicleExit', function(ctx)
    if not onDuty() then return end
    local vehicle = ctx and ctx.entidade or 0
    if vehicle == 0 or not DoesEntityExist(vehicle) then return end
    local occupants = cuffedPlayerOccupants(vehicle)
    if #occupants == 0 then return end
    closeInteraction()
    local options = {}
    for index, item in ipairs(occupants) do
        local playerIndex = NetworkGetPlayerIndexFromPed(item.ped)
        local playerName = playerIndex ~= -1 and GetPlayerName(playerIndex) or ('Jogador %d'):format(item.serverId)
        local access = item.access or FivePD_ResolveCustodySeatAccess(vehicle, item.seat)
        options[#options + 1] = {
            id = ('pexit:%d'):format(index), title = playerName or ('Jogador %d'):format(item.serverId), icon = 'SAI',
            description = doorIsOpen(vehicle, access.door) and (FivePD_CustodySeatLabel(vehicle, item.seat, access) .. ' • retirar') or (access.trunk and 'Abra o porta-malas correspondente' or 'Abra a porta correspondente'),
            disabled = not doorIsOpen(vehicle, access.door)
        }
    end
    openRadial('Retirar jogador da viatura', 'CUSTÓDIA', options, 'player_vehicle_exit', { vehicle = vehicle, occupants = occupants })
end)

RegisterNUICallback('select', function(data, cb)
    local id = tostring(data and data.id or '')
    if not onDuty() then closeRadial(); cb({ ok = false }); return end
    if not radialOpen then cb({ ok = false }); return end
    local mode = radialMode
    local context = radialContext or {}
    local ped = context.ped or currentPed

    if id == 'close' then
        local requestId = mode == 'trafficstop_type' and tonumber(context.requestId) or nil
        closeRadial()
        if requestId then TriggerEvent('fivepd_sp:trafficstop:typeChooserClosed', requestId) end
        cb({ ok = true }); return
    end

    if id == '__back' then
        if mode == 'infractions_group' then
            openInfractionsRoot(ped, context.origin)
        elseif mode == 'infractions_root' then
            if context.origin == 'person' and isValidNpc(ped) then
                openMainRadial(ped)
            elseif context.origin == 'player' and isOtherPlayerPed(ped) then
                openPlayerMainRadial(ped)
            else
                closeRadial()
            end
        elseif mode == 'dialogue' or mode == 'qru_dialogue' then
            if isValidNpc(ped) then openCategoryRadial(ped, 'identification') else closeRadial() end
        elseif mode == 'vehicle_enter' then
            if isValidNpc(ped) then openCategoryRadial(ped, 'conduction') else closeRadial() end
        elseif mode and mode:sub(1, 9) == 'category:' then
            if isValidNpc(ped) then openMainRadial(ped) else closeRadial() end
        elseif mode and mode:sub(1, 16) == 'player_category:' then
            if isOtherPlayerPed(ped) then openPlayerMainRadial(ped) else closeRadial() end
        else
            closeRadial()
        end
        cb({ ok = true }); return
    end

    if mode == 'trafficstop_type' then
        local choice = id:match('^trafficstop:(traffic)$') or id:match('^trafficstop:(preventive)$')
        local requestId = tonumber(context.requestId)
        if choice and requestId then
            closeRadial()
            TriggerEvent('fivepd_sp:trafficstop:typeSelected', requestId, choice)
        end
        cb({ ok = choice ~= nil }); return
    end

    -- Infrações não são mais lançadas pelo radial. As autuações são feitas
    -- exclusivamente pelo aplicativo Operacional PMESP.
    if mode == 'infractions_root' or mode == 'infractions_group' then
        closeRadial()
        cb({ ok = false })
        return
    end

    if mode == 'vehicle_enter' then
        if id == 'back' then openCategoryRadial(ped, 'conduction')
        else
            local seat = tonumber(id:match('^seat:(%-?%d+)$'))
            if seat then
                local vehicle = context.vehicle
                closeRadial()
                enterVehicle(ped, vehicle, seat)
            end
        end
        cb({ ok = true }); return
    end

    if mode == 'vehicle_exit' then
        local index = tonumber(id:match('^exit:(%d+)$'))
        if index and context.occupants and context.occupants[index] then
            local item = context.occupants[index]
            local vehicle = context.vehicle
            closeRadial()
            exitVehicle(vehicle, item)
        end
        cb({ ok = true }); return
    end

    if mode == 'player_vehicle_exit' then
        local index = tonumber(id:match('^pexit:(%d+)$'))
        if index and context.occupants and context.occupants[index] then
            local item = context.occupants[index]
            local vehicle = context.vehicle
            local access = item.access or FivePD_ResolveCustodySeatAccess(vehicle, item.seat)
            if not doorIsOpen(vehicle, access.door) then
                notify('aviso', 'Custódia', access.trunk and 'Abra o porta-malas antes de retirar o jogador.' or 'Abra a porta correspondente antes de retirar o jogador.')
                cb({ ok = false }); return
            end
            closeRadial()
            local netId = NetworkGetEntityIsNetworked(vehicle) and NetworkGetNetworkIdFromEntity(vehicle) or 0
            if netId > 0 then TriggerServerEvent('fivepd_sp:police:playerCustody:leaveVehicle', item.serverId, netId) end
        end
        cb({ ok = true }); return
    end

    if mode == 'player_main' or (mode and mode:sub(1, 16) == 'player_category:') then
        if not isOtherPlayerPed(ped) or playerPedIsJailed(ped) then
            closeRadial(); cb({ ok = false }); return
        end

        local playerCategory = id:match('^pcategory:(.+)$')
        if playerCategory then
            if playerCategory == 'infractions' then
                closeRadial()
                cb({ ok = false }); return
            end
            openPlayerCategoryRadial(ped, playerCategory)
            cb({ ok = true }); return
        end

        if id == 'player:search' then
            searchPlayerPed(ped)
        elseif id == 'player:documents' then
            requestPlayerDocuments(ped)
        elseif id == 'player:cuff' then
            triggerPlayerCustodyAction(ped, 'cuff')
            CreateThread(function()
                Wait(260)
                if isOtherPlayerPed(ped) and radialOpen then openPlayerCategoryRadial(ped, 'control') end
            end)
        elseif id == 'player:hold' then
            triggerPlayerCustodyAction(ped, 'hold')
            closeRadial()
        elseif id == 'player:vehicle' then
            putPlayerInNearestVehicle(ped)
            closeRadial()
        elseif id == 'player:release' then
            triggerPlayerCustodyAction(ped, 'release')
            closeRadial()
        end
        cb({ ok = true }); return
    end

    if not isValidNpc(ped) then closeRadial(); cb({ ok = false }); return end

    if mode == 'post_search' then
        if id == 'post:cuff' then
            closeRadial()
            setCuffed(ped, true)
            if isValidNpc(ped) then openCategoryRadial(ped, 'control') end
        elseif id == 'post:continue' then
            openMainRadial(ped)
        end
        cb({ ok = true }); return
    end

    if mode == 'qru_dialogue' then
        if id == 'back' then
            openCategoryRadial(ped, 'identification')
        else
            local index = tonumber(id:match('^qdlg:(%d+)$'))
            local dialogue = index and type(context.dialogues) == 'table' and context.dialogues[index] or nil
            if dialogue then
                closeRadial()
                local ok, opened = pcall(function()
                    return GetResourceState('fivepd_sp_qru') == 'started'
                        and exports.fivepd_sp_qru:OpenQruDialogueForPed(ped, dialogue.id)
                end)
                if (not ok or opened ~= true) and isValidNpc(ped) then
                    -- A QRU pode ter sido finalizada/removida enquanto o menu estava aberto.
                    openDialogue(ped)
                end
            end
        end
        cb({ ok = true }); return
    end

    if mode == 'dialogue' then
        if id == 'back' then openCategoryRadial(ped, 'identification')
        elseif id:sub(1, 4) == 'dlg:' then doDialogue(ped, id); openDialogue(ped) end
        cb({ ok = true }); return
    end

    local category = id:match('^category:(.+)$')
    if category then
        if category == 'infractions' then
            closeRadial()
            cb({ ok = false }); return
        end
        openCategoryRadial(ped, category)
        cb({ ok = true }); return
    end

    if id == 'search' then
        local inventoryOpened = searchPed(ped)
        if not inventoryOpened and isValidNpc(ped) then openCategoryRadial(ped, 'identification') end
    elseif id == 'documents' then
        requestPedDocuments(ped)
    elseif id == 'cuff' then
        setCuffed(ped, not stateFor(ped).cuffed)
        if isValidNpc(ped) then openCategoryRadial(ped, 'control') end
    elseif id == 'dialogue' then
        openDialogue(ped)
    elseif id == 'sit' then
        toggleSit(ped)
        if isValidNpc(ped) then openCategoryRadial(ped, 'control') end
    elseif id == 'follow' then
        toggleFollow(ped)
        if isValidNpc(ped) then openCategoryRadial(ped, 'conduction') end
    elseif id == 'hold' then
        toggleHold(ped)
        closeRadial()
    elseif id == 'vehicle' then
        openVehicleSeats(ped)
    elseif id == 'place' then
        beginPlacement(ped)
    elseif id == 'traffic_release_foot' or id == 'traffic_release_vehicle' then
        local mode = id == 'traffic_release_vehicle' and 'vehicle' or 'foot'
        local ok, released = pcall(function()
            return exports.fivepd_sp_trafficstop:LiberarAbordagemPorPed(ped, mode)
        end)
        if ok and released == true then
            closeRadial()
        elseif isValidNpc(ped) then
            openCategoryRadial(ped, 'finish')
        end
    elseif id == 'release' then
        if releasePed(ped) then closeRadial() else openCategoryRadial(ped, 'finish') end
    elseif id == 'dismiss' then
        closeRadial()
        dismissPed(ped)
    end
    cb({ ok = true })
end)

RegisterNUICallback('close', function(_, cb)
    local mode = radialMode
    local context = radialContext or {}
    local requestId = mode == 'trafficstop_type' and tonumber(context.requestId) or nil
    closeRadial()
    if requestId then TriggerEvent('fivepd_sp:trafficstop:typeChooserClosed', requestId) end
    cb({ ok = true })
end)


function applyNpcSurrenderSharedState(ped, st)
    if not isValidNpc(ped) or not st or IsPedInAnyVehicle(ped, false) then return end

    local mode = st.kneeling and 'kneel' or (st.handsUp and 'hands' or nil)
    if not mode then return end

    -- Só o policial que o SERVIDOR marcou como dono da rendição pode emitir a
    -- task. O network owner pode migrar entre jogadores, mas isso não dá a outro
    -- client permissão para reiniciar a animação.
    local surrenderOwner = tonumber(st.stateOwner) or 0
    if surrenderOwner <= 0 or surrenderOwner ~= localServerId() then return end

    local now = GetGameTimer()
    if not canDriveSharedPed(ped) then
        if now < (tonumber(st.surrenderControlRetryAt) or 0) then return end
        st.surrenderControlRetryAt = now + 450
        if not requestControl(ped, 350) then return end
    end

    -- Um NPC rendido deixa de ser população ambiente. Só reforçamos FLAGS aqui;
    -- nenhuma outra Task* é emitida durante a rendição.
    SetEntityAsMissionEntity(ped, true, false)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedKeepTask(ped, true)
    SetPedFleeAttributes(ped, 0, false)
    SetCurrentPedWeapon(ped, joaat('WEAPON_UNARMED'), true)
    SetPedCanRagdoll(ped, false)
    if SetPedCanPlayGestureAnims then SetPedCanPlayGestureAnims(ped, false) end
    if SetPedCanPlayAmbientAnims then SetPedCanPlayAmbientAnims(ped, false) end
    if SetPedCanPlayAmbientBaseAnims then SetPedCanPlayAmbientBaseAnims(ped, false) end
    SetEntityVelocity(ped, 0.0, 0.0, 0.0)

    local dict = mode == 'kneel' and PLAYER_KNEEL_DICT or HANDSUP_DICT
    local anim = mode == 'kneel' and PLAYER_KNEEL_ANIM or HANDSUP_ANIM
    local changed = st.surrenderMode ~= mode

    if changed then
        st.surrenderMode = mode
        st.surrenderAnimIssuedAt = 0
        st.surrenderControlRetryAt = 0

        local officer = stateOwnerPed(st)
        if officer ~= 0 and DoesEntityExist(officer) and not IsEntityDead(officer) then
            SetEntityHeading(ped, desiredHeadingToEntity(ped, officer))
        end

        -- Limpa uma única vez na TRANSIÇÃO de estado. Depois disso não existe
        -- watchdog reiniciando o clip; era essa repetição que fazia as mãos
        -- descerem/subirem continuamente quando o teste de animação oscilava.
        ClearPedTasksImmediately(ped)
        ClearPedSecondaryTask(ped)
    end

    FreezeEntityPosition(ped, true)

    -- Uma emissão por transição. Para mãos para cima usamos o slot upper-body em
    -- loop (49), mas sem TaskStandStill concorrente; a posição física já está
    -- travada pelo FreezeEntityPosition. Ajoelhar permanece corpo inteiro.
    if (tonumber(st.surrenderAnimIssuedAt) or 0) == 0 and requestAnim(dict) then
        local flag = mode == 'hands' and 49 or 1
        TaskPlayAnim(ped, dict, anim, 6.0, -6.0, -1, flag, 0.0, false, false, false)
        st.surrenderAnimIssuedAt = now
    end
end

function clearNpcSurrenderSharedState(ped, st)
    if not st or not canDriveSharedPed(ped) or st.handsUp or st.kneeling then return end
    if st.preventive or st.searching or st.placedAtPoint or st.cuffed then return end

    local hadSurrender = st.surrenderMode ~= nil
    st.surrenderMode = nil
    st.surrenderAnimIssuedAt = 0
    st.surrenderControlRetryAt = 0

    FreezeEntityPosition(ped, false)
    if IsEntityPlayingAnim(ped, HANDSUP_DICT, HANDSUP_ANIM, 3) then StopAnimTask(ped, HANDSUP_DICT, HANDSUP_ANIM, 2.0) end
    if IsEntityPlayingAnim(ped, PLAYER_KNEEL_DICT, PLAYER_KNEEL_ANIM, 3) then StopAnimTask(ped, PLAYER_KNEEL_DICT, PLAYER_KNEEL_ANIM, 2.0) end

    if hadSurrender then
        SetPedCanRagdoll(ped, true)
        if SetPedCanPlayGestureAnims then SetPedCanPlayGestureAnims(ped, true) end
        if SetPedCanPlayAmbientAnims then SetPedCanPlayAmbientAnims(ped, true) end
        if SetPedCanPlayAmbientBaseAnims then SetPedCanPlayAmbientBaseAnims(ped, true) end
    end
end


function applyPreventiveSharedState(ped, st)
    if not isValidNpc(ped) or not st or not canDriveSharedPed(ped) then return end

    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedKeepTask(ped, true)
    SetPedFleeAttributes(ped, 0, false)
    SetCurrentPedWeapon(ped, joaat('WEAPON_UNARMED'), true)

    if IsPedInAnyVehicle(ped, false) then
        FreezeEntityPosition(ped, false)
        st.preventiveApplied = false
        ClearPedTasksImmediately(ped)
        TaskLeaveAnyVehicle(ped, 0, 16)
        return
    end

    FreezeEntityPosition(ped, true)
    st.preventiveApplied = true
    if not IsEntityPlayingAnim(ped, HANDSUP_DICT, HANDSUP_ANIM, 3) then
        TaskStandStill(ped, -1)
        if requestAnim(HANDSUP_DICT) then
            TaskPlayAnim(ped, HANDSUP_DICT, HANDSUP_ANIM, 4.0, -4.0, -1, 49, 0.0, false, false, false)
        end
    end
end

function clearPreventiveSharedState(ped, st)
    if not st or not canDriveSharedPed(ped) then return end
    if st.customSearchActive or st.dialogueFrozen or st.placedAtPoint then return end

    -- Descongela mesmo quando este client não foi quem aplicou o Freeze.
    -- Isso é necessário quando a posse de rede migra durante a preventiva.
    FreezeEntityPosition(ped, false)
    st.preventiveApplied = false
    if not st.cuffed and IsEntityPlayingAnim(ped, HANDSUP_DICT, HANDSUP_ANIM, 3) then
        StopAnimTask(ped, HANDSUP_DICT, HANDSUP_ANIM, 2.0)
    end
end

function restoreSharedVehicleSeat(ped, st)
    if not st or not st.insideVehicle or IsPedInAnyVehicle(ped, false) or not canDriveSharedPed(ped) then return end
    local netId = tonumber(st.vehicleNetId) or 0
    if netId <= 0 or not NetworkDoesNetworkIdExist(netId) then return end

    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if vehicle == 0 or not DoesEntityExist(vehicle) or not IsEntityAVehicle(vehicle) then return end

    local seat = tonumber(st.vehicleSeat) or 0
    if IsVehicleSeatFree(vehicle, seat) then
        SetPedIntoVehicle(ped, vehicle, seat)
    end
end

function maintainSeatedSharedState(ped, st)
    if not st or not st.seated or not canDriveSharedPed(ped) then return end
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedKeepTask(ped, true)
    SetPedFleeAttributes(ped, 0, false)

    if st.cuffed then
        ensureCuffVisual(ped, st)
        return
    end

    if type(IsPedUsingAnyScenario) ~= 'function' or not IsPedUsingAnyScenario(ped) then
        ClearPedTasks(ped)
        TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_PICNIC', 0, true)
    end
end

-- Mantém o anchor invisível em TODOS os clientes. O objeto existe na rede
-- apenas para transportar uma transformação suave da condução.
AddStateBagChangeHandler('fivepd_sp:police:escortAnchor', nil, function(bagName, _, value)
    if value ~= true then return end
    CreateThread(function()
        for _ = 1, 30 do
            local entity = GetEntityFromStateBagName(bagName)
            if entity and entity ~= 0 and DoesEntityExist(entity) then
                SetEntityVisible(entity, false, false)
                SetEntityCollision(entity, false, false)
                SetEntityAlpha(entity, 0, false)
                return
            end
            Wait(50)
        end
    end)
end)

function FivePD_ApplyObserverCustodyVisual(ped, st)
    if not st or not DoesEntityExist(ped) then return end

    -- State bags são autoritativas. Mesmo quando este cliente não é o network
    -- owner do NPC, ele reforça localmente a pose de algemado para que todos os
    -- policiais/civis vejam o mesmo resultado imediatamente.
    if st.cuffed and not st.searching and not IsPedInAnyVehicle(ped, false) then
        SetEnableHandcuffs(ped, true)
        ensureCuffProp(ped)
        if requestAnim(CUFF_DICT) and not IsEntityPlayingAnim(ped, CUFF_DICT, CUFF_ANIM, 3) then
            TaskPlayAnim(ped, CUFF_DICT, CUFF_ANIM, 4.0, -4.0, -1, 49, 0.0, false, false, false)
        end
    end

    -- A geometria de conducao V38 e mantida exclusivamente pelo loop visual
    -- dedicado (abaixo); aqui so restauramos a pose de algemado. Antes ambos
    -- tentavam anexar o mesmo ped no mesmo frame, provocando reattaches.
end

RegisterNetEvent('fivepd_sp:pm:dutyChanged', function(enabled)
    if enabled == true then
        CreateThread(function()
            Wait(150)
            -- Os targets globais permanecem registrados durante toda a vida do
            -- resource. canInteract/onDuty decide o que fica disponível. Isso
            -- evita remover/recriar opções do ox_target em mudanças de serviço,
            -- o que podia fazer as interações de NPC sumirem ou deixar índices
            -- visuais inválidos enquanto o ALT estava aberto.
            registerVehicleIdentificationInteraction(false)
            registerPrimaryPedInteraction(false)
            registerInteraction(false)
        end)
        return
    end
    TriggerServerEvent('fivepd_sp:police:playerInteraction:releaseOwnedStates')
    -- Não removemos os targets ao sair de serviço. Todas as opções já usam
    -- onDuty() em canInteract e ficam automaticamente indisponíveis.
    closeRadial()
    cancelPlacement(false)
    escortedPed = nil
    hideEscortHelp()
    stopEscortPlayerAnim()
    clearAllCuffProps()
    for ped, st in pairs(pedStates) do
        if DoesEntityExist(ped) then
            refreshSharedState(ped, st)
            local me = localServerId()
            local ownsPrimary = tonumber(st.stateOwner or 0) == me
            local controlsPed = tonumber(st.controller or 0) == me
            local ownsSearch = tonumber(st.searchOwner or 0) == me
            local foreignController = (tonumber(st.controller or 0) or 0) > 0 and not controlsPed
            local foreignSearch = (tonumber(st.searchOwner or 0) or 0) > 0 and not ownsSearch

            if ownsSearch and not ownsPrimary and not controlsPed then
                st.searching = false
                syncState(ped, { searching = false })
            end

            if controlsPed and not ownsPrimary then
                if canDriveSharedPed(ped) then
                    detachEscort(ped)
                    stopEscortPlayerAnim()
                end
                syncState(ped, { held = false, following = false })
            elseif ownsPrimary and not foreignController and not foreignSearch then
                if canDriveSharedPed(ped) then
                    setPlacedPositionLock(ped, st, false, false)
                    detachEscort(ped)
                    stopCuffVisual(ped)
                    FreezeEntityPosition(ped, false)
                    if st.dialogueFrozen then st.dialogueFrozen = false end
                    SetPedKeepTask(ped, false)
                    SetBlockingOfNonTemporaryEvents(ped, false)
                    ClearPedTasks(ped)
                    if not IsPedInAnyVehicle(ped, false) then TaskWanderStandard(ped, 10.0, 10) end
                end

                syncState(ped, {
                    approached = false,
                    cuffed = false,
                    seated = false,
                    following = false,
                    held = false,
                    insideVehicle = false,
                    preventive = false,
                    placedAtPoint = false,
                    movingToPoint = false,
                    searching = false,
                    targetX = 0.0,
                    targetY = 0.0,
                    targetZ = 0.0,
                    vehicleNetId = 0,
                    vehicleSeat = 0
                })
            end
        end
    end
    pedStates = {}
end)

RegisterNetEvent('fivepd_sp:police:qru:new', function(call)
    TriggerEvent('fivepd_sp:phone:muralha:qruRefresh')
end)

RegisterNetEvent('fivepd_sp:police:qru:accepted', function(call)
    if call and call.coords then
        SetNewWaypoint((call.coords.x or 0.0) + 0.0, (call.coords.y or 0.0) + 0.0)
    end
    TriggerEvent('fivepd_sp:phone:muralha:qruRefresh')
end)



CreateThread(function()
    while true do
        -- Não removemos/recriamos opções do ox_target periodicamente enquanto
        -- o jogador está mirando. Regravar as opções com o menu aberto deixa o
        -- índice visual do ox_target apontando para uma tabela que já foi
        -- removida e pode causar erro em client/main.lua:411 ao selecionar.
        -- O rebind agora só acontece quando um registro realmente está ausente
        -- ou quando o próprio ox_target/resource reinicia (tratado abaixo).
        if GetResourceState('ox_target') == 'started' then
            if not vehicleIdentificationInteractionRegistered then registerVehicleIdentificationInteraction(false) end
            if not primaryPedInteractionRegistered then registerPrimaryPedInteraction(false) end
            if not interactionRegistered then registerInteraction(false) end
        else
            interactionRegistered = false
            primaryPedInteractionRegistered = false
            vehicleIdentificationInteractionRegistered = false
        end
        Wait(1000)
    end
end)

CreateThread(function()
    while true do
        for _, ped in ipairs(GetGamePool('CPed')) do
            if isValidNpc(ped) and NetworkGetEntityIsNetworked(ped) and hasSharedPoliceState(ped) then
                refreshSharedState(ped, stateFor(ped))
            end
        end
        Wait(700)
    end
end)

CreateThread(function()
    while true do
        local wait = 800
        for ped, st in pairs(pedStates) do
            if not DoesEntityExist(ped) or IsEntityDead(ped) then
                -- Ped removido da stream/dead: nunca deixar ancora local orfa.
                if st.escortAnchor and st.escortAnchor ~= 0 then
                    if DoesEntityExist(ped) and IsEntityAttachedToEntity(ped, st.escortAnchor) then
                        DetachEntity(ped, true, false)
                    end
                    FivePD_DeleteEscortAnchor(st.escortAnchor)
                    st.escortAnchor = nil
                end
                releasePlacedPedControl(ped, st)
                if escortedPed == ped then
                    escortedPed = nil
                    hideEscortHelp()
                    stopEscortPlayerAnim()
                end
                pedStates[ped] = nil
            else
                local now = GetGameTimer()
                if NetworkGetEntityIsNetworked(ped) and now - (st.sharedRefreshAt or 0) >= 300 then
                    refreshSharedState(ped, st)
                end

                local canDrive = canDriveSharedPed(ped)
                local localController = tonumber(st.controller or 0) == localServerId()

                FivePD_ApplyObserverCustodyVisual(ped, st)

                -- Um anchor LOCAL por cliente segue o ped do policial naquele
                -- render frame (ja interpolado pelo jogo). Nunca movemos um prop
                -- de rede em loop. O NPC fica visualmente na mesma posicao
                -- relativa para o condutor e para os policiais observadores.
                if st.held and st.cuffed and not IsPedInAnyVehicle(ped, false) then
                    wait = 0
                    local escortOfficer = controllerPed(st)
                    if escortOfficer ~= 0 and not IsPedInAnyVehicle(escortOfficer, false) then
                        local anchor = FivePD_EnsureLocalNpcEscortAnchor(escortOfficer, st.escortAnchor)
                        if anchor ~= 0 then
                            st.escortAnchor = anchor
                            FivePD_AttachEscortPedToAnchor(ped, escortOfficer, anchor)
                            SetEntityNoCollisionEntity(ped, escortOfficer, true)
                            SetEntityNoCollisionEntity(escortOfficer, ped, true)
                        end
                    elseif st.escortAnchor and st.escortAnchor ~= 0 then
                        -- Policial deixou o escopo OneSync / entrou em viatura.
                        -- Soltamos apenas o visual local enquanto aguardamos a
                        -- decisao definitiva de custodia no servidor.
                        detachEscort(ped)
                    end
                elseif st.escortAnchor and st.escortAnchor ~= 0 then
                    -- Um observador tambem precisa soltar seu anchor local ao
                    -- receber held=false; antes apenas o condutor limpava tudo.
                    detachEscort(ped)
                end

                -- A interface de condução pertence somente ao policial que iniciou
                -- o vínculo. O client que for network owner apenas mantém o ped
                -- anexado ao policial correto, sem assumir a condução para si.
                if st.held and localController and onDuty() and not IsPedInAnyVehicle(ped, false) then
                    wait = 0
                    escortedPed = ped
                    showEscortHelp(false)
                    DisableControlAction(0, 21, true) -- sprint
                    DisableControlAction(0, RELEASE_ESCORT_CONTROL, true)
                    DisableControlAction(1, RELEASE_ESCORT_CONTROL, true)
                    DisableControlAction(2, RELEASE_ESCORT_CONTROL, true)

                    local releasePressed = IsDisabledControlJustPressed(0, RELEASE_ESCORT_CONTROL)
                        or IsDisabledControlJustPressed(1, RELEASE_ESCORT_CONTROL)
                        or IsDisabledControlJustPressed(2, RELEASE_ESCORT_CONTROL)

                    if releasePressed then
                        toggleHold(ped)
                    elseif IsPedInAnyVehicle(PlayerPedId(), false) or IsEntityDead(PlayerPedId()) then
                        if canDrive then detachEscort(ped) end
                        st.held = false
                        st.following = false
                        syncState(ped, { held = false, following = false })
                        clearEscortOwner(ped)
                        stopEscortPlayerAnim()
                        if canDrive then restoreApproachState(ped, st) end
                    else
                        ensureEscortPlayerAnim()
                    end
                elseif escortedPed == ped and (not st.held or not localController) then
                    escortedPed = nil
                    hideEscortHelp()
                    stopEscortPlayerAnim()
                end

                -- O policial que emitiu a ordem é quem conclui a transição
                -- "andando até o ponto" -> "permanecer no ponto". A execução da
                -- task pode ocorrer em qualquer client que possua a entidade.
                if st.movingToPoint and st.targetPoint
                    and onDuty()
                    and tonumber(st.stateOwner or 0) == localServerId() then

                    if (st.moveUntil or 0) <= 0 then st.moveUntil = now + 12000 end
                    local reached = #(GetEntityCoords(ped) - st.targetPoint) <= 0.55
                    local timedOut = now >= (st.moveUntil or 0)
                    if reached or timedOut then
                        local landed = GetEntityCoords(ped)
                        st.targetPoint = vector3(landed.x, landed.y, landed.z)
                        st.movingToPoint = false
                        st.placedAtPoint = true
                        st.moveUntil = 0
                        st.busyUntil = 0
                        syncState(ped, {
                            movingToPoint = false,
                            placedAtPoint = true,
                            targetX = landed.x + 0.0,
                            targetY = landed.y + 0.0,
                            targetZ = landed.z + 0.0
                        })
                    end
                end

                local localSurrenderOwner = (st.handsUp or st.kneeling)
                    and tonumber(st.stateOwner or 0) == localServerId()

                if localSurrenderOwner then
                    -- A função pode solicitar network control caso ele tenha migrado.
                    -- Nenhum outro client emite task de rendição para este NPC.
                    wait = math.min(wait, 80)
                    applyNpcSurrenderSharedState(ped, st)
                elseif canDrive then
                    if st.preventive then
                        wait = math.min(wait, 120)
                        applyPreventiveSharedState(ped, st)
                    elseif st.handsUp or st.kneeling then
                        -- Observadores/network owners eventuais não tocam na árvore
                        -- de tasks. A animação recebida pela rede permanece intacta.
                        wait = math.min(wait, 250)
                    else
                        if not st.placedAtPoint and not st.searching then
                            clearPreventiveSharedState(ped, st)
                            clearNpcSurrenderSharedState(ped, st)
                        end

                        -- Uma revista em andamento tem prioridade sobre o
                        -- mantenedor. A animação pareada é controlada pelo
                        -- policial que iniciou a revista e não deve ser sobrescrita.
                        if st.searching then
                            wait = math.min(wait, 180)
                        elseif st.insideVehicle then
                            wait = math.min(wait, 250)
                            restoreSharedVehicleSeat(ped, st)
                            if st.cuffed then ensureCuffVisual(ped, st) end
                        elseif st.held and not IsPedInAnyVehicle(ped, false) then
                            wait = 0
                            if controllerPed(st) ~= 0 then
                                applyEscortAttachment(ped, st)
                            else
                                SetBlockingOfNonTemporaryEvents(ped, true)
                                SetPedKeepTask(ped, true)
                                TaskStandStill(ped, -1)
                                if st.cuffed then ensureCuffVisual(ped, st) end
                            end
                        elseif st.movingToPoint and not IsPedInAnyVehicle(ped, false) then
                            wait = math.min(wait, 100)
                            local target = st.targetPoint
                            if target then
                                if now - (st.lastMoveTask or 0) > 3200 and #(GetEntityCoords(ped) - target) > 0.55 then
                                    st.lastMoveTask = now
                                    SetBlockingOfNonTemporaryEvents(ped, true)
                                    SetPedKeepTask(ped, true)
                                    SetPedFleeAttributes(ped, 0, false)
                                    ClearPedTasks(ped)
                                    TaskFollowNavMeshToCoord(ped, target.x, target.y, target.z, 1.0, 11000, 0.35, false, 0.0)
                                    if st.cuffed then ensureCuffVisual(ped, st) end
                                end
                            end
                        elseif st.placedAtPoint and not IsPedInAnyVehicle(ped, false) then
                            -- Manutencao leve: sem reiniciar animacoes a cada frame.
                            wait = math.min(wait, 180)
                            if st.targetPoint then
                                holdPedAtPlacedPoint(ped, st, false)
                            end
                        elseif st.seated and not IsPedInAnyVehicle(ped, false) then
                            wait = math.min(wait, 300)
                            maintainSeatedSharedState(ped, st)
                        elseif st.following and not IsPedInAnyVehicle(ped, false) then
                            wait = math.min(wait, 250)
                            if controllerPed(st) ~= 0 then
                                if now - (st.lastFollowTask or 0) > 2200 then applyFollowTask(ped, st, false) end
                            else
                                SetBlockingOfNonTemporaryEvents(ped, true)
                                SetPedKeepTask(ped, true)
                                TaskStandStill(ped, -1)
                                if st.cuffed then ensureCuffVisual(ped, st) end
                            end
                        elseif st.approached and not st.enteringVehicle then
                            wait = math.min(wait, 350)
                            if st.cuffed then ensureCuffVisual(ped, st) end
                            if now >= (st.busyUntil or 0) and now - (st.lastHoldPositionTask or 0) > 1200 then
                                restoreApproachState(ped, st)
                            end
                        elseif st.cuffed then
                            wait = math.min(wait, 300)
                            SetBlockingOfNonTemporaryEvents(ped, true)
                            SetPedKeepTask(ped, true)
                            if now - (st.lastHoldPositionTask or 0) > 1200 then
                                TaskStandStill(ped, -1)
                                st.lastHoldPositionTask = now
                            end
                            ensureCuffVisual(ped, st)
                        end
                    end
                end

                if NetworkGetEntityIsNetworked(ped)
                    and not sharedStateActive(st)
                    and not st.customSearchActive
                    and not st.dialogueFrozen
                    and ped ~= currentPed
                    and ped ~= placementPed then

                    releasePlacedPedControl(ped, st)
                    pedStates[ped] = nil
                end
            end
        end
        if radialOpen and not onDuty() then closeRadial() end

        if placementActive then
            wait = 0
            local ped = placementPed
            if not onDuty() or not isValidNpc(ped) then
                cancelPlacement(false)
            else
                DisableControlAction(0, 24, true) -- ataque
                DisableControlAction(0, 25, true) -- mira
                DisableControlAction(0, 37, true) -- seletor de arma
                DisableControlAction(0, 38, true) -- E / confirmar apenas nesta seleção
                DisableControlAction(0, RELEASE_ESCORT_CONTROL, true) -- Z / cancelar apenas nesta seleção
                DisableControlAction(0, 140, true)
                DisableControlAction(0, 141, true)
                DisableControlAction(0, 142, true)

                placementPoint = placementCandidate()
                if placementPoint then
                    DrawMarker(
                        1,
                        placementPoint.x, placementPoint.y, placementPoint.z - 0.08,
                        0.0, 0.0, 0.0,
                        0.0, 0.0, 0.0,
                        0.72, 0.72, 0.16,
                        217, 21, 39, 190,
                        false, false, 2, false, nil, nil, false
                    )
                end
                showPlacementHelp()

                if IsDisabledControlJustPressed(0, 38) then -- E
                    if placementPoint then
                        local chosenPed = ped
                        local chosenPoint = placementPoint
                        cancelPlacement(false)
                        local st = stateFor(chosenPed)
                        st.busyUntil = GetGameTimer() + 12000
                        if sendPedToPoint(chosenPed, chosenPoint) then
                            notify('sucesso', 'Abordagem', 'Pessoa orientada a permanecer no local indicado.')
                        else
                            notify('aviso', 'Abordagem', 'Não foi possível enviar a pessoa para esse local.')
                            restoreApproachState(chosenPed, st)
                        end
                    end
                elseif IsDisabledControlJustPressed(0, RELEASE_ESCORT_CONTROL) then -- Z
                    cancelPlacement(true)
                end
            end
        end

        -- Enquanto o radial de abordagem estiver aberto, o NPC mantém atenção
        -- visual no policial. A rotação só é solicitada quando necessário e
        -- com TaskTurnPedToFaceEntity, então não há snap brusco de heading.
        if radialOpen then
            local menuPed = (radialContext and radialContext.ped) or currentPed
            if isValidNpc(menuPed) then
                turnApproachedPedNaturally(menuPed, stateFor(menuPed))
                wait = math.min(wait, 120)
            end
        end

        if (not escortedPed or not isValidNpc(escortedPed) or not stateFor(escortedPed).held) and not playerEscortOfficerActive then
            stopEscortPlayerAnim()
        end
        Wait(wait)
    end
end)

AddEventHandler('onClientResourceStart', function(resource)
    if resource == 'ox_target' then
        interactionRegistered = false
        primaryPedInteractionRegistered = false
        vehicleIdentificationInteractionRegistered = false
        CreateThread(function()
            Wait(250)
            registerVehicleIdentificationInteraction(true)
            registerPrimaryPedInteraction(true)
            registerInteraction(true)
        end)
    elseif resource == GetCurrentResourceName() then
        CreateThread(function()
            Wait(350)
            registerVehicleIdentificationInteraction(true)
            registerPrimaryPedInteraction(true)
            registerInteraction(true)
        end)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    unregisterInteraction()
    unregisterVehicleIdentificationInteraction()
    closeRadial()
    cancelPlacement(false)
    escortedPed = nil
    hideEscortHelp()
    stopEscortPlayerAnim()
    for ped, st in pairs(pedStates) do
        if DoesEntityExist(ped) then
            setPlacedPositionLock(ped, st, false, false)
            detachEscort(ped)
            if st.dialogueFrozen then FreezeEntityPosition(ped, false) end
            SetPedKeepTask(ped, false)
            if st.cuffed then stopCuffVisual(ped) end
        end
    end
end)

RegisterNetEvent('fivepd_sp:police:playerCustody:cuffAnim', function(cuffed, officerServerId)
    local ped = PlayerPedId()
    if cuffed == true then
        playerCustodyPairAnimUntil = GetGameTimer() + 3900
        local playerIndex = GetPlayerFromServerId(tonumber(officerServerId) or -1)
        local officerPed = playerIndex ~= -1 and GetPlayerPed(playerIndex) or 0
        if officerPed ~= 0 and DoesEntityExist(officerPed) then TaskTurnPedToFaceEntity(ped, officerPed, 350) end
        if requestAnim(CUFF_PAIR_DICT) then
            StopAnimTask(ped, CUFF_DICT, CUFF_ANIM, 1.0)
            TaskPlayAnim(ped, CUFF_PAIR_DICT, CUFF_SUSPECT_ANIM, 8.0, -8.0, 3750, 2, 0.0, false, false, false)
        end
    else
        playerCustodyPairAnimUntil = 0
        clearLocalPlayerCuffedVisual()
    end
end)

RegisterNetEvent('fivepd_sp:police:playerCustody:officerCuffAnim', function(targetServerId, cuffed)
    local index = GetPlayerFromServerId(tonumber(targetServerId) or -1)
    local ped = index ~= -1 and GetPlayerPed(index) or 0
    playOfficerCuffOnly(ped, cuffed == true)
end)

RegisterNetEvent('fivepd_sp:police:playerCustody:enterVehicle', function(vehicleNetId, seat)
    local vehicle = NetworkGetEntityFromNetworkId(tonumber(vehicleNetId) or 0)
    local ped = PlayerPedId()
    seat = math.floor(tonumber(seat) or 1)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return end
    local access = FivePD_ResolveCustodySeatAccess(vehicle, seat)
    detachLocalCustodyEscort()
    StopAnimTask(ped, CUFF_DICT, CUFF_ANIM, 1.0)

    if access.trunk then
        local entry = FivePD_CustodyEntryPosition(vehicle, access.door, ped)
        if entry and entry.x then
            TaskGoStraightToCoord(ped, entry.x, entry.y, entry.z, 1.0, 3000, GetEntityHeading(vehicle), 0.25)
            local untilAt = GetGameTimer() + 3000
            while DoesEntityExist(vehicle) and #(GetEntityCoords(ped) - entry) > 1.35 and GetGameTimer() < untilAt do Wait(60) end
        end
        if DoesEntityExist(vehicle) and IsVehicleSeatFree(vehicle, seat) then
            TaskTurnPedToFaceEntity(ped, vehicle, 250)
            Wait(280)
            TaskWarpPedIntoVehicle(ped, vehicle, seat)
        end
    else
        TaskEnterVehicle(ped, vehicle, 8000, seat, 1.0, 1, 0)
    end

    CreateThread(function()
        local untilAt = GetGameTimer() + (access.trunk and 2600 or 8200)
        while DoesEntityExist(vehicle) and not IsPedInVehicle(ped, vehicle, false) and GetGameTimer() < untilAt do Wait(100) end
        if DoesEntityExist(vehicle) and not IsPedInVehicle(ped, vehicle, false) and IsVehicleSeatFree(vehicle, seat) then
            TaskWarpPedIntoVehicle(ped, vehicle, seat)
        end
    end)
end)

RegisterNetEvent('fivepd_sp:police:playerCustody:leaveVehicle', function(vehicleNetId)
    local ped = PlayerPedId()
    local vehicle = NetworkGetEntityFromNetworkId(tonumber(vehicleNetId) or 0)
    if vehicle == 0 or not DoesEntityExist(vehicle) or not IsPedInVehicle(ped, vehicle, false) then return end

    local currentSeat = nil
    local maxSeat = FivePD_CustodyMaxPassengerSeat(vehicle)
    for seat = 0, maxSeat do
        if GetPedInVehicleSeat(vehicle, seat) == ped then currentSeat = seat break end
    end
    local access = currentSeat ~= nil and FivePD_ResolveCustodySeatAccess(vehicle, currentSeat) or nil
    TaskLeaveVehicle(ped, vehicle, access and access.trunk and 16 or 0)
    if access and access.trunk then
        CreateThread(function()
            local untilAt = GetGameTimer() + 2200
            while IsPedInVehicle(ped, vehicle, false) and GetGameTimer() < untilAt do Wait(80) end
            if not IsPedInAnyVehicle(ped, false) and DoesEntityExist(vehicle) then
                local entry = FivePD_CustodyEntryPosition(vehicle, access.door, ped)
                if entry and entry.x then
                    SetEntityCoordsNoOffset(ped, entry.x, entry.y, entry.z, false, false, false)
                    SetEntityHeading(ped, GetEntityHeading(vehicle))
                end
            end
        end)
    end
end)

function teleportCustodyPlayer(point)
    point = type(point) == 'table' and point or {}
    local x, y, z = tonumber(point.x), tonumber(point.y), tonumber(point.z)
    if not x or not y or not z then return end
    local ped = PlayerPedId()
    DoScreenFadeOut(250)
    local untilAt = GetGameTimer() + 900
    while not IsScreenFadedOut() and GetGameTimer() < untilAt do Wait(0) end
    detachLocalCustodyEscort()
    SetEntityCoordsNoOffset(ped, x + 0.0, y + 0.0, z + 0.0, false, false, false)
    SetEntityHeading(ped, tonumber(point.heading) or 0.0)
    SetEntityVelocity(ped, 0.0, 0.0, 0.0)
    Wait(120)
    DoScreenFadeIn(300)
end

do
    local surrender = {
        aimTarget = 0,
        pressStartedAt = 0,
        holdSent = false,
        helpVisible = false,
        cooldownUntil = 0,
        pendingPrompt = nil
    }

    function surrender.cfg()
        return type(Config.Surrender) == 'table' and Config.Surrender or {}
    end

    function surrender.aimedPed()
        if not onDuty() or IsPedInAnyVehicle(PlayerPedId(), false) or not IsPlayerFreeAiming(PlayerId()) then return 0 end
        local hit, entity = GetEntityPlayerIsFreeAimingAt(PlayerId())
        if not hit or not entity or entity == 0 or entity == PlayerPedId() then return 0 end
        if not IsEntityAPed(entity) or not IsPedHuman(entity) or IsEntityDead(entity) or IsPedInAnyVehicle(entity, false) then return 0 end
        if bagValue(entity, 'cuffed') == true or bagValue(entity, 'insideVehicle') == true then return 0 end
        if not IsPedAPlayer(entity) and (bagValue(entity, 'handsUp') == true or bagValue(entity, 'kneeling') == true) then
            local owner = bagNumber(entity, 'stateOwner') or 0
            if owner ~= localServerId() then return 0 end
        end
        if IsPedAPlayer(entity) and not canPoliceInteractWithPlayerPed(entity) then return 0 end
        local maxDistance = tonumber(surrender.cfg().maxDistance) or 18.0
        if #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(entity)) > maxDistance then return 0 end
        return entity
    end

    function surrender.showHelp()
        if surrender.helpVisible then return end
        surrender.helpVisible = true
        TriggerEvent('fivepd_sp:ui:ajuda:mostrar', {
            tecla = 'E',
            texto = 'Ordem de rendição',
            detalhe = 'Toque • mãos para cima   |   Segure 1,5s • ajoelhar'
        })
    end

    function surrender.hideHelp()
        if not surrender.helpVisible then return end
        surrender.helpVisible = false
        TriggerEvent('fivepd_sp:ui:ajuda:ocultar')
    end

    function surrender.issue(ped, order)
        if ped == 0 or not DoesEntityExist(ped) then return end
        if IsPedAPlayer(ped) then
            if not canPoliceInteractWithPlayerPed(ped) then return end
            local serverId = serverIdForPlayerPed(ped)
            if serverId then TriggerServerEvent('fivepd_sp:police:surrender:requestPlayer', serverId, order) end
        else
            if bagValue(ped, 'handsUp') == true or bagValue(ped, 'kneeling') == true then
                local owner = bagNumber(ped, 'stateOwner') or 0
                if owner ~= localServerId() then
                    notify('info', 'Abordagem', 'Esse indivíduo já está rendido sob controle de outro policial.')
                    return
                end
            end
            -- Promove o ped pelo mesmo caminho usado pela custódia. Além do
            -- network id, isso o marca como mission entity e reduz a chance de
            -- o population manager reassumir a IA durante a rendição.
            local netId = FivePD_EnsureCustodyNpcNetworked(ped)
            if netId and netId > 0 then
                SetEntityAsMissionEntity(ped, true, false)
                TriggerServerEvent('fivepd_sp:police:surrender:requestNpc', netId, order)
            end
        end
    end

    RegisterNetEvent('fivepd_sp:police:surrender:prompt', function(data)
        data = type(data) == 'table' and data or {}
        if surrender.pendingPrompt then
            TriggerServerEvent('fivepd_sp:police:surrender:respond', tonumber(data.id), false, 'busy')
            return
        end
        local id = tonumber(data.id)
        if not id then return end
        local order = tostring(data.order or 'hands')
        local timeout = math.max(3000, tonumber(data.timeoutMs) or 9000)
        surrender.pendingPrompt = { id = id, order = order, expires = GetGameTimer() + timeout }
        TriggerEvent('fivepd_sp:ui:ajuda:mostrar', {
            tecla = 'Y / N',
            texto = 'Você está sendo rendido',
            detalhe = order == 'kneel' and 'Ordem: ajoelhe-se com as mãos para cima • Y aceitar • N recusar' or 'Ordem: coloque as mãos para cima • Y aceitar • N recusar'
        })
    end)

    RegisterNetEvent('fivepd_sp:police:surrender:npcReaction', function(netId, reaction, weapon, officerServerId)
        netId = tonumber(netId)
        if not netId or netId <= 0 or not NetworkDoesNetworkIdExist(netId) then return end
        local ped = NetworkGetEntityFromNetworkId(netId)
        if ped == 0 or not DoesEntityExist(ped) or IsEntityDead(ped) or IsPedAPlayer(ped) then return end
        if not NetworkHasControlOfEntity(ped) then return end
        pedStates[ped] = nil
        FreezeEntityPosition(ped, false)
        SetBlockingOfNonTemporaryEvents(ped, false)
        SetPedKeepTask(ped, true)
        ClearPedTasksImmediately(ped)
        local idx = GetPlayerFromServerId(tonumber(officerServerId) or -1)
        local officer = idx and idx >= 0 and GetPlayerPed(idx) or 0
        if reaction == 'flee' then
            SetPedFleeAttributes(ped, 0, false)
            if officer ~= 0 and DoesEntityExist(officer) then TaskSmartFleePed(ped, officer, 500.0, -1, false, false) else TaskWanderStandard(ped, 10.0, 10) end
        elseif reaction == 'attack' then
            local weaponName = tostring(weapon or '')
            if weaponName ~= '' and weaponName ~= 'UNARMED' then
                local hash = joaat(weaponName)
                GiveWeaponToPed(ped, hash, weaponName == 'WEAPON_PISTOL' and 48 or 1, false, true)
                SetCurrentPedWeapon(ped, hash, true)
            else
                SetCurrentPedWeapon(ped, joaat('WEAPON_UNARMED'), true)
            end
            SetPedCombatAbility(ped, 1)
            SetPedCombatRange(ped, 1)
            SetPedCombatMovement(ped, 2)
            SetPedAsEnemy(ped, true)
            if officer ~= 0 and DoesEntityExist(officer) then TaskCombatPed(ped, officer, 0, 16) end
        end
    end)

    AddEventHandler('onResourceStop', function(resource)
        if resource ~= GetCurrentResourceName() then return end
        surrender.pendingPrompt = nil
        surrender.hideHelp()
        TriggerEvent('fivepd_sp:ui:ajuda:ocultar')
    end)

    CreateThread(function()
        while true do
            local waitMs = 250
            local now = GetGameTimer()
            if surrender.pendingPrompt then
                waitMs = 0
                DisableControlAction(0, 246, true) -- Y
                DisableControlAction(0, 249, true) -- N
                if IsDisabledControlJustPressed(0, 246) then
                    local id = surrender.pendingPrompt.id
                    surrender.pendingPrompt = nil
                    TriggerEvent('fivepd_sp:ui:ajuda:ocultar')
                    TriggerServerEvent('fivepd_sp:police:surrender:respond', id, true, 'accepted')
                elseif IsDisabledControlJustPressed(0, 249) then
                    local id = surrender.pendingPrompt.id
                    surrender.pendingPrompt = nil
                    TriggerEvent('fivepd_sp:ui:ajuda:ocultar')
                    TriggerServerEvent('fivepd_sp:police:surrender:respond', id, false, 'rejected')
                elseif now >= surrender.pendingPrompt.expires then
                    local id = surrender.pendingPrompt.id
                    surrender.pendingPrompt = nil
                    TriggerEvent('fivepd_sp:ui:ajuda:ocultar')
                    TriggerServerEvent('fivepd_sp:police:surrender:respond', id, false, 'timeout')
                end
            elseif surrender.cfg().enabled ~= false and onDuty() and not radialOpen and not placementActive and not (type(IsNuiFocused) == 'function' and IsNuiFocused()) then
                local target = surrender.aimedPed()
                if target ~= 0 and not playerPedIsJailed(target) then
                    waitMs = 0
                    DisableControlAction(0, 38, true)
                    surrender.showHelp()
                    if IsDisabledControlJustPressed(0, 38) and now >= surrender.cooldownUntil then
                        surrender.aimTarget = target
                        surrender.pressStartedAt = now
                        surrender.holdSent = false
                    end
                    if surrender.pressStartedAt > 0 and IsDisabledControlPressed(0, 38) then
                        if target ~= surrender.aimTarget then
                            surrender.pressStartedAt = 0
                            surrender.holdSent = false
                        elseif not surrender.holdSent and now - surrender.pressStartedAt >= (tonumber(surrender.cfg().holdMs) or 1500) then
                            surrender.holdSent = true
                            surrender.issue(surrender.aimTarget, 'kneel')
                            surrender.cooldownUntil = now + 1200
                        end
                    end
                    if surrender.pressStartedAt > 0 and IsDisabledControlJustReleased(0, 38) then
                        if not surrender.holdSent and target == surrender.aimTarget and now - surrender.pressStartedAt < (tonumber(surrender.cfg().holdMs) or 1500) then
                            surrender.issue(surrender.aimTarget, 'hands')
                            surrender.cooldownUntil = now + 900
                        end
                        surrender.pressStartedAt = 0
                        surrender.aimTarget = 0
                        surrender.holdSent = false
                    end
                else
                    surrender.hideHelp()
                    surrender.pressStartedAt = 0
                    surrender.aimTarget = 0
                    surrender.holdSent = false
                end
            else
                surrender.hideHelp()
                surrender.pressStartedAt = 0
                surrender.aimTarget = 0
                surrender.holdSent = false
            end
            Wait(waitMs)
        end
    end)
end

FivePD_PcCustodyWait = FivePD_PcCustodyWait or nil

RegisterNetEvent('fivepd_sp:police:pcCustody:notice', function(data)
    data = type(data) == 'table' and data or {}
    SendNUIMessage({ action = 'pcCustodyWait', visible = true, message = tostring(data.message or 'Aguarde o policial civil realizar os procedimentos.'), status = tostring(data.status or 'Procedimento em andamento') })
end)

RegisterNetEvent('fivepd_sp:police:pcCustody:wait', function(data)
    data = type(data) == 'table' and data or {}
    if data.active ~= true then
        FivePD_PcCustodyWait = nil
        SendNUIMessage({ action = 'pcCustodyWait', visible = false })
        return
    end
    local cell = type(data.cell) == 'table' and data.cell or {}
    FivePD_PcCustodyWait = {
        requestId = tonumber(data.requestId),
        cell = cell,
        radius = math.max(1.5, tonumber(data.radius) or 2.8),
        message = tostring(data.message or 'Aguarde o policial civil realizar os procedimentos.'),
        status = 'Aguardando lavratura pela Polícia Civil',
        countdownUntil = 0
    }
    teleportCustodyPlayer(cell)
    SendNUIMessage({ action = 'pcCustodyWait', visible = true, message = FivePD_PcCustodyWait.message, status = FivePD_PcCustodyWait.status })
end)

RegisterNetEvent('fivepd_sp:police:pcCustody:status', function(data)
    data = type(data) == 'table' and data or {}
    if not FivePD_PcCustodyWait then return end
    local seconds = math.max(0, math.floor(tonumber(data.seconds) or 0))
    FivePD_PcCustodyWait.status = tostring(data.message or 'Procedimento concluído.')
    FivePD_PcCustodyWait.countdownUntil = GetGameTimer() + (seconds * 1000)
    SendNUIMessage({ action = 'pcCustodyWait', visible = true, message = FivePD_PcCustodyWait.message, status = FivePD_PcCustodyWait.status, seconds = seconds })
end)

CreateThread(function()
    local lastHud = 0
    while true do
        if FivePD_PcCustodyWait then
            Wait(0)
            local ped = PlayerPedId()
            local cell = FivePD_PcCustodyWait.cell or {}
            local center = vector3(tonumber(cell.x) or 0.0, tonumber(cell.y) or 0.0, tonumber(cell.z) or 0.0)
            if #(GetEntityCoords(ped) - center) > (FivePD_PcCustodyWait.radius or 2.8) then
                SetEntityCoordsNoOffset(ped, center.x, center.y, center.z, false, false, false)
                SetEntityHeading(ped, tonumber(cell.heading) or 0.0)
            end
            DisableControlAction(0, 21, true)
            DisableControlAction(0, 22, true)
            DisableControlAction(0, 23, true)
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 37, true)
            DisableControlAction(0, 75, true)
            DisablePlayerFiring(PlayerId(), true)
            if GetGameTimer() - lastHud >= 500 then
                lastHud = GetGameTimer()
                local seconds = nil
                if (FivePD_PcCustodyWait.countdownUntil or 0) > 0 then seconds = math.max(0, math.ceil((FivePD_PcCustodyWait.countdownUntil - GetGameTimer()) / 1000)) end
                SendNUIMessage({ action = 'pcCustodyWait', visible = true, message = FivePD_PcCustodyWait.message, status = FivePD_PcCustodyWait.status, seconds = seconds })
            end
        else
            Wait(350)
        end
    end
end)

RegisterNetEvent('fivepd_sp:police:jail:begin', function(data)
    FivePD_PcCustodyWait = nil
    SendNUIMessage({ action = 'pcCustodyWait', visible = false })
    data = type(data) == 'table' and data or {}
    localJailState = {
        sentenceId = tonumber(data.sentenceId),
        remainingSeconds = math.max(0, math.floor(tonumber(data.remainingSeconds) or 0)),
        totalSeconds = math.max(0, math.floor(tonumber(data.totalSeconds) or 0)),
        startedAt = GetGameTimer(),
        radius = math.max(8.0, tonumber(data.radius) or 42.0),
        jail = type(data.jail) == 'table' and data.jail or {},
        release = type(data.release) == 'table' and data.release or {},
        reason = tostring(data.reason or 'Pena em cumprimento'),
        bopm = tostring(data.bopm or '')
    }
    clearLocalPlayerCuffedVisual()
    teleportCustodyPlayer(localJailState.jail)
    SendNUIMessage({ action = 'jailHud', visible = true, seconds = localJailState.remainingSeconds, reason = localJailState.reason })
    notify('aviso', 'Custódia', ('Você foi recolhido à carceragem. BOPM %s.'):format(localJailState.bopm ~= '' and localJailState.bopm or 'registrado'))
end)

RegisterNetEvent('fivepd_sp:police:jail:release', function(data)
    data = type(data) == 'table' and data or {}
    local release = type(data.release) == 'table' and data.release or (localJailState and localJailState.release) or nil
    localJailState = nil
    SendNUIMessage({ action = 'jailHud', visible = false })
    SetPlayerCanDoDriveBy(PlayerId(), true)
    if release then teleportCustodyPlayer(release) end
end)

CreateThread(function()
    local lastHudUpdate = 0
    while true do
        local waitMs = 350
        local ped = PlayerPedId()
        local cuffed = bagValue(ped, 'cuffed') == true
        local held = bagValue(ped, 'held') == true
        local handsUp = bagValue(ped, 'handsUp') == true
        local kneeling = bagValue(ped, 'kneeling') == true
        local surrenderRestricted = bagValue(ped, 'surrenderRestricted') == true
        local controller = bagNumber(ped, 'controller') or 0
        local jailed = localJailState ~= nil

        if cuffed or jailed then
            if localPlayerHandsUpApplied then
                StopAnimTask(ped, HANDSUP_DICT, HANDSUP_ANIM, 2.0)
                localPlayerHandsUpApplied = false
            end
            if localPlayerKneelingApplied then
                StopAnimTask(ped, PLAYER_KNEEL_DICT, PLAYER_KNEEL_ANIM, 2.0)
                localPlayerKneelingApplied = false
            end
        end

        if cuffed then
            waitMs = 0
            SetEnableHandcuffs(ped, true)
            SetPedCanPlayGestureAnims(ped, false)
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 37, true)
            DisableControlAction(0, 44, true)
            DisableControlAction(0, 45, true)
            DisableControlAction(0, 22, true)
            DisableControlAction(0, 23, true)
            DisableControlAction(0, 75, true)
            DisableControlAction(0, 140, true)
            DisableControlAction(0, 141, true)
            DisableControlAction(0, 142, true)
            DisableControlAction(0, 143, true)
            DisablePlayerFiring(PlayerId(), true)
            SetCurrentPedWeapon(ped, joaat('WEAPON_UNARMED'), true)

            if held and controller > 0 and not IsPedInAnyVehicle(ped, false) then
                ensureLocalCustodyEscort(controller)
            elseif playerCustodyWasAttached then
                detachLocalCustodyEscort()
            end

            if GetGameTimer() >= playerCustodyPairAnimUntil then
                ensureLocalPlayerCuffedVisual()
            end
        elseif playerCustodyLastCuffed then
            clearLocalPlayerCuffedVisual()
        end
        playerCustodyLastCuffed = cuffed

        if not cuffed and not jailed and surrenderRestricted then
            waitMs = 0
            SetCurrentPedWeapon(ped, joaat('WEAPON_UNARMED'), true)
            DisableControlAction(0, 21, true) -- sprint
            DisableControlAction(0, 22, true) -- pular
            DisableControlAction(0, 23, true) -- entrar em veículo
            DisableControlAction(0, 24, true) -- ataque
            DisableControlAction(0, 25, true) -- mirar
            DisableControlAction(0, 30, true) -- eixo lateral
            DisableControlAction(0, 31, true) -- eixo frente/trás
            DisableControlAction(0, 32, true)
            DisableControlAction(0, 33, true)
            DisableControlAction(0, 34, true)
            DisableControlAction(0, 35, true)
            DisableControlAction(0, 36, true)
            DisableControlAction(0, 37, true) -- roda de armas
            DisableControlAction(0, 44, true)
            DisableControlAction(0, 45, true) -- recarregar
            DisableControlAction(0, 75, true)
            DisableControlAction(0, 140, true)
            DisableControlAction(0, 141, true)
            DisableControlAction(0, 142, true)
            DisableControlAction(0, 143, true)
            DisablePlayerFiring(PlayerId(), true)
        end

        if not cuffed and not jailed then
            if handsUp then
                waitMs = 0
                if localPlayerKneelingApplied then
                    StopAnimTask(ped, PLAYER_KNEEL_DICT, PLAYER_KNEEL_ANIM, 2.0)
                    localPlayerKneelingApplied = false
                end
                SetCurrentPedWeapon(ped, joaat('WEAPON_UNARMED'), true)
                DisableControlAction(0, 21, true)
                DisableControlAction(0, 24, true)
                DisableControlAction(0, 25, true)
                DisableControlAction(0, 37, true)
                DisableControlAction(0, 44, true)
                DisableControlAction(0, 140, true)
                DisableControlAction(0, 141, true)
                DisableControlAction(0, 142, true)
                DisableControlAction(0, 143, true)
                DisablePlayerFiring(PlayerId(), true)
                if requestAnim(HANDSUP_DICT) and not IsEntityPlayingAnim(ped, HANDSUP_DICT, HANDSUP_ANIM, 3) then
                    TaskPlayAnim(ped, HANDSUP_DICT, HANDSUP_ANIM, 4.0, -4.0, -1, 49, 0.0, false, false, false)
                end
                localPlayerHandsUpApplied = true
            elseif kneeling then
                waitMs = 0
                if localPlayerHandsUpApplied then
                    StopAnimTask(ped, HANDSUP_DICT, HANDSUP_ANIM, 2.0)
                    localPlayerHandsUpApplied = false
                end
                SetCurrentPedWeapon(ped, joaat('WEAPON_UNARMED'), true)
                DisableControlAction(0, 21, true)
                DisableControlAction(0, 22, true)
                DisableControlAction(0, 23, true)
                DisableControlAction(0, 24, true)
                DisableControlAction(0, 25, true)
                DisableControlAction(0, 30, true)
                DisableControlAction(0, 31, true)
                DisableControlAction(0, 37, true)
                DisableControlAction(0, 44, true)
                DisableControlAction(0, 140, true)
                DisableControlAction(0, 141, true)
                DisableControlAction(0, 142, true)
                DisableControlAction(0, 143, true)
                DisablePlayerFiring(PlayerId(), true)
                if requestAnim(PLAYER_KNEEL_DICT) and not IsEntityPlayingAnim(ped, PLAYER_KNEEL_DICT, PLAYER_KNEEL_ANIM, 3) then
                    TaskPlayAnim(ped, PLAYER_KNEEL_DICT, PLAYER_KNEEL_ANIM, 4.0, -4.0, -1, 1, 0.0, false, false, false)
                end
                localPlayerKneelingApplied = true
            else
                if localPlayerHandsUpApplied then
                    StopAnimTask(ped, HANDSUP_DICT, HANDSUP_ANIM, 2.0)
                    localPlayerHandsUpApplied = false
                end
                if localPlayerKneelingApplied then
                    StopAnimTask(ped, PLAYER_KNEEL_DICT, PLAYER_KNEEL_ANIM, 2.0)
                    localPlayerKneelingApplied = false
                end
            end
        end

        -- O policial controlador mantém somente sua própria animação e pode
        -- soltar a condução com Z. O preso executa o attachment no próprio client.
        if onDuty() then
            local localId = localServerId()
            local escortTarget = nil
            for _, playerIndex in ipairs(GetActivePlayers()) do
                if playerIndex ~= PlayerId() then
                    local otherPed = GetPlayerPed(playerIndex)
                    if isOtherPlayerPed(otherPed) and bagValue(otherPed, 'held') == true and bagNumber(otherPed, 'controller') == localId then
                        escortTarget = GetPlayerServerId(playerIndex)
                        break
                    end
                end
            end
            playerEscortOfficerActive = escortTarget ~= nil
            if escortTarget then
                waitMs = 0
                ensureEscortPlayerAnim()
                DisableControlAction(0, 21, true) -- sem sprint durante condução pelo braço
                DisableControlAction(0, RELEASE_ESCORT_CONTROL, true)
                if IsDisabledControlJustPressed(0, RELEASE_ESCORT_CONTROL) then
                    TriggerServerEvent('fivepd_sp:police:playerCustody:toggleEscort', escortTarget)
                end
            elseif not escortedPed then
                stopEscortPlayerAnim()
            end
        end

        if jailed then
            waitMs = 0
            DisableControlAction(0, 21, true)
            DisableControlAction(0, 22, true)
            DisableControlAction(0, 23, true)
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 37, true)
            DisableControlAction(0, 44, true)
            DisableControlAction(0, 45, true)
            DisableControlAction(0, 75, true)
            DisableControlAction(0, 140, true)
            DisableControlAction(0, 141, true)
            DisableControlAction(0, 142, true)
            DisableControlAction(0, 143, true)
            DisablePlayerFiring(PlayerId(), true)
            SetPlayerCanDoDriveBy(PlayerId(), false)
            SetCurrentPedWeapon(ped, joaat('WEAPON_UNARMED'), true)

            local jail = localJailState.jail or {}
            local center = vector3(tonumber(jail.x) or 0.0, tonumber(jail.y) or 0.0, tonumber(jail.z) or 0.0)
            if #(GetEntityCoords(ped) - center) > (localJailState.radius or 42.0) then
                SetEntityCoordsNoOffset(ped, center.x, center.y, center.z, false, false, false)
                SetEntityHeading(ped, tonumber(jail.heading) or 0.0)
                notify('aviso', 'Custódia', 'Você deve permanecer na área da carceragem até o término da pena.')
            end

            local elapsed = math.floor((GetGameTimer() - localJailState.startedAt) / 1000)
            local remaining = math.max(0, localJailState.remainingSeconds - elapsed)
            if GetGameTimer() - lastHudUpdate >= 500 then
                lastHudUpdate = GetGameTimer()
                SendNUIMessage({ action = 'jailHud', visible = true, seconds = remaining, reason = localJailState.reason })
            end
        end

        Wait(waitMs)
    end
end)


-- -------------------------------------------------------------------------
-- Custódia NPC / BOPM no escrivão
-- -------------------------------------------------------------------------
-- Estes estados ficam no ambiente do resource (e não como locals do chunk)
-- para manter client/main.lua abaixo do limite de 200 variáveis locais do Lua.
custodyPoints = custodyPoints or {}
custodyClerks = custodyClerks or {}
custodyLastRefresh = custodyLastRefresh or 0
custodyHelpVisible = custodyHelpVisible == true
bopmOpen = bopmOpen == true
bopmContext = bopmContext or nil
pcespCustodyDocument = pcespCustodyDocument or nil
pcespClipboardProp = pcespClipboardProp or 0

function FivePD_StopBopmClipboard()
    local ped = PlayerPedId()
    if ped and ped ~= 0 then StopAnimTask(ped, 'amb@world_human_clipboard@male@base', 'base', 2.0) end
    if pcespClipboardProp and pcespClipboardProp ~= 0 and DoesEntityExist(pcespClipboardProp) then
        DetachEntity(pcespClipboardProp, true, true)
        DeleteEntity(pcespClipboardProp)
    end
    pcespClipboardProp = 0
end

function FivePD_StartBopmClipboard()
    FivePD_StopBopmClipboard()
    local ped = PlayerPedId()
    if not ped or ped == 0 then return end
    local dict = 'amb@world_human_clipboard@male@base'
    RequestAnimDict(dict)
    local deadline = GetGameTimer() + 2500
    while not HasAnimDictLoaded(dict) and GetGameTimer() < deadline do Wait(0) end
    if HasAnimDictLoaded(dict) then TaskPlayAnim(ped, dict, 'base', 4.0, -4.0, -1, 49, 0.0, false, false, false) end
    local model = joaat('p_amb_clipboard_01')
    RequestModel(model)
    deadline = GetGameTimer() + 2000
    while not HasModelLoaded(model) and GetGameTimer() < deadline do Wait(0) end
    if HasModelLoaded(model) then
        pcespClipboardProp = CreateObject(model, 0.0, 0.0, 0.0, false, false, false)
        if pcespClipboardProp and pcespClipboardProp ~= 0 then
            AttachEntityToEntity(pcespClipboardProp, ped, GetPedBoneIndex(ped, 36029), 0.10, 0.02, 0.08, -80.0, 0.0, 0.0, true, true, false, true, 1, true)
        end
        SetModelAsNoLongerNeeded(model)
    end
end

function FivePD_OpenPcespCustodyDocument()
    if not pcespCustodyDocument then return end
    local data = {}
    for key, value in pairs(pcespCustodyDocument) do data[key] = value end
    data.mode = 'civil_document'
    data.lockRecordType = true
    data.finalized = pcespCustodyDocument.finalized == true
    data.draft = pcespCustodyDocument.draft or {}
    data = enrichBopmAutomaticData(type(data) == 'table' and data or {})
    bopmOpen = true
    bopmContext = data
    hideCustodyHelp()
    closeRadial()
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'bopmOpen', data = data })
    CreateThread(FivePD_StartBopmClipboard)
end

function FivePD_TogglePcespDocument(expectedType)
    expectedType = tostring(expectedType or ''):lower()
    if not pcespCustodyDocument or tostring(pcespCustodyDocument.documentType or '') ~= expectedType then
        return notify('aviso', expectedType:upper(), ('Você não possui um documento %s ativo entregue pela Polícia Civil.'):format(expectedType:upper()))
    end
    if bopmOpen and bopmContext and bopmContext.mode == 'civil_document' then
        SendNUIMessage({ action = 'bopmRequestClose' })
    elseif not bopmOpen then
        FivePD_OpenPcespCustodyDocument()
    end
end

RegisterCommand('bopm', function() FivePD_TogglePcespDocument('bopm') end, false)
RegisterCommand('tcopm', function() FivePD_TogglePcespDocument('tcopm') end, false)

function custodyCfg()
    return type(Config.Custody) == 'table' and Config.Custody or {}
end

function hideCustodyHelp()
    if not custodyHelpVisible then return end
    custodyHelpVisible = false
    TriggerEvent('fivepd_sp:ui:ajuda:ocultar')
end

function showCustodyHelp(text, detail)
    custodyHelpVisible = true
    TriggerEvent('fivepd_sp:ui:ajuda:mostrar', {
        tecla = 'E',
        texto = text or 'Falar com o escrivão',
        detalhe = detail or 'Custódia policial'
    })
end

function custodyPointCoords(point)
    return vector3(tonumber(point.x) or 0.0, tonumber(point.y) or 0.0, tonumber(point.z) or 0.0)
end

function requestModelWithTimeout(model, timeout)
    local hash = type(model) == 'number' and model or joaat(tostring(model or 's_m_m_ciasec_01'))
    if not IsModelInCdimage(hash) or not IsModelValid(hash) then return nil end
    RequestModel(hash)
    local untilAt = GetGameTimer() + (timeout or 3500)
    while not HasModelLoaded(hash) and GetGameTimer() < untilAt do Wait(20) end
    if not HasModelLoaded(hash) then return nil end
    return hash
end

function registerClerkTarget(id, ped, point)
    if not ped or ped == 0 or not DoesEntityExist(ped) or GetResourceState('ox_target') ~= 'started' then return nil end
    local targetId = ('fivepd_sp_police:clerk:%s'):format(tostring(id))
    return FSPTarget.RegisterEntity({
        id = targetId,
        entidade = ped,
        distancia = tonumber(custodyCfg().interactionDistance) or 2.2,
        opcoes = {
            {
                id = 'custody_clerk',
                titulo = 'Falar com o escrivão',
                descricao = 'Apresentar uma pessoa algemada e iniciar o BOPM.',
                evento = 'fivepd_sp:police:custody:targetClerk',
                args = { point_id = tostring(id) },
                distancia = tonumber(custodyCfg().interactionDistance) or 2.2,
                podeInteragir = function()
                    return onDuty() and not bopmOpen and not radialOpen and not placementActive
                end
            },
            {
                id = 'custody_drug_bag',
                titulo = 'Entregar bolsa de drogas apreendida',
                descricao = 'Formalizar a apreensão no BOPM e recolher a evidência.',
                evento = 'fivepd_sp:police:evidence:targetClerk',
                args = { point_id = tostring(id) },
                distancia = tonumber(custodyCfg().interactionDistance) or 2.2,
                podeInteragir = function()
                    local state = LocalPlayer and LocalPlayer.state or nil
                    return onDuty() and state and type(state['fivepd_sp:seizedDrugBag']) == 'table'
                        and not bopmOpen and not radialOpen and not placementActive
                end
            }
        }
    })
end

function deleteClerk(id)
    local ped = custodyClerks[id]
    if type(ped) == 'table' then ped = ped.ped end
    if ped and DoesEntityExist(ped) then
        local entry = custodyClerks[id]
        local targetId = type(entry) == 'table' and entry.targetId or nil
        if targetId then FSPTarget.RemoveEntity(ped, targetId) end
        DeletePed(ped)
    end
    custodyClerks[id] = nil
end

function ensureClerk(point)
    local id = tostring(point.id or '')
    if id == '' then return end
    local coords = custodyPointCoords(point)
    local heading = tonumber(point.heading) or 0.0
    local cfg = custodyCfg()
    local scenario = tostring(cfg.clerkScenario or '')
    local entry = custodyClerks[id]
    local ped = type(entry) == 'table' and entry.ped or entry

    local function applyClerkState(target)
        if not target or target == 0 or not DoesEntityExist(target) then return false end
        SetEntityAsMissionEntity(target, true, true)
        if not IsEntityVisible(target) then SetEntityVisible(target, true, false) end
        if GetEntityAlpha(target) < 250 then ResetEntityAlpha(target) end
        SetEntityInvincible(target, true)
        SetEntityCollision(target, true, true)
        SetPedCanRagdoll(target, false)
        SetBlockingOfNonTemporaryEvents(target, true)
        SetPedFleeAttributes(target, 0, false)
        SetPedCombatAttributes(target, 17, true)
        SetPedDropsWeaponsWhenDead(target, false)
        SetEntityHeading(target, heading)
        FreezeEntityPosition(target, true)
        return true
    end

    if ped and DoesEntityExist(ped) and not IsEntityDead(ped) then
        local pedCoords = GetEntityCoords(ped)
        local distance = #(pedCoords - coords)
        -- Se o ped for empurrado para outra altura/interior ou o streaming o
        -- deslocar, reposicionamos exatamente no ponto definido pelo admin.
        if distance > 1.25 or math.abs((pedCoords.z or 0.0) - coords.z) > 2.0 then
            FreezeEntityPosition(ped, false)
            -- O Z persistido representa o piso. SetEntityCoords aplica a
            -- compensação vertical do ped e mantém os pés sobre o chão.
            SetEntityCoords(ped, coords.x, coords.y, coords.z, false, false, false, false)
        end
        applyClerkState(ped)
        if scenario ~= '' and not IsPedUsingAnyScenario(ped) then
            ClearPedTasksImmediately(ped)
            TaskStartScenarioInPlace(ped, scenario, 0, true)
        end
        local targetId = type(entry) == 'table' and entry.targetId or nil
        if not targetId then targetId = registerClerkTarget(id, ped, point) end
        custodyClerks[id] = { ped = ped, scenario = scenario, createdAt = (entry and entry.createdAt) or GetGameTimer(), targetId = targetId }
        return
    elseif ped then
        deleteClerk(id)
    end

    RequestCollisionAtCoord(coords.x, coords.y, coords.z)
    local collisionUntil = GetGameTimer() + 1300
    while not HasCollisionLoadedAroundEntity(PlayerPedId()) and GetGameTimer() < collisionUntil do
        RequestCollisionAtCoord(coords.x, coords.y, coords.z)
        Wait(25)
    end

    local models = {}
    if cfg.clerkModel then models[#models + 1] = cfg.clerkModel end
    models[#models + 1] = 's_m_m_ciasec_01'
    models[#models + 1] = 's_m_m_highsec_01'
    models[#models + 1] = 's_m_m_security_01'
    local hash = nil
    local used = {}
    for _, model in ipairs(models) do
        local key = tostring(model or '')
        if key ~= '' and not used[key] then
            used[key] = true
            hash = requestModelWithTimeout(model, 1800)
            if hash then break end
        end
    end
    if not hash then return end

    ped = CreatePed(4, hash, coords.x, coords.y, coords.z, heading, false, false)
    SetModelAsNoLongerNeeded(hash)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return end

    -- A coordenada configurada representa o piso, não a origem física do modelo.
    -- SetEntityCoords usa o bounding box do ped para encostar os pés no chão.
    SetEntityCoords(ped, coords.x, coords.y, coords.z, false, false, false, false)
    applyClerkState(ped)
    SetPedRandomComponentVariation(ped, false)
    if type(SetPedRandomProps) == 'function' then SetPedRandomProps(ped) end
    if scenario ~= '' then
        ClearPedTasksImmediately(ped)
        TaskStartScenarioInPlace(ped, scenario, 0, true)
    end
    applyClerkState(ped)
    local targetId = registerClerkTarget(id, ped, point)
    custodyClerks[id] = { ped = ped, scenario = scenario, createdAt = GetGameTimer(), targetId = targetId }
end

function nearestCuffedNpc(point)
    local coords = custodyPointCoords(point)
    local maxDistance = tonumber(custodyCfg().suspectDistance) or 4.5
    local best, bestDistance = 0, maxDistance + 0.001
    for _, ped in ipairs(GetGamePool('CPed')) do
        if ped ~= PlayerPedId() and DoesEntityExist(ped) and not IsPedAPlayer(ped)
            and IsPedHuman(ped) and not IsEntityDead(ped) and not IsPedInAnyVehicle(ped, false) then
            local distance = #(GetEntityCoords(ped) - coords)
            local custodyState = Entity(ped).state
            local arrested = custodyState and custodyState['fivepd_sp:custody:arrested'] == true
            if distance < bestDistance and not arrested and bagValue(ped, 'cuffed') == true then
                best = ped
                bestDistance = distance
            end
        end
    end
    return best, bestDistance
end

function nearestCuffedPlayer(point)
    local coords = custodyPointCoords(point)
    local maxDistance = tonumber(custodyCfg().suspectDistance) or 4.5
    local bestPed, bestDistance, bestServerId = 0, maxDistance + 0.001, nil
    for _, playerIndex in ipairs(GetActivePlayers()) do
        if playerIndex ~= PlayerId() then
            local ped = GetPlayerPed(playerIndex)
            if isOtherPlayerPed(ped) and not IsPedInAnyVehicle(ped, false) and not playerPedIsJailed(ped) then
                local distance = #(GetEntityCoords(ped) - coords)
                if distance < bestDistance and bagValue(ped, 'cuffed') == true then
                    bestPed, bestDistance, bestServerId = ped, distance, GetPlayerServerId(playerIndex)
                end
            end
        end
    end
    return bestPed, bestDistance, bestServerId
end

RegisterNetEvent('fivepd_sp:police:evidence:targetClerk', function(ctx)
    if not onDuty() or bopmOpen then return end
    local pointId = ctx and ctx.args and tostring(ctx.args.point_id or '') or ''
    if pointId == '' then return end
    FSPTarget.Close()
    TriggerServerEvent('fivepd_sp:police:evidence:beginDrugBag', pointId)
end)

RegisterNetEvent('fivepd_sp:police:custody:targetClerk', function(ctx)
    if not onDuty() or bopmOpen then return end
    local pointId = ctx and ctx.args and tostring(ctx.args.point_id or '') or ''
    local point = nil
    for _, candidate in ipairs(custodyPoints) do
        if tostring(candidate.id or '') == pointId then point = candidate break end
    end
    if not point then return end

    local npc, npcDistance = nearestCuffedNpc(point)
    local playerSuspect, playerDistance, playerServerId = nearestCuffedPlayer(point)
    local suspectType, suspect = nil, 0
    if playerSuspect ~= 0 and (npc == 0 or playerDistance <= npcDistance) then
        suspectType, suspect = 'player', playerSuspect
    elseif npc ~= 0 then
        suspectType, suspect = 'npc', npc
    end

    if suspect == 0 then
        notify('aviso', 'Custódia', 'Traga uma pessoa algemada para perto do escrivão.')
        return
    end
    if bagValue(suspect, 'held') == true or bagValue(suspect, 'following') == true then
        notify('aviso', 'Custódia', 'Solte a pessoa próxima ao balcão antes de apresentá-la.')
        return
    end

    FSPTarget.Close()
    if suspectType == 'player' then
        TriggerServerEvent('fivepd_sp:police:custody:beginPlayer', playerServerId, pointId)
    elseif not NetworkGetEntityIsNetworked(suspect) then
        notify('aviso', 'Custódia', 'Esse suspeito não possui entidade de rede válida.')
    else
        local netId = NetworkGetNetworkIdFromEntity(suspect)
        local okMale, isMale = pcall(IsPedMale, suspect)
        local visualSex = okMale and (isMale and 'masculino' or 'feminino') or nil
        TriggerServerEvent('fivepd_sp:police:custody:begin', netId, pointId, visualSex)
    end
end)

function refreshCustodyPoints(force)
    if not onDuty() then return end
    local now = GetGameTimer()
    local interval = math.max(1500, tonumber(custodyCfg().refreshPointsMs) or 5000)
    if not force and now - custodyLastRefresh < interval then return end
    custodyLastRefresh = now
    TriggerServerEvent('fivepd_sp:police:custody:requestPoints')
end

RegisterNetEvent('fivepd_sp:police:custody:points', function(points)
    custodyPoints = type(points) == 'table' and points or {}
    local valid = {}
    for _, point in ipairs(custodyPoints) do valid[tostring(point.id or '')] = true end
    for id in pairs(custodyClerks) do
        if not valid[id] then deleteClerk(id) end
    end
end)

function custodyWeatherKey(hash)
    hash = tonumber(hash) or 0
    if hash == joaat('RAIN') or hash == joaat('THUNDER') then return 'chuva' end
    if hash == joaat('FOGGY') then return 'neblina' end
    if hash == joaat('CLOUDS') or hash == joaat('OVERCAST') or hash == joaat('SMOG') then return 'nublado' end
    if hash == joaat('CLEAR') or hash == joaat('CLEARING') or hash == joaat('EXTRASUNNY') then return 'sol' end
    return 'outros'
end

function custodyLightingKey(hour)
    hour = math.floor(tonumber(hour) or 12)
    if hour == 5 or hour == 18 then return 'entardecer_amanhecer' end
    if hour >= 6 and hour <= 17 then return 'luz_solar' end
    return 'noite_com_luz'
end

function enrichBopmAutomaticData(data)
    local netId = tonumber(data.netId) or 0
    local suspect = netId > 0 and NetworkGetEntityFromNetworkId(netId) or 0
    if (suspect == 0 or not DoesEntityExist(suspect)) and data.subjectType == 'player' then
        local playerIndex = GetPlayerFromServerId(tonumber(data.targetServerId) or -1)
        suspect = playerIndex ~= -1 and GetPlayerPed(playerIndex) or 0
    elseif data.subjectType == 'evidence' then
        suspect = PlayerPedId()
    end
    if suspect == 0 or not DoesEntityExist(suspect) then return data end

    local x = bagNumber(suspect, 'arrestX')
    local y = bagNumber(suspect, 'arrestY')
    local z = bagNumber(suspect, 'arrestZ')
    if not x or not y or not z or (math.abs(x) < 0.001 and math.abs(y) < 0.001) then
        local c = GetEntityCoords(suspect)
        x, y, z = c.x, c.y, c.z
    end

    local street, crossing = '', ''
    local okStreet, streetHash, crossingHash = pcall(GetStreetNameAtCoord, x + 0.0, y + 0.0, z + 0.0)
    if okStreet then
        if tonumber(streetHash) and tonumber(streetHash) ~= 0 then street = GetStreetNameFromHashKey(streetHash) or '' end
        if tonumber(crossingHash) and tonumber(crossingHash) ~= 0 then crossing = GetStreetNameFromHashKey(crossingHash) or '' end
    end

    local arrestHour = bagNumber(suspect, 'arrestHour') or GetClockHours()
    local weatherHash = bagNumber(suspect, 'arrestWeather')
    if not weatherHash or weatherHash == 0 then
        local okWeather, currentWeather = pcall(GetPrevWeatherTypeHashName)
        if okWeather then weatherHash = tonumber(currentWeather) or 0 end
    end
    local interior = (bagNumber(suspect, 'arrestInterior') or 0) ~= 0

    data.auto = type(data.auto) == 'table' and data.auto or {}
    data.auto.street = street
    data.auto.referencePoint = crossing ~= '' and ('Cruzamento com ' .. crossing) or ''
    data.auto.placeType = interior and 'Ambiente interno' or 'Via pública'
    data.auto.environment = interior and 'interno' or 'externo'
    data.auto.placeCharacteristics = interior and {} or { 'via_publica' }
    data.auto.lighting = { custodyLightingKey(arrestHour) }
    data.auto.weather = { custodyWeatherKey(weatherHash) }
    return data
end

RegisterNetEvent('fivepd_sp:police:custody:open', function(data)
    data = enrichBopmAutomaticData(type(data) == 'table' and data or {})
    bopmOpen = true
    bopmContext = data
    hideCustodyHelp()
    closeRadial()
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'bopmOpen', data = data })
end)

RegisterNetEvent('fivepd_sp:police:custody:documentGranted', function(data)
    if type(data) ~= 'table' or not tonumber(data.requestId) then return end
    data = enrichBopmAutomaticData(data)
    data.finalized = false
    data.draft = type(data.draft) == 'table' and data.draft or {}
    pcespCustodyDocument = data
    if bopmOpen then closeBopm(false) end
    FivePD_OpenPcespCustodyDocument()
end)

-- V19: animação de entregar/receber BOPM e TCOPM, executada após validação server-side.
RegisterNetEvent('fivepd_sp:police:documentExchangeAnim', function(role)
    CreateThread(function()
        local ped = PlayerPedId()
        if ped == 0 or IsPedInAnyVehicle(ped, false) then return end
        local dict = 'mp_common'
        RequestAnimDict(dict)
        local deadline = GetGameTimer() + 1800
        while not HasAnimDictLoaded(dict) and GetGameTimer() < deadline do Wait(0) end
        if not HasAnimDictLoaded(dict) then return end
        TaskPlayAnim(ped, dict, role == 'give' and 'givetake1_a' or 'givetake1_b', 5.0, -4.0, 1600, 48, 0.0, false, false, false)
        RemoveAnimDict(dict)
    end)
end)

RegisterNetEvent('fivepd_sp:police:custody:documentReturned', function(requestId, documentType, civilName)
    if pcespCustodyDocument and tonumber(pcespCustodyDocument.requestId) == tonumber(requestId) then
        if bopmOpen and bopmContext and bopmContext.mode == 'civil_document' then closeBopm(false) end
        pcespCustodyDocument = nil
        FivePD_StopBopmClipboard()
        notify('sucesso', tostring(documentType or 'Documento'):upper(), ('Documento devolvido a %s. O comando /%s não está mais disponível para esta apresentação.'):format(tostring(civilName or 'Polícia Civil'), tostring(documentType or 'bopm'):lower()))
    end
end)


RegisterNetEvent('fivepd_sp:police:custody:documentCancelled', function(requestId, reason)
    if pcespCustodyDocument and (tonumber(requestId) == 0 or tonumber(pcespCustodyDocument.requestId) == tonumber(requestId)) then
        if bopmOpen and bopmContext and bopmContext.mode == 'civil_document' then closeBopm(false) end
        pcespCustodyDocument = nil
        FivePD_StopBopmClipboard()
        if reason and tostring(reason) ~= '' then notify('info', 'Documento encerrado', tostring(reason)) end
    end
end)

function closeBopm(cancelServer, draft)
    if not bopmOpen then return end
    local ctx = bopmContext
    if ctx and ctx.mode == 'civil_document' then
        if pcespCustodyDocument and type(draft) == 'table' and pcespCustodyDocument.finalized ~= true then
            pcespCustodyDocument.draft = draft
            TriggerServerEvent('fivepd_sp:police:custody:saveCivilDocument', pcespCustodyDocument.requestId, draft)
        end
        bopmOpen = false
        bopmContext = nil
        SetNuiFocus(false, false)
        SendNUIMessage({ action = 'bopmClose' })
        FivePD_StopBopmClipboard()
        return
    end
    bopmOpen = false
    bopmContext = nil
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'bopmClose' })
    if cancelServer and ctx then
        if ctx.subjectType == 'player' and ctx.targetServerId then
            TriggerServerEvent('fivepd_sp:police:custody:cancelPlayer', ctx.targetServerId)
        elseif ctx.subjectType == 'evidence' then
            TriggerServerEvent('fivepd_sp:police:evidence:cancelDrugBag')
        elseif ctx.netId then
            TriggerServerEvent('fivepd_sp:police:custody:cancel', ctx.netId)
        end
    end
end

RegisterNUICallback('bopmClose', function(data, cb)
    local draft = type(data) == 'table' and type(data.draft) == 'table' and data.draft or nil
    closeBopm(true, draft)
    cb({ ok = true })
end)

RegisterNUICallback('bopmSubmit', function(data, cb)
    if not bopmOpen or not bopmContext then
        cb({ ok = false, error = 'Nenhuma apresentação ativa.' })
        return
    end
    if bopmContext.mode == 'civil_document' and pcespCustodyDocument then
        pcespCustodyDocument.draft = type(data) == 'table' and data or {}
        TriggerServerEvent('fivepd_sp:police:custody:finalizeCivilDocument', pcespCustodyDocument.requestId, pcespCustodyDocument.draft)
    elseif bopmContext.subjectType == 'player' and bopmContext.targetServerId then
        TriggerServerEvent('fivepd_sp:police:custody:submitPlayer', bopmContext.targetServerId, type(data) == 'table' and data or {})
    elseif bopmContext.subjectType == 'evidence' then
        TriggerServerEvent('fivepd_sp:police:evidence:submitDrugBag', type(data) == 'table' and data or {})
    elseif bopmContext.netId then
        TriggerServerEvent('fivepd_sp:police:custody:submit', bopmContext.netId, type(data) == 'table' and data or {})
    else
        cb({ ok = false, error = 'Apresentação inválida.' })
        return
    end
    cb({ ok = true })
end)

RegisterNetEvent('fivepd_sp:police:custody:submitResult', function(ok, message, resultInfo)
    if ok == true then
        SendNUIMessage({ action = 'bopmSubmitResult', ok = true, number = tostring(message or '') })
        local number = tostring(message or '')
        local documentOnly = type(resultInfo) == 'table' and resultInfo.documentOnly == true
        local wasEvidence = (type(resultInfo) == 'table' and resultInfo.subjectType == 'evidence') or (bopmContext and bopmContext.subjectType == 'evidence')
        local xp = type(resultInfo) == 'table' and math.max(0, math.floor(tonumber(resultInfo.xp) or 0)) or 0
        if documentOnly and pcespCustodyDocument then
            pcespCustodyDocument.finalized = true
            pcespCustodyDocument.draft = type(resultInfo.form) == 'table' and resultInfo.form or pcespCustodyDocument.draft
        end
        CreateThread(function()
            Wait(450)
            closeBopm(false)
            if documentOnly then
                local procedure = tostring(type(resultInfo) == 'table' and resultInfo.procedure or 'bopm'):upper()
                notify('sucesso', procedure, ('Documento %s concluído. Aproxime-se de %s e use o ALT para entregar o documento.'):format(procedure, tostring(type(resultInfo) == 'table' and resultInfo.civilName or 'o policial civil responsável')))
            elseif wasEvidence then
                notify('sucesso', 'Apreensão', ('BOPM %s concluído. Bolsa entregue ao escrivão%s.'):format(number, xp > 0 and (' • +' .. xp .. ' XP') or ''))
            else
                notify('sucesso', 'Custódia', ('BOPM %s concluído. Suspeito entregue e registrado como preso.'):format(number))
            end
        end)
    else
        SendNUIMessage({ action = 'bopmSubmitResult', ok = false, error = tostring(message or 'Não foi possível concluir o BOPM.') })
    end
end)

RegisterNetEvent('fivepd_sp:police:custody:removeSuspect', function(netId)
    netId = tonumber(netId)
    if not netId or netId <= 0 then return end
    local ped = NetworkGetEntityFromNetworkId(netId)
    if ped == 0 or not DoesEntityExist(ped) then return end
    CreateThread(function()
        for alpha = 255, 35, -44 do
            if not DoesEntityExist(ped) then return end
            SetEntityAlpha(ped, alpha, false)
            Wait(100)
        end
        if DoesEntityExist(ped) then SetEntityVisible(ped, false, false) end
    end)
end)

CreateThread(function()
    Wait(1200)
    while true do
        local waitMs = 900
        local cfg = custodyCfg()

        if cfg.enabled ~= false and onDuty() then
            refreshCustodyPoints(false)
            local playerPed = PlayerPedId()
            local playerCoords = GetEntityCoords(playerPed)
            local spawnDistance = tonumber(cfg.clerkSpawnDistance) or 85.0
            local interactionDistance = tonumber(cfg.interactionDistance) or 2.2
            local closestPoint, closestDistance = nil, math.huge

            for _, point in ipairs(custodyPoints) do
                local id = tostring(point.id or '')
                local coords = custodyPointCoords(point)
                local distance = #(playerCoords - coords)
                if distance <= spawnDistance then
                    waitMs = math.min(waitMs, 350)
                    ensureClerk(point)
                elseif custodyClerks[id] then
                    deleteClerk(id)
                end
                if distance <= interactionDistance and distance < closestDistance then
                    closestPoint, closestDistance = point, distance
                end
            end

            -- A apresentação ao escrivão é feita exclusivamente pelo ox_target.
            hideCustodyHelp()

            if bopmOpen then
                waitMs = 0
                if not onDuty() then closeBopm(true) end
            end
        else
            hideCustodyHelp()
            for id in pairs(custodyClerks) do deleteClerk(id) end
            if bopmOpen then closeBopm(true) end
        end
        Wait(waitMs)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    -- Liberar todas as ancoras LOCAIS evita NPC preso ou prop invisivel
    -- remanescente apos o restart do script policial.
    for ped, st in pairs(pedStates) do
        if st.escortAnchor and st.escortAnchor ~= 0 then
            if DoesEntityExist(ped) and IsEntityAttachedToEntity(ped, st.escortAnchor) then
                DetachEntity(ped, true, false)
            end
            FivePD_DeleteEscortAnchor(st.escortAnchor)
            st.escortAnchor = nil
        end
    end
    hideCustodyHelp()
    for id in pairs(custodyClerks) do deleteClerk(id) end
    if bopmOpen then
        local ctx = bopmContext
        SetNuiFocus(false, false)
        FivePD_StopBopmClipboard()
        if ctx and ctx.mode ~= 'civil_document' then
            if ctx.subjectType == 'player' and ctx.targetServerId then
                TriggerServerEvent('fivepd_sp:police:custody:cancelPlayer', ctx.targetServerId)
            elseif ctx.netId then
                TriggerServerEvent('fivepd_sp:police:custody:cancel', ctx.netId)
            end
        end
    end
end)
