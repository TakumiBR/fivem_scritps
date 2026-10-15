FiveEMS = FiveEMS or {}
local C = FiveEMS.Client
local monitorOpen = false

local function nearestClinicalPatient(maxDist)
    local playerPed = PlayerPedId()
    local pos = GetEntityCoords(playerPed)
    local bestRef, bestSnapshot, bestDist

    -- Players
    for _, player in ipairs(GetActivePlayers()) do
        if player ~= PlayerId() then
            local ped = GetPlayerPed(player)
            if ped ~= 0 and DoesEntityExist(ped) then
                local dist = #(GetEntityCoords(ped) - pos)
                if dist <= (maxDist or 3.5) and (not bestDist or dist < bestDist) then
                    bestRef = {kind='player', serverId=GetPlayerServerId(player)}
                    bestSnapshot = {}
                    bestDist = dist
                end
            end
        end
    end

    -- NPCs
    for _, ped in ipairs(GetGamePool('CPed')) do
        if ped ~= playerPed and DoesEntityExist(ped) and not IsPedAPlayer(ped) and IsPedHuman(ped) then
            local dist = #(GetEntityCoords(ped) - pos)
            if dist <= (maxDist or 3.5) and (not bestDist or dist < bestDist) then
                local netId = C.ensureNpcNetId and C.ensureNpcNetId(ped) or nil
                if netId then
                    bestRef = {kind='npc', netId=netId}
                    bestSnapshot = C.snapshotNpc and C.snapshotNpc(ped) or {}
                    bestDist = dist
                end
            end
        end
    end

    return bestRef, bestSnapshot, bestDist
end

local function requestClinicalState(ref, snapshot)
    if type(ref) ~= 'table' then return false end
    C.targetRef = ref
    C.targetServerId = ref.kind == 'player' and tonumber(ref.serverId) or nil
    TriggerServerEvent('fiveems:server:monitorRequestState', ref, snapshot or {})
    return true
end


local TARGET_MONITOR_PLAYER = 'fiveems_monitor_player'
local TARGET_MONITOR_NPC = 'fiveems_monitor_npc'

local function registerMonitorTargets()
    if GetResourceState('ox_target') ~= 'started' then return end

    pcall(function() exports.ox_target:removeGlobalPlayer(TARGET_MONITOR_PLAYER) end)
    pcall(function() exports.ox_target:removeGlobalPed(TARGET_MONITOR_NPC) end)

    pcall(function()
        exports.ox_target:addGlobalPlayer({
            {
                name=TARGET_MONITOR_PLAYER,
                icon='fa-solid fa-wave-square',
                label='Conectar monitor multiparametrico',
                distance=2.5,
                canInteract=function(entity)
                    return entity and entity~=PlayerPedId() and DoesEntityExist(entity)
                end,
                onSelect=function(data)
                    local playerIndex=NetworkGetPlayerIndexFromPed(data.entity)
                    if playerIndex == -1 then return C.notify('Player nao sincronizado.') end
                    local ref={kind='player',serverId=GetPlayerServerId(playerIndex)}
                    C.targetState=nil
                    C.monitorSession={ref=ref,portable=false}
                    C.openUi('monitor',{targetRef=ref,targetServerId=ref.serverId})
                    requestClinicalState(ref,{})
                    monitorOpen=true
                end,
            }
        })
    end)

    pcall(function()
        exports.ox_target:addGlobalPed({
            {
                name=TARGET_MONITOR_NPC,
                icon='fa-solid fa-wave-square',
                label='Conectar monitor multiparametrico',
                distance=2.5,
                canInteract=function(entity)
                    return entity and entity~=PlayerPedId() and DoesEntityExist(entity)
                        and not IsPedAPlayer(entity) and IsPedHuman(entity)
                end,
                onSelect=function(data)
                    local ped=data.entity
                    local netId=C.ensureNpcNetId and C.ensureNpcNetId(ped) or nil
                    if not netId then return C.notify('NPC sem Network ID valido.') end
                    local ref={kind='npc',netId=netId}
                    local snapshot=C.snapshotNpc and C.snapshotNpc(ped) or {}
                    C.targetState=nil
                    C.monitorSession={ref=ref,portable=false}
                    C.openUi('monitor',{targetRef=ref})
                    requestClinicalState(ref,snapshot)
                    monitorOpen=true
                end,
            }
        })
    end)
