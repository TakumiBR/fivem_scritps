FiveEMS = FiveEMS or {}
local C = FiveEMS.Client
local activeEditor = nil
local requestCounter = 0

local function deepcopy(value)
    if type(value) ~= 'table' then return value end
    local out = {}
    for k,v in pairs(value) do out[k] = deepcopy(v) end
    return out
end

local function requestModel(model)
    if not model or model == '' then return nil end
    local hash = type(model) == 'number' and model or joaat(model)
    if not IsModelInCdimage(hash) or not IsModelValid(hash) then return nil end
    RequestModel(hash)
    local timeout = GetGameTimer() + 7000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(20) end
    if not HasModelLoaded(hash) then return nil end
    return hash
end

local function normalizeAngle(a)
    a = tonumber(a) or 0.0
    while a > 180.0 do a = a - 360.0 end
    while a < -180.0 do a = a + 360.0 end
    return a
end

local function vecTransform(t, fallback)
    t = t or fallback or {}
    return {
        x=tonumber(t.x) or 0.0, y=tonumber(t.y) or 0.0, z=tonumber(t.z) or 0.0,
        rx=tonumber(t.rx) or 0.0, ry=tonumber(t.ry) or 0.0, rz=tonumber(t.rz or t.heading) or 0.0,
    }
end

local function nearestMatchingVehicle(modelName, radius)
    local ped = PlayerPedId()
    local p = GetEntityCoords(ped)
    local wanted = modelName and modelName ~= '' and joaat(modelName) or nil
    local best, bestDist
    for _,veh in ipairs(GetGamePool('CVehicle')) do
        if DoesEntityExist(veh) and (not wanted or GetEntityModel(veh) == wanted) then
            local d = #(GetEntityCoords(veh) - p)
            if d <= (radius or 12.0) and (not bestDist or d < bestDist) then best, bestDist = veh, d end
        end
    end
    return best
end

local function spawnPreviewVehicle(modelName)
    local hash = requestModel(modelName)
    if not hash then return nil end
    local ped = PlayerPedId()
    local pos = GetOffsetFromEntityInWorldCoords(ped, 0.0, 5.0, 0.0)
    local veh = CreateVehicle(hash, pos.x, pos.y, pos.z, GetEntityHeading(ped), false, false)
    if veh == 0 then return nil end
    SetEntityAsMissionEntity(veh, true, true)
    SetVehicleOnGroundProperly(veh)
    FreezeEntityPosition(veh, true)
    SetModelAsNoLongerNeeded(hash)
    return veh
end

local function spawnPreviewObject(modelName, coords, rot)
    local hash = requestModel(modelName)
    if not hash then return nil end
    local obj
    if IsModelAVehicle(hash) then
        obj = CreateVehicle(hash, coords.x, coords.y, coords.z, rot.z or 0.0, false, false)
        if obj ~= 0 then SetVehicleEngineOn(obj, false, true, true) end
    else
        obj = CreateObjectNoOffset(hash, coords.x, coords.y, coords.z, false, false, false)
    end
    if not obj or obj == 0 then return nil end
    SetEntityAsMissionEntity(obj, true, true)
    SetEntityCollision(obj, false, false)
    SetEntityRotation(obj, rot.x or 0.0, rot.y or 0.0, rot.z or 0.0, 2, true)
    FreezeEntityPosition(obj, true)
    SetModelAsNoLongerNeeded(hash)
    return obj
end

local function setPreviewExtra(entity, extraId, enabled)
    if not entity or not DoesEntityExist(entity) or not IsEntityAVehicle(entity) then return end
    extraId = tonumber(extraId)
    if not extraId or not DoesExtraExist(entity, extraId) then return end
    SetVehicleExtra(entity, extraId, enabled and 0 or 1)
end

local function applyCleanPreviewStretcher(entity, high)
    if not entity or not DoesEntityExist(entity) or not IsEntityAVehicle(entity) then return end
    local ex = (Config.Stretcher and Config.Stretcher.extras) or {}

    -- StrykerPro limpa para configuracao: sem equipamentos e com cabeceira abaixada.
    setPreviewExtra(entity, ex.backboard or 3, false)
    setPreviewExtra(entity, ex.monitor or 5, false)
    setPreviewExtra(entity, ex.redBag or 6, false)
    setPreviewExtra(entity, ex.blueBag or 7, false)
    setPreviewExtra(entity, ex.headrestA or 11, false)
    setPreviewExtra(entity, ex.headrestB or 12, true)

    -- Homologado em jogo:
    -- legA = alta/aberta; legB = baixa/recolhida.
    if high then
        setPreviewExtra(entity, ex.legA or 1, true)
        setPreviewExtra(entity, ex.legB or 2, false)
    else
        setPreviewExtra(entity, ex.legA or 1, false)
        setPreviewExtra(entity, ex.legB or 2, true)
    end
