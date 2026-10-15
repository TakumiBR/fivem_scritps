FiveEMS = FiveEMS or {}
local C = FiveEMS.Client

local TARGET_NPC = 'fiveems_clinical_npc'
local TARGET_PLAYER = 'fiveems_clinical_player'

local boneRegion = {
    [31086]='head', [39317]='neck',
    [24818]='chest', [24817]='chest', [24816]='chest', [57597]='chest',
    [11816]='pelvis', [23553]='pelvis',
    [28252]='right_arm', [57005]='right_arm', [58866]='right_arm', [40269]='right_arm', [64016]='right_arm', [64017]='right_arm',
    [61163]='left_arm', [18905]='left_arm', [26610]='left_arm', [26611]='left_arm', [26612]='left_arm', [26613]='left_arm', [26614]='left_arm',
    [51826]='right_leg', [36864]='right_leg', [52301]='right_leg', [20781]='right_leg', [35502]='right_leg',
    [58271]='left_leg', [63931]='left_leg', [14201]='left_leg', [2108]='left_leg', [65245]='left_leg',
}

local meleeWeapons = {
    [joaat('WEAPON_KNIFE')]=true, [joaat('WEAPON_DAGGER')]=true, [joaat('WEAPON_SWITCHBLADE')]=true,
    [joaat('WEAPON_BOTTLE')]=true,
}
local bluntWeapons = {
    [joaat('WEAPON_BAT')]=true, [joaat('WEAPON_CROWBAR')]=true, [joaat('WEAPON_HAMMER')]=true,
    [joaat('WEAPON_NIGHTSTICK')]=true, [joaat('WEAPON_UNARMED')]=true,
}

local function categoryForPed(ped, weapon)
    local group = GetWeapontypeGroup(weapon)
    if meleeWeapons[weapon] then return 'stabbing' end
    if bluntWeapons[weapon] then return 'blunt' end
    if group == joaat('GROUP_PISTOL') or group == joaat('GROUP_RIFLE') or group == joaat('GROUP_SMG')
        or group == joaat('GROUP_SHOTGUN') or group == joaat('GROUP_SNIPER') or group == joaat('GROUP_MG') then
        return 'gunshot'
    end
    if group == joaat('GROUP_HEAVY') then return 'explosion' end
    if IsPedInAnyVehicle(ped,false) then return 'vehicle' end
    if IsPedFalling(ped) or IsPedRagdoll(ped) then return 'fall' end
    if IsEntityOnFire(ped) then return 'burn' end
    return 'blunt'
end

local function snapshotNpc(ped)
    local ok,bone = GetPedLastDamageBone(ped)
    if not ok then bone = 24818 end
    local weapon = GetPedCauseOfDeath(ped)
    local hints = FiveEMS.FrameworkClient and FiveEMS.FrameworkClient.getNpcAppearanceHints
        and FiveEMS.FrameworkClient.getNpcAppearanceHints(ped) or {}

    return {
        health=GetEntityHealth(ped),
        maxHealth=GetEntityMaxHealth(ped),
        dead=IsEntityDead(ped) or IsPedFatallyInjured(ped),
        bone=bone,
        region=boneRegion[bone] or 'chest',
        category=categoryForPed(ped,weapon),
        weapon=weapon,
        model=GetEntityModel(ped),
        model_hash=hints.model_hash or GetEntityModel(ped),
        sexo=hints.sexo,
        idade=hints.idade,
        idade_min=hints.idade_min,
        idade_max=hints.idade_max,
        age_group=hints.age_group,
        archetype=hints.archetype,
    }
end

C.snapshotNpc = snapshotNpc

local function playerServerIdFromPed(ped)
    for _,player in ipairs(GetActivePlayers()) do
        if GetPlayerPed(player) == ped then return GetPlayerServerId(player) end
    end
    return nil
end

