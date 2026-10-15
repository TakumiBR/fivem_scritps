FiveEMS = FiveEMS or {}
FiveEMS.Client = FiveEMS.Client or {}

local C = FiveEMS.Client
C.uiOpen = false
C.uiContext = nil
C.bootstrap = nil
C.department = nil
C.worldDepartments = {}
C.medicalState = nil
C.targetState = nil
C.targetServerId = nil
C.targetRef = nil
C.uiExtra = {}

-- IMPORTANTE: precisa ser declarado antes dos handlers que usam a funcao.
-- Na V0.3.0/0.3.0a ele estava declarado depois do evento bootstrap; em Lua,
-- aquele handler acabava procurando uma global chamada mergeClientTable e dava nil.
local function mergeClientTable(target, source)
    if type(target) ~= 'table' or type(source) ~= 'table' then return end
    for k, v in pairs(source) do
        if type(v) == 'table' and type(target[k]) == 'table' then
            mergeClientTable(target[k], v)
        else
            target[k] = v
        end
    end
end

local function nui(action, data)
    SendNUIMessage({action=action, data=data})
end

function C.notify(message)
    if FiveEMS.FrameworkClient and FiveEMS.FrameworkClient.notify and FiveEMS.FrameworkClient.notify(message, 'info') then return end
    if GetResourceState('fivepd_sp_ui') == 'started' then
        local ok = pcall(function()
            exports.fivepd_sp_ui:Notificar({tipo='info', titulo='FiveEMS', descricao=tostring(message or '')})
        end)
        if ok then return end
    end
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(('[FiveEMS] %s'):format(message or ''))
    EndTextCommandThefeedPostTicker(false, false)
end

function C.openUi(context, extra)
    extra = extra or {}
    C.uiOpen = true
    C.uiContext = context
    C.uiExtra = extra
    SetNuiFocus(true, true)
    pcall(function() SetNuiFocusKeepInput(false) end)
    nui('open', {context=context, extra=extra, locale=Config.Locale})

    -- O contexto fisico (pointId/departmentId) acompanha o bootstrap.
    -- Antes a garagem sabia em qual ponto estava no client, mas o servidor
    -- hidratava o departamento apenas pelo member cache. Em restart isso podia
    -- resultar em department=nil e a NUI mostrava somente a maca hardcoded.
    TriggerServerEvent('fiveems:server:requestBootstrap', context, extra)

    if context == 'garage' and extra.pointId then
        TriggerServerEvent('fiveems:server:requestGarageCatalog', tonumber(extra.pointId))
    end
end

function C.closeUi()
    -- Release input FIRST. If any scene cleanup fails afterwards the player
    -- still regains control and cannot be trapped behind the NUI.
    C.uiOpen = false
    C.uiContext = nil
    C.uiExtra = {}

    SetNuiFocus(false, false)
    pcall(function() SetNuiFocusKeepInput(false) end)

    -- Normal clinical cleanup.
    TriggerEvent('fiveems:client:forceClinicalSceneStop')

    -- Hard safety net: never leave a scripted camera/focus behind.
    RenderScriptCams(false, false, 0, true, true)
    ClearFocus()

    DisplayHud(true)
    DisplayRadar(true)
    SetRadarBigmapEnabled(false, false)

    nui('close', {})
    TriggerEvent('fiveems:client:postCloseRecovery')
end

RegisterNetEvent('fiveems:client:notify', C.notify)

-- Some CEF/FiveM builds can retain an input capture for a frame after NUI focus
-- is released. This short recovery pulse is only active after FiveEMS closes.
RegisterNetEvent('fiveems:client:postCloseRecovery', function()
    CreateThread(function()
        for _=1,8 do
            SetNuiFocus(false, false)
            pcall(function() SetNuiFocusKeepInput(false) end)
            Wait(0)
        end
    end)
end)

RegisterNetEvent('fiveems:client:consoleReport', function(title, lines)
    print(('^5[FiveEMS]^7 %s'):format(title or 'Relatorio'))
    for _, line in ipairs(lines or {}) do
        print('  '..tostring(line))
    end
end)

