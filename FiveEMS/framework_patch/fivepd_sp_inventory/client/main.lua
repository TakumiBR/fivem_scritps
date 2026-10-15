local requestSeq = 0
local pending = {}
local uiOpen = false
local currentContext = nil
local lastClothingSignature = nil
local npcFallbackTokens = {}
local vehicleFallbackTokens = {}
local vehicleInteractionRegistered = false
local vehicleSearchBusy = false
local inspectionCam = nil
local inspectionCamEntity = 0
local inspectionPreviewPed = 0
local inspectionPreviewSourcePed = 0

-- Preview de pessoa renderizado pelo frontend nativo do GTA.
--
-- A versão anterior mantinha um PED 3D fisicamente à frente da câmera. Mesmo sendo
-- local, ele ainda fazia parte da cena do mundo e podia ser tampado pelo jogador,
-- NPCs, veículos ou qualquer geometria entre a câmera e o clone. Aqui usamos o
-- pipeline de frontend/pause menu do próprio GTA: o clone continua sendo um PED
-- local e invisível no mundo, mas GIVE_PED_TO_PAUSE_MENU o desenha na camada de
-- frontend, acima da cena 3D e abaixo da NUI. Assim ele se comporta como um preview
-- de interface de verdade e ninguém no servidor consegue vê-lo no mundo.
local inspectionFrontendActive = false
local inspectionHud117 = nil
local previewStageRect = { x = 0.492, y = 0.515, w = 0.409, h = 0.632 }

local function clampNumber(value, minimum, maximum)
    value = tonumber(value) or minimum
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end


-- Carrega um dicionário de animação com timeout. Algumas rotinas de revista
-- (pessoa e veículo) usam este helper para não travar o client caso um dict
-- customizado não exista ou demore para streamar.
local function requestAnimDictSafe(dict, timeoutMs)
    dict = tostring(dict or '')
    if dict == '' then return false end
    if HasAnimDictLoaded(dict) then return true end

    RequestAnimDict(dict)
    local deadline = GetGameTimer() + math.max(250, tonumber(timeoutMs) or 1500)
    while not HasAnimDictLoaded(dict) and GetGameTimer() < deadline do
        Wait(0)
    end
    return HasAnimDictLoaded(dict)
end

local function isIllegalCharacter()
    if LocalPlayer and LocalPlayer.state then
        local value = LocalPlayer.state['fivepd_sp:personagemTipo']
        if value ~= nil then return tostring(value) == 'ilegal' end
    end
    if GetResourceState('fivepd_sp_core') == 'started' then
        local ok, result = pcall(function() return exports.fivepd_sp_core:TipoPersonagem() end)
        if ok then return tostring(result or '') == 'ilegal' end
    end
    return false
end

-- Mantém a animação da revista veicular ativa enquanto o painel estiver aberto.
-- O jogador continua animando normalmente para os demais clientes; a ocultação do
-- policial é feita apenas na renderização local mais abaixo, sem alterar alpha/rede.
local function vehicleInspectionAnimProfile(animation)
    animation = tostring(animation or 'rear')
    if animation == 'cabin' then
        return 'mini@repair', 'fixing_a_ped'
    end
    return 'amb@prop_human_bum_bin@base', 'base'
end

local function playVehicleInspectionPanelAnim(context, force)
    if type(context) ~= 'table' or context.mode ~= 'vehicle_search' then return false end
    local ped = PlayerPedId()
    if ped == 0 or not DoesEntityExist(ped) or IsEntityDead(ped) then return false end

    local dict, clip = vehicleInspectionAnimProfile(context.vehicle_animation)
    context.vehicle_anim_dict = dict
    context.vehicle_anim_clip = clip

    if not force and IsEntityPlayingAnim(ped, dict, clip, 3) then
        return true
    end

    if not requestAnimDictSafe(dict, 1200) then return false end
    if not uiOpen or currentContext ~= context then return false end

    TaskPlayAnim(ped, dict, clip, 4.0, -4.0, -1, 1, 0.0, false, false, false)
    return true
end

local function stopVehicleInspectionPanelAnim(context)
    if type(context) ~= 'table' or context.mode ~= 'vehicle_search' then return end
    local ped = PlayerPedId()
    if ped == 0 or not DoesEntityExist(ped) then return end
    local dict = tostring(context.vehicle_anim_dict or '')
    local clip = tostring(context.vehicle_anim_clip or '')
    if dict ~= '' and clip ~= '' and IsEntityPlayingAnim(ped, dict, clip, 3) then
        StopAnimTask(ped, dict, clip, 2.0)
    end
end

local function savePreviewHudColour()
    if inspectionHud117 then return end
    if type(GetHudColour) == 'function' then
        local ok, r, g, b, a = pcall(GetHudColour, 117)
        if ok and r ~= nil then
            inspectionHud117 = {
                r = tonumber(r) or 0,
                g = tonumber(g) or 0,
                b = tonumber(b) or 0,
                a = tonumber(a) or 186
            }
            return
        end
    end
    inspectionHud117 = { r = 0, g = 0, b = 0, a = 186 }
end

local function restorePreviewHudColour()
    if not inspectionHud117 then return end
    ReplaceHudColourWithRgba(
        117,
        inspectionHud117.r,
        inspectionHud117.g,
        inspectionHud117.b,
        inspectionHud117.a
    )
    inspectionHud117 = nil
end

local function setFrontendMouseVisible(state)
    if type(SetMouseCursorVisibleInMenus) == 'function' then
        pcall(SetMouseCursorVisibleInMenus, state == true)
    elseif type(SetMouseCursorVisible) == 'function' then
        pcall(SetMouseCursorVisible, state == true)
    elseif type(N_0x98215325a695e78a) == 'function' then
        pcall(N_0x98215325a695e78a, state == true)
    end
end

local function deactivateInspectionFrontend()
    if inspectionFrontendActive then
        pcall(SetPauseMenuPedLighting, false)
        pcall(SetPauseMenuPedSleepState, false)
        SetFrontendActive(false)
        inspectionFrontendActive = false
    end
    restorePreviewHudColour()
end

local function destroyInspectionPreviewPed()
    deactivateInspectionFrontend()
    if inspectionPreviewPed ~= 0 and DoesEntityExist(inspectionPreviewPed) then
        SetEntityAsMissionEntity(inspectionPreviewPed, true, true)
        DeleteEntity(inspectionPreviewPed)
    end
    inspectionPreviewPed = 0
    inspectionPreviewSourcePed = 0
end

local function destroyInspectionCamera()
    if inspectionCam and DoesCamExist(inspectionCam) then
        RenderScriptCams(false, true, 180, true, true)
        DestroyCam(inspectionCam, false)
    end
    inspectionCam = nil
    inspectionCamEntity = 0
    destroyInspectionPreviewPed()
end

local function createInspectionPreviewPed(sourcePed)
    if not sourcePed or sourcePed == 0 or not DoesEntityExist(sourcePed) or not IsEntityAPed(sourcePed) then
        return 0
    end

    -- O frontend do GTA foi feito para receber um clone real do PED. Mantemos
    -- o clone não-networked e, para NPCs, reaplicamos componentes/props através
    -- de CLONE_PED_TO_TARGET. Isso é bem mais seguro que reconstruir component 0..11
    -- manualmente (alguns modelos ambientais possuem drawables vazios e quebravam).
    local heading = GetEntityHeading(sourcePed)
    local previewPed = ClonePed(sourcePed, heading, false, false)
    if not previewPed or previewPed == 0 or not DoesEntityExist(previewPed) then
        return 0
    end

    if type(ClonePedToTarget) == 'function' then
        pcall(ClonePedToTarget, sourcePed, previewPed)
    end

    SetEntityAsMissionEntity(previewPed, true, true)
    ClearPedTasksImmediately(previewPed)
    ClearPedSecondaryTask(previewPed)
    SetBlockingOfNonTemporaryEvents(previewPed, true)
    SetPedCanRagdoll(previewPed, false)
    SetEntityInvincible(previewPed, true)
    SetEntityCollision(previewPed, false, false)
    FreezeEntityPosition(previewPed, true)
    RemoveAllPedWeapons(previewPed, true)
    SetCurrentPedWeapon(previewPed, joaat('WEAPON_UNARMED'), true)

    -- A entidade física do clone não precisa aparecer no mundo. O próprio
    -- GivePedToPauseMenu continua desenhando o modelo no frontend mesmo com o
    -- clone invisível. Mantê-lo só ~10m abaixo preserva o streaming do modelo e
    -- das roupas, evitando o LOD/streaming estranho que alguns NPCs apresentavam
    -- quando eram mandados para -250m.
    local sourceCoords = GetEntityCoords(sourcePed)
    SetEntityCoordsNoOffset(previewPed, sourceCoords.x, sourceCoords.y, sourceCoords.z - 10.0, false, false, false)
    SetEntityVisible(previewPed, false, false)

    inspectionPreviewPed = previewPed
    inspectionPreviewSourcePed = sourcePed

    savePreviewHudColour()
    ReplaceHudColourWithRgba(117, 0, 0, 0, 0)

    SetFrontendActive(true)
    inspectionFrontendActive = true
    ActivateFrontendMenu(GetHashKey('FE_MENU_VERSION_EMPTY_NO_BACKGROUND'), false, -1)
    setFrontendMouseVisible(false)

    -- Dá tempo para o drawable/props do clone terminarem de streamar antes de
    -- entregar o PED ao frontend. É o mesmo padrão usado nos previews de pause menu.
    Wait(200)
    if not uiOpen or inspectionPreviewPed ~= previewPed or not DoesEntityExist(previewPed) then
        deactivateInspectionFrontend()
        if DoesEntityExist(previewPed) then
            SetEntityAsMissionEntity(previewPed, true, true)
            DeleteEntity(previewPed)
        end
        if inspectionPreviewPed == previewPed then inspectionPreviewPed = 0 end
        return 0
    end

    GivePedToPauseMenu(previewPed, 1)
    SetPauseMenuPedLighting(true)
    SetPauseMenuPedSleepState(true)
    setFrontendMouseVisible(false)

    if type(RequestScaleformMovie) == 'function' then
        pcall(RequestScaleformMovie, 'PAUSE_MP_MENU_PLAYER_MODEL')
    end

    return previewPed
