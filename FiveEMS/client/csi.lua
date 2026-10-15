FiveEMS = FiveEMS or {}
local C = FiveEMS.Client
local evidence = {}
local npcEvidencePending = {}

RegisterNetEvent('fiveems:client:csiEvidenceCreated', function(e)
    if not e or not e.id then return end
    evidence[e.id] = e
end)

RegisterNetEvent('fiveems:client:csiEvidenceUpdated', function(e)
    if not e or not e.id then return end
    evidence[e.id] = e
    SendNUIMessage({action='csiEvidenceUpdated', data=e})
end)

RegisterNetEvent('fiveems:client:csiLabResult', function(e)
    SendNUIMessage({action='csiLabResult', data=e})
    if not C.uiOpen then C.openUi('csi', {mode='labResult'}) end
end)

RegisterNetEvent('fiveems:client:csiCaseCreated', function(id)
    C.notify('Caso pericial criado: #'..tostring(id))
end)

RegisterNUICallback('csiCollect', function(data, cb)
    TriggerServerEvent('fiveems:server:csiCollect', tonumber(data.evidenceId), data.notes)
    cb({ok=true})
end)

RegisterNUICallback('csiAnalyze', function(data, cb)
    TriggerServerEvent('fiveems:server:csiAnalyze', tonumber(data.evidenceId))
    cb({ok=true})
end)

RegisterNUICallback('csiCreateCase', function(data, cb)
    TriggerServerEvent('fiveems:server:csiCreateCase', data)
    cb({ok=true})
end)

RegisterNUICallback('csiCloseCase', function(data, cb)
    TriggerServerEvent('fiveems:server:csiCloseCase', tonumber(data.caseId), data.report)
    cb({ok=true})
end)

local function draw3dText(x,y,z,text)
    SetDrawOrigin(x,y,z,0)
    SetTextScale(0.28,0.28)
    SetTextFont(0)
    SetTextProportional(1)
    SetTextColour(255,255,255,200)
    SetTextCentre(true)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0,0)
    ClearDrawOrigin()
end

CreateThread(function()
    while true do
        local wait = 900
        local pos = GetEntityCoords(PlayerPedId())
        for id, e in pairs(evidence) do
            if e.state == 'scene' and e.x and e.y and e.z then
                local p = vector3(e.x+0.0,e.y+0.0,e.z+0.0)
                local dist = #(pos-p)
                if dist < 20.0 then
                    wait = 0
                    DrawMarker(28,p.x,p.y,p.z+0.08,0,0,0,0,0,0,0.08,0.08,0.08,255,210,80,150,false,false,2,false,nil,nil,false)
                    if dist < 1.5 then
                        draw3dText(p.x,p.y,p.z+0.25,('[E] Evidencia #%s | %s'):format(id,e.type or 'trace'))
                        if IsControlJustPressed(0,38) then
                            C.openUi('csi', {mode='scene', evidence=e})
                        end
                    end
                end
            end
        end
        Wait(wait)
    end
end)

CreateThread(function()
    while true do
        Wait(700)
        if Config.CSI.createEvidenceFromNpcDamage then
            local ped = PlayerPedId()
            local pos = GetEntityCoords(ped)
            local handle, npc = FindFirstPed()
            local success = true
            repeat
                if npc ~= 0 and npc ~= ped and not IsPedAPlayer(npc) and DoesEntityExist(npc) and IsEntityDead(npc) then
                    local npos = GetEntityCoords(npc)
                    local netId = NetworkGetEntityIsNetworked(npc) and NetworkGetNetworkIdFromEntity(npc) or 0
                    local key = netId > 0 and ('net:'..netId) or ('local:'..npc)
                    local stateLogged = false
                    if netId > 0 then
                        local okState, value = pcall(function() return Entity(npc).state.fiveemsCsiLogged end)
                        stateLogged = okState and value == true
                    end

                    if #(npos-pos) < 45.0 and not stateLogged and not npcEvidencePending[key] then
                        -- NUNCA escreve StateBag no client. Com sv_stateBagStrictMode isso gera warning
                        -- e a escrita falha, fazendo o loop repetir a cada 700ms.
                        npcEvidencePending[key] = GetGameTimer()

                        local ok,bone = GetPedLastDamageBone(npc)
                        TriggerServerEvent('fiveems:server:csiNpcEvidence', {
                            type='body_trace', x=npos.x,y=npos.y,z=npos.z,
                            category='unknown', weapon=GetPedCauseOfDeath(npc), bone=ok and bone or 0,
                            metadata={pedModel=GetEntityModel(npc), networkId=netId}
                        })
                    end
                end
                success, npc = FindNextPed(handle)
            until not success
            EndFindPed(handle)
        end
    end
end)


CreateThread(function()
    while true do
        Wait(30000)
        local now = GetGameTimer()
        for key, startedAt in pairs(npcEvidencePending) do
            if now - (startedAt or 0) > 120000 then
                npcEvidencePending[key] = nil
            end
        end
    end
end)
