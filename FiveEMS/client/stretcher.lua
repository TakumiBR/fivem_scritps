FiveEMS = FiveEMS or {}
local C = FiveEMS.Client

local stretcher = nil
local stretcherProfile = nil
local attachedVehicle = nil
local attachedPatientServerId = nil
local attachedNpcPed = nil
local attachedNpcNetId = nil
local attachedNpcStretcherNetId = nil
local selfPatientAttachment = nil
local patientProxyState = {}
local patientPosePhaseByPed = {}
local patientPosePhaseByModel = {}
local pushing = false
local stretcherHigh = true
local targetBound = false
local registeredTargetModels = {}
local vehicleUnloadTargetBound = false
local setStretcherState

local ROOT_MENU = nil
local PATIENT_MENU = 'fiveems_stretcher_patient'
local TRANSFER_MENU = 'fiveems_stretcher_transfer'
local SETTINGS_MENU = 'fiveems_stretcher_settings'
local EQUIPMENT_MENU = 'fiveems_stretcher_equipment'

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

local function vec(data, fallback)
    data = data or fallback or {}
    return vector3(tonumber(data.x) or 0.0, tonumber(data.y) or 0.0, tonumber(data.z) or 0.0)
end

local function rot(data)
    data = data or {}
    return tonumber(data.rx) or 0.0, tonumber(data.ry) or 0.0, tonumber(data.rz or data.heading) or 0.0
end

local function canUseStretcher()
    local bs = C.bootstrap or {}
    local member = bs.member
    if bs.isAdmin == true then return true end
    if not member then return false end
    if member.on_duty == true then return true end
    for _, permission in ipairs(member.permissions or {}) do
        if permission == '*' or permission == 'garage.use' or permission == 'patient.treat' or permission == 'department.manage' then
            return true
        end
    end
    return false
end

local function patientPoseConfig()
    local cfg = (Config.Stretcher and Config.Stretcher.patientPose) or {}
    return {
        dict = tostring(cfg.dict or 'anim@gangops@morgue@table@'),
        anim = tostring(cfg.anim or 'body_search'),
        phase = math.max(0.0, math.min(0.99, tonumber(cfg.phase) or 0.46)),
        autoPhase = cfg.autoPhase ~= false,
        repairIntervalMs = math.max(350, tonumber(cfg.repairIntervalMs) or 700),
        defaultTransform = cfg.defaultTransform or {x=0.0,y=0.08,z=1.12,rx=0.0,ry=0.0,rz=180.0},
    }
end

local function normalizePatientTransform(value)
    local pose = patientPoseConfig()
    local d = pose.defaultTransform
    value = type(value) == 'table' and value or {}

    if next(value) == nil then
        return {x=d.x,y=d.y,z=d.z,rx=d.rx,ry=d.ry,rz=d.rz}
    end

    local x = tonumber(value.x) or 0.0
    local y = tonumber(value.y) or 0.0
    local z = tonumber(value.z) or 0.0
    local rx = tonumber(value.rx) or 0.0
    local ry = tonumber(value.ry) or 0.0
    local rz = tonumber(value.rz or value.heading) or 0.0

    -- Compatibilidade: migra os dois baselines automaticos antigos.
    local legacy075 = math.abs(x) < 0.02 and math.abs(y) < 0.02
        and math.abs(z - 0.75) < 0.03 and math.abs(rx) < 0.5 and math.abs(ry) < 0.5
        and math.abs(math.abs(rz) - 180.0) < 1.0
    local legacy031 = math.abs(x) < 0.02 and math.abs(y - 0.10) < 0.02
        and math.abs(z - 1.12) < 0.03 and math.abs(rx) < 0.5 and math.abs(ry) < 0.5
        and math.abs(math.abs(rz) - 180.0) < 1.0
    local legacy040 = math.abs(x) < 0.02 and math.abs(y) < 0.02
        and math.abs(z - 1.12) < 0.03 and math.abs(rx) < 0.5 and math.abs(ry) < 0.5
        and math.abs(math.abs(rz) - 180.0) < 1.0
    if legacy075 or legacy031 or legacy040 then
        return {x=d.x,y=d.y,z=d.z,rx=d.rx,ry=d.ry,rz=d.rz}
    end

    return {x=x,y=y,z=z,rx=rx,ry=ry,rz=rz}
end

local function loadPatientPose()
    local pose = patientPoseConfig()
    RequestAnimDict(pose.dict)
    local timeout = GetGameTimer() + 4000
    while not HasAnimDictLoaded(pose.dict) and GetGameTimer() < timeout do Wait(20) end
    return HasAnimDictLoaded(pose.dict), pose
end

local function boneWorld(ped, boneId)
    local bone = GetPedBoneIndex(ped, boneId)
    if not bone or bone < 0 then return nil end
    local p = GetWorldPositionOfEntityBone(ped, bone)
    if not p then return nil end
    return vector3(p.x,p.y,p.z)
end

local function vsub(a,b)
    return vector3(a.x-b.x,a.y-b.y,a.z-b.z)
end

local function vlen(v)
    return math.sqrt((v.x*v.x)+(v.y*v.y)+(v.z*v.z))
end

local function vdot(a,b)
    return (a.x*b.x)+(a.y*b.y)+(a.z*b.z)
end

local function limbStraightScore(a,b,c)
    if not a or not b or not c then return 0.0 end
    local ab=vsub(b,a)
    local bc=vsub(c,b)
    local lab,lbc=vlen(ab),vlen(bc)
    if lab<0.001 or lbc<0.001 then return 0.0 end

    local cosine=math.max(-1.0,math.min(1.0,vdot(ab,bc)/(lab*lbc)))
    local direct=vlen(vsub(c,a))
    local extension=math.max(0.0,math.min(1.0,direct/(lab+lbc)))
    return ((cosine+1.0)*0.5)*0.72 + extension*0.28
end

local function currentSupineScore(ped)
    -- GTA skeleton ids: upper/thigh -> forearm/calf -> hand/foot.
    local lLeg=limbStraightScore(boneWorld(ped,58271),boneWorld(ped,63931),boneWorld(ped,14201))
    local rLeg=limbStraightScore(boneWorld(ped,51826),boneWorld(ped,36864),boneWorld(ped,52301))
    local lArm=limbStraightScore(boneWorld(ped,45509),boneWorld(ped,61163),boneWorld(ped,18905))
    local rArm=limbStraightScore(boneWorld(ped,40269),boneWorld(ped,28252),boneWorld(ped,57005))

    -- Legs matter more for the "folded/twisted on stretcher" regression.
    return (lLeg+rLeg)*2.2 + (lArm+rArm)
end

local function chooseFlatPatientPhase(ped, pose)
    if not pose.autoPhase or not ped or not DoesEntityExist(ped) then return pose.phase end

    local model=GetEntityModel(ped)
    local cached=patientPosePhaseByModel[model]
    if cached then return cached end

    local candidates={0.02,0.10,0.18,0.26,0.34,0.42,0.50,0.58,0.66,0.74,0.82,0.90}
    local bestPhase,bestScore=pose.phase,-9999.0

    for _,phase in ipairs(candidates) do
        if not DoesEntityExist(ped) then break end
        SetEntityAnimCurrentTime(ped,pose.dict,pose.anim,phase)
        SetEntityAnimSpeed(ped,pose.dict,pose.anim,0.0)
        Wait(0)
        local score=currentSupineScore(ped)
        if score>bestScore then
            bestScore,bestPhase=score,phase
        end
    end

    patientPosePhaseByModel[model]=bestPhase
    return bestPhase
end

local function pinPatientPosePhase(ped, pose, explicitPhase)
    if not ped or not DoesEntityExist(ped) then return end
    pose = pose or patientPoseConfig()

    if IsEntityPlayingAnim(ped, pose.dict, pose.anim, 3) then
        local phase=explicitPhase or patientPosePhaseByPed[ped] or pose.phase
        SetEntityAnimCurrentTime(ped, pose.dict, pose.anim, phase)
        SetEntityAnimSpeed(ped, pose.dict, pose.anim, 0.0)
    end