end

local function activateInspectionCameraForPed(sourcePed)
    -- O nome foi mantido para compatibilidade com o restante do resource. Para
    -- pessoas não existe câmera scriptada: o PED é renderizado pelo frontend nativo.
    destroyInspectionCamera()
    if not sourcePed or sourcePed == 0 or not DoesEntityExist(sourcePed) then return 0 end

    local previewPed = createInspectionPreviewPed(sourcePed)
    if previewPed == 0 then return 0 end

    inspectionCamEntity = previewPed
    return previewPed
end

local function activateInspectionCameraForVehicle(vehicle, compartment, vehicleType)
    destroyInspectionCamera()
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end
    local minDim, maxDim = GetModelDimensions(GetEntityModel(vehicle))
    local halfWidth = math.max(math.abs(minDim.x or -0.9), math.abs(maxDim.x or 0.9))
    local comp = tostring(compartment or '')
    local pos, look
    if comp == 'trunk' or comp == 'cargo' then
        pos = GetOffsetFromEntityInWorldCoords(vehicle, 0.0, (minDim.y or -2.0) - 3.25, 1.15)
        look = GetOffsetFromEntityInWorldCoords(vehicle, 0.0, (minDim.y or -2.0) + 0.55, 0.72)
    elseif comp == 'engine' then
        pos = GetOffsetFromEntityInWorldCoords(vehicle, 0.0, (maxDim.y or 2.0) + 3.0, 1.15)
        look = GetOffsetFromEntityInWorldCoords(vehicle, 0.0, (maxDim.y or 2.0) - 0.45, 0.65)
    elseif comp == 'seat' or tostring(vehicleType or '') == 'motorcycle' then
        pos = GetOffsetFromEntityInWorldCoords(vehicle, halfWidth + 2.25, -0.45, 1.15)
        look = GetOffsetFromEntityInWorldCoords(vehicle, 0.0, -0.25, 0.72)
    elseif comp == 'cabin' then
        pos = GetOffsetFromEntityInWorldCoords(vehicle, halfWidth + 2.8, (maxDim.y or 2.0) * 0.30, 1.45)
        look = GetOffsetFromEntityInWorldCoords(vehicle, 0.0, (maxDim.y or 2.0) * 0.25, 1.05)
    else
        pos = GetOffsetFromEntityInWorldCoords(vehicle, halfWidth + 2.4, 0.0, 1.18)
        look = GetOffsetFromEntityInWorldCoords(vehicle, 0.0, 0.0, 0.78)
    end
    local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(cam, pos.x, pos.y, pos.z)
    PointCamAtCoord(cam, look.x, look.y, look.z)
    SetCamFov(cam, tostring(vehicleType or '') == 'truck' and 43.0 or 40.0)
    SetCamActive(cam, true)
    RenderScriptCams(true, true, 260, true, true)
    inspectionCam, inspectionCamEntity = cam, vehicle
end

local function midVec(a, b)
    return vector3((a.x+b.x)*0.5, (a.y+b.y)*0.5, (a.z+b.z)*0.5)
end

local function personRegionWorldPoints(ped)
    local lHand = GetPedBoneCoords(ped, 18905, 0.0, 0.0, 0.0)
    local rHand = GetPedBoneCoords(ped, 57005, 0.0, 0.0, 0.0)
    local lFoot = GetPedBoneCoords(ped, 14201, 0.0, 0.0, 0.0)
    local rFoot = GetPedBoneCoords(ped, 52301, 0.0, 0.0, 0.0)
    local handMid = midVec(lHand, rHand)

    -- Os pontos abaixo usam o esqueleto do PED como referência. Isso evita que as
    -- linhas "subam" para o tronco quando a câmera muda de distância ou o modelo
    -- possui proporções diferentes.
    return {
        hands = handMid,
        front_pockets = GetPedBoneCoords(ped, 11816, -0.12, 0.12, -0.16),
        waist = GetPedBoneCoords(ped, 11816, 0.24, 0.05, 0.09),
        back_pockets = GetPedBoneCoords(ped, 11816, 0.14, -0.13, -0.17),
        jacket = GetPedBoneCoords(ped, 24816, 0.20, 0.05, 0.10),
        bag = GetPedBoneCoords(ped, 24816, 0.27, -0.18, 0.05),
        ankles = rFoot + vector3(0.0, 0.0, 0.11),
        socks = lFoot + vector3(0.0, 0.0, 0.07)
    }
end

local function personScreenAnchors(ped)
    local result = {}
    if not ped or ped == 0 or not DoesEntityExist(ped) then return result end
    for id, world in pairs(personRegionWorldPoints(ped)) do
        local visible, x, y = GetScreenCoordFromWorldCoord(world.x, world.y, world.z)
        if visible then result[id] = { x = x, y = y, visible = true } end
    end
    return result
end

local function clothingSnapshot(ped)
    ped = ped or PlayerPedId()
    if ped == 0 or not DoesEntityExist(ped) then
        return { model = 0, bag = 0, vest = 0, legs = 0, top = 0, undershirt = 0 }
    end

    local clothing = Config.Clothing or {}
    local bagComponent = tonumber(clothing.bagComponent) or 5
    local vestComponent = tonumber(clothing.vestComponent) or 9
    local legsComponent = tonumber(clothing.legsComponent) or 4
    local topComponent = tonumber(clothing.topComponent) or 11
    local undershirtComponent = tonumber(clothing.undershirtComponent) or 8

    return {
        model = GetEntityModel(ped),
        bag = GetPedDrawableVariation(ped, bagComponent),
        bag_texture = GetPedTextureVariation(ped, bagComponent),
        vest = GetPedDrawableVariation(ped, vestComponent),
        vest_texture = GetPedTextureVariation(ped, vestComponent),
        legs = GetPedDrawableVariation(ped, legsComponent),
        legs_texture = GetPedTextureVariation(ped, legsComponent),
        top = GetPedDrawableVariation(ped, topComponent),
        top_texture = GetPedTextureVariation(ped, topComponent),
        undershirt = GetPedDrawableVariation(ped, undershirtComponent),
        undershirt_texture = GetPedTextureVariation(ped, undershirtComponent)
    }
end

local function syncClothing(force)
    local snapshot = clothingSnapshot(PlayerPedId())
    local signature = table.concat({
        snapshot.model or 0, snapshot.bag or 0, snapshot.bag_texture or 0,
        snapshot.vest or 0, snapshot.vest_texture or 0,
        snapshot.legs or 0, snapshot.legs_texture or 0,
        snapshot.top or 0, snapshot.top_texture or 0,
        snapshot.undershirt or 0, snapshot.undershirt_texture or 0
    }, ':')
    if not force and signature == lastClothingSignature then return snapshot end
    lastClothingSignature = signature
    TriggerServerEvent('fivepd_sp:inventory:clothing', snapshot)
    return snapshot
end

local function rpc(action, payload, timeout)
    requestSeq = requestSeq + 1
    local id = ('%s:%s'):format(GetGameTimer(), requestSeq)
    local p = promise.new()
    pending[id] = p
    TriggerServerEvent('fivepd_sp:inventory:rpc', id, action, payload or {})

    CreateThread(function()
        Wait(timeout or 6000)
        local resolver = pending[id]
        if resolver then
            pending[id] = nil
            resolver:resolve({ ok = false, error = 'O servidor demorou para responder.' })
        end
    end)

    return Citizen.Await(p)
end

RegisterNetEvent('fivepd_sp:inventory:rpc:response', function(id, response)
    local p = pending[tostring(id or '')]
    if not p then return end
    pending[tostring(id)] = nil
    p:resolve(type(response) == 'table' and response or { ok = false, error = 'Resposta inválida.' })
end)

local function closeUi()
    if not uiOpen then return end
    local closingContext = currentContext
    uiOpen = false
    currentContext = nil
    stopVehicleInspectionPanelAnim(closingContext)
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'close' })
    destroyInspectionCamera()
    TriggerEvent('fivepd_sp:inventory:uiState', false, closingContext)
end

local function openUi(view, context)
    if type(view) ~= 'table' then return false end

    -- Guarde uma referência estável. A criação do preview de PED pode fazer Wait()
    -- enquanto o frontend nativo inicializa; nesse intervalo a UI pode ser fechada e
    -- currentContext virar nil. Nunca devemos voltar do carregamento e acessar
    -- currentContext diretamente sem confirmar que ainda é o mesmo contexto.
    local openedContext = context or { mode = view.mode }
    uiOpen = true
    currentContext = openedContext

    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    SetCursorLocation(0.5, 0.5)

    if openedContext.mode == 'admin' then
        destroyInspectionCamera()
        SendNUIMessage({ action = 'openAdmin', data = view })
    else
        SendNUIMessage({ action = 'open', data = view })

        if openedContext.mode == 'search' or openedContext.mode == 'self' then
            local sourcePed = tonumber(openedContext.ped) or PlayerPedId()
            local previewPed = activateInspectionCameraForPed(sourcePed)

            -- activateInspectionCameraForPed pode ter cedido execução durante o
            -- streaming. Só associe o clone se esta mesma UI continuar aberta.
            if not uiOpen or currentContext ~= openedContext then
                if previewPed ~= 0 and inspectionCamEntity == previewPed then
                    destroyInspectionCamera()
                end
                return false
            end

            openedContext.preview_ped = previewPed

            -- ACTIVATE_FRONTEND_MENU pode tentar assumir o foco do frontend.
            -- Reafirmamos o foco da NUI para o mouse continuar pertencendo ao inventário.
            SetNuiFocus(true, true)
            SetNuiFocusKeepInput(false)
            SetCursorLocation(0.5, 0.5)
            setFrontendMouseVisible(false)
        elseif (openedContext.mode == 'vehicle_search' or openedContext.mode == 'vehicle_storage') and openedContext.focus_compartment then
            activateInspectionCameraForVehicle(
                tonumber(openedContext.vehicle) or 0,
                openedContext.focus_compartment,
                view.vehicle_type
            )
            if openedContext.mode == 'vehicle_search' then
                -- Retoma imediatamente a animação usada na busca física. Ela será
                -- mantida pelo loop enquanto este painel continuar aberto.
                playVehicleInspectionPanelAnim(openedContext, true)
            end
        end
    end

    if not uiOpen or currentContext ~= openedContext then return false end
    TriggerEvent('fivepd_sp:inventory:uiState', true, openedContext)
    return true
