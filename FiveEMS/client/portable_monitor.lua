FiveEMS = FiveEMS or {}
local C = FiveEMS.Client

C.monitorSession = C.monitorSession or nil

local TARGET_MODEL = joaat(((Config.Monitor or {}).portable or {}).model or 'lifepak15')
local placing = false
local movingNetId = nil

local function requestModel(model)
    -- lifepak15 is a standalone drawable registered by ems_props.ytyp.
    -- Check the archetype first so a missing/duplicate YTYP is obvious in F8.
    local inCdImage = IsModelInCdimage(model)
    local valid = IsModelValid(model)
    if not inCdImage or not valid then
        print(('[FiveEMS][LIFEPAK] model=%s hash=%s inCdImage=%s valid=%s')
            :format(tostring(((Config.Monitor or {}).portable or {}).model or 'lifepak15'),
                tostring(model), tostring(inCdImage), tostring(valid)))
        return false
    end

    RequestModel(model)
    local deadline = GetGameTimer() + 7500
    while not HasModelLoaded(model) and GetGameTimer() < deadline do Wait(0) end
    return HasModelLoaded(model)
end

local function groundZAt(x,y,z)
    local found, ground = GetGroundZFor_3dCoord(x,y,z+2.0,false)
    return found and ground or z
end

local function nearestPatientFrom(origin, maxDist)
    local bestRef, bestSnapshot, bestDist
    local me = PlayerPedId()

    for _, player in ipairs(GetActivePlayers()) do
        if player ~= PlayerId() then
            local ped = GetPlayerPed(player)
            if ped ~= 0 and DoesEntityExist(ped) then
                local d = #(GetEntityCoords(ped)-origin)
                if d <= maxDist and (not bestDist or d < bestDist) then
                    bestRef = {kind='player', serverId=GetPlayerServerId(player)}
                    bestSnapshot = {}
                    bestDist = d
                end
            end
        end
    end

    for _, ped in ipairs(GetGamePool('CPed')) do
        if ped ~= me and DoesEntityExist(ped) and not IsPedAPlayer(ped) and IsPedHuman(ped) then
            local d = #(GetEntityCoords(ped)-origin)
            if d <= maxDist and (not bestDist or d < bestDist) then
                local netId = C.ensureNpcNetId and C.ensureNpcNetId(ped) or nil
                if netId then
                    bestRef = {kind='npc', netId=netId}
                    bestSnapshot = C.snapshotNpc and C.snapshotNpc(ped) or {}
                    bestDist = d
                end
            end
        end
    end
    return bestRef, bestSnapshot, bestDist
end