end

CreateThread(function()
    Wait(1800)
    registerMonitorTargets()
end)

AddEventHandler('onClientResourceStart',function(resourceName)
    if resourceName=='ox_target' then
        CreateThread(function() Wait(500); registerMonitorTargets() end)
    end
end)

RegisterNetEvent('fiveems:client:openMonitor', function(targetSrc)
    if targetSrc then
        local ref = {kind='player', serverId=tonumber(targetSrc)}
        C.targetState = nil
        C.monitorSession={ref=ref,portable=false}
        C.openUi('monitor', {targetRef=ref, targetServerId=ref.serverId})
        requestClinicalState(ref, {})
    else
        C.targetRef = nil
        C.targetServerId = nil
        C.targetState = nil
        C.monitorSession=nil
        C.openUi('monitor', {})
    end
    monitorOpen = true
end)

RegisterNUICallback('monitorRefresh', function(_, cb)
    if C.targetRef then
        requestClinicalState(C.targetRef, {})
    elseif C.targetServerId then
        requestClinicalState({kind='player',serverId=C.targetServerId}, {})
    end
    cb({ok=true})
end)

RegisterNUICallback('monitorAttachNearest', function(_, cb)
    local ref, snapshot = nearestClinicalPatient(4.0)
    if not ref then
        C.notify('Nenhum paciente proximo para conectar ao monitor.')
        cb({ok=false})
        return
    end

    C.targetState = nil
    C.monitorSession={ref=ref,portable=false}
    requestClinicalState(ref, snapshot)
    cb({ok=true, targetRef=ref, targetServerId=ref.kind=='player' and ref.serverId or nil})
end)

RegisterNUICallback('monitorAttachById', function(data, cb)
    local target = tonumber(data and data.targetServerId)
    if not target then
        cb({ok=false})
        return
    end

    local ref = {kind='player', serverId=target}
    C.targetState = nil
    C.monitorSession={ref=ref,portable=false}
    requestClinicalState(ref, {})
    cb({ok=true, targetRef=ref, targetServerId=target})
end)

RegisterNUICallback('monitorDetach', function(_, cb)
    if C.monitorSession and C.monitorSession.portable and C.monitorSession.netId then
        TriggerServerEvent('fiveems:server:portableMonitorDetach', C.monitorSession.netId)
    elseif C.targetRef then
        TriggerServerEvent('fiveems:server:clinicalClose', C.targetRef)
    end
    C.monitorSession = nil
    C.targetRef = nil
    C.targetServerId = nil
    C.targetState = nil
    SendNUIMessage({action='monitorDetached', data={}})
    cb({ok=true})
end)

RegisterNUICallback('monitorClose', function(_, cb)
    monitorOpen = false
    if C.targetRef and not (C.monitorSession and C.monitorSession.portable) then
        TriggerServerEvent('fiveems:server:clinicalClose', C.targetRef)
    end
    C.targetRef = nil
    C.targetServerId = nil
    C.targetState = nil
    C.monitorSession = nil
    C.closeUi()
    cb({ok=true})
end)


AddEventHandler('onResourceStop',function(resourceName)
    if resourceName~=GetCurrentResourceName() then return end
    if GetResourceState('ox_target')~='started' then return end
    pcall(function() exports.ox_target:removeGlobalPlayer(TARGET_MONITOR_PLAYER) end)
    pcall(function() exports.ox_target:removeGlobalPed(TARGET_MONITOR_NPC) end)
end)