RegisterNetEvent('fiveems:client:openUi', function(context)
    C.openUi(context or 'os')
end)

RegisterNetEvent('fiveems:client:bootstrap', function(data)
    C.bootstrap = data
    C.department = data and data.department or nil

    if data and data.config and type(data.config.stretcher) == 'table' then
        Config.Stretcher = Config.Stretcher or {}
        mergeClientTable(Config.Stretcher, data.config.stretcher)
    end
    if data and data.config and type(data.config.npcPersistence) == 'table' then
        Config.NpcPersistence = Config.NpcPersistence or {}
        mergeClientTable(Config.NpcPersistence, data.config.npcPersistence)
    end
    if data and data.config and type(data.config.commands) == 'table' then
        Config.Commands = Config.Commands or {}
        mergeClientTable(Config.Commands, data.config.commands)
    end

    nui('bootstrap', data)
    TriggerEvent('fiveems:client:refreshDepartmentWorld')
end)

RegisterNetEvent('fiveems:client:garageCatalog', function(data)
    if type(data) ~= 'table' then return end
    C.department = data
    if C.bootstrap then C.bootstrap.department = data end
    nui('garageCatalog', data)
end)

RegisterNetEvent('fiveems:client:departmentData', function(data)
    C.department = data
    if C.bootstrap then C.bootstrap.department = data end
    nui('department', data)
    TriggerEvent('fiveems:client:refreshDepartmentWorld')
end)

RegisterNetEvent('fiveems:client:departmentSaved', function(data)
    C.department = data
    nui('departmentSaved', data)
    TriggerEvent('fiveems:client:refreshDepartmentWorld')
end)

-- V0.5.1a: o servidor ja emitia este evento, mas o client nao o escutava.
-- Sem este handler o banco podia excluir o departamento e o Creator continuava
-- exibindo a linha antiga ate um novo bootstrap/restart.
RegisterNetEvent('fiveems:client:departmentDeleted', function(departmentId)
    departmentId = tonumber(departmentId)
    if not departmentId then return end

    if C.department and tonumber(C.department.id) == departmentId then
        C.department = nil
    end

    if C.bootstrap then
        if C.bootstrap.department and tonumber(C.bootstrap.department.id) == departmentId then
            C.bootstrap.department = nil
        end

        local filtered = {}
        for _, department in ipairs(C.bootstrap.departments or {}) do
            if tonumber(department.id) ~= departmentId then
                filtered[#filtered + 1] = department
            end
        end
        C.bootstrap.departments = filtered
    end

    nui('departmentDeleted', {id=departmentId})
    TriggerEvent('fiveems:client:refreshDepartmentWorld')
end)

RegisterNetEvent('fiveems:client:departmentDeleteFailed', function(departmentId, message)
    nui('departmentDeleteFailed', {
        id = tonumber(departmentId),
        message = tostring(message or 'Nao foi possivel excluir o departamento.')
    })
end)


RegisterNetEvent('fiveems:client:worldDepartments', function(departments)
    C.worldDepartments = departments or {}
    TriggerEvent('fiveems:client:refreshDepartmentWorld')
end)

local function requestWorldDepartments()
    TriggerServerEvent('fiveems:server:requestWorldDepartments')
end

-- O mundo do FiveEMS precisa ser hidratado independentemente da NUI/Creator.
-- Isso garante blips e pontos logo apos restart do resource, mesmo para admins
-- que nao pertencem ao departamento que estao configurando.
CreateThread(function()
    Wait(750)
    for i = 1, 5 do
        requestWorldDepartments()
        Wait(i == 1 and 1000 or 2500)
        if C.worldDepartments and #C.worldDepartments > 0 then break end
    end
end)

CreateThread(function()
    while true do
        if C.uiOpen and (C.uiContext == 'patient' or C.uiContext == 'monitor') then
            DisplayHud(false)
            DisplayRadar(false)
            SetRadarBigmapEnabled(false, false)
            HideHudAndRadarThisFrame()
            for i = 1, 22 do
                HideHudComponentThisFrame(i)
            end
            Wait(0)
        else
            Wait(250)
        end
    end
end)

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    CreateThread(function()
        Wait(1000)
        requestWorldDepartments()
        TriggerServerEvent('fiveems:server:requestRuntimeConfig')
    end)
end)

