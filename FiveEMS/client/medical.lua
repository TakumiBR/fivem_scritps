FiveEMS = FiveEMS or {}
local C = FiveEMS.Client
local cprActive = false
local cprTarget = nil
local cprPresses = {}

local function nearestPlayer(maxDist)
    local playerPed = PlayerPedId()
    local pos = GetEntityCoords(playerPed)
    local best, bestDist
    for _, player in ipairs(GetActivePlayers()) do
        if player ~= PlayerId() then
            local ped = GetPlayerPed(player)
            local dist = #(GetEntityCoords(ped) - pos)
            if dist <= (maxDist or 3.0) and (not bestDist or dist < bestDist) then
                best = GetPlayerServerId(player)
                bestDist = dist
            end
        end
    end
    return best, bestDist
end

RegisterNetEvent('fiveems:client:commandNearestPatient', function(context)
    local target = nearestPlayer(3.0)
    if not target then
        return C.notify(context == 'monitor' and 'Nenhum paciente proximo.' or 'Nenhum player proximo para atendimento.')
    end
    TriggerServerEvent('fiveems:server:requestOperationalOpen', context == 'monitor' and 'monitor' or 'patient', target)
end)

RegisterNetEvent('fiveems:client:authorizedOperationalOpen', function(context, target)
    target = tonumber(target)
    if not target then return end

    C.targetRef = {kind='player', serverId=target}
    C.targetServerId = target
    C.openUi(context == 'monitor' and 'monitor' or 'patient', {targetRef=C.targetRef,targetServerId=target})
    if context == 'monitor' then
        TriggerServerEvent('fiveems:server:monitorRequestState', C.targetRef, {})
    else
        TriggerServerEvent('fiveems:server:clinicalRequestState', C.targetRef, {})
    end
end)

RegisterNetEvent('fiveems:client:defibAnalysis', function(targetSrc, rhythm, shockable)
    SendNUIMessage({action='defibAnalysis', data={targetServerId=targetSrc, rhythm=rhythm, shockable=shockable}})
end)

local function ensureAnim(dict)
    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 4000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < timeout do Wait(20) end
    return HasAnimDictLoaded(dict)
end

local function prunePresses()
    local now = GetGameTimer()
    local kept = {}
    for _, t in ipairs(cprPresses) do
        if now - t <= 10000 then table.insert(kept, t) end
    end
    cprPresses = kept
end