end

local function playPatientPose(ped, base)
    if not ped or not DoesEntityExist(ped) then return false end
    local loaded, pose = loadPatientPose()
    if not loaded then return false end

    TaskPlayAnim(ped, pose.dict, pose.anim, 8.0, -8.0, -1, 1, 0.0, false, false, false)
    Wait(0)

    local phase=patientPosePhaseByPed[ped]
    if not phase then
        phase=chooseFlatPatientPhase(ped,pose)
        patientPosePhaseByPed[ped]=phase
    end
    pinPatientPosePhase(ped,pose,phase)
    return true
end

-- FiveFD kept hospital-bed rendering independent from the Stryker's pinned
-- transport frame. The ANCHOR is authoritative; body_search is allowed to
-- establish its normal supine bed pose and the world transform is re-pinned.
local function playCarePointPose(ped)
    if not ped or not DoesEntityExist(ped) then return false end
    local loaded,pose=loadPatientPose()
    if not loaded then return false end

    TaskPlayAnim(ped,pose.dict,pose.anim,8.0,-8.0,-1,1,0.0,false,false,false)
    return true
end

local function preparePatientPed(ped, isPlayer)
    if not ped or not DoesEntityExist(ped) then return end

    if not patientProxyState[ped] then
        patientProxyState[ped] = {
            wasDead = (not isPlayer) and (IsEntityDead(ped) or IsPedFatallyInjured(ped)) or false,
            health = GetEntityHealth(ped),
            invincible = GetPlayerInvincible and isPlayer and GetPlayerInvincible(PlayerId()) or false,
        }
    end

    -- FiveFD Clinical NPC Transport Proxy: o estado clinico logico continua no servidor,
    -- enquanto o ped fisico e normalizado para aceitar uma pose deterministica.
    if not isPlayer and (IsEntityDead(ped) or IsPedFatallyInjured(ped)) then
        ResurrectPed(ped)
        ReviveInjuredPed(ped)
        SetEntityHealth(ped, math.max(120, GetEntityMaxHealth(ped)))
        ClearPedTasksImmediately(ped)
    elseif not isPlayer and IsPedInjured(ped) then
        -- Proxy apenas fisico; o estado clinico real continua no Medical Engine.
        ReviveInjuredPed(ped)
        ClearPedTasksImmediately(ped)
    end

    FreezeEntityPosition(ped, false)
    SetPedCanRagdoll(ped, false)
    SetEntityCollision(ped, false, false)
    SetEntityInvincible(ped, true)

    if not isPlayer then
        SetEntityAsMissionEntity(ped, true, true)
        SetBlockingOfNonTemporaryEvents(ped, true)
        SetPedFleeAttributes(ped, 0, false)
        SetPedKeepTask(ped, true)
    end
end

local function restorePatientPed(ped, isPlayer, restoreClinicalState)
    if not ped or not DoesEntityExist(ped) then return end
    local proxy = patientProxyState[ped]

    FreezeEntityPosition(ped, false)
    SetPedCanRagdoll(ped, true)
    SetEntityCollision(ped, true, true)
    if isPlayer then
        SetEntityInvincible(ped, proxy and proxy.invincible == true or false)
    else
        SetEntityInvincible(ped, false)
    end

    if not isPlayer then
        SetBlockingOfNonTemporaryEvents(ped, false)
        SetPedKeepTask(ped, false)
        if restoreClinicalState ~= false and proxy and proxy.wasDead then
            SetEntityHealth(ped, 0)
        elseif proxy and tonumber(proxy.health) and proxy.health > 0 then
            SetEntityHealth(ped, math.max(1, tonumber(proxy.health)))
        end
    end

    patientProxyState[ped] = nil
    patientPosePhaseByPed[ped] = nil
end

local function attachPatientEntity(ped, base, transform, isPlayer)
    if not ped or not DoesEntityExist(ped) or not base or not DoesEntityExist(base) then return false end

    local t = normalizePatientTransform(transform)
    preparePatientPed(ped, isPlayer)

    -- Ordem homologada no FiveFD: limpa ragdoll/tasks -> ATTACH -> anima deitado.
    ClearPedTasksImmediately(ped)
    AttachEntityToEntity(
        ped, base, 0,
        t.x, t.y, t.z,
        t.rx, t.ry, t.rz,
        false, false, false, false, 2, true
    )

    Wait(0)
    playPatientPose(ped, base)
    return true
end

local function patientPoseStillPlaying(ped)
    local pose = patientPoseConfig()
    return IsEntityPlayingAnim(ped, pose.dict, pose.anim, 3)
end

local function startAttachmentWatchdog(ped, base, transform, isPlayer, stillWanted)
    local t = normalizePatientTransform(transform)
    local pose = patientPoseConfig()

    CreateThread(function()
        while stillWanted() do
            if not ped or not DoesEntityExist(ped) or not base or not DoesEntityExist(base) then break end

            -- V0.6.8b/FiveFD: NUNCA reattach em todo tick.
            -- Repara o vinculo apenas quando ele realmente foi perdido.
            if not IsEntityAttachedToEntity(ped, base) then
                attachPatientEntity(ped, base, t, isPlayer)
            elseif not patientPoseStillPlaying(ped) then
                -- Se o attach continua correto, reinicia SOMENTE a animacao.
                playPatientPose(ped, base)
            else
                -- Sem ClearPedTasks/reattach em loop: apenas mantem a fase estatica.
                pinPatientPosePhase(ped, pose)
            end

            Wait(pose.repairIntervalMs)
        end
    end)
end

local function hasPatient()
    return attachedPatientServerId ~= nil
        or (attachedNpcNetId ~= nil and tonumber(attachedNpcNetId) > 0)
        or (attachedNpcPed and DoesEntityExist(attachedNpcPed))
end

local function transportConfig()
    local cfg = (Config.Stretcher and Config.Stretcher.patientTransport) or {}
    return {
        streamGraceMs = math.max(1500, tonumber(cfg.streamGraceMs) or 12000),
        refreshMs = math.max(1500, tonumber(cfg.refreshMs) or 5000),
        transferRadius = math.max(2.5, tonumber(cfg.transferRadius) or 7.5),
    }
end

local function ensureNpcNetworked(ped)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end

    NetworkRequestControlOfEntity(ped)
    local deadline = GetGameTimer() + 1800
    while not NetworkHasControlOfEntity(ped) and GetGameTimer() < deadline do
        NetworkRequestControlOfEntity(ped)
        Wait(0)
    end

    SetEntityAsMissionEntity(ped, true, true)

    if not NetworkGetEntityIsNetworked(ped) then
        NetworkRegisterEntityAsNetworked(ped)
        Wait(0)
    end

    if not NetworkGetEntityIsNetworked(ped) then return nil end

    local netId = PedToNet(ped)
    if not netId or netId <= 0 then return nil end

    pcall(function() SetNetworkIdCanMigrate(netId, true) end)
    pcall(function() NetworkSetNetworkIdExistsOnAllMachines(netId, true) end)

    return netId
end

local function resolveNpcByNetId(netId, timeoutMs)
    netId = tonumber(netId)
    if not netId or netId <= 0 then return nil end

    if attachedNpcPed and DoesEntityExist(attachedNpcPed)
        and NetworkGetEntityIsNetworked(attachedNpcPed)
        and PedToNet(attachedNpcPed) == netId then
        return attachedNpcPed
    end

    local deadline = GetGameTimer() + math.max(0, tonumber(timeoutMs) or 0)
    repeat
        if NetworkDoesEntityExistWithNetworkId(netId) then
            local ped = NetworkGetEntityFromNetworkId(netId)
            if ped and ped ~= 0 and DoesEntityExist(ped) and IsEntityAPed(ped) then
                attachedNpcPed = ped
                SetEntityAsMissionEntity(ped, true, true)
                SetPedKeepTask(ped, true)
                return ped
            end
        end
        if GetGameTimer() >= deadline then break end
        Wait(50)
    until false

    return nil