RegisterNetEvent('fiveems:client:medicalState', function(state)
    C.medicalState = state
    nui('selfMedicalState', state)
    TriggerEvent('fiveems:client:applyFunctionalEffects', state)
end)

RegisterNetEvent('fiveems:client:targetStateUpdated', function(targetSrc, state)
    C.targetServerId = tonumber(targetSrc)
    C.targetState = state
    nui('targetMedicalState', {targetServerId=C.targetServerId, state=state})
end)

RegisterNetEvent('fiveems:client:xpUpdated', function(payload)
    C.notify(_L('xp_gain', payload.amount or 0))
    nui('xpUpdated', payload)
end)

RegisterNetEvent('fiveems:client:adminSettings', function(settings)
    nui('adminSettings', settings)
end)



RegisterNetEvent('fiveems:client:commandsUpdated', function(commands)
    if type(commands) ~= 'table' then return end
    Config.Commands = Config.Commands or {}
    for k, v in pairs(commands) do Config.Commands[k] = v end

    if C.bootstrap and C.bootstrap.config then
        C.bootstrap.config.commands = Config.Commands
    end

    nui('runtimeCommandsConfig', Config.Commands)
end)

RegisterNetEvent('fiveems:client:applyStretcherConfig', function(stretcherConfig)
    if type(stretcherConfig) ~= 'table' then return end
    Config.Stretcher = Config.Stretcher or {}
    mergeClientTable(Config.Stretcher, stretcherConfig)

    if C.bootstrap and C.bootstrap.config then
        C.bootstrap.config.stretcher = Config.Stretcher
    end

    -- Se a NUI estiver aberta, ela recebe os valores atualizados no proximo render/bootstrap.
    nui('runtimeStretcherConfig', Config.Stretcher)
end)

RegisterNetEvent('fiveems:client:openPatientFromCommand', function(target)
    target=tonumber(target)
    if not target then return end
    C.targetRef={kind='player',serverId=target}
    C.targetServerId=target
    C.openUi('patient',{targetRef=C.targetRef,targetServerId=target})
    TriggerServerEvent('fiveems:server:clinicalRequestState',C.targetRef,{})
end)

RegisterNUICallback('close', function(data, cb)
    data = type(data) == 'table' and data or {}
    local targetRef = C.targetRef
    local targetServerId = C.targetServerId

    -- If the portable monitor is pinned as an overlay, leaving another FiveEMS
    -- screen must only release NUI/camera focus. The monitor session remains alive.
    if data.keepMonitorOverlay == true and C.monitorSession and C.monitorSession.ref then
        C.uiOpen = false
        C.uiContext = 'monitor_overlay'
        C.uiExtra = {}
        SetNuiFocus(false, false)
        pcall(function() SetNuiFocusKeepInput(false) end)
        TriggerEvent('fiveems:client:forceClinicalSceneStop')
        RenderScriptCams(false, false, 0, true, true)
        ClearFocus()
        DisplayHud(true)
        DisplayRadar(true)
        SetRadarBigmapEnabled(false, false)

        -- Release the clinical attendance claim, but restore the monitor target.
        if targetRef then TriggerServerEvent('fiveems:server:clinicalClose', targetRef) end
        C.targetRef = C.monitorSession.ref
        C.targetServerId = C.targetRef.kind == 'player' and tonumber(C.targetRef.serverId) or nil
        SendNUIMessage({action='monitorOverlayOnly', data={netId=C.monitorSession.netId}})
        cb({ok=true, overlay=true})
        return
    end

    C.closeUi()
    C.targetRef = nil
    C.targetServerId = nil
    C.targetState = nil
    C.monitorSession = nil

    if targetRef then
        TriggerServerEvent('fiveems:server:clinicalClose', targetRef)
    elseif targetServerId then
        TriggerServerEvent('fiveems:server:releasePatientClaim', targetServerId)
    end

    cb({ok=true})
end)

