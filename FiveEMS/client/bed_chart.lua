FiveEMS = FiveEMS or {}
local C = FiveEMS.Client

local careTargetZones = {}
local occupantCache = {}
local lastScanAt = 0
local scanIntervalMs = 350

local CARE_TYPES = {
    [FiveEMS.PointTypes.BED]=true,
    [FiveEMS.PointTypes.SURGERY]=true,
    [FiveEMS.PointTypes.IML]=true,
    [FiveEMS.PointTypes.OTHER]=true,
}

local regionLabels = {
    head='Cabeca', neck='Pescoco', chest='Torax', abdomen='Abdome', pelvis='Pelve',
    left_arm='Braco esquerdo', right_arm='Braco direito', left_leg='Perna esquerda', right_leg='Perna direita',
    left_foot='Pe esquerdo', right_foot='Pe direito',
}

local function normalizePointId(v) return tonumber(v) or 0 end

local function patientWorldPosition(point)
    local t=(point.data and point.data.patient_transform) or {}
    local heading=tonumber(point.heading) or 0.0
    local rad=math.rad(heading)
    local lx,ly=tonumber(t.x) or 0.0,tonumber(t.y) or 0.0
    local wx=(tonumber(point.x) or 0.0)+(lx*math.cos(rad))-(ly*math.sin(rad))
    local wy=(tonumber(point.y) or 0.0)+(lx*math.sin(rad))+(ly*math.cos(rad))
    local wz=(tonumber(point.z) or 0.0)+(tonumber(t.z) or 0.90)
    return vector3(wx,wy,wz)
end

local function stateCarePointId(ped)
    if not ped or ped==0 or not DoesEntityExist(ped) then return 0 end
    local ok,value=pcall(function() return Entity(ped).state['fiveems:carePointId'] end)
    return ok and (tonumber(value) or 0) or 0
end

local function refFromPed(ped)
    if not ped or ped==0 or not DoesEntityExist(ped) then return nil end
    if IsPedAPlayer(ped) then
        local player = NetworkGetPlayerIndexFromPed(ped)
        if player and player ~= -1 then
            local sid = GetPlayerServerId(player)
            if sid and sid > 0 then return {kind='player',serverId=sid} end
        end
        return nil
    end
    if not IsPedHuman(ped) then return nil end
    if not NetworkGetEntityIsNetworked(ped) then return nil end
    local netId=PedToNet(ped)
    if netId and netId>0 then return {kind='npc',netId=netId} end
    return nil
end

local function scanOccupant(point)
    local pointId=normalizePointId(point and point.id)
    if pointId<=0 then return nil end
    local anchor=patientWorldPosition(point)
    local best,bestDist
    for _,ped in ipairs(GetGamePool('CPed')) do
        if DoesEntityExist(ped) and IsPedHuman(ped) and stateCarePointId(ped)==pointId then
            local d=#(GetEntityCoords(ped)-anchor)
            if d<4.5 and (not bestDist or d<bestDist) then
                local ref=refFromPed(ped)
                if ref then best={ref=ref,ped=ped};bestDist=d end
            end
        end
    end
    return best
end