end

local function currentModelName()
    return (C.department and C.department.settings and C.department.settings.defaultStretcherModel)
        or Config.Stretcher.defaultModel
        or 'strykerpro'
end

local function selectProfileForVehicle(veh)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return nil end
    local hash = GetEntityModel(veh)
    for _, p in ipairs((C.department and C.department.stretcherProfiles) or {}) do
        if joaat(p.vehicle_model or '') == hash or tostring(p.vehicle_model) == tostring(hash) then
            return p
        end
    end
    return stretcherProfile
end

local function closestVehicle(radius)
    local pos = GetEntityCoords(PlayerPedId())
    local best, bestDist
    for _, veh in ipairs(GetGamePool('CVehicle')) do
        if DoesEntityExist(veh) and veh ~= stretcher then
            local d = #(GetEntityCoords(veh) - pos)
            if d <= (radius or 7.0) and (not bestDist or d < bestDist) then
                best, bestDist = veh, d
            end
        end
    end
    return best
end

local function closestPlayerServerId(radius)
    local ped = PlayerPedId()
    local p = GetEntityCoords(ped)
    local best, bestDist
    for _, player in ipairs(GetActivePlayers()) do
        if player ~= PlayerId() then
            local targetPed = GetPlayerPed(player)
            if targetPed ~= 0 and DoesEntityExist(targetPed) then
                local d = #(GetEntityCoords(targetPed) - p)
                if d <= (radius or 3.0) and (not bestDist or d < bestDist) then
                    best, bestDist = GetPlayerServerId(player), d
                end
            end
        end
    end
    return best
end

local function closestNpc(radius)
    local p = GetEntityCoords(PlayerPedId())
    local best, bestDist
    for _, ped in ipairs(GetGamePool('CPed')) do
        if ped ~= PlayerPedId() and DoesEntityExist(ped) and not IsPedAPlayer(ped) then
            local d = #(GetEntityCoords(ped) - p)
            if d <= (radius or 3.5) and (not bestDist or d < bestDist) then
                best, bestDist = ped, d
            end
        end
    end
    return best
end