end

local function openSelfInventory()
    local clothing = syncClothing(true)
    local result = rpc('self', { clothing = clothing })
    if not result or result.ok ~= true then
        notify('erro', 'Inventário', result and result.error or 'Não foi possível abrir o inventário.')
        return false
    end
    return openUi(result.view, { mode = 'self', ped = PlayerPedId() })
end

local function npcToken(ped)
    -- Nunca transforme um NPC local em entidade de rede apenas para revistá-lo.
    -- Isso pode mudar ownership/migração do ped e fazer alguns NPCs de ocorrência
    -- desaparecerem no cliente. Se ele já for networked, apenas lemos o net id.
    local netId = 0
    if NetworkGetEntityIsNetworked(ped) then
        netId = NetworkGetNetworkIdFromEntity(ped) or 0
    end

    if GetResourceState('fivepd_sp_records') == 'started' then
        local ok, registro = pcall(function()
            return exports.fivepd_sp_records:ObterOuCriarNPC(ped, { persistir = true })
        end)
        if ok and type(registro) == 'table' and registro.encontrado ~= false then
            local ref = registro.record_id or registro.npc_key or registro.rg
            if ref then
                return ('npc:record:%s'):format(tostring(ref)), netId, registro
            end
        end
    end

    if netId > 0 then return ('net:%d'):format(netId), netId, nil end

    local token = npcFallbackTokens[ped]
    if not token then
        token = ('local:%d:%d:%d'):format(GetPlayerServerId(PlayerId()), ped, GetGameTimer())
        npcFallbackTokens[ped] = token
    end
    return token, 0, nil
end

local function vehicleToken(vehicle)
    local netId = 0
    if NetworkGetEntityIsNetworked(vehicle) then
        netId = NetworkGetNetworkIdFromEntity(vehicle) or 0
    else
        NetworkRegisterEntityAsNetworked(vehicle)
        local untilAt = GetGameTimer() + 900
        while GetGameTimer() < untilAt and not NetworkGetEntityIsNetworked(vehicle) do Wait(0) end
        if NetworkGetEntityIsNetworked(vehicle) then
            netId = NetworkGetNetworkIdFromEntity(vehicle) or 0
        end
    end

    if GetResourceState('fivepd_sp_records') == 'started' then
        pcall(function()
            exports.fivepd_sp_records:ObterOuCriarVeiculo(vehicle, { persistir = true })
        end)
    end

    local plate = (GetVehicleNumberPlateText(vehicle) or ''):upper():gsub('[^A-Z0-9]', ''):sub(1, 8)
    if plate ~= '' then
        return ('vehicle:plate:%s'):format(plate), netId
    end

    if netId > 0 then return ('vehicle:net:%d'):format(netId), netId end

    local token = vehicleFallbackTokens[vehicle]
    if not token then
        token = ('vehicle:local:%d:%d:%d'):format(
            GetPlayerServerId(PlayerId()),
            vehicle,
            GetGameTimer()
        )
        vehicleFallbackTokens[vehicle] = token
    end
    return token, 0
end

local function playerServerIdFromPed(ped)
    if not IsPedAPlayer(ped) then return 0 end

    -- Alguns artifacts não expõem NetworkGetPlayerIndexFromPed. Nesse caso,
    -- resolvemos o player pelo ped ativo sem quebrar a revista.
    if type(NetworkGetPlayerIndexFromPed) == 'function' then
        local ok, playerIndex = pcall(NetworkGetPlayerIndexFromPed, ped)
        if ok and playerIndex ~= nil and playerIndex >= 0 then
            return GetPlayerServerId(playerIndex) or 0
        end
    end

    for _, playerIndex in ipairs(GetActivePlayers()) do
        if GetPlayerPed(playerIndex) == ped then
            return GetPlayerServerId(playerIndex) or 0
        end
    end
    return 0
end

local WEAPON_COMPARTMENTS = {
    { id = 'hand', label = 'Em mãos', group = 'Armamento', slots = 1, active = true },
    { id = 'waist_right', label = 'Cintura direita', group = 'Cintura', slots = 1, active = true },
    { id = 'waist_left', label = 'Cintura esquerda', group = 'Cintura', slots = 1, active = true },
    { id = 'waist_back', label = 'Parte traseira', group = 'Cintura', slots = 1, active = true }
}

local function weaponCategoryText(category)
    if category == 'handgun' then return 'Arma curta' end
    if category == 'blade' then return 'Arma branca' end
    if category == 'long' then return 'Arma longa' end
    return 'Armamento'
end

local function weaponIsInHand(ped, weaponHash, selectedHash)
    if selectedHash ~= weaponHash then return false end

    -- GET_SELECTED_PED_WEAPON informa a arma selecionada, mas alguns scripts de
    -- coldre mantêm a seleção mesmo quando o prop já foi escondido. Quando o
    -- native de entidade da arma estiver disponível, usamos a visibilidade real
    -- para distinguir "em mãos" de "guardada". Em builds que não o expõem,
    -- a seleção continua sendo o fallback compatível.
    if type(GetCurrentPedWeaponEntityIndex) == 'function' then
        local ok, entity = pcall(GetCurrentPedWeaponEntityIndex, ped, 0)
        if ok then
            entity = tonumber(entity) or 0
            if entity == 0 or not DoesEntityExist(entity) then return false end
            if type(IsEntityVisible) == 'function' then
                local visibleOk, visible = pcall(IsEntityVisible, entity)
                if visibleOk then return visible == true end
            end
            return true
        end
    end
    return true
end

local function scanPedWeapons(ped, catalog, suppressed)
    local items = {}
    local assigned = { hand = 0, waist_right = 0, waist_left = 0, waist_back = 0, carried_weapon = 0 }
    local occupiedWaist = {}
    local selected = GetSelectedPedWeapon(ped)
    local now = GetGameTimer()

    for _, definition in ipairs(catalog or {}) do
        local weaponName = tostring(definition.name or definition.key or ''):upper()
        if weaponName ~= '' then
            local hiddenUntil = suppressed and tonumber(suppressed[weaponName]) or 0
            if hiddenUntil <= now then
                local weaponHash = joaat(weaponName)
                if weaponHash and weaponHash ~= 0 and HasPedGotWeapon(ped, weaponHash, false) then
                    local category = tostring(definition.category or 'other')
                    local compartment = nil
                    if weaponIsInHand(ped, weaponHash, selected) then
                        compartment = 'hand'
                    elseif category == 'handgun' or category == 'blade' then
                        local preferences = type(definition.waist_slots) == 'table' and definition.waist_slots or {}
                        if #preferences == 0 then
                            preferences = category == 'blade'
                                and { 'waist_left', 'waist_back', 'waist_right' }
                                or { 'waist_right', 'waist_left', 'waist_back' }
                        end
                        for _, slotName in ipairs(preferences) do
                            if not occupiedWaist[slotName] then
                                compartment = slotName
                                occupiedWaist[slotName] = true
                                break
                            end
                        end
                    end
                    if not compartment then compartment = 'carried_weapon' end

                    assigned[compartment] = (assigned[compartment] or 0) + 1
                    local inHand = compartment == 'hand'
                    local atWaist = compartment:sub(1, 6) == 'waist_'
                    local detail = inHand and 'ARMA EMPUNHADA'
                        or atWaist and 'Guardada junto à cintura'
                        or 'Armamento portado fora dos bolsos'
                    items[#items + 1] = {
                        id = ('weapon:%s'):format(weaponName),
                        kind = 'weapon',
                        weapon_name = weaponName,
                        label = tostring(definition.label or weaponName),
                        description = weaponCategoryText(category),
                        detail = detail,
                        size = 'weapon',
                        icon = tostring(definition.icon or 'ARM'),
                        image = tostring(definition.image or ''),
                        illegal = definition.illegal == true,
                        compartment = compartment,
                        slot = assigned[compartment],
                        category = category,
                        in_hand = inHand
                    }
                end
            end
        end
    end

    return items, assigned, selected
end