local function cprQuality()
    prunePresses()
    if #cprPresses < 3 then return 0.0, 0 end
    local durationMs = math.max(1, cprPresses[#cprPresses] - cprPresses[1])
    local rate = ((#cprPresses - 1) / durationMs) * 60000.0
    local rateQuality = 1.0 - math.min(1.0, math.abs(rate - 110.0) / 60.0)
    local variance = 0.0
    local expected = 60000.0 / math.max(1.0, rate)
    for i=2, #cprPresses do
        variance = variance + math.abs((cprPresses[i] - cprPresses[i-1]) - expected)
    end
    variance = variance / math.max(1, #cprPresses - 1)
    local rhythmQuality = 1.0 - math.min(1.0, variance / 420.0)
    return math.max(0.0, math.min(1.0, rateQuality * 0.65 + rhythmQuality * 0.35)), math.floor(rate + 0.5)
end

AddEventHandler('fiveems:client:startCPR', function(target)
    if cprActive then return end
    cprActive = true
    cprTarget = tonumber(target)
    cprPresses = {}
    C.closeUi()
    C.notify('RCP iniciada. Pressione E acompanhando o ritmo de 100-120 compressões/min. Pressione X para encerrar.')

    local ped = PlayerPedId()
    if ensureAnim('mini@cpr@char_a@cpr_str') then
        TaskPlayAnim(ped, 'mini@cpr@char_a@cpr_str', 'cpr_pumpchest', 8.0, -8.0, -1, 1, 0.0, false, false, false)
    end
end)

AddEventHandler('fiveems:client:stopCPR', function()
    cprActive = false
    cprTarget = nil
    cprPresses = {}
    ClearPedTasks(PlayerPedId())
end)

CreateThread(function()
    local lastSync = 0
    while true do
        if cprActive and cprTarget then
            Wait(0)
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            if IsControlJustPressed(0, 38) then
                table.insert(cprPresses, GetGameTimer())
                local q, rate = cprQuality()
                BeginTextCommandDisplayHelp('STRING')
                AddTextComponentSubstringPlayerName(('RCP | ritmo: %d/min | qualidade: %d%% | X encerra'):format(rate, math.floor(q*100)))
                EndTextCommandDisplayHelp(0, false, false, 1)
            end
            if IsControlJustPressed(0, 73) then
                TriggerEvent('fiveems:client:stopCPR')
            end
            if GetGameTimer() - lastSync > 2500 then
                local q = cprQuality()
                TriggerServerEvent('fiveems:server:cprCycle', cprTarget, q)
                lastSync = GetGameTimer()
            end
        else
            Wait(400)
        end
    end
end)

local carePointPinned = false

local function carePointPose()
    local cfg=(Config.Stretcher and Config.Stretcher.patientPose) or {}
    return tostring(cfg.dict or 'anim@gangops@morgue@table@'),
        tostring(cfg.anim or 'body_search')
end

local function loadCarePointPose()
    local dict,anim=carePointPose()
    RequestAnimDict(dict)
    local timeout=GetGameTimer()+4000
    while not HasAnimDictLoaded(dict) and GetGameTimer()<timeout do Wait(20) end
    return HasAnimDictLoaded(dict),dict,anim
end

local function carePointWorldTransform(point)
    local t=(point.data and point.data.patient_transform) or {}
    local heading=tonumber(point.heading) or 0.0
    local rad=math.rad(heading)
    local lx,ly=tonumber(t.x) or 0.0,tonumber(t.y) or 0.0
    local wx=(tonumber(point.x) or 0.0)+(lx*math.cos(rad))-(ly*math.sin(rad))
    local wy=(tonumber(point.y) or 0.0)+(lx*math.sin(rad))+(ly*math.cos(rad))
    local wz=(tonumber(point.z) or 0.0)+(tonumber(t.z) or 0.90)
    return vector3(wx,wy,wz),vector3(tonumber(t.rx) or 0.0,tonumber(t.ry) or 0.0,heading+(tonumber(t.rz or t.heading) or 0.0))
end

RegisterNetEvent('fiveems:client:placeOnCarePoint', function(point)
    if not point then return end
    local ped=PlayerPedId()
    local pos,rot=carePointWorldTransform(point)
    local loaded,dict,anim=loadCarePointPose()

    carePointPinned=true
    ClearPedTasksImmediately(ped)
    SetPedCanRagdoll(ped,false)
    SetEntityCollision(ped,false,false)

    local function pin()
        if not carePointPinned or not DoesEntityExist(ped) then return end
        SetEntityCoordsNoOffset(ped,pos.x,pos.y,pos.z,false,false,false)
        SetEntityRotation(ped,rot.x,rot.y,rot.z,2,true)
        SetEntityCollision(ped,false,false)
        SetPedCanRagdoll(ped,false)
        FreezeEntityPosition(ped,true)
    end

    pin()
    FreezeEntityPosition(ped,false)
    if loaded then
        TaskPlayAnim(ped,dict,anim,8.0,-8.0,-1,1,0.0,false,false,false)
    end
    pin()

    -- FiveFD ANCHOR: a animacao full-body pode aplicar root offset nos primeiros frames.
    CreateThread(function()
        for _,delay in ipairs({50,150,350,700}) do
            Wait(delay)
            pin()
        end
    end)
end)

RegisterNetEvent('fiveems:client:releaseCarePoint', function()
    carePointPinned=false
    local ped=PlayerPedId()
    FreezeEntityPosition(ped,false)
    ClearPedTasksImmediately(ped)
    SetPedCanRagdoll(ped,true)
    SetEntityCollision(ped,true,true)
end)