local function carePointCandidates()
    local out, seen = {}, {}
    local selectedDepartmentId = C.department and tonumber(C.department.id) or nil

    local function add(points)
        for _, point in ipairs(points or {}) do
            local id = tonumber(point.id)
            if id and not seen[id] then
                seen[id] = true
                out[#out+1] = point
            end
        end
    end

    add(C.department and C.department.points)

    for _, department in ipairs(C.worldDepartments or {}) do
        if not selectedDepartmentId or tonumber(department.id) == selectedDepartmentId then
            add(department.points)
        end
    end

    return out
end

local function nearestCarePoint(kind, radius)
    local p = GetEntityCoords(stretcher and DoesEntityExist(stretcher) and stretcher or PlayerPedId())
    local best, bestDist

    for _, point in ipairs(carePointCandidates()) do
        if point.type == kind and point.x and point.y and point.z then
            local d = #(vector3(point.x + 0.0, point.y + 0.0, point.z + 0.0) - p)
            if d <= (radius or 12.0) and (not bestDist or d < bestDist) then
                best, bestDist = point, d
            end
        end
    end

    return best, bestDist
end

local function nearestTransferPoint(radius)
    local allowed = {
        [FiveEMS.PointTypes.BED or 'bed'] = true,
        [FiveEMS.PointTypes.SURGERY or 'surgery'] = true,
        [FiveEMS.PointTypes.IML or 'iml'] = true,
        [FiveEMS.PointTypes.OTHER or 'other'] = true,
        bed = true, surgery = true, iml = true, other = true,
    }

    local p = GetEntityCoords(stretcher and DoesEntityExist(stretcher) and stretcher or PlayerPedId())
    local best, bestDist

    for _, point in ipairs(carePointCandidates()) do
        if allowed[point.type] and point.x and point.y and point.z then
            local d = #(vector3(point.x + 0.0, point.y + 0.0, point.z + 0.0) - p)
            if d <= (radius or transportConfig().transferRadius) and (not bestDist or d < bestDist) then
                best, bestDist = point, d
            end
        end
    end

    return best, bestDist
end

local function worldTransformForPoint(point)
    local t = point.data and point.data.patient_transform or {}
    local heading = tonumber(point.heading) or 0.0
    local rad = math.rad(heading)
    local lx, ly = tonumber(t.x) or 0.0, tonumber(t.y) or 0.0
    local wx = (tonumber(point.x) or 0.0) + (lx * math.cos(rad)) - (ly * math.sin(rad))
    local wy = (tonumber(point.y) or 0.0) + (lx * math.sin(rad)) + (ly * math.cos(rad))
    local wz = (tonumber(point.z) or 0.0) + (tonumber(t.z) or 0.65)
    local rz = heading + (tonumber(t.rz or t.heading) or 0.0)
    return vector3(wx, wy, wz), vector3(tonumber(t.rx) or 0.0, tonumber(t.ry) or 0.0, rz)
end

local function extraConfig()
    return (Config.Stretcher and Config.Stretcher.extras) or {}
end

local function setExtraEnabled(entity, extraId, enabled)
    if not entity or not DoesEntityExist(entity) or not IsEntityAVehicle(entity) then return false end
    extraId = tonumber(extraId)
    if not extraId or not DoesExtraExist(entity, extraId) then return false end
    -- SET_VEHICLE_EXTRA recebe "disable": 0 = ligado, 1 = desligado.
    SetVehicleExtra(entity, extraId, enabled and 0 or 1)
    return true
end

local function isExtraEnabled(entity, extraId)
    return entity and DoesEntityExist(entity) and IsEntityAVehicle(entity) and DoesExtraExist(entity, extraId) and IsVehicleExtraTurnedOn(entity, extraId)
end

local function applyLegVisual(high)
    if not stretcher or not DoesEntityExist(stretcher) or not IsEntityAVehicle(stretcher) then return end
    local ex = extraConfig()
    -- Correcao homologada em jogo:
    -- Extra 1 (legA) = maca alta / aberta / operacional.
    -- Extra 2 (legB) = maca baixa / recolhida / interna na ambulancia.
    if high then
        setExtraEnabled(stretcher, ex.legA or 1, true)
        setExtraEnabled(stretcher, ex.legB or 2, false)
    else
        setExtraEnabled(stretcher, ex.legA or 1, false)
        setExtraEnabled(stretcher, ex.legB or 2, true)
    end
end

local function applyMovingVisual()
    -- O resource de referencia usa A ligado / B desligado durante a conducao.
    if not stretcher or not DoesEntityExist(stretcher) then return end
    local ex = extraConfig()
    setExtraEnabled(stretcher, ex.legA or 1, true)
    setExtraEnabled(stretcher, ex.legB or 2, false)
end

local function restoreDefaultEquipment()
    if not stretcher or not DoesEntityExist(stretcher) or not IsEntityAVehicle(stretcher) then return end
    local ex = extraConfig()
    local preset = (Config.Stretcher and Config.Stretcher.garagePreset) or {}

    -- Estado de garagem:
    --  - maca alta/aberta para uso;
    --  - sem equipamentos sobre a maca;
    --  - encosto/cabeceira abaixado.
    -- O Stretcher-1.0.5 de referencia usa Extra 12 ligado / Extra 11 desligado
    -- como estado inicial da cabeceira.
    applyLegVisual(preset.legsHigh ~= false)
    setExtraEnabled(stretcher, ex.backboard or 3, preset.backboard == true)
    setExtraEnabled(stretcher, ex.monitor or 5, preset.monitor == true)
    setExtraEnabled(stretcher, ex.redBag or 6, preset.redBag == true)
    setExtraEnabled(stretcher, ex.blueBag or 7, preset.blueBag == true)

    local headrest = tostring(preset.headrest or 'down')
    if headrest == 'up' then
        setExtraEnabled(stretcher, ex.headrestB or 12, false)
        setExtraEnabled(stretcher, ex.headrestA or 11, true)
    else
        setExtraEnabled(stretcher, ex.headrestA or 11, false)
        setExtraEnabled(stretcher, ex.headrestB or 12, true)
    end
end

local function toggleEquipmentExtra(extraId, label)
    if not stretcher or not DoesEntityExist(stretcher) or not IsEntityAVehicle(stretcher) then return end
    if not DoesExtraExist(stretcher, extraId) then return C.notify((label or 'Extra')..' nao existe neste modelo.') end
    local enabled = isExtraEnabled(stretcher, extraId)
    setExtraEnabled(stretcher, extraId, not enabled)
    C.notify(('%s %s.'):format(label or ('Extra '..extraId), (not enabled) and 'ativado' or 'removido'))
end

local function toggleHeadrest()
    if not stretcher or not DoesEntityExist(stretcher) or not IsEntityAVehicle(stretcher) then return end
    local ex = extraConfig()
    local a, b = ex.headrestA or 11, ex.headrestB or 12
    if not DoesExtraExist(stretcher, a) and not DoesExtraExist(stretcher, b) then return C.notify('Cabeceira nao disponivel neste modelo.') end
    if isExtraEnabled(stretcher, a) then
        setExtraEnabled(stretcher, a, false)
        setExtraEnabled(stretcher, b, true)
    else
        setExtraEnabled(stretcher, b, false)
        setExtraEnabled(stretcher, a, true)
    end
    C.notify('Posicao da cabeceira alternada.')
end

local function loadCarryAnim()
    local dict = 'anim@heists@box_carry@'
    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 3000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < timeout do Wait(10) end
    return HasAnimDictLoaded(dict) and dict or nil
end

local function requestEntityControl(entity, timeoutMs)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return false end
    if not NetworkGetEntityIsNetworked(entity) then return true end
    NetworkRequestControlOfEntity(entity)
    local timeout = GetGameTimer() + (tonumber(timeoutMs) or 1500)
    while not NetworkHasControlOfEntity(entity) and GetGameTimer() < timeout do
        NetworkRequestControlOfEntity(entity)
        Wait(0)
    end
    return NetworkHasControlOfEntity(entity)
end

local function nativeGroundLowGeometry(entity)
    if not entity or not DoesEntityExist(entity) or not IsEntityAVehicle(entity) then return nil end
    requestEntityControl(entity, 1000)

    local pos = GetEntityCoords(entity)
    local rotation = GetEntityRotation(entity, 2)
    local ex = extraConfig()

    -- O GTA conhece corretamente o contato de chao da geometria BAIXA (Extra 2),
    -- que e o mesmo estado usado pelo resource original ao largar a maca.
    setExtraEnabled(entity, ex.legA or 1, false)
    setExtraEnabled(entity, ex.legB or 2, true)
    SetEntityCollision(entity, true, true)
    SetVehicleGravity(entity, true)
    SetEntityVelocity(entity, 0.0, 0.0, 0.0)
    SetVehicleOnGroundProperly(entity)

    local grounded = GetEntityCoords(entity)
    SetEntityCoordsNoOffset(entity, pos.x, pos.y, grounded.z, false, false, false)
    SetEntityRotation(entity, rotation.x, rotation.y, rotation.z, 2, true)
    SetEntityVelocity(entity, 0.0, 0.0, 0.0)
    return grounded.z
end

local function placeStretcherAtOperationalHeight(high)
    if not stretcher or not DoesEntityExist(stretcher) then return end
    if not IsEntityAVehicle(stretcher) then
        PlaceObjectOnGroundProperly(stretcher)
        return
    end

    local pos = GetEntityCoords(stretcher)
    local rotation = GetEntityRotation(stretcher, 2)
    local cfg = (Config.Stretcher and Config.Stretcher.heightCalibration) or {}
    local lift = high and (tonumber(cfg.highLift) or 0.465) or (tonumber(cfg.lowLift) or 0.0)

    -- 1) Descobre o Z real do piso usando a geometria baixa, que o GTA consegue aterrar.
    local baseZ = nativeGroundLowGeometry(stretcher) or pos.z

    -- 2) Volta para a geometria desejada.
    applyLegVisual(high)

    -- 3) A geometria alta precisa de um lift explicito para que as rodas visuais fiquem no solo.
    SetEntityCoordsNoOffset(stretcher, pos.x, pos.y, baseZ + lift, false, false, false)
    SetEntityRotation(stretcher, rotation.x, rotation.y, rotation.z, 2, true)
    SetEntityVelocity(stretcher, 0.0, 0.0, 0.0)

    local entity = stretcher
    local x,y,z = pos.x,pos.y,baseZ+lift
    local rx,ry,rz = rotation.x,rotation.y,rotation.z
    CreateThread(function()
        Wait(0)
        if entity and DoesEntityExist(entity) and not IsEntityAttached(entity) then
            applyLegVisual(high)
            SetEntityCoordsNoOffset(entity, x,y,z, false,false,false)
            SetEntityRotation(entity, rx,ry,rz, 2, true)
            SetEntityVelocity(entity,0.0,0.0,0.0)
        end
    end)
end

local function setEntityGroundState(entity)
    if not entity or not DoesEntityExist(entity) then return end
    if entity == stretcher then
        placeStretcherAtOperationalHeight(stretcherHigh)
    elseif IsEntityAVehicle(entity) then
        local pos=GetEntityCoords(entity)
        local rotation=GetEntityRotation(entity,2)
        SetVehicleOnGroundProperly(entity)
        local grounded=GetEntityCoords(entity)
        SetEntityCoordsNoOffset(entity,pos.x,pos.y,grounded.z,false,false,false)
        SetEntityRotation(entity,rotation.x,rotation.y,rotation.z,2,true)
    elseif IsEntityAnObject(entity) then
        PlaceObjectOnGroundProperly(entity)
    end
end

local function stopPush()
    if not pushing or not stretcher or not DoesEntityExist(stretcher) then return end
    local ped=PlayerPedId()
    pushing=false
    requestEntityControl(stretcher,1000)

    local worldPos=GetEntityCoords(stretcher)
    local worldRot=GetEntityRotation(stretcher,2)

    ClearPedTasks(ped)
    DetachEntity(stretcher,true,false)
    SetEntityCollision(stretcher,true,true)
    if IsEntityAVehicle(stretcher) then
        SetVehicleGravity(stretcher,true)
        SetVehicleEngineOn(stretcher,false,true,true)
    end

    SetEntityCoordsNoOffset(stretcher,worldPos.x,worldPos.y,worldPos.z,false,false,false)
    SetEntityRotation(stretcher,worldRot.x,worldRot.y,worldRot.z,2,true)
    applyLegVisual(stretcherHigh)
    SetEntityVelocity(stretcher,0.0,0.0,0.0)

    -- Recalibra somente a altura final das rodas; heading/rotacao permanecem os mesmos.
    placeStretcherAtOperationalHeight(stretcherHigh)
end