local function ensureNpcNetId(ped)
    if not NetworkGetEntityIsNetworked(ped) then
        NetworkRegisterEntityAsNetworked(ped)
        local timeout=GetGameTimer()+1200
        while not NetworkGetEntityIsNetworked(ped) and GetGameTimer()<timeout do Wait(0) end
    end
    if not NetworkGetEntityIsNetworked(ped) then return nil end
    local netId=PedToNet(ped)
    return netId and netId>0 and netId or nil
end

C.ensureNpcNetId = ensureNpcNetId

function C.openClinicalTarget(targetRef, snapshot)
    if type(targetRef)~='table' then return end
    C.targetRef=targetRef
    C.targetServerId=targetRef.kind=='player' and tonumber(targetRef.serverId) or nil
    C.openUi('patient',{targetRef=targetRef})
    TriggerServerEvent('fiveems:server:clinicalRequestState',targetRef,snapshot or {})
end

local TREAT_PLAYER_ROOT = 'fiveems_hand_treatment_player_root'
local TREAT_NPC_ROOT = 'fiveems_hand_treatment_npc_root'
local treatmentTargetNamesPlayer={TARGET_PLAYER,TREAT_PLAYER_ROOT}
local treatmentTargetNamesNpc={TARGET_NPC,TREAT_NPC_ROOT}

local regionLabelsTarget={
    head='Cabeca',neck='Pescoco',chest='Torax',abdomen='Abdome',pelvis='Pelve',
    left_arm='Braco esquerdo',right_arm='Braco direito',left_leg='Perna esquerda',right_leg='Perna direita',
    left_foot='Pe esquerdo',right_foot='Pe direito',
}

local function localHandItems()
    local cached=C.fieldItems
    if type(cached)=='table' then return cached end
    local st=LocalPlayer and LocalPlayer.state and LocalPlayer.state.fiveemsFieldItems or nil
    return type(st)=='table' and st or {}
end

local function hasHandTreatmentItem(def)
    if not def or not def.item then return true end
    return (tonumber(localHandItems()[def.item]) or 0)>0
end

local function resolveTreatmentTarget(entity,isPlayer)
    if not entity or entity==0 or not DoesEntityExist(entity) then return nil end
    if isPlayer then
        local serverId=playerServerIdFromPed(entity)
        if serverId then return {kind='player',serverId=serverId} end
        return nil
    end
    local netId=ensureNpcNetId(entity)
    if not netId then return nil end
    return {kind='npc',netId=netId}
end

local function beginHandTreatment(entity,isPlayer,treatmentKey,region)
    local ref=resolveTreatmentTarget(entity,isPlayer)
    if not ref then return C.notify('Paciente nao sincronizado.') end
    C.targetRef=ref
    C.targetServerId=ref.kind=='player' and tonumber(ref.serverId) or nil
    TriggerServerEvent('fiveems:server:clinicalBeginHandTreatment',ref,nil,treatmentKey,region,isPlayer and {} or snapshotNpc(entity))
end