local function viewWithWeapons(baseView, ped, catalog, suppressed)
    if type(baseView) ~= 'table' then return baseView, '' end
    local weaponItems, counts, selected = scanPedWeapons(ped, catalog, suppressed)
    local view = {
        mode = baseView.mode,
        title = baseView.title,
        subject = baseView.subject,
        subtitle = baseView.subtitle,
        compartments = {},
        items = {}
    }

    for _, comp in ipairs(WEAPON_COMPARTMENTS) do
        view.compartments[#view.compartments + 1] = {
            id = comp.id,
            label = comp.label,
            group = comp.group,
            slots = comp.slots,
            active = true,
            used = math.min(comp.slots, counts[comp.id] or 0)
        }
    end
    for _, comp in ipairs(baseView.compartments or {}) do view.compartments[#view.compartments + 1] = comp end

    local carriedCount = counts.carried_weapon or 0
    view.compartments[#view.compartments + 1] = {
        id = 'carried_weapon',
        label = 'Armamento portado',
        group = 'Armamento portado',
        slots = math.max(1, carriedCount),
        active = true,
        used = carriedCount
    }

    for _, item in ipairs(baseView.items or {}) do view.items[#view.items + 1] = item end
    for _, item in ipairs(weaponItems) do view.items[#view.items + 1] = item end

    local sigParts = { tostring(selected or 0) }
    for _, item in ipairs(weaponItems) do
        sigParts[#sigParts + 1] = ('%s@%s'):format(item.weapon_name, item.compartment)
    end
    table.sort(sigParts)
    return view, table.concat(sigParts, '|')
end

local function updateSearchView(baseView, force)
    local context = currentContext
    if not context or context.mode ~= 'search' then return end
    if type(baseView) == 'table' then context.base_view = baseView end
    if force and type(context.base_view) == 'table' then
        SendNUIMessage({ action = 'update', data = context.base_view })
    end
end

local function openPersonSearch(ped)
    if not LocalPlayer or not LocalPlayer.state or LocalPlayer.state['fivepd_sp:pmEmServico'] ~= true then
        notify('aviso', 'Revista pessoal', 'Entre em serviço para realizar uma revista.')
        return false
    end
    if not ped or ped == 0 or not DoesEntityExist(ped) or not IsEntityAPed(ped) or not IsPedHuman(ped) then return false end
    if ped == PlayerPedId() then return false end

    local targetClothing = clothingSnapshot(ped)
    local targetServerId = playerServerIdFromPed(ped)
    local token, netId, npcRecord = '', 0, nil
    if targetServerId <= 0 then token, netId, npcRecord = npcToken(ped) end

    local result = rpc('search_person', {
        token = token,
        net_id = netId,
        target_server_id = targetServerId,
        model = GetEntityModel(ped),
        clothing = targetClothing,
        record_id = npcRecord and npcRecord.record_id or nil,
        npc_key = npcRecord and npcRecord.npc_key or nil,
        subject_name = npcRecord and npcRecord.nome_completo or nil,
        rg = npcRecord and npcRecord.rg or nil
    }, 7000)

    if not result or result.ok ~= true then
        notify('erro', 'Revista pessoal', result and result.error or 'Não foi possível consultar os objetos da pessoa.')
        return false
    end

    local context = {
        mode = 'search',
        token = tostring(result.token or token),
        net_id = netId,
        target_server_id = targetServerId,
        ped = ped,
        base_view = result.view,
        searched_regions = {}
    }
    return openUi(result.view, context)
end


local function beginVehicleSearchSession(vehicle)
    if not LocalPlayer or not LocalPlayer.state or LocalPlayer.state['fivepd_sp:pmEmServico'] ~= true then
        notify('aviso', 'Revista veicular', 'Entre em serviço para revistar veículos.')
        return nil
    end
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) or not IsEntityAVehicle(vehicle) then return nil end
    if GetVehicleClass(vehicle) == 13 then
        notify('aviso', 'Revista veicular', 'Esta bicicleta não possui compartimentos configurados para revista.')
        return nil
    end

    local token, netId = vehicleToken(vehicle)
    local result = rpc('search_vehicle', {
        token = token,
        net_id = netId,
        model = GetEntityModel(vehicle),
        class_id = GetVehicleClass(vehicle),
        plate = GetVehicleNumberPlateText(vehicle) or ''
    }, 7000)

    if not result or result.ok ~= true then
        notify('aviso', 'Revista veicular', result and result.error or 'Não foi possível iniciar a revista do veículo.')
        return nil
    end

    return result, token, netId
end

local function openVehicleSearch(vehicle)
    local result, token, netId = beginVehicleSearchSession(vehicle)
    if not result then return false end
    return openUi(result.view, {
        mode = 'vehicle_search',
        token = tostring(result.token or token),
        net_id = netId,
        vehicle = vehicle,
        last_view = result.view
    })
end

local VEHICLE_ANCHORS = {
    front_right = vector3(1.05, 0.55, 0.0),
    front_left = vector3(-1.05, 0.45, 0.0),
    rear_right = vector3(1.05, -0.55, 0.0),
    rear_left = vector3(-1.05, -0.55, 0.0),
    rear = vector3(0.0, -1.65, 0.0)
}

local VEHICLE_COMPARTMENT_ORDER = { 'interior', 'glovebox', 'engine', 'trunk', 'seat', 'cabin', 'cargo' }
local VEHICLE_TRUCK_CLASSES = { [10]=true, [11]=true, [12]=true, [17]=true, [19]=true, [20]=true }

local function vehicleUiTypeFromClass(classId)
    classId = tonumber(classId) or 0
    if classId == 8 then return 'motorcycle' end
    if VEHICLE_TRUCK_CLASSES[classId] then return 'truck' end
    return 'car'
end

local function vehicleLogicalDefinitions(vehicle)
    local uiType = vehicleUiTypeFromClass(GetVehicleClass(vehicle))
    if uiType == 'motorcycle' then
        return { seat={ id='seat', label='Assento', animation='bike', anchor='rear', door=-1, require_open=false } }, uiType
    end
    if uiType == 'truck' then
        return {
            cabin={ id='cabin', label='Cabine', animation='cabin', anchor='front_left', door=0, door_label='porta da cabine', require_open=true },
            cargo={ id='cargo', label='Baú / Carga', animation='rear', anchor='rear', door=5, door_label='porta traseira / carga', require_open=false }
        }, uiType
    end
    return {
        interior={ id='interior', label='Interior', animation='cabin', anchor='front_left', door=0, door_label='porta do motorista', require_open=true },
        glovebox={ id='glovebox', label='Porta-luvas', animation='cabin', anchor='front_right', door=1, door_label='porta do passageiro', require_open=true },
        engine={ id='engine', label='Compartimento do motor', animation='engine', anchor='front', door=4, door_label='capô', require_open=true },
        trunk={ id='trunk', label='Porta-malas', animation='rear', anchor='rear', door=5, door_label='porta-malas', require_open=true }
    }, uiType
end

local function vehicleCompartmentConfigFor(vehicle, id)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return nil end
    local defs = vehicleLogicalDefinitions(vehicle)
    return defs[tostring(id or '')]
end

local function vehicleClassHasCompartment(vehicle, id)
    return vehicleCompartmentConfigFor(vehicle, id) ~= nil
end

local function vehicleSearchAnchor(vehicle, name, door)
    name = tostring(name or 'rear')
    door = tonumber(door) or -1

    -- Para portas laterais, quando o native estiver disponível, usamos a posição
    -- real de entrada do modelo. Isso evita offsets ruins em SUVs/vans maiores.
    if door >= 0 and door <= 3 and type(GetEntryPositionOfDoor) == 'function' then
        local ok, entry = pcall(GetEntryPositionOfDoor, vehicle, door)
        if ok and entry and entry.x and entry.y and entry.z then
            local okGround, groundZ = GetGroundZFor_3dCoord(entry.x, entry.y, entry.z + 1.5, false)
            return vector3(entry.x, entry.y, okGround and groundZ or entry.z)
        end
    end

    local minDim, maxDim = GetModelDimensions(GetEntityModel(vehicle))
    local halfWidth = math.max(math.abs(minDim.x or -0.8), math.abs(maxDim.x or 0.8))
    local x, y = 0.0, 0.0

    if name == 'front_right' then
        x = halfWidth + 0.42
        y = (maxDim.y or 1.6) * 0.32
    elseif name == 'front_left' then
        x = -(halfWidth + 0.42)
        y = (maxDim.y or 1.6) * 0.32
    elseif name == 'rear_right' then
        x = halfWidth + 0.42
        y = (minDim.y or -1.6) * 0.28
    elseif name == 'rear_left' then
        x = -(halfWidth + 0.42)
        y = (minDim.y or -1.6) * 0.28
    elseif name == 'rear' then
        x = 0.0
        y = (minDim.y or -1.6) - 0.55
    elseif name == 'front' then
        x = 0.0
        y = (maxDim.y or 1.6) + 0.55
    else
        local fallback = VEHICLE_ANCHORS[name] or VEHICLE_ANCHORS.rear
        x, y = fallback.x, fallback.y
    end

    local pos = GetOffsetFromEntityInWorldCoords(vehicle, x, y, 0.0)
    local ok, groundZ = GetGroundZFor_3dCoord(pos.x, pos.y, pos.z + 2.0, false)
    if ok then return vector3(pos.x, pos.y, groundZ) end
    return pos
end

local function compartmentRequiresOpenDoor(vehicle, comp)
    -- require_open é autoritativo. Antes, a revista dependia de GetIsDoorValid;
    -- em alguns modelos o native retorna false para o boot mesmo existindo e o
    -- compartimento acabava sendo considerado "sem porta". Isso permitia
    -- revistar o porta-malas fechado.
    if type(comp) ~= 'table' or comp.require_open ~= true then return false end
    local door = tonumber(comp.door) or -1
    return door >= 0
end

local function vehicleDoorIsOpen(vehicle, comp)
    if not compartmentRequiresOpenDoor(vehicle, comp) then return true end
    local door = tonumber(comp.door) or -1

    -- O que libera a revista é a abertura física da porta/tampa. Não usamos
    -- IsVehicleDoorDamaged como atalho porque uma porta amassada ainda pode
    -- estar fechada.
    local ok, ratio = pcall(GetVehicleDoorAngleRatio, vehicle, door)
    if not ok then return false end
    local threshold = tonumber((Config.VehicleSearch or {}).doorOpenRatio) or 0.18
    return tonumber(ratio or 0.0) >= threshold
end

local function vehicleDoorsUnlocked(vehicle)
    local ok, status = pcall(GetVehicleDoorLockStatus, vehicle)
    if not ok then return true end
    status = tonumber(status) or 0
    return status == 0 or status == 1
end

local function requestVehicleControl(vehicle, timeout)
    if not NetworkGetEntityIsNetworked(vehicle) or NetworkHasControlOfEntity(vehicle) then return true end
    local untilAt = GetGameTimer() + (timeout or 900)
    NetworkRequestControlOfEntity(vehicle)
    while GetGameTimer() < untilAt and not NetworkHasControlOfEntity(vehicle) do
        Wait(0)
        NetworkRequestControlOfEntity(vehicle)
    end
    return NetworkHasControlOfEntity(vehicle)
end

local function isNearVehicleCompartment(vehicle, id, extraDistance)
    local comp = vehicleCompartmentConfigFor(vehicle, id)
    if not comp then return false, nil, nil end
    if not vehicleClassHasCompartment(vehicle, id) then return false, nil, comp end
    local anchor = vehicleSearchAnchor(vehicle, comp.anchor, comp.door)
    local limit = tonumber(comp.distance) or tonumber((Config.VehicleSearch or {}).compartmentDistance) or 1.75
    limit = limit + (tonumber(extraDistance) or 0.0)
    return #(GetEntityCoords(PlayerPedId()) - anchor) <= limit, anchor, comp
end

local function vehicleHitLocalCoords(vehicle, worldCoords)
    if type(worldCoords) ~= 'vector3' and type(worldCoords) ~= 'table' then return nil end
    if type(GetOffsetFromEntityGivenWorldCoords) ~= 'function' then return nil end
    local ok, localCoords = pcall(
        GetOffsetFromEntityGivenWorldCoords,
        vehicle,
        worldCoords.x + 0.0,
        worldCoords.y + 0.0,
        worldCoords.z + 0.0
    )
    if not ok or not localCoords then return nil end
    return localCoords
end

local function vehicleCompartmentMatchesAim(vehicle, id, context)
    -- A revista usa o mesmo resolvedor físico do fivepd_sp_vehicle. Assim a
    -- porta mostrada pelo interaction e o compartimento revistável nunca
    -- discordam entre si.
    if type(context) ~= 'table' or not context.coords then return true end

    local comp = vehicleCompartmentConfigFor(vehicle, id)
    if not comp then return false end
    if id == 'seat' or id == 'cargo' or id == 'cabin' then return true end

    local anchorName = tostring(comp.anchor or 'rear')
    local expectedRegion = ({
        front_left = 'porta_dianteira_esquerda',
        front_right = 'porta_dianteira_direita',
        rear_left = 'porta_traseira_esquerda',
        rear_right = 'porta_traseira_direita',
        rear = (id == 'trunk') and 'porta_malas' or nil,
        front = (id == 'engine') and 'capo' or nil
    })[anchorName]

    if expectedRegion
        and GetResourceState('fivepd_sp_vehicle') == 'started'
    then
        local ok, region = pcall(function()
            return exports.fivepd_sp_vehicle:RegiaoAlvo(
                vehicle,
                context.coords
            )
        end)

        if ok then
            return region == expectedRegion
        end
    end

    -- Fallback para uma inicialização parcial do recurso de veículos.
    local localHit = vehicleHitLocalCoords(vehicle, context.coords)
    if not localHit then return false end

    local minDim, maxDim = GetModelDimensions(GetEntityModel(vehicle))
    local centerX = ((minDim.x or -0.8) + (maxDim.x or 0.8)) * 0.5
    local centerY = ((minDim.y or -1.5) + (maxDim.y or 1.5)) * 0.5
    local width = math.max(1.2, (maxDim.x or 0.8) - (minDim.x or -0.8))
    local length = math.max(2.0, (maxDim.y or 1.5) - (minDim.y or -1.5))
    local halfWidth = width * 0.5
    local x = localHit.x - centerX
    local y = localHit.y - centerY

    if anchorName == 'rear' then
        return y <= -(length * 0.22)
    end

    if anchorName == 'front_left' or anchorName == 'front_right'
        or anchorName == 'rear_left' or anchorName == 'rear_right'
    then
        if math.abs(x) < halfWidth * 0.34 then return false end
        if y <= -(length * 0.22) or y >= (length * 0.22) then return false end
        if anchorName:find('left', 1, true) and x >= 0.0 then return false end
        if anchorName:find('right', 1, true) and x <= 0.0 then return false end

        if anchorName:find('front', 1, true) then
            return y > 0.0
        end
        return y < 0.0
    end

    return true
end

local function runVehicleSearchProgress(label, duration)
    local progressId = nil
    if GetResourceState('fivepd_sp_ui') == 'started' then
        local ok, id = pcall(function()
            return exports.fivepd_sp_ui:IniciarProgresso({
                titulo = 'Revistando veículo',
                descricao = tostring(label or 'Compartimento'),
                dica = 'Aguarde a busca terminar.',
                progresso = 0
            })
        end)
        if ok then progressId = id end
    end

    local startedAt = GetGameTimer()
    while GetGameTimer() - startedAt < duration do
        local elapsed = GetGameTimer() - startedAt
        local percent = math.min(100, math.floor((elapsed / duration) * 100))
        DisableControlAction(0, 24, true)
        DisableControlAction(0, 25, true)
        DisableControlAction(0, 37, true)
        DisableControlAction(0, 44, true)
        DisablePlayerFiring(PlayerId(), true)
        if progressId then
            pcall(function() exports.fivepd_sp_ui:AtualizarProgresso(progressId, percent, {}) end)
        end
        Wait(20)
    end

    if progressId then
        pcall(function() exports.fivepd_sp_ui:AtualizarProgresso(progressId, 100, {}) end)
        pcall(function() exports.fivepd_sp_ui:FinalizarProgresso(progressId, true, 'Compartimento revistado.') end)
    end
end

local function performVehicleCompartmentSearch(vehicle, comp)
    if vehicleSearchBusy then return false end
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return false end
    if type(comp) ~= 'table' then return false end

    local id = tostring(comp.id or '')
    local localComp = vehicleCompartmentConfigFor(vehicle, id) or comp
    local near, anchor = isNearVehicleCompartment(vehicle, id, 0.0)
    if not near or not anchor then
        notify('aviso', 'Revista veicular', 'Vá fisicamente até este compartimento para realizar a revista.')
        return false
    end

    if compartmentRequiresOpenDoor(vehicle, localComp) and not vehicleDoorIsOpen(vehicle, localComp) then
        notify('aviso', 'Revista veicular', ('Abra %s antes de revistar este compartimento.'):format(tostring(localComp.door_label or 'a porta correspondente')))
        return false
    end

    vehicleSearchBusy = true
    local playerPed = PlayerPedId()

    -- O script não desloca o jogador e não abre/fecha a porta por ele.
    -- A revista só começa quando o policial já está no ponto físico correto.
    TaskTurnPedToFaceEntity(playerPed, vehicle, 550)
    Wait(550)

    local duration = math.max(2500, tonumber((Config.VehicleSearch or {}).duration) or 4600)
    local animation = tostring(localComp.animation or comp.animation or 'cabin')
    local played = false

    if animation == 'cabin' then
        if requestAnimDictSafe('mini@repair', 1600) then
            TaskPlayAnim(playerPed, 'mini@repair', 'fixing_a_ped', 4.0, -4.0, duration, 1, 0.0, false, false, false)
            played = true
        end
    else
        if requestAnimDictSafe('amb@prop_human_bum_bin@base', 1600) then
            TaskPlayAnim(playerPed, 'amb@prop_human_bum_bin@base', 'base', 4.0, -4.0, duration, 1, 0.0, false, false, false)
            played = true
        end
    end

    if not played then
        TaskStartScenarioInPlace(playerPed, 'PROP_HUMAN_BUM_BIN', 0, true)
    end

    runVehicleSearchProgress(localComp.label or comp.label, duration)
    ClearPedTasks(playerPed)
    vehicleSearchBusy = false
    return DoesEntityExist(vehicle)
end

local function canVehicleBase(entity)
    if uiOpen or vehicleSearchBusy then return false end
    if not LocalPlayer or not LocalPlayer.state or LocalPlayer.state['fivepd_sp:pmEmServico'] ~= true then return false end
    if not entity or entity == 0 or not DoesEntityExist(entity) or not IsEntityAVehicle(entity) then return false end
    if GetEntityModel(entity) == joaat('strykerpro') then return false end
    local okState, entityState = pcall(function() return Entity(entity).state end)
    if okState and entityState and entityState['fiveems:stretcher'] == true then return false end
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) or IsEntityDead(ped) then return false end
    if GetVehicleClass(entity) == 13 then return false end
    return true
end

local function canInteractAtVehicleCompartment(entity, id, context)
    if not canVehicleBase(entity) then return false end
    local near = isNearVehicleCompartment(entity, id, 0.0)
    if near ~= true then return false end
    return vehicleCompartmentMatchesAim(entity, id, context)
end

local function canOpenVehicleCompartmentDoor(entity, id, context)
    if not canInteractAtVehicleCompartment(entity, id, context) then return false end
    local comp = vehicleCompartmentConfigFor(entity, id)
    return compartmentRequiresOpenDoor(entity, comp) and not vehicleDoorIsOpen(entity, comp)
end

local function canCloseVehicleCompartmentDoor(entity, id, context)
    if not canInteractAtVehicleCompartment(entity, id, context) then return false end
    local comp = vehicleCompartmentConfigFor(entity, id)
    return compartmentRequiresOpenDoor(entity, comp) and vehicleDoorIsOpen(entity, comp)
end

local function canSearchVehicleCompartment(entity, id, context)
    local okState, entityState = pcall(function() return Entity(entity).state end)
    if okState and entityState and entityState['fiveems:stretcher'] == true then return false end
    if not canInteractAtVehicleCompartment(entity, id, context) then return false end
    local comp = vehicleCompartmentConfigFor(entity, id)
    -- A opção de revista nem aparece enquanto a porta/tampa necessária
    -- estiver fechada. A mesma regra ainda é revalidada no handler.
    return not compartmentRequiresOpenDoor(entity, comp) or vehicleDoorIsOpen(entity, comp)
end

local function handleVehicleDoorInteraction(vehicle, id, opening)
    if not canInteractAtVehicleCompartment(vehicle, id) then
        notify('aviso', 'Veículo', 'Aproxime-se da porta correspondente.')
        return false
    end
    local comp = vehicleCompartmentConfigFor(vehicle, id)
    if not comp or not compartmentRequiresOpenDoor(vehicle, comp) then return false end

    local door = tonumber(comp.door) or -1
    if opening and not vehicleDoorsUnlocked(vehicle) then
        notify('aviso', 'Veículo', 'O veículo está trancado.')
        return false
    end

    requestVehicleControl(vehicle, 1000)
    if opening then
        SetVehicleDoorOpen(vehicle, door, false, false)
    else
        SetVehicleDoorShut(vehicle, door, false)
    end
    return true
end

local function findVehicleViewCompartment(view, id)
    for _, comp in ipairs(type(view) == 'table' and type(view.compartments) == 'table' and view.compartments or {}) do
        if tostring(comp.id) == tostring(id) then return comp end
    end
    return nil
end

local function searchVehicleCompartmentFromInteraction(vehicle, id)
    if vehicleSearchBusy then return false end
    if not canInteractAtVehicleCompartment(vehicle, id) then
        notify('aviso', 'Revista veicular', 'Vá até o compartimento que deseja revistar.')
        return false
    end

    local localComp = vehicleCompartmentConfigFor(vehicle, id)
    if compartmentRequiresOpenDoor(vehicle, localComp) and not vehicleDoorIsOpen(vehicle, localComp) then
        notify('aviso', 'Revista veicular', ('Abra %s antes de iniciar a revista.'):format(tostring(localComp.door_label or 'a porta correspondente')))
        return false
    end

    local result, token, netId = beginVehicleSearchSession(vehicle)
    if not result then return false end
    local viewComp = findVehicleViewCompartment(result.view, id)
    if not viewComp then
        notify('aviso', 'Revista veicular', 'Este veículo não possui este compartimento configurado para revista.')
        return false
    end

    viewComp.id = id
    if not performVehicleCompartmentSearch(vehicle, viewComp) then return false end

    -- Revalidamos posição e porta depois da animação antes de revelar o conteúdo.
    if not canInteractAtVehicleCompartment(vehicle, id) then
        notify('aviso', 'Revista veicular', 'A revista foi interrompida porque você se afastou do compartimento.')
        return false
    end
    if compartmentRequiresOpenDoor(vehicle, localComp) and not vehicleDoorIsOpen(vehicle, localComp) then
        notify('aviso', 'Revista veicular', 'A porta foi fechada antes do término da revista.')
        return false
    end

    local response = rpc('search_vehicle_compartment', {
        token = tostring(result.token or token),
        compartment = id
    }, 7000)

    if not response or response.ok ~= true or type(response.view) ~= 'table' then
        notify('aviso', 'Revista veicular', response and response.error or 'Não foi possível revelar o conteúdo deste compartimento.')
        return false
    end

    response.view.focus_compartment = id
    return openUi(response.view, {
        mode = 'vehicle_search',
        token = tostring(result.token or token),
        net_id = netId,
        vehicle = vehicle,
        last_view = response.view,
        focus_compartment = id,
        vehicle_animation = tostring(localComp.animation or viewComp.animation or 'rear')
    })
end


local function vehicleCompartmentHasStorage(id)
    id = tostring(id or '')
    return id == 'interior' or id == 'glovebox' or id == 'trunk'
        or id == 'seat' or id == 'cabin' or id == 'cargo'
end

local function canAccessIllegalVehicleStorage(entity, id, context)
    local okState, entityState = pcall(function() return Entity(entity).state end)
    if okState and entityState and entityState['fiveems:stretcher'] == true then return false end
    if uiOpen or vehicleSearchBusy or not isIllegalCharacter() then return false end
    if (Config.VehicleSearch or {}).storageForIllegal == false then return false end
    if not entity or entity == 0 or not DoesEntityExist(entity) or not IsEntityAVehicle(entity) then return false end
    if GetVehicleClass(entity) == 13 or IsPedInAnyVehicle(PlayerPedId(), false) or IsEntityDead(PlayerPedId()) then return false end
    if not vehicleCompartmentHasStorage(id) then return false end
    local near = isNearVehicleCompartment(entity, id, 0.0)
    if near ~= true then return false end
    if context and not vehicleCompartmentMatchesAim(entity, id, context) then return false end
    if (Config.VehicleSearch or {}).storageRequiresUnlockedVehicle ~= false and not vehicleDoorsUnlocked(entity) then return false end
    local comp = vehicleCompartmentConfigFor(entity, id)
    return not compartmentRequiresOpenDoor(entity, comp) or vehicleDoorIsOpen(entity, comp)
end

local function openIllegalVehicleStorage(vehicle, id)
    if not isIllegalCharacter() then return false end
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return false end
    id = tostring(id or '')
    if not canAccessIllegalVehicleStorage(vehicle, id) then
        notify('aviso', 'Armazenamento', 'Aproxime-se, destranque e abra o compartimento antes de acessá-lo.')
        return false
    end

    local token, netId = vehicleToken(vehicle)
    local result = rpc('vehicle_storage_open', {
        token = token,
        net_id = netId,
        model = GetEntityModel(vehicle),
        class_id = GetVehicleClass(vehicle),
        plate = GetVehicleNumberPlateText(vehicle) or '',
        compartment = id
    }, 7000)
    if not result or result.ok ~= true or type(result.view) ~= 'table' then
        notify('aviso', 'Armazenamento', result and result.error or 'Não foi possível acessar o compartimento.')
        return false
    end

    result.view.focus_compartment = id
    return openUi(result.view, {
        mode = 'vehicle_storage',
        token = tostring(result.token or token),
        net_id = netId,
        vehicle = vehicle,
        focus_compartment = id,
        last_view = result.view
    })
end

RegisterNetEvent('fivepd_sp:inventory:vehicleStorageInteraction', function(context)
    local vehicle = type(context) == 'table' and tonumber(context.entidade) or 0
    local args = type(context) == 'table' and type(context.args) == 'table' and context.args or {}
    local id = tostring(args.compartment or '')
    if vehicle ~= 0 and id ~= '' then
        CreateThread(function() openIllegalVehicleStorage(vehicle, id) end)
    end
end)

local function registerVehicleInteraction()
    if vehicleInteractionRegistered or GetResourceState('ox_target') ~= 'started' then return false end

    local options = {}
    local labelMap = { interior='Interior', glovebox='Porta-luvas', engine='Compartimento do motor', trunk='Porta-malas', seat='Assento', cabin='Cabine', cargo='Baú / Carga' }
    for _, rawId in ipairs(VEHICLE_COMPARTMENT_ORDER) do
        local id = tostring(rawId)
        local label = labelMap[id] or id
        do

            -- A abertura/fechamento das portas pertence ao fivepd_sp_vehicle.
            -- O inventário só adiciona a ação de revista, e somente quando a
            -- porta/tampa exigida já estiver fisicamente aberta. Isso evita
            -- opções duplicadas no interaction.
            options[#options + 1] = {
                id = 'search_' .. id,
                titulo = 'Revistar ' .. label,
                descricao = 'Revistar somente este compartimento.',
                evento = 'fivepd_sp:inventory:vehicleCompartmentInteraction',
                args = { compartment = id },
                distancia = tonumber((Config.VehicleSearch or {}).interactionDistance) or 6.2,
                podeInteragir = function(entity, distance, context)
                    return canSearchVehicleCompartment(entity, id, context)
                end
            }

            if vehicleCompartmentHasStorage(id) then
                options[#options + 1] = {
                    id = 'storage_' .. id,
                    titulo = 'Acessar ' .. label,
                    descricao = 'Guardar ou retirar objetos deste compartimento.',
                    evento = 'fivepd_sp:inventory:vehicleStorageInteraction',
                    args = { compartment = id },
                    distancia = tonumber((Config.VehicleSearch or {}).interactionDistance) or 6.2,
                    podeInteragir = function(entity, distance, context)
                        return canAccessIllegalVehicleStorage(entity, id, context)
                    end
                }
            end
        end
    end

    local interactionDistance = tonumber((Config.VehicleSearch or {}).interactionDistance) or 6.2
    local ok, regId = pcall(function()
        return FSPTarget.RegisterGlobal('vehicle', {
            id = 'fivepd_sp_inventory:vehicle_search',
            nome = 'Veículo',
            distancia = interactionDistance,
            opcoes = options
        })
    end)
    vehicleInteractionRegistered = ok and regId ~= false
    return vehicleInteractionRegistered
end

RegisterNetEvent('fivepd_sp:inventory:vehicleDoorInteraction', function(context)
    local vehicle = type(context) == 'table' and tonumber(context.entidade) or 0
    local args = type(context) == 'table' and type(context.args) == 'table' and context.args or {}
    local id = tostring(args.compartment or '')
    if vehicle ~= 0 and id ~= '' then
        handleVehicleDoorInteraction(vehicle, id, args.opening == true)
    end
end)

RegisterNetEvent('fivepd_sp:inventory:vehicleCompartmentInteraction', function(context)
    local vehicle = type(context) == 'table' and tonumber(context.entidade) or 0
    local args = type(context) == 'table' and type(context.args) == 'table' and context.args or {}
    local id = tostring(args.compartment or '')
    if vehicle ~= 0 and id ~= '' then
        CreateThread(function()
            searchVehicleCompartmentFromInteraction(vehicle, id)
        end)
    end
end)

-- Compatibilidade com integrações antigas que ainda disparam a busca geral.
RegisterNetEvent('fivepd_sp:inventory:vehicleInteractionSearch', function(context)
    local vehicle = type(context) == 'table' and tonumber(context.entidade) or 0
    if vehicle and vehicle ~= 0 then openVehicleSearch(vehicle) end
end)

local function openAdminPanel()
    if uiOpen then closeUi() end
    local clothing = clothingSnapshot(PlayerPedId())
    local result = rpc('admin_get', { clothing = clothing }, 8000)
    if not result or result.ok ~= true then
        notify('aviso', 'Inventário Admin', result and result.error or 'Não foi possível abrir o painel administrativo.')
        return false
    end
    return openUi(result.admin, { mode = 'admin' })
end

exports('AbrirInventario', openSelfInventory)
exports('AbrirRevistaNpc', openPersonSearch)
exports('AbrirRevistaPessoa', openPersonSearch)
exports('AbrirRevistaVeiculo', openVehicleSearch)
exports('EstaAberto', function() return uiOpen == true end)
exports('RevistaAbertaPara', function(ped)
    return uiOpen == true
        and currentContext ~= nil
        and currentContext.mode == 'search'
        and tonumber(currentContext.ped or 0) == tonumber(ped or -1)
end)
exports('ObterRoupaAtual', function(ped) return clothingSnapshot(ped or PlayerPedId()) end)

RegisterCommand(Config.InventoryCommand or 'inventario', function()
    if uiOpen then closeUi() else openSelfInventory() end
end, false)
RegisterKeyMapping(Config.InventoryCommand or 'inventario', 'Abrir inventário pessoal', 'keyboard', Config.InventoryKey or 'I')

RegisterCommand((Config.Admin and Config.Admin.command) or 'inventarioadmin', function()
    openAdminPanel()
end, false)

RegisterCommand((Config.Clothing and Config.Clothing.debugCommand) or 'invroupa', function(_, args)
    args = args or {}
    local snapshot = clothingSnapshot(PlayerPedId())
    local keyword = tostring(args[1] or ''):lower()

    if keyword == '' then
        print(('[fivepd_sp_inventory] roupa atual: %s'):format(json.encode(snapshot)))
        notify('info', 'Classificação de roupa', 'Use /invroupa para exceções rápidas ou /inventarioadmin para o painel completo.')
        print('[fivepd_sp_inventory] Exemplos: /invroupa saia | /invroupa vestido | /invroupa padrao pernas | /invroupa status')
        return
    end

    local scope = tostring(args[2] or ''):lower()
    local textureSpecific = scope == 'textura'
    local component = nil
    if scope == 'pernas' or scope == 'legs' then component = 'legs' end
    if scope == 'topo' or scope == 'top' then component = 'top' end

    local result = rpc('classify_clothing', {
        clothing = snapshot,
        keyword = keyword,
        component = component,
        texture_specific = textureSpecific
    }, 7000)

    if result and result.ok then
        notify('sucesso', 'Classificação de roupa', result.message or 'Classificação atualizada.')
        syncClothing(true)
    else
        notify('aviso', 'Classificação de roupa', result and result.error or 'Não foi possível atualizar esta roupa.')
    end
end, false)

RegisterNetEvent('fivepd_sp:pm:dutyChanged', function(enabled)
    if enabled == true then return end
    if uiOpen and currentContext and (currentContext.mode == 'search' or currentContext.mode == 'vehicle_search') then closeUi() end
end)

RegisterNetEvent('fivepd_sp:inventory:weapon:remove', function(weaponName)
    weaponName = tostring(weaponName or ''):upper()
    if weaponName == '' then return end
    local ped = PlayerPedId()
    local hash = joaat(weaponName)
    if ped ~= 0 and DoesEntityExist(ped) and hash and hash ~= 0 and HasPedGotWeapon(ped, hash, false) then
        RemoveWeaponFromPed(ped, hash)
    end
end)

RegisterNetEvent('fivepd_sp:inventory:inventoryChanged', function()
    if not uiOpen or not currentContext or currentContext.mode ~= 'self' then return end
    CreateThread(function()
        local result = rpc('self', { clothing = syncClothing(true) }, 7000)
        if result and result.ok and result.view and uiOpen and currentContext and currentContext.mode == 'self' then
            SendNUIMessage({ action = 'update', data = result.view })
        end
    end)
end)

RegisterNetEvent('fivepd_sp:inventory:runtimeChanged', function()
    if uiOpen and currentContext and currentContext.mode == 'admin' then
        CreateThread(function()
            local result = rpc('admin_get', { clothing = clothingSnapshot(PlayerPedId()) }, 7000)
            if result and result.ok and currentContext and currentContext.mode == 'admin' then
                SendNUIMessage({ action = 'adminUpdate', data = result.admin })
            end
        end)
    end
end)

local PERSON_SEARCH_REGIONS = {
    hands=true, front_pockets=true, waist=true, back_pockets=true,
    jacket=true, bag=true, ankles=true, socks=true
}

RegisterNUICallback('searchPersonRegion', function(data, cb)
    if not currentContext or currentContext.mode ~= 'search' then cb({ ok=false, error='Ação indisponível.' }); return end
    local context = currentContext
    local region = tostring(data and data.region or '')
    if not PERSON_SEARCH_REGIONS[region] then cb({ ok=false, error='Região inválida.' }); return end
    if context.searched_regions and context.searched_regions[region] then cb({ ok=true, already=true }); return end
    local target = tonumber(context.ped) or 0
    if target == 0 or not DoesEntityExist(target) or #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(target)) > 4.0 then
        cb({ ok=false, error='A pessoa se afastou.' }); return
    end

    local duration = 1450
    local ped = PlayerPedId()
    local dict, anim = 'anim@gangops@facility@servers@bodysearch@', 'player_search'
    if requestAnimDictSafe(dict, 900) then
        TaskPlayAnim(ped, dict, anim, 5.0, -5.0, duration, 48, 0.0, false, false, false)
    end
    SendNUIMessage({ action='regionProgress', region=region, duration=duration })
    local started = GetGameTimer()
    while GetGameTimer() - started < duration do
        DisableControlAction(0, 24, true); DisableControlAction(0, 25, true); DisablePlayerFiring(PlayerId(), true)
        Wait(0)
    end
    ClearPedSecondaryTask(ped)
    context.searched_regions = context.searched_regions or {}
    context.searched_regions[region] = true
    if uiOpen and currentContext == context then
        SendNUIMessage({ action='personRegionSearched', region=region })
    end
    cb({ ok=true })
end)

RegisterNUICallback('previewStageRect', function(data, cb)
    data = type(data) == 'table' and data or {}
    previewStageRect = {
        x = clampNumber(data.x, 0.10, 0.90),
        y = clampNumber(data.y, 0.10, 0.90),
        w = clampNumber(data.w, 0.10, 0.80),
        h = clampNumber(data.h, 0.10, 0.85)
    }
    cb({ ok = true })
end)

RegisterNUICallback('close', function(_, cb)
    closeUi()
    cb({ ok = true })
end)

RegisterNUICallback('move', function(data, cb)
    if not currentContext or currentContext.mode ~= 'self' then
        cb({ ok = false, error = 'Ação indisponível.' })
        return
    end
    local result = rpc('move', {
        item_id = data and data.item_id or nil,
        compartment = tostring(data and data.compartment or ''),
        clothing = syncClothing(true)
    })
    if result and result.ok then
        if result.view then SendNUIMessage({ action = 'update', data = result.view }) end
        notify('sucesso', 'Inventário', 'Item movido.')
    else
        notify('aviso', 'Inventário', result and result.error or 'Não foi possível mover o item.')
    end
    cb(result or { ok = false })
end)

RegisterNUICallback('illegalSellingToggle', function(data, cb)
    if not currentContext or currentContext.mode ~= 'self' then
        cb({ ok = false, error = 'Ação indisponível.' })
        return
    end
    if GetResourceState('fivepd_sp_illegal') ~= 'started' then
        cb({ ok = false, error = 'Sistema ilegal indisponível.' })
        return
    end
    TriggerServerEvent('fivepd_sp:illegal:selling:set', data and data.enabled == true)
    cb({ ok = true })
end)

RegisterNetEvent('fivepd_sp:illegal:selling:state', function()
    if not uiOpen or not currentContext or currentContext.mode ~= 'self' then return end
    CreateThread(function()
        Wait(120)
        local result = rpc('self', { clothing = syncClothing(true) }, 7000)
        if result and result.ok and result.view and uiOpen and currentContext and currentContext.mode == 'self' then
            SendNUIMessage({ action = 'update', data = result.view })
        end
    end)
end)

RegisterNUICallback('seize', function(data, cb)
    if not currentContext or (currentContext.mode ~= 'search' and currentContext.mode ~= 'vehicle_search') then
        cb({ ok = false, error = 'Ação indisponível.' })
        return
    end

    if tostring(data and data.kind or '') == 'weapon' then
        local weaponName = tostring(data and data.weapon_name or ''):upper()
        local result = rpc('seize_weapon', {
            token = currentContext.token,
            weapon_name = weaponName
        })
        if result and result.ok then
            currentContext.suppressed_weapons[weaponName] = GetGameTimer() + 2200
            if result.remove_local == true then
                local ped = tonumber(currentContext.ped) or 0
                if ped ~= 0 and DoesEntityExist(ped) then RemoveWeaponFromPed(ped, joaat(weaponName)) end
            end
            if result.view then currentContext.base_view = result.view end
            updateSearchView(currentContext.base_view, true)
            notify('sucesso', 'Revista pessoal', 'Armamento apreendido da pessoa.')
        else
            notify('aviso', 'Revista pessoal', result and result.error or 'Não foi possível apreender o armamento.')
        end
        cb(result or { ok = false })
        return
    end

    local result = rpc('seize', {
        token = currentContext.token,
        item_id = tostring(data and data.item_id or ''),
        clothing = syncClothing(true)
    })
    if result and result.ok then
        if currentContext.mode == 'vehicle_search' then
            if result.view then
                currentContext.last_view = result.view
                SendNUIMessage({ action = 'update', data = result.view })
            end
            notify('sucesso', 'Revista veicular', 'Item apreendido e guardado com você.')
        else
            if result.view then currentContext.base_view = result.view end
            updateSearchView(currentContext.base_view, true)
            notify('sucesso', 'Revista pessoal', 'Item apreendido e guardado com você.')
        end
    else
        notify('aviso', currentContext.mode == 'vehicle_search' and 'Revista veicular' or 'Revista pessoal',
            result and result.error or 'Não foi possível apreender o item.')
    end
    cb(result or { ok = false })
end)

local function adminResultToUi(result, title)
    if result and result.ok then
        if result.admin then SendNUIMessage({ action = 'adminUpdate', data = result.admin }) end
        notify('sucesso', title or 'Inventário Admin', result.message or 'Alteração salva.')
    else
        notify('aviso', title or 'Inventário Admin', result and result.error or 'Não foi possível salvar a alteração.')
    end
    return result or { ok = false }
end



local function updateVehicleStorageFromResult(result, successMessage)
    if result and result.ok == true and type(result.view) == 'table' and currentContext and currentContext.mode == 'vehicle_storage' then
        currentContext.last_view = result.view
        SendNUIMessage({ action = 'update', data = result.view })
        if successMessage then notify('sucesso', 'Armazenamento', successMessage) end
    elseif result and result.ok ~= true then
        notify('aviso', 'Armazenamento', result.error or 'Não foi possível concluir a transferência.')
    end
    return result or { ok = false }
end

RegisterNUICallback('vehicleStore', function(data, cb)
    if not currentContext or currentContext.mode ~= 'vehicle_storage' then cb({ ok=false }); return end
    local result = rpc('vehicle_storage_store', {
        token = currentContext.token,
        item_id = tonumber(data and data.item_id),
        amount = tonumber(data and data.amount)
    }, 7000)
    cb(updateVehicleStorageFromResult(result, 'Item guardado no veículo.'))
end)

RegisterNUICallback('vehicleTake', function(data, cb)
    if not currentContext or currentContext.mode ~= 'vehicle_storage' then cb({ ok=false }); return end
    local result = rpc('vehicle_storage_take', {
        token = currentContext.token,
        item_id = tostring(data and data.item_id or ''),
        amount = tonumber(data and data.amount) or 1
    }, 7000)
    cb(updateVehicleStorageFromResult(result, 'Item retirado do veículo.'))
end)

RegisterNUICallback('vehicleLoadMissionCargo', function(data, cb)
    if not currentContext or currentContext.mode ~= 'vehicle_storage' then cb({ ok=false }); return end
    local result = rpc('vehicle_storage_load_mission', {
        token = currentContext.token,
        item_name = tostring(data and data.item_name or ''),
        amount = tonumber(data and data.amount)
    }, 7000)
    cb(updateVehicleStorageFromResult(result, 'Carga colocada no compartimento.'))
end)

RegisterNUICallback('focusVehicleCompartment', function(data, cb)
    if not currentContext or currentContext.mode ~= 'vehicle_search' then cb({ ok=false }); return end
    local vehicle = tonumber(currentContext.vehicle) or 0
    local id = tostring(data and data.compartment or '')
    if vehicle == 0 or not DoesEntityExist(vehicle) or id == '' then cb({ ok=false }); return end
    local comp = findVehicleViewCompartment(currentContext.last_view or {}, id)
    if not comp then cb({ ok=false }); return end
    currentContext.focus_compartment = id
    activateInspectionCameraForVehicle(vehicle, id, (currentContext.last_view or {}).vehicle_type)
    -- Se o usuário alternar entre compartimentos já revistados, preservamos a
    -- animação em andamento; só atualizamos o perfil quando houver configuração.
    local localComp = vehicleCompartmentConfigFor(vehicle, id)
    if localComp and localComp.animation then
        currentContext.vehicle_animation = tostring(localComp.animation)
    end
    playVehicleInspectionPanelAnim(currentContext, false)
    cb({ ok=true })
end)

RegisterNUICallback('searchVehicleCompartment', function(_, cb)
    cb({
        ok = false,
        error = 'Feche o painel, vá fisicamente até o compartimento e use ALT para realizar a revista.'
    })
end)

RegisterNUICallback('adminSave', function(data, cb)
    if not currentContext or currentContext.mode ~= 'admin' then cb({ ok = false }); return end
    data = type(data) == 'table' and data or {}
    local result = rpc('admin_save', {
        category = data.category,
        key = data.key,
        data = data.data,
        enabled = data.enabled ~= false,
        sort_order = tonumber(data.sort_order) or 0,
        clothing = clothingSnapshot(PlayerPedId())
    }, 8000)
    cb(adminResultToUi(result))
end)

RegisterNUICallback('adminDelete', function(data, cb)
    if not currentContext or currentContext.mode ~= 'admin' then cb({ ok = false }); return end
    data = type(data) == 'table' and data or {}
    local result = rpc('admin_delete', {
        category = data.category,
        key = data.key,
        clothing = clothingSnapshot(PlayerPedId())
    }, 8000)
    cb(adminResultToUi(result))
end)

RegisterNUICallback('adminClothingSave', function(data, cb)
    if not currentContext or currentContext.mode ~= 'admin' then cb({ ok = false }); return end
    data = type(data) == 'table' and data or {}
    local result = rpc('admin_clothing_save', {
        clothing = clothingSnapshot(PlayerPedId()),
        component = data.component,
        profile = data.profile,
        texture_specific = data.texture_specific == true
    }, 8000)
    cb(adminResultToUi(result, 'Roupas do inventário'))
end)

RegisterNUICallback('adminClothingDelete', function(data, cb)
    if not currentContext or currentContext.mode ~= 'admin' then cb({ ok = false }); return end
    data = type(data) == 'table' and data or {}
    local result = rpc('admin_clothing_delete', {
        id = tonumber(data.id),
        clothing = clothingSnapshot(PlayerPedId())
    }, 8000)
    cb(adminResultToUi(result, 'Roupas do inventário'))
end)

RegisterNUICallback('adminRefresh', function(_, cb)
    if not currentContext or currentContext.mode ~= 'admin' then cb({ ok = false }); return end
    local result = rpc('admin_get', { clothing = clothingSnapshot(PlayerPedId()) }, 8000)
    if result and result.ok and result.admin then SendNUIMessage({ action = 'adminUpdate', data = result.admin }) end
    cb(result or { ok = false })
end)

RegisterNetEvent('fivepd_sp:core:personagemCarregado', function()
    CreateThread(function()
        Wait(1200)
        syncClothing(true)
    end)
end)

RegisterNetEvent('fivepd_sp:core:personagemDescarregado', function()
    closeUi()
    lastClothingSignature = nil
end)

-- Fundo da área central do preview. A NUI fica transparente apenas nessa janela;
-- este retângulo é desenhado na camada gráfica atrás do pause-menu PED e acima do
-- mundo 3D. Com isso o cenário real não "vaza" pelo painel e, ao mesmo tempo, o
-- personagem do frontend continua aparecendo na frente do fundo.
CreateThread(function()
    while true do
        if uiOpen and currentContext and (currentContext.mode == 'search' or currentContext.mode == 'self')
            and inspectionFrontendActive then
            local rect = previewStageRect
            SetScriptGfxDrawBehindPausemenu(true)
            DrawRect(rect.x, rect.y, rect.w, rect.h, 8, 12, 17, 250)
            -- Camada interna levemente mais clara para dar profundidade sem depender
            -- de transparência do HTML, que ficaria acima do PED do frontend.
            DrawRect(rect.x, rect.y - (rect.h * 0.015), rect.w * 0.94, rect.h * 0.93, 17, 23, 30, 118)
            SetScriptGfxDrawBehindPausemenu(false)
            setFrontendMouseVisible(false)
            Wait(0)
        else
            Wait(160)
        end
    end
end)

-- Durante a revista veicular o policial real continua existindo e animando no
-- mundo para todos os outros jogadores. Apenas este cliente deixa de desenhar seu
-- próprio ped, evitando que ele fique entre a câmera e o compartimento inspecionado.
-- SET_ENTITY_LOCALLY_INVISIBLE/SET_PLAYER_INVISIBLE_LOCALLY são locais e precisam
-- ser reaplicados por frame; ao fechar o painel paramos de chamá-los e a renderização
-- normal volta automaticamente, sem SetEntityVisible/alpha/network hacks.
CreateThread(function()
    local nextAnimCheck = 0
    while true do
        if uiOpen and currentContext and (currentContext.mode == 'vehicle_search' or currentContext.mode == 'vehicle_storage') then
            local ped = PlayerPedId()
            if ped ~= 0 and DoesEntityExist(ped) then
                pcall(SetEntityLocallyInvisible, ped)
                if type(SetPlayerInvisibleLocally) == 'function' then
                    pcall(SetPlayerInvisibleLocally, PlayerId())
                end

                if currentContext.mode == 'vehicle_search' then
                    local now = GetGameTimer()
                    if now >= nextAnimCheck then
                        nextAnimCheck = now + 450
                        playVehicleInspectionPanelAnim(currentContext, false)
                    end
                end
            end
            Wait(0)
        else
            nextAnimCheck = 0
            Wait(120)
        end
    end
end)

CreateThread(function()
    while true do
        Wait(650)
        if uiOpen and currentContext and currentContext.mode == 'search' then
            local ped = tonumber(currentContext.ped) or 0
            if ped ~= 0 and DoesEntityExist(ped) then updateSearchView(nil, false) end
        elseif uiOpen and currentContext and (currentContext.mode == 'vehicle_search' or currentContext.mode == 'vehicle_storage') and not vehicleSearchBusy then
            local vehicle = tonumber(currentContext.vehicle) or 0
            if vehicle == 0 or not DoesEntityExist(vehicle)
                or #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(vehicle)) > 14.0 then
                local storage = currentContext.mode == 'vehicle_storage'
                notify('aviso', storage and 'Armazenamento' or 'Revista veicular', storage
                    and 'O armazenamento foi fechado porque você se afastou do veículo.'
                    or 'A revista foi encerrada porque você se afastou do veículo.')
                closeUi()
            end
        end
    end
end)

CreateThread(function()
    while true do
        Wait(8000)
        if NetworkIsPlayerActive(PlayerId()) then syncClothing(false) end
    end
end)


CreateThread(function()
    while not vehicleInteractionRegistered do
        if GetResourceState('ox_target') == 'started' then
            registerVehicleInteraction()
        end
        Wait(vehicleInteractionRegistered and 30000 or 1200)
    end
end)

AddEventHandler('onClientResourceStart', function(resource)
    if resource == 'ox_target' or resource == GetCurrentResourceName() then
        vehicleInteractionRegistered = false
        CreateThread(function()
            Wait(500)
            registerVehicleInteraction()
        end)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    closeUi()
    destroyInspectionCamera()
end)