end

local function playPatientPose(ped)
    local cfg = (Config.Stretcher and Config.Stretcher.patientPose) or {}
    local dict = tostring(cfg.dict or 'anim@gangops@morgue@table@')
    local anim = tostring(cfg.anim or 'body_search')
    local phase = math.max(0.0, math.min(0.99, tonumber(cfg.phase) or 0.0))

    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 4000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < timeout do Wait(20) end
    if HasAnimDictLoaded(dict) then
        SetPedCanRagdoll(ped, false)
        TaskPlayAnim(ped, dict, anim, 8.0, -8.0, -1, 1, 0.0, false, false, false)
        Wait(0)
        SetEntityAnimCurrentTime(ped, dict, anim, phase)
        SetEntityAnimSpeed(ped, dict, anim, 0.0)
    end
end

local function spawnPreviewPatient(coords, rot)
    local hash = requestModel('a_m_m_business_01')
    if not hash then return nil end
    local ped = CreatePed(4, hash, coords.x, coords.y, coords.z, rot.z or 0.0, false, false)
    if ped == 0 then return nil end
    SetEntityAsMissionEntity(ped, true, true)
    SetEntityCollision(ped, false, false)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanRagdoll(ped, false)
    ClearPedTasksImmediately(ped)
    SetEntityRotation(ped, rot.x or 0.0, rot.y or 0.0, rot.z or 0.0, 2, true)
    playPatientPose(ped)
    Wait(0)
    -- Preview e runtime compartilham exatamente a mesma pose; o transform salvo
    -- pelo Gizmo continua sendo a unica autoridade de posicionamento.
    SetEntityCoordsNoOffset(ped, coords.x, coords.y, coords.z, false, false, false)
    SetEntityRotation(ped, rot.x or 0.0, rot.y or 0.0, rot.z or 0.0, 2, true)
    FreezeEntityPosition(ped, true)
    SetModelAsNoLongerNeeded(hash)
    return ped
end

-- V0.5.1b: preview proprio para o atendente da garagem.
-- Ele usa exatamente o mesmo ped/modelo que sera criado no runtime.
local function spawnPreviewGaragePed(modelName, coords, rot, snapToGround)
    local hash = requestModel(modelName or 's_m_m_paramedic_01')
    if not hash then return nil end

    local ped = CreatePed(4, hash, coords.x, coords.y, coords.z, rot.z or 0.0, false, false)
    if ped == 0 then
        SetModelAsNoLongerNeeded(hash)
        return nil
    end

    SetEntityAsMissionEntity(ped, true, true)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanRagdoll(ped, false)
    ClearPedTasksImmediately(ped)
    SetEntityCollision(ped, false, false)

    -- Ped nao possui PlaceEntityOnGroundProperly no FiveM.
    -- O ponto da garagem ja vem da posicao real do player; o Gizmo assume
    -- a partir daqui a autoridade total sobre Z/rotacao.
    SetEntityCoordsNoOffset(ped, coords.x, coords.y, coords.z, false, false, false)

    local p = GetEntityCoords(ped)
    SetEntityCoordsNoOffset(ped, p.x, p.y, p.z, false, false, false)
    SetEntityRotation(ped, rot.x or 0.0, rot.y or 0.0, rot.z or 0.0, 2, true)
    FreezeEntityPosition(ped, true)
    SetEntityAlpha(ped, 210, false)
    SetModelAsNoLongerNeeded(hash)
    return ped
end

local function worldTransformFromEntity(base, localT)
    local t = vecTransform(localT)
    local p = GetOffsetFromEntityInWorldCoords(base, t.x,t.y,t.z)
    local br = GetEntityRotation(base, 2)
    return vector3(p.x,p.y,p.z), vector3(br.x+t.rx, br.y+t.ry, br.z+t.rz)
end

