FiveEMS = FiveEMS or {}
local C = FiveEMS.Client
local worldPoints = {}
local blips = {}
local garagePeds = {}
-- V0.5.1b: cada refresh invalida qualquer thread antiga que ainda esteja
-- carregando modelo de NPC. Isso evita peds duplicados/"fantasmas".
local garagePedGeneration = 0

local function clearBlips()
    for _, b in ipairs(blips) do if DoesBlipExist(b) then RemoveBlip(b) end end
    blips = {}
end


local function clearGaragePeds()
    garagePedGeneration = garagePedGeneration + 1
    for _, ped in pairs(garagePeds) do
        if ped and DoesEntityExist(ped) then
            SetEntityAsMissionEntity(ped, true, true)
            DeleteEntity(ped)
        end
    end
    garagePeds = {}
end

local function requestPedModel(model)
    local hash = type(model) == 'number' and model or joaat(model or 's_m_m_paramedic_01')
    if not IsModelInCdimage(hash) or not IsModelValid(hash) then return nil end
    RequestModel(hash)
    local timeout = GetGameTimer() + 6000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(20) end
    if not HasModelLoaded(hash) then return nil end
    return hash
end

local function spawnGaragePed(point, generation)
    local interaction = point.data and point.data.interaction or {}
    if interaction.kind ~= 'ped' then return end

    local pointId = tonumber(point.id)
    CreateThread(function()
        local hash = requestPedModel(interaction.ped_model or 's_m_m_paramedic_01')
        if not hash then return end

        -- O mundo pode ter sido atualizado enquanto o modelo carregava.
        -- Nesse caso esta thread pertence a uma configuracao antiga e deve morrer.
        if generation ~= garagePedGeneration then
            SetModelAsNoLongerNeeded(hash)
            return
        end

        local previous = pointId and garagePeds[pointId] or nil
        if previous and DoesEntityExist(previous) then
            SetEntityAsMissionEntity(previous, true, true)
            DeleteEntity(previous)
            garagePeds[pointId] = nil
        end

        local transform = type(interaction.ped_transform) == 'table' and interaction.ped_transform or nil
        local px = transform and tonumber(transform.x) or tonumber(point.x) or 0.0
        local py = transform and tonumber(transform.y) or tonumber(point.y) or 0.0
        local pz = transform and tonumber(transform.z) or tonumber(point.z) or 0.0
        local heading = transform and tonumber(transform.rz or transform.heading) or tonumber(point.heading) or 0.0

        -- Sem Gizmo salvo, usamos exatamente o Z do ponto criado pelo player.
        -- Com Gizmo, respeitamos exatamente o transform escolhido pelo admin.
        local ped = CreatePed(4, hash, px, py, pz, heading, false, false)
        if ped ~= 0 then
            SetEntityAsMissionEntity(ped, true, true)
            SetEntityInvincible(ped, true)
            SetBlockingOfNonTemporaryEvents(ped, true)
            SetPedCanRagdoll(ped, false)

            if transform then
                SetEntityCoordsNoOffset(ped, px, py, pz, false, false, false)
                SetEntityRotation(
                    ped,
                    tonumber(transform.rx) or 0.0,
                    tonumber(transform.ry) or 0.0,
                    heading,
                    2,
                    true
                )
            else
                SetEntityCoordsNoOffset(ped, px, py, pz, false, false, false)
                SetEntityRotation(ped, 0.0, 0.0, heading, 2, true)
            end

            FreezeEntityPosition(ped, true)

            if generation ~= garagePedGeneration then
                DeleteEntity(ped)
            elseif pointId then
                garagePeds[pointId] = ped
            else
                DeleteEntity(ped)
            end
        end
        SetModelAsNoLongerNeeded(hash)
    end)
end