-- Emergency recovery command. It is intentionally local and harmless:
-- if another resource/NUI error ever captures focus, this restores the player.
RegisterCommand('fiveemsclose', function()
    C.closeUi()
    C.targetRef = nil
    C.targetServerId = nil
    C.targetState = nil
    C.monitorSession = nil
end, false)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    SetNuiFocus(false, false)
    pcall(function() SetNuiFocusKeepInput(false) end)
    RenderScriptCams(false, false, 0, true, true)
    ClearFocus()
    DisplayHud(true)
    DisplayRadar(true)
end)

RegisterNUICallback('requestBootstrap', function(data, cb)
    local context = data and data.context or C.uiContext
    local extra = C.uiExtra or {}
    TriggerServerEvent('fiveems:server:requestBootstrap', context, extra)
    if context == 'garage' and extra.pointId then
        TriggerServerEvent('fiveems:server:requestGarageCatalog', tonumber(extra.pointId))
    end
    cb({ok=true})
end)

RegisterNUICallback('selectDepartment', function(data, cb)
    TriggerServerEvent('fiveems:server:getDepartment', tonumber(data.id))
    cb({ok=true})
end)

RegisterNUICallback('saveDepartment', function(data, cb)
    local coords = data.useCurrentBlip and GetEntityCoords(PlayerPedId()) or nil
    if coords then
        data.blip_x, data.blip_y, data.blip_z = coords.x, coords.y, coords.z
    end
    TriggerServerEvent('fiveems:server:saveDepartment', data)
    cb({ok=true})
end)

RegisterNUICallback('deleteDepartment', function(data, cb)
    TriggerServerEvent('fiveems:server:deleteDepartment', tonumber(data.departmentId))
    cb({ok=true})
end)

RegisterNUICallback('saveRank', function(data, cb)
    TriggerServerEvent('fiveems:server:saveRank', tonumber(data.departmentId), data.rank)
    cb({ok=true})
end)

RegisterNUICallback('savePointAtCurrent', function(data, cb)
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local point = data.point or {}
    point.x, point.y, point.z = coords.x, coords.y, coords.z
    point.heading = GetEntityHeading(ped)
    TriggerServerEvent('fiveems:server:savePoint', tonumber(data.departmentId), point)
    cb({ok=true, coords={x=coords.x,y=coords.y,z=coords.z,heading=point.heading}})
end)

RegisterNUICallback('deletePoint', function(data, cb)
    TriggerServerEvent('fiveems:server:deletePoint', tonumber(data.departmentId), tonumber(data.pointId))
    cb({ok=true})
end)


RegisterNUICallback('creatorCreateGarage', function(data, cb)
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local point = {
        type = 'garage',
        label = tostring(data.label or 'Garagem'),
        x = coords.x, y = coords.y, z = coords.z,
        heading = GetEntityHeading(ped),
        data = data.data or {},
    }
    point.data.garage_configured = point.data.garage_configured == true
    TriggerServerEvent('fiveems:server:savePoint', tonumber(data.departmentId), point)
    cb({ok=true, coords={x=coords.x,y=coords.y,z=coords.z,heading=point.heading}})
end)

RegisterNUICallback('creatorSaveGarage', function(data, cb)
    local point = data.point or {}
    if data.useCurrent == true then
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)
        point.x, point.y, point.z = coords.x, coords.y, coords.z
        point.heading = GetEntityHeading(ped)
    end
    point.preserveGarageSpawns = true
    point.type = 'garage'
    TriggerServerEvent('fiveems:server:savePoint', tonumber(data.departmentId), point)
    cb({ok=true})
end)