local function treatmentTargetOptions(isPlayer)
    local rootName=isPlayer and TREAT_PLAYER_ROOT or TREAT_NPC_ROOT
    local menuRoot=isPlayer and 'fiveems_hand_player_menu' or 'fiveems_hand_npc_menu'
    local options={
        {
            name=rootName,
            icon='fa-solid fa-briefcase-medical',
            label='Tratamentos EMS',
            distance=2.5,
            openMenu=menuRoot,
            canInteract=function(entity)
                if not entity or entity==PlayerPedId() or not DoesEntityExist(entity) then return false end
                if not isPlayer and (IsPedAPlayer(entity) or not IsPedHuman(entity)) then return false end
                return true
            end,
        }
    }

    for treatmentKey,def in pairs(FiveEMS.Treatments or {}) do
        local key=tostring(treatmentKey)
        local tdef=def
        local treatmentMenu=menuRoot..'_'..key
        local treatmentName=(isPlayer and 'fiveems_player_treat_' or 'fiveems_npc_treat_')..key
        table.insert(isPlayer and treatmentTargetNamesPlayer or treatmentTargetNamesNpc,treatmentName)
        options[#options+1]={
            name=treatmentName,
            menuName=menuRoot,
            openMenu=treatmentMenu,
            icon='fa-solid fa-kit-medical',
            label=tostring(tdef.label or key),
            distance=2.5,
            canInteract=function()
                return hasHandTreatmentItem(tdef)
            end,
        }

        local regions={}
        if tdef.region then
            regions={tostring(tdef.region)}
        else
            for _,region in ipairs((FiveEMS.Clinical and FiveEMS.Clinical.treatmentRegions and FiveEMS.Clinical.treatmentRegions[key]) or {'chest'}) do
                regions[#regions+1]=tostring(region)
            end
        end
        if key=='thermal_blanket' then regions={'chest'} end

        for _,region in ipairs(regions) do
            local r=tostring(region)
            local regionOptionName=treatmentName..'_'..r
            table.insert(isPlayer and treatmentTargetNamesPlayer or treatmentTargetNamesNpc,regionOptionName)
            options[#options+1]={
                name=regionOptionName,
                menuName=treatmentMenu,
                icon='fa-solid fa-location-dot',
                label=(key=='thermal_blanket' and 'Corpo inteiro' or (regionLabelsTarget[r] or r)),
                distance=2.5,
                canInteract=function()
                    return hasHandTreatmentItem(tdef)
                end,
                onSelect=function(data)
                    beginHandTreatment(data.entity,isPlayer,key,r)
                end,
            }
        end
    end
    return options
end

local function registerTargets()
    if GetResourceState('ox_target')~='started' then return end

    pcall(function() exports.ox_target:removeGlobalPlayer(treatmentTargetNamesPlayer) end)
    pcall(function() exports.ox_target:removeGlobalPed(treatmentTargetNamesNpc) end)
    treatmentTargetNamesPlayer={TARGET_PLAYER,TREAT_PLAYER_ROOT}
    treatmentTargetNamesNpc={TARGET_NPC,TREAT_NPC_ROOT}

    local playerBase={
        {
            name=TARGET_PLAYER,
            icon='fa-solid fa-kit-medical',
            label='Atender paciente',
            distance=2.5,
            canInteract=function(entity)
                return entity and entity~=PlayerPedId() and DoesEntityExist(entity)
            end,
            onSelect=function(data)
                local serverId=playerServerIdFromPed(data.entity)
                if not serverId then return C.notify('Player nao sincronizado.') end
                C.openClinicalTarget({kind='player',serverId=serverId})
            end,
        }
    }
    local npcBase={
        {
            name=TARGET_NPC,
            icon='fa-solid fa-kit-medical',
            label='Atender paciente',
            distance=2.5,
            canInteract=function(entity)
                return entity and entity~=PlayerPedId() and DoesEntityExist(entity)
                    and not IsPedAPlayer(entity) and IsPedHuman(entity)
            end,
            onSelect=function(data)
                local ped=data.entity
                local netId=ensureNpcNetId(ped)
                if not netId then return C.notify('NPC sem Network ID valido.') end
                C.openClinicalTarget({kind='npc',netId=netId},snapshotNpc(ped))
            end,
        }
    }

    pcall(function() exports.ox_target:addGlobalPlayer(playerBase) end)
    pcall(function() exports.ox_target:addGlobalPed(npcBase) end)

    local okPlayer,errPlayer=pcall(function() exports.ox_target:addGlobalPlayer(treatmentTargetOptions(true)) end)
    if not okPlayer then print(('[FiveEMS][Treatments] Falha ao registrar ox_target Player: %s'):format(tostring(errPlayer))) end
    local okNpc,errNpc=pcall(function() exports.ox_target:addGlobalPed(treatmentTargetOptions(false)) end)
    if not okNpc then print(('[FiveEMS][Treatments] Falha ao registrar ox_target NPC: %s'):format(tostring(errNpc))) end
end
CreateThread(function()
    Wait(1500)
    registerTargets()
end)

AddEventHandler('onClientResourceStart',function(resourceName)
    if resourceName=='ox_target' then CreateThread(function() Wait(500); registerTargets() end) end
end)

RegisterNetEvent('fiveems:client:clinicalStateUpdated',function(payload)
    if type(payload)~='table' then return end
    C.targetRef=payload.targetRef or C.targetRef
    C.targetServerId=C.targetRef and C.targetRef.kind=='player' and tonumber(C.targetRef.serverId) or nil
    C.targetState=payload.state
    if C.bootstrap then
        C.bootstrap.medicalBag=payload.bag or C.bootstrap.medicalBag
        C.bootstrap.clinicalCatalog=payload.clinicalCatalog or C.bootstrap.clinicalCatalog
        C.bootstrap.treatments=payload.treatmentCatalog or C.bootstrap.treatments
    end
    SendNUIMessage({action='clinicalState',data=payload})
end)

RegisterNetEvent('fiveems:client:monitorStateUpdated',function(payload)
    if type(payload)~='table' then return end
    C.monitorState=payload.state
    if C.monitorSession then
        C.monitorSession.ref=payload.targetRef or C.monitorSession.ref
    end
    if C.uiContext=='monitor' then
        C.targetRef=payload.targetRef or C.targetRef
        C.targetServerId=C.targetRef and C.targetRef.kind=='player' and tonumber(C.targetRef.serverId) or nil
        C.targetState=payload.state
    end
    SendNUIMessage({action='monitorState',data=payload})
end)

RegisterNetEvent('fiveems:client:medicalBagUpdated',function(bag)
    if C.bootstrap then C.bootstrap.medicalBag=bag or {} end
    SendNUIMessage({action='medicalBag',data=bag or {}})
end)

RegisterNetEvent('fiveems:client:fieldItemsUpdated',function(items)
    C.fieldItems=type(items)=='table' and items or {}
end)

local handTreatmentInProgress=false

local function targetPedFromRef(ref)
    if type(ref)~='table' then return nil end
    if ref.kind=='player' then
        local player=GetPlayerFromServerId(tonumber(ref.serverId) or -1)
        if player==-1 then return nil end
        local ped=GetPlayerPed(player)
        return ped~=0 and DoesEntityExist(ped) and ped or nil
    end
    if ref.kind=='npc' then
        local netId=tonumber(ref.netId)
        if not netId or netId<=0 or not NetworkDoesEntityExistWithNetworkId(netId) then return nil end
        local ped=NetToPed(netId)
        return ped~=0 and DoesEntityExist(ped) and ped or nil
    end
    return nil
end

RegisterNetEvent('fiveems:client:handTreatmentApproved',function(payload)
    if handTreatmentInProgress or type(payload)~='table' then return end
    local token=tostring(payload.token or '')
    if token=='' then return end
    local targetPed=targetPedFromRef(payload.targetRef)
    if not targetPed then
        TriggerServerEvent('fiveems:server:clinicalCancelHandTreatment',token)
        return C.notify('Paciente nao esta mais disponivel.')
    end

    handTreatmentInProgress=true
    local ped=PlayerPedId()
    TaskTurnPedToFaceEntity(ped,targetPed,650)
    Wait(250)

    local completed=false
    if lib and lib.progressCircle then
        local targetOnGround=not IsPedInAnyVehicle(targetPed,false) and (tonumber(GetEntityHeightAboveGround(targetPed)) or 0.0)<=0.40
        local treatmentAnim=targetOnGround
            and {scenario='CODE_HUMAN_MEDIC_KNEEL'}
            or {dict='amb@medic@standing@tendtodead@base',clip='base',flag=1}
        completed=lib.progressCircle({
            duration=math.max(1200,math.floor(tonumber(payload.durationMs) or 4500)),
            position='bottom',
            label=tostring(payload.progressLabel or payload.label or 'Realizando procedimento...'),
            useWhileDead=false,
            canCancel=true,
            disable={move=true,car=true,combat=true,sprint=true},
            anim=treatmentAnim,
        })==true
    else
        local duration=math.max(1200,math.floor(tonumber(payload.durationMs) or 4500))
        local untilAt=GetGameTimer()+duration
        TaskStartScenarioInPlace(ped,'CODE_HUMAN_MEDIC_TEND_TO_DEAD',0,true)
        completed=true
        while GetGameTimer()<untilAt do
            Wait(0)
            DisableControlAction(0,21,true)
            DisableControlAction(0,22,true)
            DisableControlAction(0,24,true)
            DisableControlAction(0,25,true)
            if IsControlJustPressed(0,177) then completed=false break end
        end
        ClearPedTasks(ped)
    end

    handTreatmentInProgress=false
    if completed then
        TriggerServerEvent('fiveems:server:clinicalCompleteHandTreatment',token)
    else
        TriggerServerEvent('fiveems:server:clinicalCancelHandTreatment',token)
        C.notify('Procedimento cancelado. O item nao foi consumido.')
    end
end)



-- =====================================================================
-- FiveFD Scene Health Audit camera + live bone projection
-- =====================================================================
local sceneAuditActive = false
local sceneAuditCam = nil
local sceneAuditAngle = 92.0
local sceneAuditDistance = 2.15
local sceneAuditHeight = 0.80

local sceneRegionBones = {
    head = 31086,
    neck = 39317,
    chest = 24818,
    abdomen = 24817,
    pelvis = 11816,
    left_arm = 61163,
    right_arm = 28252,
    left_leg = 63931,
    right_leg = 36864,
    left_foot = 14201,
    right_foot = 52301,
}

local sceneRegionScreenOffsets = {
    head = {x = 0.0, y = -0.016},
    neck = {x = 0.0, y = -0.010},
    chest = {x = 0.0, y = 0.000},
    abdomen = {x = 0.0, y = 0.010},
    pelvis = {x = 0.0, y = 0.012},
    left_arm = {x = -0.006, y = 0.002},
    right_arm = {x = 0.006, y = 0.002},
    left_leg = {x = -0.004, y = 0.026},
    right_leg = {x = 0.004, y = 0.026},
    left_foot = {x = -0.005, y = 0.014},
    right_foot = {x = 0.005, y = 0.014},
}

local function clinicalTargetPed()
    local ref = C.targetRef
    if type(ref) ~= 'table' then return nil end
    if ref.kind == 'player' then
        local player = GetPlayerFromServerId(tonumber(ref.serverId) or -1)
        if player == -1 then return nil end
        local ped = GetPlayerPed(player)
        return ped ~= 0 and DoesEntityExist(ped) and ped or nil
    end
    if ref.kind == 'npc' then
        local netId = tonumber(ref.netId)
        if not netId or netId <= 0 or not NetworkDoesEntityExistWithNetworkId(netId) then return nil end
        local ped = NetToPed(netId)
        return ped ~= 0 and DoesEntityExist(ped) and ped or nil
    end
    return nil
end

local providerGroundScenarioActive = false

local function clinicalPatientOnGround(ped)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return false end
    if IsPedInAnyVehicle(ped, false) then return false end
    local height = tonumber(GetEntityHeightAboveGround(ped)) or 0.0
    return height <= 0.35
end

local function setProviderGroundScenario(active)
    local playerPed = PlayerPedId()
    if not playerPed or playerPed == 0 or not DoesEntityExist(playerPed) then return end

    if active then
        if providerGroundScenarioActive then return end
        ClearPedTasks(playerPed)
        TaskStartScenarioInPlace(playerPed, 'CODE_HUMAN_MEDIC_KNEEL', 0, true)
        providerGroundScenarioActive = true
        return
    end

    if providerGroundScenarioActive then
        ClearPedTasks(playerPed)
        providerGroundScenarioActive = false
    end
end

local function refreshProviderGroundScenario()
    if not sceneAuditActive then return setProviderGroundScenario(false) end
    setProviderGroundScenario(clinicalPatientOnGround(clinicalTargetPed()))
end

local function destroyClinicalSceneCamera()
    sceneAuditActive = false
    if sceneAuditCam and DoesCamExist(sceneAuditCam) then
        RenderScriptCams(false, true, 220, true, true)
        DestroyCam(sceneAuditCam, false)
    end
    sceneAuditCam = nil
    ClearFocus()
    setProviderGroundScenario(false)
    SendNUIMessage({action='clinicalSceneMarkers', data={markers={}}})
end

local function updateClinicalSceneCamera()
    if not sceneAuditActive then return end
    local ped = clinicalTargetPed()
    if not ped then return end
    refreshProviderGroundScenario()

    local chestBone = GetPedBoneIndex(ped, 24818)
    local target = chestBone and chestBone >= 0 and GetWorldPositionOfEntityBone(ped, chestBone) or GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    local theta = math.rad(heading + sceneAuditAngle)
    local camX = target.x + math.cos(theta) * sceneAuditDistance
    local camY = target.y + math.sin(theta) * sceneAuditDistance
    local camZ = target.z + sceneAuditHeight

    if not sceneAuditCam or not DoesCamExist(sceneAuditCam) then
        sceneAuditCam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
        SetCamActive(sceneAuditCam, true)
        RenderScriptCams(true, true, 260, true, true)
    end
    SetCamCoord(sceneAuditCam, camX, camY, camZ)
    PointCamAtCoord(sceneAuditCam, target.x, target.y, target.z + 0.02)
    SetCamFov(sceneAuditCam, 47.0)
end

local function dot3(a,b)
    return (a.x*b.x) + (a.y*b.y) + (a.z*b.z)
end

local function cross3(a,b)
    return vector3(
        (a.y*b.z) - (a.z*b.y),
        (a.z*b.x) - (a.x*b.z),
        (a.x*b.y) - (a.y*b.x)
    )
end

local function norm3(v)
    local len = math.sqrt((v.x*v.x)+(v.y*v.y)+(v.z*v.z))
    if len <= 0.00001 then return vector3(0.0,0.0,0.0) end
    return vector3(v.x/len,v.y/len,v.z/len)
end

-- GetScreenCoordFromWorldCoord can return false with some scripted-camera/MLO
-- combinations. This fallback projects against the FINAL rendered camera.
local function manualWorldToScreen(point)
    local okCoord, cam = pcall(GetFinalRenderedCamCoord)
    local okRot, rot = pcall(GetFinalRenderedCamRot, 2)
    local okFov, fov = pcall(GetFinalRenderedCamFov)
    if not okCoord or not okRot or not cam or not rot then return false,0.5,0.5 end

    fov = okFov and tonumber(fov) or 47.0
    local pitch = math.rad(tonumber(rot.x) or 0.0)
    local yaw = math.rad(tonumber(rot.z) or 0.0)

    local forward = norm3(vector3(
        -math.sin(yaw) * math.cos(pitch),
         math.cos(yaw) * math.cos(pitch),
         math.sin(pitch)
    ))
    local right = norm3(vector3(math.cos(yaw), math.sin(yaw), 0.0))
    local up = norm3(cross3(right, forward))
    local rel = vector3(point.x-cam.x, point.y-cam.y, point.z-cam.z)

    local depth = dot3(rel, forward)
    if depth <= 0.04 then return false,0.5,0.5 end

    local horizontal = dot3(rel, right)
    local vertical = dot3(rel, up)

    local screenW, screenH = 1920.0, 1080.0
    local okRes, w, h = pcall(GetActiveScreenResolution)
    if okRes and tonumber(w) and tonumber(h) and w > 0 and h > 0 then
        screenW, screenH = w + 0.0, h + 0.0
    end

    local aspect = screenW / math.max(1.0, screenH)
    local tanHalf = math.tan(math.rad(math.max(15.0, math.min(100.0, fov))) * 0.5)
    if tanHalf <= 0.0001 then return false,0.5,0.5 end

    local sx = 0.5 + (horizontal / (depth * tanHalf * aspect)) * 0.5
    local sy = 0.5 - (vertical / (depth * tanHalf)) * 0.5
    local visible = sx >= -0.04 and sx <= 1.04 and sy >= -0.04 and sy <= 1.04

    return visible, math.max(0.0,math.min(1.0,sx)), math.max(0.0,math.min(1.0,sy))
end

local function projectClinicalPoint(point)
    local ok, sx, sy = GetScreenCoordFromWorldCoord(point.x, point.y, point.z)
    local valid = ok == true and tonumber(sx) and tonumber(sy)
        and sx >= 0.0 and sx <= 1.0 and sy >= 0.0 and sy <= 1.0
    if valid then return true,sx,sy end
    return manualWorldToScreen(point)
end

local function sendClinicalSceneMarkers()
    local ped = clinicalTargetPed()
    if not ped then
        SendNUIMessage({action='clinicalSceneMarkers', data={markers={}}})
        return
    end
    local markers = {}
    for region,boneId in pairs(sceneRegionBones) do
        local bone = GetPedBoneIndex(ped, boneId)
        if bone and bone >= 0 then
            local p = GetWorldPositionOfEntityBone(ped, bone)
            local ok, sx, sy = projectClinicalPoint(p)
            local tweak = sceneRegionScreenOffsets[region] or {}
            sx = math.max(0.0, math.min(1.0, (sx or 0.5) + (tonumber(tweak.x) or 0.0)))
            sy = math.max(0.0, math.min(1.0, (sy or 0.5) + (tonumber(tweak.y) or 0.0)))
            markers[region] = {x=sx, y=sy, visible=ok == true}
        else
            markers[region] = {x=0.5,y=0.5,visible=false}
        end
    end
    SendNUIMessage({action='clinicalSceneMarkers', data={markers=markers}})
end

RegisterNUICallback('clinicalSceneStart', function(_, cb)
    sceneAuditActive = true
    sceneAuditAngle = 92.0
    sceneAuditDistance = 2.15
    sceneAuditHeight = 0.80
    updateClinicalSceneCamera()
    cb({ok=true})
end)

RegisterNUICallback('clinicalSceneStop', function(_, cb)
    destroyClinicalSceneCamera()
    cb({ok=true})
end)

AddEventHandler('fiveems:client:forceClinicalSceneStop', function()
    destroyClinicalSceneCamera()
end)

RegisterNUICallback('clinicalSceneCamera', function(data, cb)
    local action = tostring(data and data.action or '')
    if action == 'left' then sceneAuditAngle = sceneAuditAngle - 22.5
    elseif action == 'right' then sceneAuditAngle = sceneAuditAngle + 22.5
    elseif action == 'zoom_in' then sceneAuditDistance = math.max(1.05, sceneAuditDistance - 0.18)
    elseif action == 'zoom_out' then sceneAuditDistance = math.min(4.0, sceneAuditDistance + 0.18)
    elseif action == 'reset' or action == 'prepare' then
        sceneAuditAngle = 92.0; sceneAuditDistance = 2.15; sceneAuditHeight = 0.80
    elseif action == 'focus' then
        sceneAuditDistance = sceneAuditDistance > 1.85 and 1.65 or 2.15
    end
    sceneAuditActive = true
    updateClinicalSceneCamera()
    cb({ok=true})
end)

CreateThread(function()
    while true do
        if sceneAuditActive then
            updateClinicalSceneCamera()
            sendClinicalSceneMarkers()
            Wait(50)
        else
            Wait(400)
        end
    end
end)

AddEventHandler('onResourceStop',function(resourceName)
    if resourceName~=GetCurrentResourceName() then return end
    destroyClinicalSceneCamera()
    if GetResourceState('ox_target')~='started' then return end
    pcall(function() exports.ox_target:removeGlobalPlayer(treatmentTargetNamesPlayer) end)
    pcall(function() exports.ox_target:removeGlobalPed(treatmentTargetNamesNpc) end)
end)