local function applyPushAttachment()
    if not stretcher or not DoesEntityExist(stretcher) then return false end
    local ped=PlayerPedId()
    if not requestEntityControl(stretcher,1800) then
        C.notify('Nao foi possivel assumir controle da maca.')
        return false
    end

    local cfg=Config.Stretcher.pushOffset or {}
    local heightCfg=(Config.Stretcher and Config.Stretcher.heightCalibration) or {}
    local highLift=tonumber(heightCfg.highLift) or 0.465
    local baseZ=tonumber(cfg.z) or -0.345
    local pushZ=stretcherHigh and baseZ or (baseZ - highLift)

    -- O resource Stretcher-1.0.5 usa exatamente este attachment no estado alto.
    -- Nao tentamos derivar o Z do origin do CVehicle, porque esse origin nao acompanha os extras.
    SetEntityVelocity(stretcher,0.0,0.0,0.0)
    if IsEntityAVehicle(stretcher) then
        SetVehicleEngineOn(stretcher,false,true,true)
        SetVehicleGravity(stretcher,false)
    end
    SetEntityCollision(stretcher,false,false)
    applyLegVisual(stretcherHigh)

    AttachEntityToEntity(
        stretcher,ped,ped,
        tonumber(cfg.x) or -0.05,
        tonumber(cfg.y) or 1.375,
        pushZ,
        tonumber(cfg.rx) or 180.0,
        tonumber(cfg.ry) or 180.0,
        tonumber(cfg.rz) or 180.0,
        0.0,false,false,false,false,2,true
    )
    return true
end

local function startPush()
    if not stretcher or not DoesEntityExist(stretcher) or attachedVehicle then return end
    if pushing then return end
    if not applyPushAttachment() then return end
    pushing = true
    local dict = loadCarryAnim()
    if dict then
        TaskPlayAnim(PlayerPedId(), dict, 'idle', 8.0, 8.0, -1, 50, 0.0, false, false, false)
    end
    CreateThread(function()
        while pushing and stretcher and DoesEntityExist(stretcher) and IsEntityAttachedToEntity(stretcher, PlayerPedId()) do
            DisablePlayerFiring(PlayerId(), true)
            DisableControlAction(0, 22, true)
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 37, true)
            DisableControlAction(0, 44, true)
            if dict and not IsEntityPlayingAnim(PlayerPedId(), dict, 'idle', 3) then
                TaskPlayAnim(PlayerPedId(), dict, 'idle', 8.0, 8.0, -1, 50, 0.0, false, false, false)
            end
            if IsPedDeadOrDying(PlayerPedId(), true) or IsPedRagdoll(PlayerPedId()) then
                stopPush()
                break
            end
            Wait(0)
        end
    end)
end

local function setHeight(high)
    if stretcherHigh==high then return end
    if pushing or attachedVehicle then return C.notify('Solte a maca antes de ajustar a altura.') end
    if not stretcher or not DoesEntityExist(stretcher) then return end

    stretcherHigh=high
    placeStretcherAtOperationalHeight(high)
end

local function startNpcTransportWatchdog(netId, stretcherNetId, transform)
    local cfg = transportConfig()
    local lastRefresh = 0
    local missingSince = nil

    CreateThread(function()
        while attachedNpcNetId == netId do
            local base = stretcher
            if (not base or not DoesEntityExist(base))
                and stretcherNetId and NetworkDoesEntityExistWithNetworkId(stretcherNetId) then
                base = NetworkGetEntityFromNetworkId(stretcherNetId)
                if base and base ~= 0 and DoesEntityExist(base) then
                    stretcher = base
                end
            end

            local ped = resolveNpcByNetId(netId, 0)

            if not ped or not DoesEntityExist(ped) then
                -- Interior/MLO pode causar um curto intervalo de streaming.
                -- O NetID continua sendo a identidade do paciente; nao limpamos o estado.
                missingSince = missingSince or GetGameTimer()

                if GetGameTimer() - lastRefresh >= cfg.refreshMs then
                    TriggerServerEvent('fiveems:server:refreshNpcTransport', netId, stretcherNetId)
                    lastRefresh = GetGameTimer()
                end

                Wait(150)
            else
                missingSince = nil
                attachedNpcPed = ped

                SetEntityAsMissionEntity(ped, true, true)
                SetPedKeepTask(ped, true)

                if base and DoesEntityExist(base) then
                    if not IsEntityAttachedToEntity(ped, base) then
                        attachPatientEntity(ped, base, transform, false)
                    elseif not patientPoseStillPlaying(ped) then
                        playPatientPose(ped, base)
                    end
                end

                if GetGameTimer() - lastRefresh >= cfg.refreshMs then
                    TriggerServerEvent('fiveems:server:refreshNpcTransport', netId, stretcherNetId)
                    lastRefresh = GetGameTimer()
                end

                Wait(patientPoseConfig().repairIntervalMs)
            end
        end
    end)
end

local function attachNpc(ped)
    if not ped or not DoesEntityExist(ped) or not stretcher or not DoesEntityExist(stretcher) then return end
    if hasPatient() then return C.notify('A maca ja possui um paciente.') end

    local npcNetId = ensureNpcNetworked(ped)
    if not npcNetId then
        return C.notify('Nao foi possivel sincronizar este NPC no OneSync.')
    end

    local stretcherNetId = NetworkGetEntityIsNetworked(stretcher) and NetworkGetNetworkIdFromEntity(stretcher) or 0
    if not stretcherNetId or stretcherNetId <= 0 then
        return C.notify('Nao foi possivel sincronizar a maca.')
    end

    local t = normalizePatientTransform(stretcherProfile and stretcherProfile.patient_transform)

    -- Reivindica/protege ANTES do attach. Isso impede o world cleanup da base
    -- ao atravessar portas e trocar exterior <-> interior/MLO.
    TriggerServerEvent('fiveems:server:claimNpcTransport', npcNetId, stretcherNetId, t)

    if not attachPatientEntity(ped, stretcher, t, false) then
        return C.notify('Nao foi possivel estabilizar o NPC na maca.')
    end

    attachedNpcPed = ped
    attachedNpcNetId = npcNetId
    attachedNpcStretcherNetId = stretcherNetId

    startNpcTransportWatchdog(npcNetId, stretcherNetId, t)
end

local function releaseNpc()
    local netId = attachedNpcNetId
    local ped = resolveNpcByNetId(netId, 1200) or attachedNpcPed

    attachedNpcPed = nil
    attachedNpcNetId = nil
    attachedNpcStretcherNetId = nil

    if ped and DoesEntityExist(ped) then
        if IsEntityAttached(ped) then DetachEntity(ped, true, true) end
        ClearPedTasksImmediately(ped)
        restorePatientPed(ped, false, true)
    end

    if netId then
        -- Continua protegido pelo TTL; apenas deixa de estar vinculado a maca.
        TriggerServerEvent('fiveems:server:npcPatientGrounded', netId)
    end
end

local function releasePatient()
    if attachedPatientServerId then
        TriggerServerEvent('fiveems:server:stretcherReleasePlayer', attachedPatientServerId)
        attachedPatientServerId = nil
    end
    releaseNpc()
end

local function requestTransferToPoint(point)
    if not point or not point.id then return C.notify('Nenhum leito/local compativel proximo.') end

    if attachedPatientServerId then
        TriggerServerEvent('fiveems:server:stretcherTransferPlayer', attachedPatientServerId, point.id)
        attachedPatientServerId = nil
        return
    end

    if attachedNpcNetId then
        TriggerServerEvent('fiveems:server:stretcherTransferNpc', attachedNpcNetId, point.id)
        return
    end
end

local function transferToNearest()
    if not hasPatient() then return C.notify('Nenhum paciente na maca.') end
    if pushing then return C.notify('Solte a maca com H antes de transferir o paciente.') end

    local point = nearestTransferPoint(transportConfig().transferRadius)
    if not point then
        return C.notify('Encoste a maca ao lado de um leito/local configurado.')
    end

    requestTransferToPoint(point)
end