local function localTransformFromEntity(base, worldPos, worldRot)
    local o = GetOffsetFromEntityGivenWorldCoords(base, worldPos.x,worldPos.y,worldPos.z)
    local br = GetEntityRotation(base, 2)
    return {x=o.x+0.0,y=o.y+0.0,z=o.z+0.0,rx=normalizeAngle(worldRot.x-br.x),ry=normalizeAngle(worldRot.y-br.y),rz=normalizeAngle(worldRot.z-br.z)}
end


local function nearNumber(a, b, eps)
    return math.abs((tonumber(a) or 0.0) - (tonumber(b) or 0.0)) <= (eps or 0.06)
end

local function shouldStageStretcher(mode, transform)
    transform = transform or {}
    if mode == 'inside' then
        return nearNumber(transform.x, 0.0) and nearNumber(transform.y, -2.0, 0.15) and nearNumber(transform.z, 0.2, 0.15)
    end
    return nearNumber(transform.x, 0.0) and nearNumber(transform.y, -3.0, 0.2) and nearNumber(transform.z, 0.0, 0.2)
end

local function openPreviewDoors(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end
    for door=0,5 do
        if GetIsDoorValid(vehicle, door) then SetVehicleDoorOpen(vehicle, door, false, false) end
    end
end

local function spawnGhostVehicle(modelName, coords, rot)
    local hash = requestModel(modelName)
    if not hash then return nil end
    local veh = CreateVehicle(hash, coords.x, coords.y, coords.z, rot.z or 0.0, false, false)
    if veh == 0 then return nil end
    SetEntityAsMissionEntity(veh, true, true)
    SetVehicleEngineOn(veh, false, true, true)
    SetEntityCollision(veh, false, false)
    SetEntityInvincible(veh, true)
    SetEntityAlpha(veh, 155, false)
    SetEntityRotation(veh, rot.x or 0.0, rot.y or 0.0, rot.z or 0.0, 2, true)
    FreezeEntityPosition(veh, true)
    SetModelAsNoLongerNeeded(hash)
    return veh
end

local function createAnchor(point)
    local hash = requestModel('prop_cs_cardbox_01')
    if not hash then return nil end
    local anchor = CreateObjectNoOffset(hash, point.x+0.0,point.y+0.0,point.z+0.0,false,false,false)
    SetEntityHeading(anchor, tonumber(point.heading) or 0.0)
    SetEntityVisible(anchor, false, false)
    SetEntityCollision(anchor, false, false)
    FreezeEntityPosition(anchor, true)
    SetModelAsNoLongerNeeded(hash)
    return anchor
end

local function cleanupEditor()
    if not activeEditor then return end
    for _,e in ipairs(activeEditor.cleanup or {}) do
        if e and DoesEntityExist(e) then DeleteEntity(e) end
    end
    if activeEditor.baseVehicle and DoesEntityExist(activeEditor.baseVehicle) and not activeEditor.spawnedVehicle then
        FreezeEntityPosition(activeEditor.baseVehicle, activeEditor.vehicleWasFrozen == true)
    end
    activeEditor = nil
end

local function reopenCreator()
    Wait(250)
    C.openUi('creator', {departmentId=C.department and C.department.id})
end

local function beginGizmo(entity, state)
    requestCounter = requestCounter + 1
    state.requestId = ('%d_%d'):format(GetGameTimer(), requestCounter)
    state.entity = entity
    activeEditor = state
    C.closeUi()
    TriggerEvent('fiveems:gizmo:start', json.encode({requestId=state.requestId,entity=entity}))
end

local function prepareVehicleAndStretcher(data, mode)
    local profile = deepcopy(data.profile or {})
    profile.vehicle_model = tostring(profile.vehicle_model or data.vehicle_model or 'ambulance')
    profile.stretcher_model = tostring(profile.stretcher_model or data.stretcher_model or Config.Stretcher.defaultModel or '')
    if profile.stretcher_model == '' then return C.notify('Informe o modelo da maca antes de abrir o Gizmo.') end

    local veh = nearestMatchingVehicle(profile.vehicle_model, 12.0)
    local spawned = false
    if not veh then veh = spawnPreviewVehicle(profile.vehicle_model); spawned = veh ~= nil end
    if not veh then return C.notify('Nao encontrei nem consegui criar a ambulancia de preview.') end
    local wasFrozen = IsEntityPositionFrozen(veh)
    FreezeEntityPosition(veh, true)

    local key = mode == 'inside' and 'inside_transform' or 'outside_transform'
    local configuredT = profile[key]
    -- Calcula a traseira real do modelo para que o preview sempre nasca visivel,
    -- independentemente do comprimento da ambulancia/aeronave.
    local minDim, maxDim = GetModelDimensions(GetEntityModel(veh))
    local rearY = (minDim and minDim.y or -3.5) - 1.15
    local defaultT = mode == 'inside'
        and {x=0.0,y=rearY,z=0.25,rx=0,ry=0,rz=0}
        or {x=0.0,y=rearY-0.75,z=0.05,rx=0,ry=0,rz=0}
    local startT = configuredT or defaultT
    local configuredLooksInside = false
    if configuredT and minDim and maxDim then
        local cx, cy = tonumber(configuredT.x) or 0.0, tonumber(configuredT.y) or 0.0
        configuredLooksInside = cx >= (minDim.x-0.15) and cx <= (maxDim.x+0.15) and cy >= (minDim.y-0.15) and cy <= (maxDim.y+0.15)
    end
    if shouldStageStretcher(mode, configuredT) or (mode == 'outside' and configuredLooksInside) then startT = defaultT end
    local pos, rot = worldTransformFromEntity(veh, startT)
    openPreviewDoors(veh)
    local stretcher = spawnPreviewObject(profile.stretcher_model, pos, {x=rot.x,y=rot.y,z=rot.z})
    if not stretcher then if spawned then DeleteEntity(veh) else FreezeEntityPosition(veh, wasFrozen) end return C.notify('Modelo de maca invalido.') end

    -- Preview sempre limpo. Dentro = baixa; fora = alta.
    applyCleanPreviewStretcher(stretcher, mode ~= 'inside')
    CreateThread(function()
        Wait(0)
        if stretcher and DoesEntityExist(stretcher) then applyCleanPreviewStretcher(stretcher, mode ~= 'inside') end
    end)

    local cleanup = {stretcher}
    if spawned then cleanup[#cleanup+1] = veh end
    beginGizmo(stretcher, {
        kind='stretcher_'..mode, departmentId=tonumber(data.departmentId), profile=profile,
        baseVehicle=veh, spawnedVehicle=spawned, vehicleWasFrozen=wasFrozen, cleanup=cleanup
    })
end

RegisterNUICallback('creatorGizmoStretcher', function(data, cb)
    cb({ok=true})
    local mode = tostring(data.mode or '')
    if mode == 'inside' or mode == 'outside' then
        prepareVehicleAndStretcher(data, mode)
        return
    end
    if mode ~= 'patient' then return end

    local profile = deepcopy(data.profile or {})
    profile.vehicle_model = tostring(profile.vehicle_model or data.vehicle_model or 'ambulance')
    profile.stretcher_model = tostring(profile.stretcher_model or data.stretcher_model or Config.Stretcher.defaultModel or '')
    if profile.stretcher_model == '' then return C.notify('Informe o modelo da maca antes de abrir o Gizmo.') end
    local ped = PlayerPedId()
    local basePos = GetOffsetFromEntityInWorldCoords(ped, 0.0, 2.4, -0.9)
    local stretcher = spawnPreviewObject(profile.stretcher_model, basePos, {x=0,y=0,z=GetEntityHeading(ped)})
    if not stretcher then return C.notify('Modelo de maca invalido.') end
    applyCleanPreviewStretcher(stretcher, true)
    CreateThread(function()
        Wait(0)
        if stretcher and DoesEntityExist(stretcher) then applyCleanPreviewStretcher(stretcher, true) end
    end)
    if IsEntityAVehicle(stretcher) then SetVehicleOnGroundProperly(stretcher) else PlaceObjectOnGroundProperly(stretcher) end
    FreezeEntityPosition(stretcher, true)
    local pos, rot = worldTransformFromEntity(stretcher, profile.patient_transform or (((Config.Stretcher or {}).patientPose or {}).defaultTransform or {x=0,y=0.08,z=1.12,rx=0,ry=0,rz=180}))
    local patient = spawnPreviewPatient(pos, {x=rot.x,y=rot.y,z=rot.z})
    if not patient then DeleteEntity(stretcher) return C.notify('Nao consegui criar o paciente de preview.') end
    beginGizmo(patient, {kind='stretcher_patient', departmentId=tonumber(data.departmentId), profile=profile, anchor=stretcher, cleanup={patient,stretcher}})
end)

local function startCarePointGizmo(point, departmentId)
    if not point then return C.notify('Leito/outro nao encontrado.') end
    local anchor = createAnchor(point)
    if not anchor then return C.notify('Nao consegui criar a ancora de preview.') end
    local t = point.data and point.data.patient_transform or {x=0,y=0,z=0.90,rx=0,ry=0,rz=180}
    local pos, rot = worldTransformFromEntity(anchor, t)
    local patient = spawnPreviewPatient(pos, {x=rot.x,y=rot.y,z=rot.z})
    if not patient then DeleteEntity(anchor) return C.notify('Nao consegui criar o paciente de preview.') end
    beginGizmo(patient, {kind='care_patient', departmentId=tonumber(departmentId), point=deepcopy(point), anchor=anchor, cleanup={patient,anchor}})
end

RegisterNUICallback('creatorGizmoCarePoint', function(data, cb)
    cb({ok=true})
    local pointId = tonumber(data.pointId)
    local point
    for _,p in ipairs((C.department and C.department.points) or {}) do if tonumber(p.id) == pointId then point = deepcopy(p) break end end
    startCarePointGizmo(point, tonumber(data.departmentId))
end)

RegisterNUICallback('creatorGizmoVehicleEquipment', function(data, cb)
    cb({ok=true})
    local departmentId=tonumber(data.departmentId)
    local vehicleModel=tostring(data.vehicleModel or 'ambulance')
    local root=type(data.transform)=='table' and deepcopy(data.transform) or {}
    local mode=tostring(data.mode or 'compartment')
    local veh=nearestMatchingVehicle(vehicleModel,12.0)
    local spawned=false
    if not veh then veh=spawnPreviewVehicle(vehicleModel); spawned=veh~=nil end
    if not veh then return C.notify('Nao encontrei nem consegui criar a viatura de preview.') end
    local wasFrozen=IsEntityPositionFrozen(veh); FreezeEntityPosition(veh,true); openPreviewDoors(veh)
    local minDim,maxDim=GetModelDimensions(GetEntityModel(veh))
    local rearY=(minDim and minDim.y or -3.5)-0.35
    local legacy={x=tonumber(root.x) or 0.0,y=tonumber(root.y) or rearY,z=tonumber(root.z) or 0.85,rx=tonumber(root.rx) or 0.0,ry=tonumber(root.ry) or 0.0,rz=tonumber(root.rz or root.heading) or 0.0}
    local t
    if mode=='bag' then
        t=type(root.bag)=='table' and root.bag or type(root.bag_mount)=='table' and root.bag_mount or type(root.compartment)=='table' and root.compartment or legacy
    else
        t=type(root.compartment)=='table' and root.compartment or legacy
    end
    local pos,rot=worldTransformFromEntity(veh,t)
    local previewModel
    if mode=='bag' then
        previewModel=((((Config.FieldEquipment or {}).medicalBag or {}).models or {})[1]) or 'xm_prop_x17_bag_med_01a'
    else
        previewModel=((Config.FieldEquipment or {}).vehicleCompartment or {}).previewModel or 'prop_cs_cardbox_01'
    end
    local preview=spawnPreviewObject(previewModel,pos,{x=rot.x,y=rot.y,z=rot.z})
    if not preview then preview=spawnPreviewObject('prop_cs_cardbox_01',pos,{x=rot.x,y=rot.y,z=rot.z}) end
    if not preview then if spawned then DeleteEntity(veh) else FreezeEntityPosition(veh,wasFrozen) end return C.notify('Nao consegui criar o marcador de preview do equipamento.') end
    SetEntityAlpha(preview,mode=='bag' and 230 or 110,false); SetEntityCollision(preview,false,false)
    local cleanup={preview}; if spawned then cleanup[#cleanup+1]=veh end
    local editorState={kind=mode=='bag' and 'vehicle_equipment_bag' or 'vehicle_equipment_compartment',departmentId=departmentId,vehicleModel=vehicleModel,profileTransform=root,baseVehicle=veh,spawnedVehicle=spawned,vehicleWasFrozen=wasFrozen,cleanup=cleanup}
    beginGizmo(preview,editorState)

    -- Para o compartimento, o prop e apenas a ancora manipulavel do Gizmo.
    -- O que o usuario enxerga como referencia e o volume 3D real salvo no perfil.
    if mode~='bag' then
        local defaults=((Config.FieldEquipment or {}).vehicleCompartment or {}).defaultSize or {x=1.2,y=1.0,z=1.1}
        local configuredSize=(type(root.zone)=='table' and type(root.zone.size)=='table') and root.zone.size or defaults
        local sx=math.max(0.25,tonumber(configuredSize.x) or 1.2)
        local sy=math.max(0.25,tonumber(configuredSize.y) or 1.0)
        local sz=math.max(0.25,tonumber(configuredSize.z) or 1.1)
        CreateThread(function()
            while activeEditor==editorState and preview and DoesEntityExist(preview) do
                Wait(0)
                local p=GetEntityCoords(preview)
                local r=GetEntityRotation(preview,2)
                DrawMarker(1,p.x,p.y,p.z,0.0,0.0,0.0,r.x,r.y,r.z,sx,sy,sz,55,180,255,75,false,false,2,false,nil,nil,false)
            end
        end)
    end
end)

RegisterNUICallback('creatorSaveVehicleEquipmentLayout', function(data, cb)
    cb({ok=true})
    local departmentId=tonumber(data.departmentId)
    local vehicleModel=tostring(data.vehicleModel or 'ambulance')
    if not departmentId or vehicleModel=='' then return end
    TriggerServerEvent('fiveems:server:saveVehicleEquipmentProfile',departmentId,{vehicle_model=vehicleModel,transform=type(data.transform)=='table' and data.transform or {},enabled=true})
    C.notify('Dimensoes da area do Compartimento EMS salvas.')
end)

RegisterNUICallback('creatorCreateCarePoint', function(data, cb)
    local departmentId = tonumber(data.departmentId)
    local pointType = tostring(data.type or 'bed')
    local label = tostring(data.label or 'Leito')
    local allowed = {bed=true,surgery=true,iml=true,other=true}
    if not departmentId or not allowed[pointType] then cb({ok=false}) return end
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    TriggerServerEvent('fiveems:server:createCarePoint', departmentId, {
        type=pointType, label=label, x=coords.x, y=coords.y, z=coords.z,
        heading=GetEntityHeading(ped), data={patient_transform={x=0.0,y=0.0,z=0.90,rx=0.0,ry=0.0,rz=180.0}}
    })
    cb({ok=true})
end)

RegisterNetEvent('fiveems:client:carePointCreated', function(department, pointId)
    if type(department) == 'table' then
        C.department = department
        if C.bootstrap then C.bootstrap.department = department end
        TriggerEvent('fiveems:client:refreshDepartmentWorld')
    end
    local point
    for _,p in ipairs((department and department.points) or {}) do
        if tonumber(p.id) == tonumber(pointId) then point = deepcopy(p) break end
    end
    if not point then return C.notify('Leito/outro criado, mas nao consegui abrir o Gizmo automaticamente.') end
    startCarePointGizmo(point, department.id)
end)


local function findDepartmentPoint(pointId)
    for _,p in ipairs((C.department and C.department.points) or {}) do
        if tonumber(p.id) == tonumber(pointId) then return deepcopy(p) end
    end
    return nil
end

local function startGaragePedGizmo(point, departmentId, pedModel)
    if not point or point.type ~= 'garage' then
        return C.notify('Garagem nao encontrada.')
    end

    point.data = point.data or {}
    point.data.interaction = point.data.interaction or {}
    local interaction = point.data.interaction
    local model = tostring(pedModel or interaction.ped_model or 's_m_m_paramedic_01')
    if model == '' then model = 's_m_m_paramedic_01' end

    local configured = type(interaction.ped_transform) == 'table' and interaction.ped_transform or nil
    local coords = vector3(
        configured and (tonumber(configured.x) or point.x) or point.x,
        configured and (tonumber(configured.y) or point.y) or point.y,
        configured and (tonumber(configured.z) or point.z) or point.z
    )
    local rot = {
        x = configured and tonumber(configured.rx) or 0.0,
        y = configured and tonumber(configured.ry) or 0.0,
        z = configured and tonumber(configured.rz or configured.heading) or tonumber(point.heading) or 0.0
    }

    local preview = spawnPreviewGaragePed(model, coords, rot, configured == nil)
    if not preview then return C.notify('Modelo de NPC invalido: '..model) end

    -- Se foi assentado automaticamente no chao, o Gizmo deve iniciar da
    -- posicao realmente corrigida do preview.
    local p = GetEntityCoords(preview)
    local r = GetEntityRotation(preview, 2)
    SetEntityCoordsNoOffset(preview, p.x, p.y, p.z, false, false, false)
    SetEntityRotation(preview, r.x, r.y, r.z, 2, true)

    beginGizmo(preview, {
        kind='garage_ped',
        departmentId=tonumber(departmentId),
        point=point,
        pedModel=model,
        cleanup={preview},
    })
end

RegisterNUICallback('creatorGizmoGaragePed', function(data, cb)
    cb({ok=true})
    local point = findDepartmentPoint(data.pointId)
    if not point then return C.notify('Garagem nao encontrada.') end
    startGaragePedGizmo(point, tonumber(data.departmentId), data.pedModel)
end)

-- Ao criar uma garagem ja como Ped/NPC, abre o Gizmo automaticamente.
RegisterNetEvent('fiveems:client:garagePointCreated', function(department, pointId)
    if type(department) == 'table' then
        C.department = department
        if C.bootstrap then C.bootstrap.department = department end
        TriggerEvent('fiveems:client:refreshDepartmentWorld')
    end

    local point
    for _, p in ipairs((department and department.points) or {}) do
        if tonumber(p.id) == tonumber(pointId) then
            point = deepcopy(p)
            break
        end
    end

    if not point then return end
    local interaction = point.data and point.data.interaction or {}
    if interaction.kind == 'ped' then
        Wait(100)
        startGaragePedGizmo(point, department.id, interaction.ped_model)
    end
end)

RegisterNUICallback('creatorGizmoGarageSpawn', function(data, cb)
    cb({ok=true})
    local point = findDepartmentPoint(data.pointId)
    if not point or point.type ~= 'garage' then return C.notify('Garagem nao encontrada.') end
    point.data = point.data or {}
    point.data.spawns = point.data.spawns or {}
    local spawnIndex = tonumber(data.spawnIndex)
    local existing = spawnIndex and point.data.spawns[spawnIndex] or nil
    local model = tostring(data.previewModel or point.data.preview_model or '')
    if model == '' then model = 'ambulance' end

    local coords, rot
    if existing then
        coords = vector3(tonumber(existing.x) or point.x, tonumber(existing.y) or point.y, tonumber(existing.z) or point.z)
        rot = {x=tonumber(existing.rx) or 0.0,y=tonumber(existing.ry) or 0.0,z=tonumber(existing.rz or existing.heading) or point.heading or 0.0}
    else
        local ped = PlayerPedId()
        local pos = GetOffsetFromEntityInWorldCoords(ped, 0.0, 4.0, 0.0)
        coords = vector3(pos.x,pos.y,pos.z)
        rot = {x=0.0,y=0.0,z=GetEntityHeading(ped)}
    end

    local veh = spawnGhostVehicle(model, coords, rot)
    if not veh then return C.notify('Modelo de preview invalido: '..model) end
    beginGizmo(veh, {
        kind='garage_spawn', departmentId=tonumber(data.departmentId), point=point,
        spawnIndex=spawnIndex, previewModel=model, cleanup={veh}
    })
end)

RegisterNUICallback('creatorDeleteGarageSpawn', function(data, cb)
    local point = findDepartmentPoint(data.pointId)
    local index = tonumber(data.spawnIndex)
    if not point or not index then cb({ok=false}) return end
    point.data = point.data or {}
    point.data.spawns = point.data.spawns or {}
    table.remove(point.data.spawns, index)
    point.data.garage_configured = #point.data.spawns > 0
    TriggerServerEvent('fiveems:server:savePoint', tonumber(data.departmentId), point)
    cb({ok=true})
end)

AddEventHandler('fiveems:gizmo:result', function(payloadJson)
    local ok, result = pcall(json.decode, payloadJson or '{}')
    if not ok or not activeEditor or tostring(result.requestId) ~= tostring(activeEditor.requestId) then return end
    local state = activeEditor
    if result.cancelled or not result.confirmed or not result.position or not result.rotation then
        cleanupEditor()
        C.notify('Edicao 3D cancelada.')
        reopenCreator()
        return
    end
    local wp = vector3(result.position.x+0.0,result.position.y+0.0,result.position.z+0.0)
    local wr = vector3(result.rotation.x+0.0,result.rotation.y+0.0,result.rotation.z+0.0)

    if state.kind == 'stretcher_inside' or state.kind == 'stretcher_outside' then
        local key = state.kind == 'stretcher_inside' and 'inside_transform' or 'outside_transform'
        state.profile[key] = localTransformFromEntity(state.baseVehicle, wp, wr)
        TriggerServerEvent('fiveems:server:saveStretcherProfile', state.departmentId, state.profile)
        C.notify(key == 'inside_transform' and 'Posicao da maca dentro da ambulancia salva.' or 'Posicao de retirada da maca salva.')
    elseif state.kind == 'stretcher_patient' then
        state.profile.patient_transform = localTransformFromEntity(state.anchor, wp, wr)
        TriggerServerEvent('fiveems:server:saveStretcherProfile', state.departmentId, state.profile)
        C.notify('Posicao do paciente Player/NPC sobre a maca salva.')
    elseif state.kind == 'garage_spawn' then
        state.point.data = state.point.data or {}
        state.point.data.spawns = state.point.data.spawns or {}
        local spawn = {x=wp.x+0.0,y=wp.y+0.0,z=wp.z+0.0,rx=wr.x+0.0,ry=wr.y+0.0,rz=wr.z+0.0,heading=wr.z+0.0,preview_model=state.previewModel}
        if state.spawnIndex and state.point.data.spawns[state.spawnIndex] then
            state.point.data.spawns[state.spawnIndex] = spawn
        else
            table.insert(state.point.data.spawns, spawn)
        end
        state.point.data.preview_model = state.previewModel
        state.point.data.garage_configured = #state.point.data.spawns > 0
        TriggerServerEvent('fiveems:server:savePoint', state.departmentId, state.point)
        C.notify('Vaga da garagem salva com o 3D Gizmo.')
    elseif state.kind == 'garage_ped' then
        state.point.data = state.point.data or {}
        state.point.data.interaction = state.point.data.interaction or {}
        state.point.data.interaction.kind = 'ped'
        state.point.data.interaction.ped_model = state.pedModel or state.point.data.interaction.ped_model or 's_m_m_paramedic_01'
        state.point.data.interaction.ped_transform = {
            x=wp.x+0.0, y=wp.y+0.0, z=wp.z+0.0,
            rx=wr.x+0.0, ry=wr.y+0.0, rz=wr.z+0.0
        }

        -- O ponto interativo acompanha o NPC. Assim E/distancia/blip e o ped
        -- ficam todos no mesmo lugar escolhido no Gizmo.
        state.point.x, state.point.y, state.point.z = wp.x+0.0, wp.y+0.0, wp.z+0.0
        state.point.heading = wr.z+0.0

        TriggerServerEvent('fiveems:server:savePoint', state.departmentId, state.point)
        C.notify('NPC da garagem posicionado com o 3D Gizmo.')
    elseif state.kind == 'vehicle_equipment_compartment' or state.kind == 'vehicle_equipment_bag' then
        local localTransform=localTransformFromEntity(state.baseVehicle,wp,wr)
        local root=type(state.profileTransform)=='table' and deepcopy(state.profileTransform) or {}
        -- Migra automaticamente perfis antigos (x/y/z na raiz) para a estrutura
        -- V0.4.11 sem perder compatibilidade.
        if type(root.compartment)~='table' then
            root.compartment={x=tonumber(root.x) or 0.0,y=tonumber(root.y) or -2.5,z=tonumber(root.z) or 0.8,rx=tonumber(root.rx) or 0.0,ry=tonumber(root.ry) or 0.0,rz=tonumber(root.rz or root.heading) or 0.0}
        end
        if type(root.bag)~='table' then root.bag=deepcopy(root.compartment) end
        root.zone=type(root.zone)=='table' and root.zone or {}
        root.zone.size=type(root.zone.size)=='table' and root.zone.size or deepcopy(((Config.FieldEquipment or {}).vehicleCompartment or {}).defaultSize or {x=1.2,y=1.0,z=1.1})

        if state.kind == 'vehicle_equipment_bag' then
            root.bag=localTransform
            C.notify('Posicao fisica da bolsa medica salva para '..tostring(state.vehicleModel)..'.')
        else
            root.compartment=localTransform
            C.notify('Centro da area do Compartimento EMS salvo para '..tostring(state.vehicleModel)..'.')
        end
        TriggerServerEvent('fiveems:server:saveVehicleEquipmentProfile',state.departmentId,{vehicle_model=state.vehicleModel,transform=root,enabled=true})
    elseif state.kind == 'care_patient' then
        state.point.data = state.point.data or {}
        state.point.data.patient_transform = localTransformFromEntity(state.anchor, wp, wr)
        TriggerServerEvent('fiveems:server:savePoint', state.departmentId, state.point)
        C.notify('Posicao do paciente no leito/outro salva.')
    end

    cleanupEditor()
    reopenCreator()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    cleanupEditor()
end)