local function refresh()
    worldPoints = {}
    clearBlips()
    clearGaragePeds()
    local pedGeneration = garagePedGeneration

    local departments = C.worldDepartments or {}
    if #departments == 0 and C.department then
        departments = { C.department }
    end

    for _, d in ipairs(departments) do
        if d then
            if d.blip_x and d.blip_y and d.blip_z then
                local settings = d.settings or {}
                local bs = settings.blip or {}
                local blip = AddBlipForCoord(d.blip_x + 0.0, d.blip_y + 0.0, d.blip_z + 0.0)
                SetBlipSprite(blip, tonumber(bs.sprite) or 61)
                SetBlipColour(blip, tonumber(bs.color) or 2)
                SetBlipScale(blip, tonumber(bs.scale) or 0.85)
                SetBlipAsShortRange(blip, true)
                BeginTextCommandSetBlipName('STRING')
                AddTextComponentString(d.name or 'FiveEMS')
                EndTextCommandSetBlipName(blip)
                table.insert(blips, blip)
            end

            for _, point in ipairs(d.points or {}) do
                point.department_id = point.department_id or d.id
                point.department_name = point.department_name or d.name
                point.data = point.data or {}
                if point.type == FiveEMS.PointTypes.GARAGE then
                    local gb = point.data.blip or {}
                    if gb.enabled ~= false then
                        local b = AddBlipForCoord(point.x+0.0, point.y+0.0, point.z+0.0)
                        SetBlipSprite(b, tonumber(gb.sprite) or 225)
                        SetBlipColour(b, tonumber(gb.color) or 3)
                        SetBlipScale(b, tonumber(gb.scale) or 0.75)
                        SetBlipAsShortRange(b, true)
                        BeginTextCommandSetBlipName('STRING')
                        AddTextComponentString(point.label or 'Garagem')
                        EndTextCommandSetBlipName(b)
                        table.insert(blips, b)
                    end
                    spawnGaragePed(point, pedGeneration)
                end
                table.insert(worldPoints, point)
            end
        end
    end
end

AddEventHandler('fiveems:client:refreshDepartmentWorld', refresh)

local function interact(point)
    if point.type == FiveEMS.PointTypes.DUTY then
        local member = C.bootstrap and C.bootstrap.member
        TriggerServerEvent('fiveems:server:setDuty', not (member and member.on_duty))
        Wait(350)
        TriggerServerEvent('fiveems:server:requestBootstrap', C.uiContext)
    elseif point.type == FiveEMS.PointTypes.SUPPLY then
        C.openUi('stock', {pointId=point.id})
    elseif point.type == FiveEMS.PointTypes.GARAGE then
        C.openUi('garage', {pointId=point.id, departmentId=point.department_id})
    elseif point.type == FiveEMS.PointTypes.DIRECTOR then
        C.openUi('director', {pointId=point.id})
    elseif point.type == FiveEMS.PointTypes.COMPUTER then
        C.openUi('computer', {pointId=point.id})
    elseif point.type == FiveEMS.PointTypes.TABLET then
        C.openUi('tablet', {pointId=point.id})
    elseif point.type == FiveEMS.PointTypes.MONITOR then
        C.openUi('monitor', {pointId=point.id})
    elseif point.type == FiveEMS.PointTypes.LAB then
        C.openUi('csi', {mode='lab', pointId=point.id})
    elseif point.type == FiveEMS.PointTypes.EVIDENCE_LOCKER then
        C.openUi('csi', {mode='locker', pointId=point.id})
    elseif point.type == FiveEMS.PointTypes.BED or point.type == FiveEMS.PointTypes.SURGERY or point.type == FiveEMS.PointTypes.IML or point.type == FiveEMS.PointTypes.OTHER then
        -- V0.5.1: o marker do leito representa a ficha/prancheta daquele leito.
        -- Nunca abra o prontuario sem um paciente resolvido, pois isso fazia a NUI
        -- herdar o proprio profissional como alvo.
        if C.openCarePointChart then
            C.openCarePointChart(point)
        else
            C.notify('Modulo de ficha do leito ainda esta inicializando.')
        end
    end
end