local function carePoints()
    local out={}
    local departments=C.worldDepartments or {}
    if #departments==0 and C.department then departments={C.department} end
    for _,d in ipairs(departments) do
        for _,point in ipairs((d and d.points) or {}) do
            if CARE_TYPES[point.type] then
                point.department_id=point.department_id or d.id
                point.department_name=point.department_name or d.name
                point.data=point.data or {}
                out[#out+1]=point
            end
        end
    end
    return out
end

local function refreshOccupants(force)
    local now=GetGameTimer()
    if not force and now-lastScanAt<scanIntervalMs then return end
    lastScanAt=now

    -- Uma unica varredura de peds alimenta todos os leitos. Evita custo
    -- O(leitos x peds) em hospitais maiores.
    local pointsById={}
    local anchors={}
    for _,point in ipairs(carePoints()) do
        local id=normalizePointId(point.id)
        if id>0 then pointsById[id]=point; anchors[id]=patientWorldPosition(point) end
    end

    local nextCache={}
    local bestDist={}
    for _,ped in ipairs(GetGamePool('CPed')) do
        if DoesEntityExist(ped) and IsPedHuman(ped) then
            local id=stateCarePointId(ped)
            local anchor=anchors[id]
            if anchor then
                local d=#(GetEntityCoords(ped)-anchor)
                if d<4.5 and (not bestDist[id] or d<bestDist[id]) then
                    local ref=refFromPed(ped)
                    if ref then
                        nextCache[id]={ref=ref,ped=ped}
                        bestDist[id]=d
                    end
                end
            end
        end
    end
    occupantCache=nextCache
end

function C.resolveCarePointOccupant(point, force)
    if force then refreshOccupants(true) else refreshOccupants(false) end
    local row=occupantCache[normalizePointId(point and point.id)]
    if row and row.ped and DoesEntityExist(row.ped) and stateCarePointId(row.ped)==normalizePointId(point and point.id) then
        return row.ref,row.ped
    end
    if force then
        row=scanOccupant(point)
        if row then occupantCache[normalizePointId(point.id)]=row; return row.ref,row.ped end
    end
    return nil,nil
end

local function npcSnapshotForPed(ped)
    if ped and C.snapshotNpc then return C.snapshotNpc(ped) end
    return {}
end

function C.openCarePointChart(point)
    local ref,ped=C.resolveCarePointOccupant(point,true)
    if not ref then return C.notify(('Leito vazio: %s.'):format(point and (point.label or point.type) or 'sem paciente')) end
    C.targetRef=ref
    C.targetServerId=ref.kind=='player' and tonumber(ref.serverId) or nil
    C.openUi('bed_chart',{carePoint=point,targetRef=ref,targetServerId=C.targetServerId})
    TriggerServerEvent('fiveems:server:bedChartRequest',ref,normalizePointId(point.id),ref.kind=='npc' and npcSnapshotForPed(ped) or {})
end

local function openFullClinical(point)
    local ref,ped=C.resolveCarePointOccupant(point,true)
    if not ref then return C.notify('Nao ha paciente neste leito.') end
    if C.openClinicalTarget then
        C.openClinicalTarget(ref,ref.kind=='npc' and npcSnapshotForPed(ped) or {})
    else
        C.targetRef=ref
        C.targetServerId=ref.kind=='player' and tonumber(ref.serverId) or nil
        C.openUi('patient',{targetRef=ref,targetServerId=C.targetServerId})
        TriggerServerEvent('fiveems:server:clinicalRequestState',ref,ref.kind=='npc' and npcSnapshotForPed(ped) or {})
    end
end

local function fieldItems()
    local items=C.fieldItems
    if type(items)=='table' then return items end
    local st=LocalPlayer and LocalPlayer.state and LocalPlayer.state.fiveemsFieldItems or nil
    return type(st)=='table' and st or {}
end

local function treatmentAvailable(def)
    if not def or not def.item then return true end
    return (tonumber(fieldItems()[def.item]) or 0)>0
end

local function beginBedTreatment(point,key,region)
    local ref,ped=C.resolveCarePointOccupant(point,true)
    if not ref then return C.notify('O leito ficou vazio.') end
    TriggerServerEvent('fiveems:server:clinicalBeginHandTreatment',ref,nil,key,region,ref.kind=='npc' and npcSnapshotForPed(ped) or {})
end

local function regionListForTreatment(key,def)
    if def and def.region then return {tostring(def.region)} end
    local list=((FiveEMS.Clinical or {}).treatmentRegions or {})[key]
    if type(list)=='table' and #list>0 then return list end
    return {'chest'}
end

function C.openCarePointTreatmentMenu(point)
    local ref=C.resolveCarePointOccupant(point,true)
    if not ref then return C.notify('Nao ha paciente neste leito.') end
    if not lib or not lib.registerContext or not lib.showContext then
        return openFullClinical(point)
    end

    local ordered={'direct_pressure','wound_pack','pressure_bandage','tourniquet','chest_seal','c_collar','splint','airway_opa','suction','iv_access','thermal_blanket','burn_dressing'}
    local options={}
    for _,key in ipairs(ordered) do
        local def=(FiveEMS.Treatments or {})[key]
        if def and treatmentAvailable(def) then
            local regions=regionListForTreatment(key,def)
            options[#options+1]={
                title=tostring(def.label or key),
                description=def.item and ('Item em maos: '..tostring(def.item)) or 'Sem item obrigatorio',
                icon='kit-medical',
                onSelect=function()
                    if #regions==1 then return beginBedTreatment(point,key,tostring(regions[1])) end
                    local regionOptions={}
                    for _,r in ipairs(regions) do
                        local region=tostring(r)
                        regionOptions[#regionOptions+1]={
                            title=regionLabels[region] or region,
                            icon='location-dot',
                            onSelect=function() beginBedTreatment(point,key,region) end,
                        }
                    end
                    local regionMenu=('fiveems_bed_regions_%s_%s'):format(normalizePointId(point.id),key)
                    lib.registerContext({id=regionMenu,title=(def.label or key)..' - regiao',menu=('fiveems_bed_treatments_%s'):format(normalizePointId(point.id)),options=regionOptions})
                    lib.showContext(regionMenu)
                end,
            }
        end
    end
    if #options==0 then
        options={{title='Nenhum tratamento disponivel',description='Pegue o material na bolsa medica antes de tratar.',disabled=true,icon='briefcase-medical'}}
    end
    local menuId=('fiveems_bed_treatments_%s'):format(normalizePointId(point.id))
    lib.registerContext({id=menuId,title=('Tratamentos - %s'):format(point.label or 'Leito'),options=options})
    lib.showContext(menuId)
end

local function clearTargetZones()
    if GetResourceState('ox_target')=='started' then
        for _,id in ipairs(careTargetZones) do pcall(function() exports.ox_target:removeZone(id) end) end
    end
    careTargetZones={}
end

local function registerTargetZones()
    clearTargetZones()
    if GetResourceState('ox_target')~='started' then return end
    for _,point in ipairs(carePoints()) do
        local pos=patientWorldPosition(point)
        local pointCopy=point
        local ok,id=pcall(function()
            return exports.ox_target:addSphereZone({
                coords=pos,
                radius=1.05,
                debug=false,
                drawSprite=false,
                options={
                    {
                        name=('fiveems_bed_chart_%s'):format(pointCopy.id),
                        icon='fa-solid fa-clipboard-list',
                        label='Abrir ficha do leito',
                        distance=2.8,
                        canInteract=function() return C.resolveCarePointOccupant(pointCopy,false)~=nil end,
                        onSelect=function() C.openCarePointChart(pointCopy) end,
                    },
                    {
                        name=('fiveems_bed_attend_%s'):format(pointCopy.id),
                        icon='fa-solid fa-user-doctor',
                        label='Atender paciente no leito',
                        distance=2.8,
                        canInteract=function() return C.resolveCarePointOccupant(pointCopy,false)~=nil end,
                        onSelect=function() openFullClinical(pointCopy) end,
                    },
                    {
                        name=('fiveems_bed_treat_%s'):format(pointCopy.id),
                        icon='fa-solid fa-kit-medical',
                        label='Tratamentos EMS',
                        distance=2.8,
                        canInteract=function() return C.resolveCarePointOccupant(pointCopy,false)~=nil end,
                        onSelect=function() C.openCarePointTreatmentMenu(pointCopy) end,
                    },
                },
            })
        end)
        if ok and id then careTargetZones[#careTargetZones+1]=id end
    end
end

RegisterNetEvent('fiveems:client:bedChartData',function(payload)
    if type(payload)~='table' then return end
    C.targetRef=payload.targetRef or C.targetRef
    C.targetServerId=C.targetRef and C.targetRef.kind=='player' and tonumber(C.targetRef.serverId) or nil
    C.targetState=payload.state
    SendNUIMessage({action='bedChartData',data=payload})
end)

AddEventHandler('fiveems:client:refreshDepartmentWorld',function()
    CreateThread(function()
        Wait(150)
        refreshOccupants(true)
        registerTargetZones()
    end)
end)

AddEventHandler('onClientResourceStart',function(resourceName)
    if resourceName=='ox_target' or resourceName==GetCurrentResourceName() then
        CreateThread(function()
            Wait(1200)
            refreshOccupants(true)
            registerTargetZones()
        end)
    end
end)

AddEventHandler('onResourceStop',function(resourceName)
    if resourceName~=GetCurrentResourceName() then return end
    clearTargetZones()
end)

CreateThread(function()
    while true do
        Wait(scanIntervalMs)
        refreshOccupants(true)
    end
end)