RegisterNetEvent('fiveems:client:transferNpcAuthorized', function(netId, point)
    netId = tonumber(netId)
    if not netId or not point or not attachedNpcNetId or tonumber(attachedNpcNetId) ~= netId then return end

    local ped = resolveNpcByNetId(netId, transportConfig().streamGraceMs)
    if not ped or not DoesEntityExist(ped) then
        return C.notify('Paciente ainda nao sincronizou neste interior. Tente novamente em alguns segundos.')
    end

    NetworkRequestControlOfEntity(ped)
    local deadline = GetGameTimer() + 1800
    while not NetworkHasControlOfEntity(ped) and GetGameTimer() < deadline do
        NetworkRequestControlOfEntity(ped)
        Wait(0)
    end

    -- Encerra o watchdog da maca antes do detach.
    attachedNpcPed = nil
    attachedNpcNetId = nil
    attachedNpcStretcherNetId = nil

    if IsEntityAttached(ped) then DetachEntity(ped, true, true) end
    ClearPedTasksImmediately(ped)

    local pos, rotation = worldTransformForPoint(point)

    preparePatientPed(ped, false)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedKeepTask(ped, true)

    local function pinExactAnchor()
        if not ped or not DoesEntityExist(ped) then return end
        SetEntityCoordsNoOffset(ped, pos.x, pos.y, pos.z, false, false, false)
        SetEntityRotation(ped, rotation.x, rotation.y, rotation.z, 2, true)
        SetEntityCollision(ped, false, false)
        SetPedCanRagdoll(ped, false)
        FreezeEntityPosition(ped, true)
    end

    pinExactAnchor()
    FreezeEntityPosition(ped, false)
    playCarePointPose(ped)
    pinExactAnchor()

    -- FiveFD ANCHOR fix: a animacao pode aplicar root offset nos primeiros frames.
    -- Reaplicamos brevemente o transform world-space salvo pelo Gizmo.
    CreateThread(function()
        for _, delay in ipairs({50,150,350,700}) do
            Wait(delay)
            pinExactAnchor()
        end
    end)

    pcall(function()
        Entity(ped).state:set('fiveems:carePointId', tonumber(point.id) or 0, true)
    end)
    TriggerServerEvent('fiveems:server:npcPatientAtCarePoint', netId, point.id)
    C.notify(('Paciente transferido para %s.'):format(point.label or 'leito/local'))
end)

local function loadIntoVehicle()
    if not stretcher or not DoesEntityExist(stretcher) or attachedVehicle then return end
    local veh = closestVehicle(8.0)
    if not veh then return C.notify('Nenhuma ambulancia/aeronave proxima.') end
    local selected = selectProfileForVehicle(veh)
    if not selected then return C.notify('Sem perfil de maca configurado para este veiculo.') end
    stopPush()
    stretcherProfile = selected
    stretcherHigh = false -- dentro sempre baixa
    applyLegVisual(false)
    local o = vec(selected.inside_transform, {x=0,y=-2,z=0.2})
    local rx,ry,rz = rot(selected.inside_transform)
    AttachEntityToEntity(stretcher, veh, 0, o.x,o.y,o.z, rx,ry,rz, false,false,false,false,2,true)
    SetEntityCollision(stretcher, false, false)
    attachedVehicle = veh
    setStretcherState('fiveems:stretcherHigh', false)
    local vehNet = NetworkGetNetworkIdFromEntity(veh)
    setStretcherState('fiveems:attachedVehicle', vehNet or 0)
end

local function unloadFromVehicle()
    if not stretcher or not DoesEntityExist(stretcher) then return end
    local veh = attachedVehicle
    if not veh or not DoesEntityExist(veh) then veh = closestVehicle(10.0) end
    DetachEntity(stretcher, true, true)
    local selected = stretcherProfile or (veh and selectProfileForVehicle(veh))
    if selected and veh and DoesEntityExist(veh) then
        local t = selected.outside_transform or {x=0,y=-3,z=0}
        local o = vec(t, {x=0,y=-3,z=0})
        local p = GetOffsetFromEntityInWorldCoords(veh, o.x,o.y,o.z)
        local vr = GetEntityRotation(veh, 2)
        local rx,ry,rz = rot(t)
        SetEntityCoordsNoOffset(stretcher, p.x,p.y,p.z, false,false,false)
        SetEntityRotation(stretcher, vr.x+rx, vr.y+ry, vr.z+rz, 2, true)
    end
    SetEntityCollision(stretcher, true, true)
    attachedVehicle = nil
    stretcherHigh = true -- fora sempre alta
    applyLegVisual(true)
    setEntityGroundState(stretcher)
    setStretcherState('fiveems:stretcherHigh', true)
    setStretcherState('fiveems:attachedVehicle', 0)
end

local function removeStretcher()
    if not stretcher or not DoesEntityExist(stretcher) then return end
    releasePatient()
    stopPush()
    if attachedVehicle then DetachEntity(stretcher, true, true) end
    DeleteEntity(stretcher)
    stretcher = nil
    stretcherProfile = nil
    attachedVehicle = nil
    pushing = false
end