CreateThread(function()
    while true do
        local wait = 900
        local ped = PlayerPedId()
        local pos = GetEntityCoords(ped)
        for _, point in ipairs(worldPoints) do
            if point.x and point.y and point.z then
                local p = vector3(point.x + 0.0, point.y + 0.0, point.z + 0.0)
                local dist = #(pos - p)
                if dist < Config.Interaction.drawDistance then
                    wait = 0
                    local drawPointMarker = true
                    local allowPointInteraction = true
                    local markerType = Config.Interaction.markerType
                    if point.type == FiveEMS.PointTypes.GARAGE then
                        local interaction = point.data and point.data.interaction or {}
                        if interaction.kind == 'ped' then
                            drawPointMarker = false
                        elseif interaction.kind == 'none' then
                            drawPointMarker = false
                            allowPointInteraction = false
                        else
                            markerType = tonumber(interaction.marker_type) or markerType
                        end
                    end
                    if drawPointMarker then
                        DrawMarker(markerType, p.x, p.y, p.z - 0.95, 0,0,0, 0,0,0, 0.35,0.35,0.25, 120,190,255,145, false,false,2,false,nil,nil,false)
                    end
                    if allowPointInteraction and dist < Config.Interaction.interactDistance then
                        BeginTextCommandDisplayHelp('STRING')
                        AddTextComponentSubstringPlayerName((point.label or point.type) .. '\n' .. _L('interact'))
                        EndTextCommandDisplayHelp(0, false, true, 1)
                        if IsControlJustPressed(0, Config.Interaction.key) then interact(point) end
                    end
                end
            end
        end
        Wait(wait)
    end
end)

AddEventHandler('fiveems:client:spawnDepartmentVehicle', function(model, garageData)
    if not model or model == '' then return end
    local hash = joaat(model)
    RequestModel(hash)
    local timeout = GetGameTimer() + 8000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(20) end
    if not HasModelLoaded(hash) then return C.notify('Modelo de veiculo invalido: '..tostring(model)) end

    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    local spawn = nil
    local spawns = garageData and garageData.data and garageData.data.spawns or nil
    if type(spawns) ~= 'table' or #spawns == 0 then
        SetModelAsNoLongerNeeded(hash)
        return C.notify('Esta garagem nao possui vagas configuradas.')
    end
    if type(spawns) == 'table' and #spawns > 0 then
        for _, s in ipairs(spawns) do
            local sx,sy,sz = tonumber(s.x),tonumber(s.y),tonumber(s.z)
            if sx and sy and sz then
                local occupied = false
                for _, other in ipairs(GetGamePool('CVehicle')) do
                    if DoesEntityExist(other) and #(GetEntityCoords(other) - vector3(sx,sy,sz)) < 2.4 then occupied = true break end
                end
                if not occupied then spawn = s break end
            end
        end
        if not spawn then
            SetModelAsNoLongerNeeded(hash)
            return C.notify('Todas as vagas desta garagem estao ocupadas.')
        end
    end

    local x,y,z,h
    if spawn then
        x,y,z,h = tonumber(spawn.x),tonumber(spawn.y),tonumber(spawn.z),tonumber(spawn.heading or spawn.rz) or 0.0
    else
        x,y,z,h = pos.x+3.0,pos.y,pos.z,heading
    end
    local veh = CreateVehicle(hash, x,y,z,h, true, false)
    if spawn then SetEntityRotation(veh, tonumber(spawn.rx) or 0.0, tonumber(spawn.ry) or 0.0, tonumber(spawn.rz or spawn.heading) or h, 2, true) end
    SetVehicleOnGroundProperly(veh)
    SetEntityAsMissionEntity(veh, true, true)
    SetModelAsNoLongerNeeded(hash)
end)

AddEventHandler('fiveems:client:storeNearestVehicle', function(model)
    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)
    local wantedHash = model and model ~= '' and joaat(model) or nil
    local best, bestDist
    for _, veh in ipairs(GetGamePool('CVehicle')) do
        if DoesEntityExist(veh) then
            local isStretcher = false
            pcall(function() isStretcher = Entity(veh).state['fiveems:stretcher'] == true end)
            if not isStretcher and (not wantedHash or GetEntityModel(veh) == wantedHash) then
                local d = #(GetEntityCoords(veh) - pos)
                if d <= 10.0 and (not bestDist or d < bestDist) then best, bestDist = veh, d end
            end
        end
    end
    if best then
        DeleteEntity(best)
        C.notify('Veiculo guardado.')
    else
        C.notify(wantedHash and 'Nenhum veiculo deste modelo esta proximo.' or 'Nenhum veiculo proximo.')
    end
end)

RegisterNetEvent('fiveems:client:spawnAuthorizedVehicle', function(model, garageData)
    TriggerEvent('fiveems:client:spawnDepartmentVehicle', model, garageData)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    clearBlips()
    clearGaragePeds()
end)