RegisterNUICallback('saveVehicle', function(data, cb)
    TriggerServerEvent('fiveems:server:saveVehicle', tonumber(data.departmentId), data.vehicle)
    cb({ok=true})
end)

RegisterNUICallback('deleteVehicle', function(data, cb)
    TriggerServerEvent('fiveems:server:deleteVehicle', tonumber(data.departmentId), tonumber(data.vehicleId))
    cb({ok=true})
end)

RegisterNUICallback('saveSupply', function(data, cb)
    TriggerServerEvent('fiveems:server:saveSupply', tonumber(data.departmentId), data.item)
    cb({ok=true})
end)

RegisterNUICallback('seedSupplies', function(data, cb)
    TriggerServerEvent('fiveems:server:seedSupplies', tonumber(data.departmentId))
    cb({ok=true})
end)

RegisterNUICallback('saveStretcherProfile', function(data, cb)
    TriggerServerEvent('fiveems:server:saveStretcherProfile', tonumber(data.departmentId), data.profile)
    cb({ok=true})
end)

RegisterNUICallback('setDuty', function(data, cb)
    TriggerServerEvent('fiveems:server:setDuty', data.onDuty == true)
    cb({ok=true})
end)

RegisterNUICallback('assignMember', function(data, cb)
    TriggerServerEvent('fiveems:server:assignMember', tonumber(data.targetServerId), tonumber(data.departmentId), tonumber(data.rankId))
    cb({ok=true})
end)

RegisterNUICallback('saveAdminSetting', function(data, cb)
    TriggerServerEvent('fiveems:server:saveAdminSetting', data.key, data.value)
    cb({ok=true})
end)

RegisterNUICallback('getAdminSettings', function(_, cb)
    TriggerServerEvent('fiveems:server:getAdminSettings')
    cb({ok=true})
end)

RegisterNUICallback('openPatient', function(data, cb)
    local targetRef = type(data.targetRef)=='table' and data.targetRef or nil
    local target = tonumber(data.targetServerId)
    if not targetRef and target then targetRef={kind='player',serverId=target} end
    if targetRef then
        C.targetRef = targetRef
        C.targetServerId = targetRef.kind=='player' and tonumber(targetRef.serverId) or nil
        TriggerServerEvent('fiveems:server:clinicalRequestState', targetRef, {})
        nui('setContext', {context='patient', targetRef=targetRef, targetServerId=C.targetServerId})
    end
    cb({ok=true})
end)

RegisterNUICallback('clinicalAssessRegion', function(data, cb)
    if C.targetRef then TriggerServerEvent('fiveems:server:clinicalAssessRegion', C.targetRef, data.region) end
    cb({ok=true})
end)

RegisterNUICallback('clinicalAssessXABCDE', function(data, cb)
    if C.targetRef then TriggerServerEvent('fiveems:server:clinicalAssessXABCDE', C.targetRef, data.step) end
    cb({ok=true})
end)

RegisterNUICallback('clinicalMeasureVital', function(data, cb)
    if C.targetRef then TriggerServerEvent('fiveems:server:clinicalMeasureVital', C.targetRef, data.measurement) end
    cb({ok=true})
end)

RegisterNUICallback('applyTreatment', function(data, cb)
    if C.targetRef then
        TriggerServerEvent('fiveems:server:clinicalApplyTreatment', C.targetRef, data.injuryId, data.treatmentKey, data.region, data.extra or {})
    elseif C.targetServerId then
        TriggerServerEvent('fiveems:server:applyTreatment', C.targetServerId, data.injuryId, data.treatmentKey, data.extra or {})
    end
    cb({ok=true})
end)

RegisterNUICallback('setOxygen', function(data, cb)
    if C.targetRef then TriggerServerEvent('fiveems:server:clinicalSetOxygen', C.targetRef, data.device, tonumber(data.flow))
    elseif C.targetServerId then TriggerServerEvent('fiveems:server:setOxygen', C.targetServerId, data.device, tonumber(data.flow)) end
    cb({ok=true})
end)