local function isFiveEMSStretcher(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return false end
    local ok, state = pcall(function() return Entity(entity).state end)
    if ok and state and state['fiveems:stretcher'] == true then return true end
    local model = GetEntityModel(entity)
    if model == joaat(Config.Stretcher.defaultModel or 'strykerpro') then return true end
    for _, profile in ipairs((C.department and C.department.stretcherProfiles) or {}) do
        if profile.stretcher_model and joaat(profile.stretcher_model) == model then return true end
    end
    return false
end

local function syncStretcherState(entity)
    if not isFiveEMSStretcher(entity) then return false end
    stretcher = entity
    local ok, state = pcall(function() return Entity(entity).state end)
    if ok and state then
        if state['fiveems:stretcherHigh'] ~= nil then stretcherHigh = state['fiveems:stretcherHigh'] == true end
        local vehNet = tonumber(state['fiveems:attachedVehicle'] or 0)
        if vehNet > 0 and NetworkDoesEntityExistWithNetworkId(vehNet) then attachedVehicle = NetworkGetEntityFromNetworkId(vehNet)
        elseif vehNet == 0 then attachedVehicle = nil end
    end
    return true
end

setStretcherState = function(key, value)
    if not stretcher or not DoesEntityExist(stretcher) then return end
    local netId = NetworkGetNetworkIdFromEntity(stretcher)
    if netId and netId > 0 then
        TriggerServerEvent('fiveems:server:setStretcherState', netId, key, value)
    end
end

local function targetDistance()
    return tonumber(Config.Stretcher.targetDistance) or 2.5
end

local function wrapSelect(fn)
    return function(data)
        if data and syncStretcherState(data.entity) then fn(data.entity, data) end
    end
end

local function canTarget(entity, predicate)
    if not syncStretcherState(entity) or not canUseStretcher() then return false end
    if predicate then return predicate(entity) == true end
    return true
end

local function buildTargetOptions()
    local dist = targetDistance()
    local options = {
        {name='fiveems_st_push', icon='fa-solid fa-hand', label='Conduzir', distance=dist, canInteract=function(entity) return canTarget(entity,function() return not pushing and not attachedVehicle end) end, onSelect=wrapSelect(function() startPush() end)},
        {name='fiveems_st_release_push', icon='fa-solid fa-hand-paper', label='Soltar', distance=dist, canInteract=function(entity) return canTarget(entity,function() return pushing end) end, onSelect=wrapSelect(function() stopPush() end)},
        {name='fiveems_st_raise', icon='fa-solid fa-arrow-up', label='Levantar', distance=dist, canInteract=function(entity)
            return canTarget(entity,function() return not attachedVehicle and not pushing and not stretcherHigh end)
        end, onSelect=wrapSelect(function()
            setHeight(true)
            setStretcherState('fiveems:stretcherHigh', true)
            C.notify('Maca elevada.')
        end)},
        {name='fiveems_st_lower', icon='fa-solid fa-arrow-down', label='Abaixar', distance=dist, canInteract=function(entity)
            return canTarget(entity,function() return not attachedVehicle and not pushing and stretcherHigh end)
        end, onSelect=wrapSelect(function()
            setHeight(false)
            setStretcherState('fiveems:stretcherHigh', false)
            C.notify('Maca abaixada.')
        end)},
        {name='fiveems_st_patient_menu', icon='fa-solid fa-user-injured', label='Paciente', distance=dist, canInteract=function(entity) return canTarget(entity) end, openMenu=PATIENT_MENU},
        {name='fiveems_st_transfer_patient', icon='fa-solid fa-bed', label='Transferir NPC/Player', distance=dist, canInteract=function(entity) return canTarget(entity,function() return hasPatient() and not pushing and nearestTransferPoint(transportConfig().transferRadius) ~= nil end) end, onSelect=wrapSelect(function() transferToNearest() end)},
        {name='fiveems_st_load', icon='fa-solid fa-truck-medical', label='Carregar', distance=dist, canInteract=function(entity) return canTarget(entity,function() return not attachedVehicle end) end, onSelect=wrapSelect(function() loadIntoVehicle() end)},
        {name='fiveems_st_unload', icon='fa-solid fa-truck-ramp-box', label='Descarregar', distance=dist, canInteract=function(entity) return canTarget(entity,function() return attachedVehicle ~= nil end) end, onSelect=wrapSelect(function() unloadFromVehicle() end)},
        {name='fiveems_st_settings_menu', icon='fa-solid fa-sliders', label='Ajustes', distance=dist, canInteract=function(entity) return canTarget(entity) end, openMenu=SETTINGS_MENU},

        {name='fiveems_st_player', icon='fa-solid fa-user', label='Player proximo', menuName=PATIENT_MENU, distance=dist, canInteract=function(entity) return canTarget(entity,function() return not hasPatient() end) end, onSelect=wrapSelect(function()
            local serverId = closestPlayerServerId(3.0)
            if not serverId then return C.notify('Nenhum player proximo.') end
            local t = normalizePatientTransform(stretcherProfile and stretcherProfile.patient_transform)
            local netId = NetworkGetNetworkIdFromEntity(stretcher)
            if not netId or netId == 0 then return C.notify('Nao foi possivel sincronizar a maca.') end
            attachedPatientServerId = serverId
            TriggerServerEvent('fiveems:server:stretcherAttachPlayer', serverId, netId, t)
        end)},
        {name='fiveems_st_npc', icon='fa-solid fa-person', label='NPC proximo', menuName=PATIENT_MENU, distance=dist, canInteract=function(entity) return canTarget(entity,function() return not hasPatient() end) end, onSelect=wrapSelect(function()
            local ped = closestNpc(3.5)
            if not ped then return C.notify('Nenhum cidadao NPC proximo.') end
            attachNpc(ped)
        end)},
        {name='fiveems_st_patient_release', icon='fa-solid fa-user-minus', label='Retirar paciente', menuName=PATIENT_MENU, distance=dist, canInteract=function(entity) return canTarget(entity,function() return hasPatient() end) end, onSelect=wrapSelect(function() releasePatient() end)},

                                    }

    options[#options+1] = {
        name='fiveems_st_equipment_menu', icon='fa-solid fa-kit-medical', label='Equipamentos',
        menuName=SETTINGS_MENU, openMenu=EQUIPMENT_MENU, distance=dist,
        canInteract=function(entity) return canTarget(entity) end
    }

    local ex = extraConfig()
    options[#options+1] = {name='fiveems_st_headrest', icon='fa-solid fa-bed', label='Cabeceira', menuName=EQUIPMENT_MENU, distance=dist, canInteract=function(entity) return canTarget(entity) end, onSelect=wrapSelect(function() toggleHeadrest() end)}
    options[#options+1] = {name='fiveems_st_backboard', icon='fa-solid fa-person-falling', label='Prancha', menuName=EQUIPMENT_MENU, distance=dist, canInteract=function(entity) return canTarget(entity) end, onSelect=wrapSelect(function() toggleEquipmentExtra(ex.backboard or 3, 'Prancha') end)}
    options[#options+1] = {name='fiveems_st_monitor_extra', icon='fa-solid fa-heart-pulse', label='Monitor', menuName=EQUIPMENT_MENU, distance=dist, canInteract=function(entity) return canTarget(entity) end, onSelect=wrapSelect(function() toggleEquipmentExtra(ex.monitor or 5, 'Monitor') end)}
    options[#options+1] = {name='fiveems_st_redbag', icon='fa-solid fa-briefcase-medical', label='Bolsa vermelha', menuName=EQUIPMENT_MENU, distance=dist, canInteract=function(entity) return canTarget(entity) end, onSelect=wrapSelect(function() toggleEquipmentExtra(ex.redBag or 6, 'Bolsa vermelha') end)}
    options[#options+1] = {name='fiveems_st_bluebag', icon='fa-solid fa-briefcase-medical', label='Bolsa azul', menuName=EQUIPMENT_MENU, distance=dist, canInteract=function(entity) return canTarget(entity) end, onSelect=wrapSelect(function() toggleEquipmentExtra(ex.blueBag or 7, 'Bolsa azul') end)}
    options[#options+1] = {name='fiveems_st_reset_equipment', icon='fa-solid fa-rotate-left', label='Limpar equipamentos', menuName=EQUIPMENT_MENU, distance=dist, canInteract=function(entity) return canTarget(entity) end, onSelect=wrapSelect(function() restoreDefaultEquipment(); C.notify('Maca limpa: sem equipamentos e com encosto abaixado.') end)}

    options[#options+1] = {name='fiveems_st_remove', icon='fa-solid fa-trash', label='Remover maca', menuName=SETTINGS_MENU, distance=dist, canInteract=function(entity) return canTarget(entity) end, onSelect=wrapSelect(function() removeStretcher() end)}
    return options
end

local function targetModels()
    local out, seen = {}, {}
    local function add(model)
        model = tostring(model or '')
        if model == '' then return end
        local hash = joaat(model)
        if seen[hash] then return end
        seen[hash] = true
        out[#out+1] = model
    end
    add(Config.Stretcher.defaultModel or 'strykerpro')
    add(currentModelName())
    for _, profile in ipairs((C.department and C.department.stretcherProfiles) or {}) do add(profile.stretcher_model) end
    return out
end

local function findAttachedStretcherForVehicle(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return nil end
    if stretcher and DoesEntityExist(stretcher) and IsEntityAttachedToEntity(stretcher, vehicle) then
        attachedVehicle = vehicle
        return stretcher
    end
    for _, candidate in ipairs(GetGamePool('CVehicle')) do
        if candidate ~= vehicle and DoesEntityExist(candidate) and IsEntityAttachedToEntity(candidate, vehicle) and isFiveEMSStretcher(candidate) then
            stretcher = candidate
            attachedVehicle = vehicle
            syncStretcherState(candidate)
            return candidate
        end
    end
    return nil
end

local function bindVehicleUnloadTarget()
    if vehicleUnloadTargetBound or GetResourceState('ox_target') ~= 'started' then return end
    local option = {
        name='fiveems_vehicle_unload_stretcher',
        icon='fa-solid fa-truck-ramp-box',
        label='Retirar maca',
        distance=3.0,
        canInteract=function(entity)
            if not canUseStretcher() then return false end
            return findAttachedStretcherForVehicle(entity) ~= nil
        end,
        onSelect=function(data)
            if data and findAttachedStretcherForVehicle(data.entity) then unloadFromVehicle() end
        end
    }
    pcall(function() exports.ox_target:addGlobalVehicle(option) end)
    vehicleUnloadTargetBound = true
end

local function bindTarget()
    if GetResourceState('ox_target') ~= 'started' then return end
    local options = buildTargetOptions()
    for _, model in ipairs(targetModels()) do
        local hash = joaat(model)
        if not registeredTargetModels[hash] then
            pcall(function() exports.ox_target:addModel(model, options) end)
            registeredTargetModels[hash] = model
        end
    end
    bindVehicleUnloadTarget()
    targetBound = true
end

AddEventHandler('fiveems:client:refreshStretcherTarget', bindTarget)
AddEventHandler('fiveems:client:refreshDepartmentWorld', function()
    if GetResourceState('ox_target') == 'started' then bindTarget() end
end)

AddEventHandler('onClientResourceStart', function(resource)
    if resource == 'ox_target' then
        registeredTargetModels = {}
        vehicleUnloadTargetBound = false
        targetBound = false
    end
    if resource == 'ox_target' or resource == GetCurrentResourceName() then
        CreateThread(function()
            Wait(500)
            bindTarget()
        end)
    end
end)

CreateThread(function()
    while GetResourceState('ox_target') ~= 'started' do Wait(500) end
    bindTarget()
end)

CreateThread(function()
    Wait(2500)
    if GetResourceState('Stretcher') == 'started' then
        print('^3[FiveEMS] AVISO: resource Stretcher legado esta ativo. Use apenas o FiveEMS + FiveEMS_StrykerPro_ModelOnly para evitar conflito de altura e attachment.^7')
    end
end)

local function spawnStretcher(model)
    if stretcher and DoesEntityExist(stretcher) then return C.notify('Voce ja retirou uma maca.') end
    local hash = requestModel(model or currentModelName())
    if not hash then return C.notify('Modelo de maca invalido: '..tostring(model or currentModelName())) end
    local ped = PlayerPedId()
    local pos = GetOffsetFromEntityInWorldCoords(ped, 0.0, 2.0, 0.0)
    if IsModelAVehicle(hash) then
        stretcher = CreateVehicle(hash, pos.x, pos.y, pos.z, GetEntityHeading(ped) - 90.0, true, true)
        if stretcher ~= 0 then
            SetVehicleEngineOn(stretcher, false, true, true)
        end
    else
        stretcher = CreateObject(hash, pos.x, pos.y, pos.z, true, true, false)
        if stretcher ~= 0 then
            SetEntityHeading(stretcher, GetEntityHeading(ped))
            PlaceObjectOnGroundProperly(stretcher)
        end
    end
    if not stretcher or stretcher == 0 then return C.notify('Nao foi possivel criar a maca.') end
    SetEntityAsMissionEntity(stretcher, true, true)
    local stretcherNetId = NetworkGetNetworkIdFromEntity(stretcher)
    if stretcherNetId and stretcherNetId > 0 then
        TriggerServerEvent('fiveems:server:initStretcherState', stretcherNetId)
    end
    stretcherHigh = true
    if IsEntityAVehicle(stretcher) then
        restoreDefaultEquipment()
        placeStretcherAtOperationalHeight(true)

        -- Alguns addons confirmam os extras um frame depois da criacao.
        CreateThread(function()
            Wait(0)
            if stretcher and DoesEntityExist(stretcher) then
                restoreDefaultEquipment()
                placeStretcherAtOperationalHeight(true)
            end
        end)
    end
    stretcherProfile = ((C.department and C.department.stretcherProfiles) or {})[1]
    attachedVehicle = nil
    pushing = false
    SetModelAsNoLongerNeeded(hash)
    bindTarget()
    C.notify('Maca retirada da garagem. Use o ox_target para operar.')
end

RegisterNetEvent('fiveems:client:spawnAuthorizedStretcher', function(model)
    spawnStretcher(model)
end)

RegisterNUICallback('stretcherSetProfile', function(data, cb)
    stretcherProfile = data.profile
    cb({ok=true})
end)

RegisterNetEvent('fiveems:client:storeLocalStretcher', function()
    if not stretcher or not DoesEntityExist(stretcher) then return C.notify('Nenhuma maca retirada por voce.') end
    if attachedVehicle then DetachEntity(stretcher, true, true) end
    removeStretcher()
    C.notify('Maca guardada.')
end)

-- Durante a conducao nao e pratico mirar na propria maca com ox_target.
-- Por isso existe uma tecla dedicada SOMENTE para SOLTAR.
-- Ela nao pega a maca, nao altera altura e nao mexe nos extras.
RegisterCommand('+fiveems_stretcher_release', function()
    if pushing then
        stopPush()
    end
end, false)
RegisterCommand('-fiveems_stretcher_release', function() end, false)
RegisterKeyMapping(
    '+fiveems_stretcher_release',
    'FiveEMS - soltar maca durante conducao',
    'keyboard',
    (Config.Stretcher and Config.Stretcher.releaseKey) or 'H'
)


-- Debug/fallback: estes eventos sao disparados SOMENTE pelo servidor
-- depois de validar permissao de administrador. O gameplay normal e garagem + ox_target.
RegisterNetEvent('fiveems:client:debugStretcherToggle', function()
    if stretcher and DoesEntityExist(stretcher) then
        removeStretcher()
    else
        spawnStretcher(currentModelName())
    end
end)

RegisterNetEvent('fiveems:client:debugStretcherIn', function()
    loadIntoVehicle()
end)

RegisterNetEvent('fiveems:client:debugStretcherOut', function()
    unloadFromVehicle()
end)

RegisterNetEvent('fiveems:client:debugPatientToStretcher', function(serverId)
    if not stretcher or not DoesEntityExist(stretcher) then return C.notify('Maca nao criada.') end
    serverId = tonumber(serverId)
    if not serverId then return C.notify('Server ID invalido.') end

    local tr = normalizePatientTransform(stretcherProfile and stretcherProfile.patient_transform)
    local netId = NetworkGetNetworkIdFromEntity(stretcher)
    if not netId or netId == 0 then return C.notify('Nao foi possivel sincronizar a maca no OneSync.') end

    attachedPatientServerId = serverId
    TriggerServerEvent('fiveems:server:stretcherAttachPlayer', serverId, netId, tr)
end)

RegisterNetEvent('fiveems:client:debugPatientRelease', function()
    releasePatient()
end)

RegisterNetEvent('fiveems:client:stretcherAttachSelf', function(stretcherNetId, transform)
    local timeout = GetGameTimer() + 5000
    while not NetworkDoesEntityExistWithNetworkId(stretcherNetId) and GetGameTimer() < timeout do Wait(20) end
    if not NetworkDoesEntityExistWithNetworkId(stretcherNetId) then
        return C.notify('Maca nao sincronizada no cliente do paciente.')
    end

    local entity = NetworkGetEntityFromNetworkId(stretcherNetId)
    if entity == 0 or not DoesEntityExist(entity) then return end

    local ped = PlayerPedId()
    local t = normalizePatientTransform(transform)

    selfPatientAttachment = {
        stretcher = entity,
        transform = t,
    }

    attachPatientEntity(ped, entity, t, true)

    local tracked = selfPatientAttachment
    startAttachmentWatchdog(
        ped,
        entity,
        t,
        true,
        function()
            return selfPatientAttachment == tracked
                and tracked.stretcher == entity
                and DoesEntityExist(entity)
        end
    )
end)

RegisterNetEvent('fiveems:client:stretcherReleaseSelf', function()
    selfPatientAttachment = nil
    local ped = PlayerPedId()
    if IsEntityAttached(ped) then DetachEntity(ped, true, true) end
    ClearPedTasksImmediately(ped)
    restorePatientPed(ped, true)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if GetResourceState('ox_target') == 'started' then
        for _, model in pairs(registeredTargetModels) do
            pcall(function() exports.ox_target:removeModel(model) end)
        end
        pcall(function() exports.ox_target:removeGlobalVehicle('fiveems_vehicle_unload_stretcher') end)
    end
    if stretcher and DoesEntityExist(stretcher) then removeStretcher() end
end)