local function portableState(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return nil end
    local st = Entity(entity).state
    if not st or st['fiveems:portableMonitor'] ~= true then return nil end
    local kind = tostring(st['fiveems:monitorPatientKind'] or '')
    local id = tonumber(st['fiveems:monitorPatientId']) or 0
    local ref
    if st['fiveems:monitorConnected'] == true and id > 0 then
        ref = kind == 'player' and {kind='player',serverId=id} or kind == 'npc' and {kind='npc',netId=id} or nil
    end
    return {ref=ref, connected=ref~=nil, owner=tonumber(st['fiveems:monitorOwner']) or 0}
end

local function enterPlacement(existingEntity, existingNetId)
    if placing then return end
    placing = true
    movingNetId = existingNetId

    local model = TARGET_MODEL
    if not requestModel(model) then
        placing = false
        C.notify('Nao foi possivel carregar o LIFEPAK 15. Verifique o F8: archetype ems_props.ytyp / model lifepak15.')
        return
    end

    local ghost = existingEntity
    local createdGhost = false
    if not ghost or ghost == 0 or not DoesEntityExist(ghost) then
        ghost = CreateObject(model, 0.0,0.0,0.0, false,false,false)
        createdGhost = true
    else
        NetworkRequestControlOfEntity(ghost)
        local deadline=GetGameTimer()+1000
        while not NetworkHasControlOfEntity(ghost) and GetGameTimer()<deadline do
            NetworkRequestControlOfEntity(ghost); Wait(0)
        end
        FreezeEntityPosition(ghost,false)
    end

    SetEntityCollision(ghost,false,false)
    SetEntityAlpha(ghost,175,false)
    local heading = GetEntityHeading(PlayerPedId()) + tonumber(((Config.Monitor or {}).portable or {}).defaultHeadingOffset or 180.0)
    local dist = tonumber(((Config.Monitor or {}).portable or {}).deployDistance) or 1.35
    local zOffset = 0.02

    C.notify('Posicionando LIFEPAK 15: setas ajustam, PgUp/PgDn altura, Q/E gira, ENTER confirma, BACKSPACE cancela.')

    CreateThread(function()
        local cancelled = false
        while placing and DoesEntityExist(ghost) do
            Wait(0)
            local ped=PlayerPedId()
            local p=GetEntityCoords(ped)
            local f=GetEntityForwardVector(ped)
            local right=vector3(f.y,-f.x,0.0)
            local x=p.x+f.x*dist
            local y=p.y+f.y*dist
            local z=groundZAt(x,y,p.z)+zOffset

            if IsControlPressed(0,172) then dist=math.min(2.6,dist+0.012) end
            if IsControlPressed(0,173) then dist=math.max(0.7,dist-0.012) end
            if IsControlPressed(0,174) then x=x-right.x*0.35; y=y-right.y*0.35 end
            if IsControlPressed(0,175) then x=x+right.x*0.35; y=y+right.y*0.35 end
            if IsControlPressed(0,10) then zOffset=zOffset+0.006 end
            if IsControlPressed(0,11) then zOffset=zOffset-0.006 end
            DisableControlAction(0,38,true) -- E: avoid triggering world interactions while rotating
            if IsControlPressed(0,44) then heading=heading-1.4 end
            if IsDisabledControlPressed(0,38) then heading=heading+1.4 end

            SetEntityCoordsNoOffset(ghost,x,y,z,false,false,false)
            SetEntityHeading(ghost,heading)

            BeginTextCommandDisplayHelp('STRING')
            AddTextComponentSubstringPlayerName('LIFEPAK 15 | ENTER colocar | BACKSPACE cancelar | Q/E rotacionar | Setas/PgUp/PgDn ajustar')
            EndTextCommandDisplayHelp(0,false,true,-1)

            if IsControlJustPressed(0,191) then -- ENTER
                placing=false
                local final=GetEntityCoords(ghost)
                if createdGhost then
                    DeleteEntity(ghost)
                    TriggerServerEvent('fiveems:server:portableMonitorDeploy',{x=final.x,y=final.y,z=final.z,heading=heading})
                else
                    SetEntityAlpha(ghost,255,false)
                    SetEntityCollision(ghost,true,true)
                    FreezeEntityPosition(ghost,true)
                    TriggerServerEvent('fiveems:server:portableMonitorMoved',movingNetId,{x=final.x,y=final.y,z=final.z},heading)
                end
                break
            elseif IsControlJustPressed(0,177) then -- BACKSPACE
                placing=false
                cancelled=true
                if createdGhost then DeleteEntity(ghost)
                else
                    SetEntityAlpha(ghost,255,false)
                    SetEntityCollision(ghost,true,true)
                    FreezeEntityPosition(ghost,true)
                end
                break
            end
        end
        movingNetId=nil
        SetModelAsNoLongerNeeded(model)
        if cancelled then C.notify('Posicionamento cancelado.') end
    end)
end

local function usePortableMonitor()
    if placing then return end
    -- Server validates permission + exact FiveEMS inventory metadata before
    -- we even show the placement ghost. Deploy validates again on confirm.
    TriggerServerEvent('fiveems:server:portableMonitorUseRequest')
end

RegisterNetEvent('fiveems:client:portableMonitorBeginPlacement',function()
    if placing then return end
    enterPlacement(nil,nil)
end)

RegisterNetEvent('fiveems:client:usePortableMonitor',usePortableMonitor)
exports('UsePortableMonitor',usePortableMonitor)

RegisterCommand('fiveemslifepak',function()
    usePortableMonitor()
end,false)
RegisterKeyMapping('fiveemslifepak','FiveEMS - Usar/colocar LIFEPAK 15','keyboard','F7')

RegisterCommand('fiveemslifepaktest', function()
    local model = TARGET_MODEL
    local inCd = IsModelInCdimage(model)
    local valid = IsModelValid(model)
    RequestModel(model)
    local deadline = GetGameTimer() + 3000
    while not HasModelLoaded(model) and GetGameTimer() < deadline do Wait(0) end
    local loaded = HasModelLoaded(model)

    print(('[FiveEMS][LIFEPAK TEST] hash=%s | InCdImage=%s | Valid=%s | Loaded=%s')
        :format(tostring(model), tostring(inCd), tostring(valid), tostring(loaded)))

    C.notify(('LIFEPAK TEST | CD:%s | Valido:%s | Carregado:%s')
        :format(inCd and 'SIM' or 'NAO', valid and 'SIM' or 'NAO', loaded and 'SIM' or 'NAO'))

    if loaded then SetModelAsNoLongerNeeded(model) end
end, false)

RegisterCommand('fiveemsmonitoroverlay',function()
    if not C.monitorSession or not C.monitorSession.ref then
        return C.notify('Nenhum monitor conectado nesta sessao.')
    end
    C.uiOpen=true
    C.uiContext='monitor_overlay'
    SetNuiFocus(true,true)
    pcall(function() SetNuiFocusKeepInput(false) end)
    SendNUIMessage({action='monitorOverlayFocus',data={netId=C.monitorSession.netId}})
end,false)

local function registerTarget()
    if GetResourceState('ox_target')~='started' then return end
    pcall(function() exports.ox_target:removeModel(TARGET_MODEL,{
        'fiveems_lifepak_connect','fiveems_lifepak_open','fiveems_lifepak_overlay','fiveems_lifepak_detach','fiveems_lifepak_move','fiveems_lifepak_store'
    }) end)

    exports.ox_target:addModel(TARGET_MODEL,{
        {
            name='fiveems_lifepak_connect', icon='fa-solid fa-plug', label='Conectar paciente', distance=2.5,
            canInteract=function(entity)
                local st=portableState(entity); return st and not st.connected
            end,
            onSelect=function(data)
                local entity=data.entity
                local origin=GetEntityCoords(entity)
                local maxDist=tonumber(((Config.Monitor or {}).portable or {}).maxCableDistance) or 5.5
                local ref,snapshot=nearestPatientFrom(origin,maxDist)
                if not ref then return C.notify('Nenhum paciente dentro do alcance dos cabos.') end
                TriggerServerEvent('fiveems:server:portableMonitorAttach',NetworkGetNetworkIdFromEntity(entity),ref,snapshot,'full')
            end,
        },
        {
            name='fiveems_lifepak_open', icon='fa-solid fa-wave-square', label='Abrir monitor', distance=2.5,
            canInteract=function(entity) local st=portableState(entity); return st and st.connected end,
            onSelect=function(data) TriggerServerEvent('fiveems:server:portableMonitorRequestOpen',NetworkGetNetworkIdFromEntity(data.entity),'full') end,
        },
        {
            name='fiveems_lifepak_overlay', icon='fa-solid fa-window-restore', label='Abrir em overlay', distance=2.5,
            canInteract=function(entity) local st=portableState(entity); return st and st.connected end,
            onSelect=function(data) TriggerServerEvent('fiveems:server:portableMonitorRequestOpen',NetworkGetNetworkIdFromEntity(data.entity),'overlay') end,
        },
        {
            name='fiveems_lifepak_detach', icon='fa-solid fa-link-slash', label='Desconectar paciente', distance=2.5,
            canInteract=function(entity) local st=portableState(entity); return st and st.connected end,
            onSelect=function(data) TriggerServerEvent('fiveems:server:portableMonitorDetach',NetworkGetNetworkIdFromEntity(data.entity)) end,
        },
        {
            name='fiveems_lifepak_move', icon='fa-solid fa-arrows-up-down-left-right', label='Reposicionar', distance=2.5,
            canInteract=function(entity) return portableState(entity)~=nil end,
            onSelect=function(data) enterPlacement(data.entity,NetworkGetNetworkIdFromEntity(data.entity)) end,
        },
        {
            name='fiveems_lifepak_store', icon='fa-solid fa-hand', label='Recolher LIFEPAK 15', distance=2.5,
            canInteract=function(entity) return portableState(entity)~=nil end,
            onSelect=function(data) TriggerServerEvent('fiveems:server:portableMonitorStore',NetworkGetNetworkIdFromEntity(data.entity)) end,
        },
    })
end

CreateThread(function() Wait(1800); registerTarget() end)
AddEventHandler('onClientResourceStart',function(resourceName)
    if resourceName=='ox_target' then CreateThread(function() Wait(500); registerTarget() end) end
end)

RegisterNetEvent('fiveems:client:portableMonitorDeployed',function(netId)
    C.portableMonitorNetId=tonumber(netId)
end)

RegisterNetEvent('fiveems:client:portableMonitorAttached',function(netId,ref)
    if C.monitorSession and tonumber(C.monitorSession.netId)==tonumber(netId) then
        C.monitorSession.ref=ref
    end
end)

RegisterNetEvent('fiveems:client:openPortableMonitor',function(netId,ref,snapshot,mode)
    netId=tonumber(netId)
    if not netId or type(ref)~='table' then return end
    C.monitorSession={netId=netId,ref=ref,portable=true}
    C.targetRef=ref
    C.targetServerId=ref.kind=='player' and tonumber(ref.serverId) or nil
    C.targetState=nil
    C.openUi('monitor',{targetRef=ref,targetServerId=C.targetServerId,portableMonitorNetId=netId,openMode=mode})
    TriggerServerEvent('fiveems:server:monitorRequestState',ref,snapshot or {})
end)

RegisterNetEvent('fiveems:client:portableMonitorDetached',function(netId,reason)
    netId=tonumber(netId)
    if C.monitorSession and tonumber(C.monitorSession.netId)==netId then
        C.monitorSession=nil
        C.targetRef=nil
        C.targetServerId=nil
        C.targetState=nil
        SendNUIMessage({action='portableMonitorDetached',data={netId=netId,reason=reason}})
        if reason then C.notify(reason) end
    end
end)

RegisterNetEvent('fiveems:client:portableMonitorRemoved',function(netId,reason)
    netId=tonumber(netId)
    if C.monitorSession and tonumber(C.monitorSession.netId)==netId then
        C.monitorSession=nil
        C.targetRef=nil
        C.targetServerId=nil
        C.targetState=nil
        SendNUIMessage({action='portableMonitorRemoved',data={netId=netId,reason=reason}})
    end
end)

RegisterNUICallback('monitorOverlayRelease',function(data,cb)
    if C.monitorSession then
        local leavingClinical = C.uiContext == 'patient'
        local clinicalRef = leavingClinical and C.targetRef or nil

        C.uiOpen=false
        C.uiContext='monitor_overlay'
        TriggerEvent('fiveems:client:forceClinicalSceneStop')
        SetNuiFocus(false,false)
        pcall(function() SetNuiFocusKeepInput(false) end)
        RenderScriptCams(false,false,0,true,true)
        ClearFocus()
        DisplayHud(true)
        DisplayRadar(true)

        if clinicalRef then TriggerServerEvent('fiveems:server:clinicalClose',clinicalRef) end
        C.targetRef=C.monitorSession.ref
        C.targetServerId=C.targetRef and C.targetRef.kind=='player' and tonumber(C.targetRef.serverId) or nil
        C.targetState=C.monitorState or C.targetState

        SendNUIMessage({action='monitorOverlayOnly',data={netId=C.monitorSession.netId}})
        cb({ok=true})
        return
    end
    cb({ok=false})
end)

RegisterNUICallback('monitorOverlayFocus',function(_,cb)
    if C.monitorSession then
        C.uiOpen=true
        C.uiContext='monitor_overlay'
        SetNuiFocus(true,true)
        pcall(function() SetNuiFocusKeepInput(false) end)
        SendNUIMessage({action='monitorOverlayFocus',data={}})
        cb({ok=true})
        return
    end
    cb({ok=false})
end)

-- Keep the portable monitor alive while the player is using other FiveEMS screens.
CreateThread(function()
    while true do
        if C.monitorSession and C.monitorSession.ref then
            TriggerServerEvent('fiveems:server:monitorRequestState',C.monitorSession.ref,{})
            Wait(1800)
        else
            Wait(1200)
        end
    end
end)

AddEventHandler('onResourceStop',function(resourceName)
    if resourceName~=GetCurrentResourceName() then return end
    if GetResourceState('ox_target')=='started' then
        pcall(function() exports.ox_target:removeModel(TARGET_MODEL,{
            'fiveems_lifepak_connect','fiveems_lifepak_open','fiveems_lifepak_overlay','fiveems_lifepak_detach','fiveems_lifepak_move','fiveems_lifepak_store'
        }) end)
    end
end)