RegisterNUICallback('stopOxygen', function(_, cb)
    if C.targetRef then TriggerServerEvent('fiveems:server:clinicalStopOxygen', C.targetRef)
    elseif C.targetServerId then TriggerServerEvent('fiveems:server:stopOxygen', C.targetServerId) end
    cb({ok=true})
end)

RegisterNUICallback('clinicalRestockBag', function(_, cb)
    TriggerServerEvent('fiveems:server:clinicalRestockBag')
    cb({ok=true})
end)

RegisterNUICallback('submitReport', function(data, cb)
    if C.targetRef then TriggerServerEvent('fiveems:server:clinicalSubmitReport', C.targetRef, data.form or {})
    elseif C.targetServerId then TriggerServerEvent('fiveems:server:submitAssessment', C.targetServerId, data.form or {}) end
    cb({ok=true})
end)

RegisterNUICallback('defibAnalyze', function(_, cb)
    if C.targetServerId then TriggerServerEvent('fiveems:server:defibAnalyze', C.targetServerId) end
    cb({ok=true})
end)

RegisterNUICallback('defibShock', function(data, cb)
    if C.targetServerId then TriggerServerEvent('fiveems:server:defibShock', C.targetServerId, tonumber(data.energy)) end
    cb({ok=true})
end)

RegisterNUICallback('startCPR', function(_, cb)
    if C.targetServerId then TriggerEvent('fiveems:client:startCPR', C.targetServerId) else C.notify('RCP em NPC entra na proxima etapa do Medical Actor.') end
    cb({ok=true})
end)

RegisterNUICallback('stopCPR', function(_, cb)
    TriggerEvent('fiveems:client:stopCPR')
    cb({ok=true})
end)

RegisterNUICallback('spawnVehicle', function(data, cb)
    TriggerServerEvent('fiveems:server:requestVehicle', tonumber(data.vehicleId), tonumber(data.garagePointId))
    cb({ok=true})
end)

RegisterNUICallback('spawnStretcher', function(_, cb)
    TriggerServerEvent('fiveems:server:requestStretcher')
    cb({ok=true})
end)

RegisterNUICallback('storeVehicle', function(data, cb)
    TriggerEvent('fiveems:client:storeNearestVehicle', data and data.model or nil)
    cb({ok=true})
end)

RegisterNUICallback('storeStretcher', function(_, cb)
    TriggerEvent('fiveems:client:storeLocalStretcher')
    cb({ok=true})
end)

RegisterNUICallback('takeSupply', function(data, cb)
    TriggerServerEvent('fiveems:server:takeSupply', tonumber(data.supplyId), tonumber(data.count) or 1)
    cb({ok=true})
end)

RegisterNUICallback('bedChartRefresh', function(data, cb)
    local pointId = tonumber((data and data.pointId) or (C.uiExtra and C.uiExtra.carePoint and C.uiExtra.carePoint.id))
    if C.targetRef and pointId then
        TriggerServerEvent('fiveems:server:bedChartRequest', C.targetRef, pointId, {})
    end
    cb({ok=true})
end)

RegisterNUICallback('bedChartOpenClinical', function(_, cb)
    local ref = C.targetRef
    if ref and C.openClinicalTarget then
        C.openClinicalTarget(ref, {})
    elseif ref then
        C.openUi('patient', {targetRef=ref, targetServerId=ref.kind=='player' and tonumber(ref.serverId) or nil})
        TriggerServerEvent('fiveems:server:clinicalRequestState', ref, {})
    end
    cb({ok=true})
end)

RegisterNUICallback('placePatientAtCarePoint', function(data, cb)
    if C.targetServerId and data.pointId then
        TriggerServerEvent('fiveems:server:placePatientAtCarePoint', C.targetServerId, tonumber(data.pointId))
    end
    cb({ok=true})
end)

RegisterNUICallback('releasePatientFromCarePoint', function(_, cb)
    if C.targetServerId then TriggerServerEvent('fiveems:server:releasePatientFromCarePoint', C.targetServerId) end
    cb({ok=true})
end)
