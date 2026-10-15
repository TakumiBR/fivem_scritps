FiveEMS = FiveEMS or {}
local C = FiveEMS.Client

local bagCfg = ((Config.FieldEquipment or {}).medicalBag or {})
local vehicleCfg = ((Config.FieldEquipment or {}).vehicleCompartment or {})
local placingBag = false
local carryingMedicalBag = false
local carriedBagProp = 0
local carriedBagModel = nil
local carryCfg = bagCfg.carry or {}
local carryAnimDict = tostring(carryCfg.animDict or 'move_weapon@jerrycan@generic')
local carryAnimName = tostring(carryCfg.animName or 'idle')
local carryAnimFlag = tonumber(carryCfg.animFlag) or 51
local bagModels = {}
for _,name in ipairs(bagCfg.models or {'xm_prop_x17_bag_med_01a','prop_cs_heist_bag_02','prop_ld_health_pack'}) do
    bagModels[#bagModels+1] = {name=tostring(name),hash=joaat(tostring(name))}
end

local function requestModel(hash)
    if not IsModelInCdimage(hash) or not IsModelValid(hash) then return false end
    RequestModel(hash)
    local deadline=GetGameTimer()+5000
    while not HasModelLoaded(hash) and GetGameTimer()<deadline do Wait(0) end
    return HasModelLoaded(hash)
end

local function requestAnim(dict)
    RequestAnimDict(dict)
    local deadline=GetGameTimer()+3500
    while not HasAnimDictLoaded(dict) and GetGameTimer()<deadline do Wait(0) end
    return HasAnimDictLoaded(dict)
end

local function firstValidBagModel(preferred)
    if preferred and tostring(preferred)~='' then
        local hash=joaat(tostring(preferred))
        if requestModel(hash) then return {name=tostring(preferred),hash=hash} end
    end
    for _,m in ipairs(bagModels) do
        if requestModel(m.hash) then return m end
    end
    return nil
end

local function medicalBagState(entity)
    if not entity or entity==0 or not DoesEntityExist(entity) then return nil end
    local st=Entity(entity).state
    if not st or st['fiveems:medicalBag']~=true then return nil end
    return {owner=tonumber(st['fiveems:medicalBagOwner']) or 0}
end

local function stopMedicalBagCarry(deleteProp)
    carryingMedicalBag=false
    local ped=PlayerPedId()
    if IsEntityPlayingAnim(ped,carryAnimDict,carryAnimName,3) then
        StopAnimTask(ped,carryAnimDict,carryAnimName,1.5)
    end
    if carriedBagProp and carriedBagProp~=0 and DoesEntityExist(carriedBagProp) then
        DetachEntity(carriedBagProp,true,true)
        if deleteProp~=false then DeleteEntity(carriedBagProp) end
    end
    carriedBagProp=0
    carriedBagModel=nil
end

local function startMedicalBagCarry(modelName)
    if placingBag then return end
    stopMedicalBagCarry(true)
    local chosen=firstValidBagModel(modelName)
    if not chosen then
        return C.notify('Nao encontrei um modelo valido para a bolsa medica. Ajuste Config.FieldEquipment.medicalBag.models.')
    end
    local ped=PlayerPedId()
    local pos=GetEntityCoords(ped)
    local obj=CreateObject(chosen.hash,pos.x,pos.y,pos.z+0.2,true,true,false)
    if not obj or obj==0 then
        SetModelAsNoLongerNeeded(chosen.hash)
        return C.notify('Nao consegui criar a bolsa medica na mao.')
    end
    local netId=NetworkGetNetworkIdFromEntity(obj)
    if netId and netId~=0 then
        SetNetworkIdCanMigrate(netId,true)
        SetNetworkIdExistsOnAllMachines(netId,true)
    end
    local c=bagCfg.carry or {}
    local bone=GetPedBoneIndex(ped,tonumber(c.bone) or 57005)
    SetEntityCollision(obj,false,false)
    AttachEntityToEntity(
        obj,ped,bone,
        tonumber(c.x) or 0.00,tonumber(c.y) or -0.18,tonumber(c.z) or -0.18,
        tonumber(c.rx) or 0.0,tonumber(c.ry) or 0.0,tonumber(c.rz) or 0.0,
        true,true,false,true,1,true
    )
    carriedBagProp=obj
    carriedBagModel=chosen.name
    carryingMedicalBag=true
    requestAnim(carryAnimDict)
    TaskPlayAnim(ped,carryAnimDict,carryAnimName,8.0,8.0,-1,carryAnimFlag,0.0,false,false,false)
    SetModelAsNoLongerNeeded(chosen.hash)
    C.notify('Bolsa medica em maos. Leve ate o paciente e use G para colocar no chao, ou mire no paciente com o ox_target.')

    CreateThread(function()
        while carryingMedicalBag do
            Wait(0)
            ped=PlayerPedId()
            DisablePlayerFiring(PlayerId(),true)
            DisableControlAction(0,21,true) -- sprint
            DisableControlAction(0,22,true) -- pular
            DisableControlAction(0,23,true) -- entrar em veiculo
            DisableControlAction(0,24,true) -- ataque
            DisableControlAction(0,25,true) -- mirar
            DisableControlAction(0,37,true) -- roda de armas
            DisableControlAction(0,44,true) -- cover
            if not IsEntityPlayingAnim(ped,carryAnimDict,carryAnimName,3) then
                if requestAnim(carryAnimDict) then
                    TaskPlayAnim(ped,carryAnimDict,carryAnimName,8.0,8.0,-1,carryAnimFlag,0.0,false,false,false)
                end
            end
            BeginTextCommandDisplayHelp('STRING')
            AddTextComponentSubstringPlayerName('BOLSA MEDICA | G colocar no chao | ox_target no paciente para colocar ao lado')
            EndTextCommandDisplayHelp(0,false,true,-1)
            if IsControlJustPressed(0,47) then
                TriggerServerEvent('fiveems:server:fieldBagPlaceRequest')
                Wait(400)
            end
        end
    end)
end

local function createPlacedBag(chosen,x,y,z,heading)
    local obj=CreateObject(chosen.hash,x,y,z,true,true,false)
    if not obj or obj==0 then return false end
    SetEntityHeading(obj,heading or 0.0)
    PlaceObjectOnGroundProperly(obj)
    FreezeEntityPosition(obj,true)
    local netId=NetworkGetNetworkIdFromEntity(obj)
    local deadline=GetGameTimer()+2200
    while (not netId or netId==0) and GetGameTimer()<deadline do Wait(0); netId=NetworkGetNetworkIdFromEntity(obj) end
    if not netId or netId==0 then DeleteEntity(obj); return false end
    TriggerServerEvent('fiveems:server:fieldBagRegister',netId,chosen.name)
    return true
end

local function beginBagPlacement()
    if placingBag then return end
    local chosen=firstValidBagModel(carriedBagModel)
    if not chosen then return C.notify('Nao encontrei um modelo valido para a bolsa medica. Ajuste Config.FieldEquipment.medicalBag.models.') end
    local restoreModel=carriedBagModel or chosen.name
    stopMedicalBagCarry(true)
    placingBag=true
    local ped=PlayerPedId()
    local pos=GetOffsetFromEntityInWorldCoords(ped,0.0,tonumber(bagCfg.deployDistance) or 1.15,-0.9)
    local ghost=CreateObject(chosen.hash,pos.x,pos.y,pos.z,false,false,false)
    if not ghost or ghost==0 then
        placingBag=false
        startMedicalBagCarry(restoreModel)
        return C.notify('Nao consegui criar o preview da bolsa medica.')
    end
    SetEntityAlpha(ghost,180,false); SetEntityCollision(ghost,false,false); FreezeEntityPosition(ghost,false)
    local heading=GetEntityHeading(ped)
    local dist=tonumber(bagCfg.deployDistance) or 1.15
    local side=0.0
    local zOff=0.02
    C.notify('Bolsa medica: setas movem, PgUp/PgDn altura, Q/E gira, ENTER coloca, BACKSPACE cancela.')
    CreateThread(function()
        local cancelled=false
        while placingBag and DoesEntityExist(ghost) do
            Wait(0)
            ped=PlayerPedId()
            local p=GetEntityCoords(ped); local f=GetEntityForwardVector(ped); local r=vector3(f.y,-f.x,0.0)
            if IsControlPressed(0,172) then dist=math.min(2.4,dist+0.012) end
            if IsControlPressed(0,173) then dist=math.max(0.6,dist-0.012) end
            if IsControlPressed(0,174) then side=math.max(-1.5,side-0.012) end
            if IsControlPressed(0,175) then side=math.min(1.5,side+0.012) end
            if IsControlPressed(0,10) then zOff=zOff+0.006 end
            if IsControlPressed(0,11) then zOff=zOff-0.006 end
            DisableControlAction(0,38,true)
            if IsControlPressed(0,44) then heading=heading-1.5 end
            if IsDisabledControlPressed(0,38) then heading=heading+1.5 end
            local x=p.x+f.x*dist+r.x*side; local y=p.y+f.y*dist+r.y*side
            local found,gz=GetGroundZFor_3dCoord(x,y,p.z+2.0,false)
            local z=(found and gz or p.z)+zOff
            SetEntityCoordsNoOffset(ghost,x,y,z,false,false,false); SetEntityHeading(ghost,heading)
            BeginTextCommandDisplayHelp('STRING'); AddTextComponentSubstringPlayerName('BOLSA MEDICA | ENTER colocar | BACKSPACE cancelar | Q/E girar'); EndTextCommandDisplayHelp(0,false,true,-1)
            if IsControlJustPressed(0,191) then
                placingBag=false
                local fp=GetEntityCoords(ghost); local fh=GetEntityHeading(ghost)
                DeleteEntity(ghost)
                if not createPlacedBag(chosen,fp.x,fp.y,fp.z,fh) then
                    startMedicalBagCarry(restoreModel)
                    C.notify('Falha ao sincronizar a bolsa medica. Ela voltou para suas maos.')
                end
                break
            elseif IsControlJustPressed(0,177) then
                placingBag=false; cancelled=true; DeleteEntity(ghost); break
            end
        end
        SetModelAsNoLongerNeeded(chosen.hash)
        if cancelled then
            startMedicalBagCarry(restoreModel)
            C.notify('Posicionamento cancelado. A bolsa voltou para suas maos.')
        end
    end)
end

local function placeBagBesideEntity(targetNetId)
    if placingBag then return end
    local target=NetworkGetEntityFromNetworkId(tonumber(targetNetId) or 0)
    if not target or target==0 or not DoesEntityExist(target) then
        return C.notify('Paciente nao encontrado para colocar a bolsa.')
    end
    local chosen=firstValidBagModel(carriedBagModel)
    if not chosen then return C.notify('Nao encontrei um modelo valido para a bolsa medica.') end
    local restoreModel=carriedBagModel or chosen.name
    local side=tonumber(((bagCfg.carry or {}).patientSideOffset)) or 0.85
    local p=GetOffsetFromEntityInWorldCoords(target,side,0.05,0.0)
    local found,gz=GetGroundZFor_3dCoord(p.x,p.y,p.z+2.0,false)
    local z=(found and gz or p.z)+0.02
    local heading=(GetEntityHeading(target)+90.0)%360.0
    stopMedicalBagCarry(true)
    if not createPlacedBag(chosen,p.x,p.y,z,heading) then
        startMedicalBagCarry(restoreModel)
        C.notify('Nao consegui colocar a bolsa ao lado do paciente. Ela voltou para suas maos.')
    end
    SetModelAsNoLongerNeeded(chosen.hash)
end

local function useMedicalBag()
    if placingBag then return end
    TriggerServerEvent('fiveems:server:fieldBagUseRequest')
end
RegisterNetEvent('fiveems:client:fieldBagCarryStart',function(modelName) startMedicalBagCarry(modelName) end)
RegisterNetEvent('fiveems:client:fieldBagCarryStop',function() stopMedicalBagCarry(true) end)
RegisterNetEvent('fiveems:client:fieldBagBeginPlacement',beginBagPlacement)
RegisterNetEvent('fiveems:client:fieldBagPlaceBeside',placeBagBesideEntity)
RegisterNetEvent('fiveems:client:useMedicalBag',useMedicalBag)
exports('UseMedicalBag',useMedicalBag)
RegisterCommand('fiveemsbag',useMedicalBag,false)

local function profileEnabled(profile)
    if type(profile)~='table' then return false end
    local value=profile.enabled
    if value==nil then return true end
    if value==false or value==0 or value=='0' then return false end
    return true
end

local function cachedVehicleProfiles()
    local out={}
    local seen={}
    local function add(departmentId,profiles)
        departmentId=tonumber(departmentId)
        for _,profile in ipairs(profiles or {}) do
            if profileEnabled(profile) then
                local row={}
                for k,v in pairs(profile) do row[k]=v end
                row.department_id=tonumber(row.department_id) or departmentId
                local key=('%s:%s:%s'):format(
                    tostring(row.department_id or 0),
                    tostring(row.vehicle_model or ''),
                    tostring(row.id or '')
                )
                if not seen[key] then
                    seen[key]=true
                    out[#out+1]=row
                end
            end
        end
    end

    -- O departamento ativo continua tendo prioridade, mas nao e mais a unica
    -- fonte. O Creator pode editar um departamento diferente do membro e o
    -- bootstrap pode momentaneamente deixar C.department vazio/desatualizado.
    if C.department then add(C.department.id,C.department.vehicleEquipmentProfiles) end
    for _,department in ipairs(C.worldDepartments or {}) do
        add(department.id,department.vehicleEquipmentProfiles)
    end
    return out
end

local function clientMemberDepartmentId()
    local member=C.bootstrap and C.bootstrap.member or nil
    return tonumber(member and member.department_id)
end

local function clientIsAdmin()
    return C.bootstrap and C.bootstrap.isAdmin==true or false
end

local function profileRootTransform(profile)
    local t=profile and profile.transform or {}
    return type(t)=='table' and t or {}
end

local function compartmentSpec(profile)
    local root=profileRootTransform(profile)
    local center=type(root.compartment)=='table' and root.compartment or root
    local zone=type(root.zone)=='table' and root.zone or {}
    local defaults=vehicleCfg.defaultSize or {x=1.20,y=1.00,z=1.10}
    local size=type(zone.size)=='table' and zone.size or type(root.size)=='table' and root.size or defaults
    return center,{
        x=math.max(0.25,tonumber(size.x or size.width) or tonumber(defaults.x) or 1.20),
        y=math.max(0.25,tonumber(size.y or size.depth) or tonumber(defaults.y) or 1.00),
        z=math.max(0.25,tonumber(size.z or size.height) or tonumber(defaults.z) or 1.10),
    }
end

local function bagMountSpec(profile)
    local root=profileRootTransform(profile)
    local mount=type(root.bag)=='table' and root.bag
        or type(root.bag_mount)=='table' and root.bag_mount
        or type(root.compartment)=='table' and root.compartment
        or root
    return mount
end

local function worldFromLocalTransform(entity,t)
    t=type(t)=='table' and t or {}
    return GetOffsetFromEntityInWorldCoords(
        entity,
        tonumber(t.x) or 0.0,
        tonumber(t.y) or -2.0,
        tonumber(t.z) or 0.5
    )
end

local function compartmentWorld(entity,profile)
    local center=compartmentSpec(profile)
    return worldFromLocalTransform(entity,center)
end

local function bagMountWorld(entity,profile)
    return worldFromLocalTransform(entity,bagMountSpec(profile))
end

local function profileMatchesVehicle(profile,model)
    return profileEnabled(profile) and joaat(tostring(profile.vehicle_model or ''))==model
end

local function profileAllowedForPlayer(profile)
    local profileDepartmentId=tonumber(profile.department_id)
    local memberDepartmentId=clientMemberDepartmentId()
    if clientIsAdmin() then return true end
    if not memberDepartmentId then return false end
    return not profileDepartmentId or profileDepartmentId==memberDepartmentId
end

local function referenceInsideCompartment(entity,profile,referenceCoords)
    local center,size=compartmentSpec(profile)
    local playerPos=GetEntityCoords(PlayerPedId())
    local world=worldFromLocalTransform(entity,center)
    local interactDistance=tonumber(vehicleCfg.interactDistance) or 3.75
    if #(playerPos-world)>interactDistance then return false,world end
    if not referenceCoords then return true,world end

    local localHit=GetOffsetFromEntityGivenWorldCoords(entity,referenceCoords.x,referenceCoords.y,referenceCoords.z)
    local dx=math.abs((localHit.x or 0.0)-(tonumber(center.x) or 0.0))
    local dy=math.abs((localHit.y or 0.0)-(tonumber(center.y) or -2.0))
    local dz=math.abs((localHit.z or 0.0)-(tonumber(center.z) or 0.5))
    return dx<=size.x*0.5 and dy<=size.y*0.5 and dz<=size.z*0.5,world
end

local function profileForVehicle(entity,referenceCoords,requireRange)
    if not entity or entity==0 or not DoesEntityExist(entity) then return nil,nil end
    local model=GetEntityModel(entity)
    local best,bestWorld,bestScore
    for _,profile in ipairs(cachedVehicleProfiles()) do
        if profileAllowedForPlayer(profile) and profileMatchesVehicle(profile,model) then
            local inside,world=referenceInsideCompartment(entity,profile,referenceCoords)
            if (not requireRange) or inside then
                local score=referenceCoords and #(referenceCoords-world) or #(GetEntityCoords(PlayerPedId())-world)
                if not bestScore or score<bestScore then best,bestWorld,bestScore=profile,world,score end
            end
        end
    end
    return best,bestWorld
end

local function profileForBagMount(entity,referenceCoords,requireRange)
    if not entity or entity==0 or not DoesEntityExist(entity) then return nil,nil end
    local model=GetEntityModel(entity)
    local best,bestWorld,bestScore
    local playerPos=GetEntityCoords(PlayerPedId())
    local interactDistance=tonumber(vehicleCfg.interactDistance) or 3.75
    local radius=tonumber((((bagCfg.vehicle or {}).mountTargetRadius))) or 0.85
    for _,profile in ipairs(cachedVehicleProfiles()) do
        if profileAllowedForPlayer(profile) and profileMatchesVehicle(profile,model) then
            local world=bagMountWorld(entity,profile)
            local playerDistance=#(playerPos-world)
            local hitDistance=referenceCoords and #(referenceCoords-world) or playerDistance
            local inRange=(not requireRange) or (playerDistance<=interactDistance and hitDistance<=radius)
            if inRange and (not bestScore or hitDistance<bestScore) then
                best,bestWorld,bestScore=profile,world,hitDistance
            end
        end
    end
    return best,bestWorld
end

local function canUseVehicleCompartment(entity,_,coords)
    local profile=profileForVehicle(entity,coords,true)
    return profile~=nil
end

local function selectedVehicleProfile(data)
    if type(data)~='table' then return nil end
    local profile=profileForVehicle(data.entity,data.coords,true)
    if profile then return profile end
    return profileForVehicle(data.entity,nil,true)
end

local function selectedVehicleBagProfile(data)
    if type(data)~='table' then return nil end
    local profile=profileForBagMount(data.entity,data.coords,true)
    if profile then return profile end
    -- onSelect do ox_target pode chegar sem coords em algumas versoes.
    -- Nesse caso escolhemos o suporte mais proximo sem refazer a validacao
    -- apertada de raio; o canInteract ja validou a area antes de exibir a opcao.
    return profileForBagMount(data.entity,data.coords or GetEntityCoords(PlayerPedId()),false)
end

local function vehicleBagStored(vehicle)
    if not vehicle or vehicle==0 or not DoesEntityExist(vehicle) then return false end
    local st=Entity(vehicle).state
    local value=st and st['fiveems:vehicleMedicalBagStored']
    return value~=false
end

local function profileForVisualVehicle(vehicle)
    if not vehicle or vehicle==0 or not DoesEntityExist(vehicle) then return nil end
    local model=GetEntityModel(vehicle)
    local st=Entity(vehicle).state
    local stateDepartment=tonumber(st and st['fiveems:vehicleMedicalBagDepartmentId'])
    local activeDepartment=tonumber(C.department and C.department.id)
    local memberDepartment=clientMemberDepartmentId()
    local first,activeMatch,memberMatch
    for _,profile in ipairs(cachedVehicleProfiles()) do
        if profileMatchesVehicle(profile,model) then
            if not first then first=profile end
            if stateDepartment and tonumber(profile.department_id)==stateDepartment then return profile end
            if activeDepartment and tonumber(profile.department_id)==activeDepartment then activeMatch=activeMatch or profile end
            if memberDepartment and tonumber(profile.department_id)==memberDepartment then memberMatch=memberMatch or profile end
        end
    end
    return activeMatch or memberMatch or first
end

local vehicleBagVisuals={}
local vehicleBagVisualByProp={}

local function mountSignature(profile)
    local m=bagMountSpec(profile)
    return ('%s:%.4f:%.4f:%.4f:%.3f:%.3f:%.3f'):format(
        tostring(profile and profile.department_id or 0),
        tonumber(m.x) or 0.0,tonumber(m.y) or -2.0,tonumber(m.z) or 0.5,
        tonumber(m.rx) or 0.0,tonumber(m.ry) or 0.0,tonumber(m.rz or m.heading) or 0.0
    )
end

local function removeVehicleBagVisual(vehicle)
    local row=vehicleBagVisuals[vehicle]
    if not row then return end
    vehicleBagVisuals[vehicle]=nil
    if row.prop and row.prop~=0 then
        vehicleBagVisualByProp[row.prop]=nil
        if GetResourceState('ox_target')=='started' then
            pcall(function() exports.ox_target:removeLocalEntity(row.prop,row.targetName) end)
        end
        if DoesEntityExist(row.prop) then DeleteEntity(row.prop) end
    end
end

local function createVehicleBagVisual(vehicle,profile)
    if not vehicle or vehicle==0 or not DoesEntityExist(vehicle) or not profile then return end
    if vehicleBagVisuals[vehicle] then return end
    local preferred=tostring((profileRootTransform(profile).bag_model) or '')
    local chosen=firstValidBagModel(preferred)
    if not chosen then return end
    local mount=bagMountSpec(profile)
    local pos=bagMountWorld(vehicle,profile)
    local prop=CreateObject(chosen.hash,pos.x,pos.y,pos.z,false,false,false)
    if not prop or prop==0 then SetModelAsNoLongerNeeded(chosen.hash); return end
    SetEntityAsMissionEntity(prop,true,true)
    SetEntityCollision(prop,false,false)
    AttachEntityToEntity(
        prop,vehicle,0,
        tonumber(mount.x) or 0.0,tonumber(mount.y) or -2.0,tonumber(mount.z) or 0.5,
        tonumber(mount.rx) or 0.0,tonumber(mount.ry) or 0.0,tonumber(mount.rz or mount.heading) or 0.0,
        false,false,false,false,2,true
    )
    local netId=NetworkGetNetworkIdFromEntity(vehicle)
    local targetName=('fiveems_vehicle_bag_take_%s'):format(tostring(netId~=0 and netId or vehicle))
    vehicleBagVisuals[vehicle]={prop=prop,profile=profile,targetName=targetName,signature=mountSignature(profile)}
    vehicleBagVisualByProp[prop]=vehicle
    if GetResourceState('ox_target')=='started' then
        exports.ox_target:addLocalEntity(prop,{
            {
                name=targetName,
                icon='fa-solid fa-briefcase-medical',
                label='Retirar bolsa medica',
                distance=2.5,
                canInteract=function()
                    local current=vehicleBagVisuals[vehicle]
                    local p=current and current.profile or profile
                    return not carryingMedicalBag and DoesEntityExist(vehicle) and vehicleBagStored(vehicle) and profileAllowedForPlayer(p)
                end,
                onSelect=function()
                    local current=vehicleBagVisuals[vehicle]
                    local p=current and current.profile or profile
                    TriggerServerEvent('fiveems:server:vehicleEquipmentTakeBag',NetworkGetNetworkIdFromEntity(vehicle),tonumber(p and p.department_id))
                end
            }
        })
    end
    SetModelAsNoLongerNeeded(chosen.hash)
end

local function syncVehicleBagVisuals()
    local ped=PlayerPedId()
    local playerPos=GetEntityCoords(ped)
    local maxDistance=tonumber((((bagCfg.vehicle or {}).visualDistance))) or 85.0

    if C.uiOpen and C.uiContext=='creator' then
        local cleanup={}
        for vehicle in pairs(vehicleBagVisuals) do cleanup[#cleanup+1]=vehicle end
        for _,vehicle in ipairs(cleanup) do removeVehicleBagVisual(vehicle) end
        return
    end

    for vehicle,row in pairs(vehicleBagVisuals) do
        local profile=DoesEntityExist(vehicle) and profileForVisualVehicle(vehicle) or nil
        local tooFar=not DoesEntityExist(vehicle) or #(GetEntityCoords(vehicle)-playerPos)>(maxDistance+20.0)
        if tooFar or not profile or not vehicleBagStored(vehicle) or row.signature~=mountSignature(profile) then
            removeVehicleBagVisual(vehicle)
        end
    end

    for _,vehicle in ipairs(GetGamePool('CVehicle')) do
        if DoesEntityExist(vehicle) and #(GetEntityCoords(vehicle)-playerPos)<=maxDistance then
            local profile=profileForVisualVehicle(vehicle)
            if profile and vehicleBagStored(vehicle) and not vehicleBagVisuals[vehicle] then
                createVehicleBagVisual(vehicle,profile)
            end
        end
    end
end

CreateThread(function()
    while true do
        Wait(900)
        syncVehicleBagVisuals()
    end
end)

local function registerTargets()
    if GetResourceState('ox_target')~='started' then return end
    local names={}
    for _,m in ipairs(bagModels) do names[#names+1]=m.hash end
    pcall(function() exports.ox_target:removeModel(names,{'fiveems_bag_open','fiveems_bag_pickup'}) end)
    exports.ox_target:addModel(names,{
        {name='fiveems_bag_open',icon='fa-solid fa-kit-medical',label='Abrir bolsa medica',distance=2.5,canInteract=function(e)return medicalBagState(e)~=nil end,onSelect=function(d)TriggerServerEvent('fiveems:server:fieldBagOpen',NetworkGetNetworkIdFromEntity(d.entity))end},
        {name='fiveems_bag_pickup',icon='fa-solid fa-hand',label='Recolher bolsa medica',distance=2.5,canInteract=function(e)local st=medicalBagState(e); return st and st.owner==GetPlayerServerId(PlayerId()) end,onSelect=function(d)TriggerServerEvent('fiveems:server:fieldBagStore',NetworkGetNetworkIdFromEntity(d.entity))end},
    })

    pcall(function() exports.ox_target:removeGlobalVehicle({'fiveems_vehicle_store_medical_bag','fiveems_vehicle_ems_compartment','fiveems_vehicle_take_medical_bag'}) end)
    exports.ox_target:addGlobalVehicle({
        {
            -- V0.4.12: a bolsa visual montada e propositalmente sem colisao para
            -- nao interferir com a ambulancia. Portanto o raycast do ox_target
            -- pode atravessar o prop. Esta opcao e registrada na propria viatura
            -- e so aparece quando o ponto mirado esta dentro do raio do suporte
            -- da bolsa. Visualmente o jogador continua mirando na bolsa.
            name='fiveems_vehicle_take_medical_bag',
            icon='fa-solid fa-briefcase-medical',
            label='Retirar bolsa medica',
            distance=tonumber(vehicleCfg.openDistance) or 4.0,
            canInteract=function(entity,distance,coords)
                if carryingMedicalBag or not vehicleBagStored(entity) then return false end
                local profile=profileForBagMount(entity,coords,true)
                return profile~=nil
            end,
            onSelect=function(data)
                local profile=selectedVehicleBagProfile(data)
                if not profile then return C.notify('Suporte da bolsa medica nao encontrado nesta viatura.') end
                TriggerServerEvent(
                    'fiveems:server:vehicleEquipmentTakeBag',
                    NetworkGetNetworkIdFromEntity(data.entity),
                    tonumber(profile.department_id)
                )
            end
        },
        {
            name='fiveems_vehicle_store_medical_bag',
            icon='fa-solid fa-box-archive',
            label='Guardar bolsa medica na viatura',
            distance=tonumber(vehicleCfg.openDistance) or 4.0,
            canInteract=function(entity,distance,coords)
                if not carryingMedicalBag or vehicleBagStored(entity) then return false end
                local profile=profileForBagMount(entity,coords,true)
                return profile~=nil
            end,
            onSelect=function(data)
                local profile=selectedVehicleBagProfile(data)
                if not profile then return C.notify('Suporte da bolsa medica nao encontrado nesta viatura.') end
                TriggerServerEvent(
                    'fiveems:server:vehicleEquipmentStoreBag',
                    NetworkGetNetworkIdFromEntity(data.entity),
                    tonumber(profile.department_id)
                )
            end
        },
        {
            name='fiveems_vehicle_ems_compartment',
            icon='fa-solid fa-truck-medical',
            label='Compartimento EMS',
            distance=tonumber(vehicleCfg.openDistance) or 4.0,
            canInteract=function(entity,distance,coords)
                return canUseVehicleCompartment(entity,distance,coords)
            end,
            onSelect=function(data)
                local profile=selectedVehicleProfile(data)
                if not profile then return C.notify('Area do compartimento EMS nao encontrada nesta viatura.') end
                TriggerServerEvent(
                    'fiveems:server:vehicleEquipmentOpen',
                    NetworkGetNetworkIdFromEntity(data.entity),
                    tonumber(profile.department_id)
                )
            end
        }
    })

    pcall(function() exports.ox_target:removeGlobalPed('fiveems_bag_place_patient') end)
    exports.ox_target:addGlobalPed({
        {name='fiveems_bag_place_patient',icon='fa-solid fa-kit-medical',label='Colocar bolsa medica ao lado',distance=3.0,canInteract=function(entity)
            return carryingMedicalBag and entity~=PlayerPedId() and DoesEntityExist(entity) and IsPedHuman(entity)
        end,onSelect=function(data)
            local netId=NetworkGetNetworkIdFromEntity(data.entity)
            if netId and netId~=0 then
                TriggerServerEvent('fiveems:server:fieldBagPlaceBesideRequest',netId)
            else
                TriggerServerEvent('fiveems:server:fieldBagPlaceRequest')
            end
        end}
    })

    -- Os props locais da bolsa montada sao recriados por cliente; ao reiniciar
    -- ox_target re-registra o alvo diretamente sobre a bolsa visivel.
    for vehicle,row in pairs(vehicleBagVisuals) do
        if row.prop and DoesEntityExist(row.prop) then
            pcall(function() exports.ox_target:removeLocalEntity(row.prop,row.targetName) end)
            vehicleBagVisuals[vehicle]=nil
            vehicleBagVisualByProp[row.prop]=nil
            DeleteEntity(row.prop)
        end
    end
    syncVehicleBagVisuals()
end

CreateThread(function() Wait(2200); registerTargets() end)
AddEventHandler('onClientResourceStart',function(resourceName) if resourceName=='ox_target' then CreateThread(function() Wait(500); registerTargets() end) end end)

-- Diagnostico V0.4.11: mostra separadamente a area do compartimento e o
-- suporte fisico da bolsa. Verde = compartimento; azul = bolsa.
RegisterCommand('fiveemscompartmentdebug',function()
    local ped=PlayerPedId()
    local pos=GetEntityCoords(ped)
    local nearest,bestDistance
    for _,vehicle in ipairs(GetGamePool('CVehicle')) do
        if DoesEntityExist(vehicle) then
            local d=#(GetEntityCoords(vehicle)-pos)
            if d<=12.0 and (not bestDistance or d<bestDistance) then
                nearest,bestDistance=vehicle,d
            end
        end
    end
    if not nearest then
        print('^3[FiveEMS][EquipDebug]^7 Nenhuma viatura encontrada em 12m.')
        return C.notify('EquipDebug: aproxime-se de uma viatura.')
    end

    local model=GetEntityModel(nearest)
    local matches={}
    for _,profile in ipairs(cachedVehicleProfiles()) do
        if joaat(tostring(profile.vehicle_model or ''))==model then
            matches[#matches+1]=profile
        end
    end

    print(('^5[FiveEMS][EquipDebug]^7 vehicle=%s hash=%s perfis=%d distancia=%.2f')
        :format(tostring(nearest),tostring(model),#matches,bestDistance or -1.0))

    if #matches==0 then
        C.notify('EquipDebug: nenhum hotspot carregado para este modelo. Veja o F8.')
        return
    end

    local markers={}
    for i,profile in ipairs(matches) do
        local world=compartmentWorld(nearest,profile)
        local bagWorld=bagMountWorld(nearest,profile)
        local _,size=compartmentSpec(profile)
        local d=#(pos-world)
        markers[#markers+1]={compartment=world,bag=bagWorld,size=size}
        print(('^5[FiveEMS][EquipDebug]^7 #%d dept=%s model=%s compartment=(%.2f, %.2f, %.2f) size=(%.2f, %.2f, %.2f) bag=(%.2f, %.2f, %.2f) distancia=%.2f')
            :format(i,tostring(profile.department_id or '?'),tostring(profile.vehicle_model or '?'),world.x,world.y,world.z,size.x,size.y,size.z,bagWorld.x,bagWorld.y,bagWorld.z,d))
    end
    C.notify(('EquipDebug: %d perfil(is). Verde=compartimento, azul=bolsa por 15s; detalhes no F8.'):format(#markers))
    CreateThread(function()
        local untilTime=GetGameTimer()+15000
        while GetGameTimer()<untilTime do
            Wait(0)
            for _,row in ipairs(markers) do
                local world=row.compartment
                DrawMarker(1,world.x,world.y,world.z,0.0,0.0,0.0,0.0,0.0,GetEntityHeading(nearest),row.size.x,row.size.y,row.size.z,50,220,120,55,false,false,2,false,nil,nil,false)
                local b=row.bag
                DrawMarker(28,b.x,b.y,b.z+0.08,0.0,0.0,0.0,0.0,0.0,0.0,0.22,0.22,0.22,80,150,255,220,false,false,2,false,nil,nil,false)
            end
        end
    end)
end,false)

RegisterNetEvent('fiveems:client:fieldBagOpenData',function(payload)
    if C.uiOpen and C.uiContext=='field_bag' then SendNUIMessage({action='fieldBagData',data=payload})
    else C.openUi('field_bag',payload or {}) end
end)
RegisterNetEvent('fiveems:client:vehicleEquipmentOpenData',function(payload)
    if C.uiOpen and C.uiContext=='vehicle_equipment' then SendNUIMessage({action='vehicleEquipmentData',data=payload})
    else C.openUi('vehicle_equipment',payload or {}) end
end)
RegisterNetEvent('fiveems:client:fieldBagRemoved',function(netId,reason)
    if C.uiOpen and C.uiContext=='field_bag' and tonumber(C.uiExtra.netId)==tonumber(netId) then C.closeUi() end
    if reason then C.notify(reason) end
end)

RegisterNUICallback('fieldBagTake',function(data,cb) TriggerServerEvent('fiveems:server:fieldBagTake',tonumber(data.netId),data.item,tonumber(data.count) or 1); cb({ok=true}) end)
RegisterNUICallback('fieldBagReturn',function(data,cb) TriggerServerEvent('fiveems:server:fieldBagReturn',tonumber(data.netId),data.item,tonumber(data.count) or 1); cb({ok=true}) end)
RegisterNUICallback('fieldBagRefresh',function(data,cb) TriggerServerEvent('fiveems:server:fieldBagOpen',tonumber(data.netId)); cb({ok=true}) end)
RegisterNUICallback('vehicleEquipmentTake',function(data,cb) TriggerServerEvent('fiveems:server:vehicleEquipmentTake',tonumber(data.vehicleNetId),tonumber(data.supplyId),tonumber(data.count) or 1,tonumber(data.departmentId)); cb({ok=true}) end)
RegisterNUICallback('vehicleEquipmentLoadBag',function(data,cb) TriggerServerEvent('fiveems:server:vehicleEquipmentLoadBag',tonumber(data.vehicleNetId),tonumber(data.supplyId),tonumber(data.count) or 1,tonumber(data.departmentId)); cb({ok=true}) end)
RegisterNUICallback('vehicleEquipmentRestockBag',function(data,cb) TriggerServerEvent('fiveems:server:vehicleEquipmentRestockBag',tonumber(data.vehicleNetId),tonumber(data.departmentId)); cb({ok=true}) end)
RegisterNUICallback('vehicleEquipmentRefresh',function(data,cb) TriggerServerEvent('fiveems:server:vehicleEquipmentOpen',tonumber(data.vehicleNetId),tonumber(data.departmentId)); cb({ok=true}) end)

AddEventHandler('onResourceStop',function(resourceName)
    if resourceName~=GetCurrentResourceName() then return end
    stopMedicalBagCarry(true)
    for vehicle in pairs(vehicleBagVisuals) do removeVehicleBagVisual(vehicle) end
    if GetResourceState('ox_target')~='started' then return end
    local names={}; for _,m in ipairs(bagModels) do names[#names+1]=m.hash end
    pcall(function() exports.ox_target:removeModel(names,{'fiveems_bag_open','fiveems_bag_pickup'}) end)
    pcall(function() exports.ox_target:removeGlobalVehicle({'fiveems_vehicle_store_medical_bag','fiveems_vehicle_ems_compartment','fiveems_vehicle_take_medical_bag'}) end)
    pcall(function() exports.ox_target:removeGlobalPed('fiveems_bag_place_patient') end)
end)


-- V0.4.8 - Equipamentos portateis addon (LUCAS / CombiCarrier)
local portableEquipmentCfg = ((Config.FieldEquipment or {}).portableEquipment or {})
local placingPortableEquipment = false

local function portableEquipmentDef(key)
    key=tostring(key or '')
    local def=portableEquipmentCfg[key]
    if type(def)~='table' then return nil end
    return def,key
end

local function portableEquipmentState(entity)
    if not entity or entity==0 or not DoesEntityExist(entity) then return nil end
    local st=Entity(entity).state
    if not st or st['fiveems:portableEquipment']~=true then return nil end
    local key=tostring(st['fiveems:portableEquipmentType'] or '')
    local def=portableEquipmentCfg[key]
    if not def then return nil end
    return {key=key,def=def,owner=tonumber(st['fiveems:portableEquipmentOwner']) or 0}
end

local function beginPortableEquipmentPlacement(key)
    if placingPortableEquipment then return end
    local def,equipKey=portableEquipmentDef(key)
    if not def then return C.notify('Equipamento EMS desconhecido.') end
    local modelName=tostring(def.model or '')
    local hash=joaat(modelName)
    if modelName=='' or not requestModel(hash) then
        return C.notify(('Nao foi possivel carregar %s (%s). Verifique os arquivos em stream/.'):format(tostring(def.label or equipKey),modelName))
    end

    placingPortableEquipment=true
    local ped=PlayerPedId()
    local heading=GetEntityHeading(ped)
    local dist=tonumber(def.deployDistance) or 1.15
    local side=0.0
    local zOff=0.02
    local p=GetEntityCoords(ped)
    local ghost=CreateObject(hash,p.x,p.y,p.z,false,false,false)
    if not ghost or ghost==0 then
        placingPortableEquipment=false
        SetModelAsNoLongerNeeded(hash)
        return C.notify('Nao consegui criar o preview do equipamento EMS.')
    end
    SetEntityAlpha(ghost,180,false)
    SetEntityCollision(ghost,false,false)
    FreezeEntityPosition(ghost,false)
    C.notify(('%s: setas movem, PgUp/PgDn altura, Q/E gira, ENTER coloca, BACKSPACE cancela.'):format(tostring(def.label or equipKey)))

    CreateThread(function()
        local cancelled=false
        while placingPortableEquipment and DoesEntityExist(ghost) do
            Wait(0)
            ped=PlayerPedId()
            p=GetEntityCoords(ped)
            local f=GetEntityForwardVector(ped)
            local r=vector3(f.y,-f.x,0.0)
            if IsControlPressed(0,172) then dist=math.min(2.8,dist+0.012) end
            if IsControlPressed(0,173) then dist=math.max(0.6,dist-0.012) end
            if IsControlPressed(0,174) then side=math.max(-1.8,side-0.012) end
            if IsControlPressed(0,175) then side=math.min(1.8,side+0.012) end
            if IsControlPressed(0,10) then zOff=zOff+0.006 end
            if IsControlPressed(0,11) then zOff=zOff-0.006 end
            DisableControlAction(0,38,true)
            if IsControlPressed(0,44) then heading=heading-1.5 end
            if IsDisabledControlPressed(0,38) then heading=heading+1.5 end
            local x=p.x+f.x*dist+r.x*side
            local y=p.y+f.y*dist+r.y*side
            local found,gz=GetGroundZFor_3dCoord(x,y,p.z+2.0,false)
            local z=(found and gz or p.z)+zOff
            SetEntityCoordsNoOffset(ghost,x,y,z,false,false,false)
            SetEntityHeading(ghost,heading)
            BeginTextCommandDisplayHelp('STRING')
            AddTextComponentSubstringPlayerName(('%s | ENTER colocar | BACKSPACE cancelar | Q/E girar'):format(tostring(def.label or equipKey)))
            EndTextCommandDisplayHelp(0,false,true,-1)

            if IsControlJustPressed(0,191) then
                placingPortableEquipment=false
                local fp=GetEntityCoords(ghost)
                local fh=GetEntityHeading(ghost)
                DeleteEntity(ghost)
                TriggerServerEvent('fiveems:server:portableEquipmentDeploy',equipKey,{x=fp.x,y=fp.y,z=fp.z,heading=fh})
                break
            elseif IsControlJustPressed(0,177) then
                placingPortableEquipment=false
                cancelled=true
                DeleteEntity(ghost)
                break
            end
        end
        SetModelAsNoLongerNeeded(hash)
        if cancelled then C.notify('Posicionamento do equipamento cancelado.') end
    end)
end

RegisterNetEvent('fiveems:client:portableEquipmentBeginPlacement',function(key)
    beginPortableEquipmentPlacement(key)
end)

local function usePortableEquipment(key)
    if placingPortableEquipment then return end
    TriggerServerEvent('fiveems:server:portableEquipmentUseRequest',tostring(key or ''))
end
exports('UsePortableEquipment',usePortableEquipment)

RegisterCommand('fiveemsequip',function(_,args)
    local key=tostring((args or {})[1] or '')
    if key=='' then
        local names={}
        for k,def in pairs(portableEquipmentCfg) do names[#names+1]=('%s=%s'):format(k,tostring(def.label or k)) end
        table.sort(names)
        return C.notify('Use /fiveemsequip <tipo>. Tipos: '..table.concat(names,', '))
    end
    usePortableEquipment(key)
end,false)
RegisterCommand('fiveemslucas2',function() usePortableEquipment('lucas2') end,false)
RegisterCommand('fiveemslucas3',function() usePortableEquipment('lucas3') end,false)
RegisterCommand('fiveemscombi',function() usePortableEquipment('combicarrier') end,false)

RegisterCommand('fiveemsequiptest',function()
    local models={}
    for key,def in pairs(portableEquipmentCfg) do models[#models+1]={key=key,model=tostring(def.model or '')} end
    for _,modelName in ipairs(((Config.FieldEquipment or {}).stretcherPropLibrary or {})) do
        models[#models+1]={key='stretcher-preview',model=tostring(modelName)}
    end
    table.sort(models,function(a,b) return a.model<b.model end)
    local okCount=0
    for _,row in ipairs(models) do
        local hash=joaat(row.model)
        local inCd=IsModelInCdimage(hash)
        local valid=IsModelValid(hash)
        local loaded=false
        if inCd and valid then
            RequestModel(hash)
            local deadline=GetGameTimer()+2200
            while not HasModelLoaded(hash) and GetGameTimer()<deadline do Wait(0) end
            loaded=HasModelLoaded(hash)
            if loaded then okCount=okCount+1; SetModelAsNoLongerNeeded(hash) end
        end
        print(('[FiveEMS][EMS PROP TEST] %s | hash=%s | CD=%s | Valid=%s | Loaded=%s')
            :format(row.model,tostring(hash),tostring(inCd),tostring(valid),tostring(loaded)))
    end
    C.notify(('EMS Props: %d/%d modelos carregaram. Veja o F8 para detalhes.'):format(okCount,#models))
end,false)

local function registerPortableEquipmentTargets()
    if GetResourceState('ox_target')~='started' then return end
    for key,def in pairs(portableEquipmentCfg) do
        local equipKey=tostring(key)
        local equipDef=def
        local hash=joaat(tostring(equipDef.model or ''))
        local optionName='fiveems_portable_equipment_store_'..equipKey
        pcall(function() exports.ox_target:removeModel(hash,{optionName}) end)
        exports.ox_target:addModel(hash,{
            {
                name=optionName,
                icon='fa-solid fa-hand',
                label='Recolher '..tostring(equipDef.label or equipKey),
                distance=tonumber(equipDef.openDistance) or 2.5,
                canInteract=function(entity)
                    local st=portableEquipmentState(entity)
                    return st and st.key==equipKey
                end,
                onSelect=function(data)
                    TriggerServerEvent('fiveems:server:portableEquipmentStore',NetworkGetNetworkIdFromEntity(data.entity))
                end,
            },
        })
    end
end

CreateThread(function() Wait(2400); registerPortableEquipmentTargets() end)
AddEventHandler('onClientResourceStart',function(resourceName)
    if resourceName=='ox_target' then CreateThread(function() Wait(650); registerPortableEquipmentTargets() end) end
end)

AddEventHandler('onResourceStop',function(resourceName)
    if resourceName~=GetCurrentResourceName() or GetResourceState('ox_target')~='started' then return end
    for key,def in pairs(portableEquipmentCfg) do
        local hash=joaat(tostring(def.model or ''))
        pcall(function() exports.ox_target:removeModel(hash,{'fiveems_portable_equipment_store_'..tostring(key)}) end)
    end
end)
