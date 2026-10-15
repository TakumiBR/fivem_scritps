FiveEMS = FiveEMS or {}
FiveEMS.ClinicalRuntime = FiveEMS.ClinicalRuntime or {}

local CR = FiveEMS.ClinicalRuntime
local M = FiveEMS.Medical
local DB = FiveEMS.DB
local F = FiveEMS.Framework
local Server = FiveEMS.Server
local P = FiveEMS.Progression

CR.pendingHandTreatments = CR.pendingHandTreatments or {}
local pendingHandTreatments = CR.pendingHandTreatments

local function clamp(v, a, b)
    v = tonumber(v) or 0
    if v < a then return a end
    if v > b then return b end
    return v
end

local function shallowCopy(t)
    local out = {}
    for k,v in pairs(type(t)=='table' and t or {}) do out[k]=v end
    return out
end

local function normalizeTarget(ref)
    if type(ref) == 'number' then
        return {kind='player', serverId=tonumber(ref)}
    end
    if type(ref) ~= 'table' then return nil end
    local kind = tostring(ref.kind or (ref.serverId and 'player') or (ref.netId and 'npc') or '')
    if kind == 'player' then
        local id = tonumber(ref.serverId or ref.id)
        if id and id > 0 then return {kind='player', serverId=id} end
    elseif kind == 'npc' then
        local netId = tonumber(ref.netId or ref.id)
        if netId and netId > 0 then return {kind='npc', netId=netId} end
    end
    return nil
end

local function targetCoords(target)
    if not target then return nil end
    if target.kind == 'player' then
        local ped = GetPlayerPed(target.serverId)
        if ped ~= 0 and DoesEntityExist(ped) then return GetEntityCoords(ped) end
    elseif target.kind == 'npc' then
        local entity = NetworkGetEntityFromNetworkId(target.netId)
        if entity ~= 0 and DoesEntityExist(entity) then return GetEntityCoords(entity) end
    end
    return nil
end

local function providerNearTarget(src, target, maxDistance)
    if Server.isAdmin(src) then return true end
    local providerPed = GetPlayerPed(src)
    if providerPed == 0 or not DoesEntityExist(providerPed) then return false end
    local tcoords = targetCoords(target)
    if not tcoords then return false end
    return #(GetEntityCoords(providerPed) - tcoords) <= (maxDistance or 5.0)
end

local function ensureStateFields(state)
    state.injuries = state.injuries or {}
    state.organs = state.organs or {}
    state.treatments = state.treatments or {}
    state.vitals = state.vitals or {hr=78,rr=16,sys=120,dia=78,spo2=98,temp=36.8,gcs=15,etco2=38,rhythm='sinus'}
    state.observedVitals = state.observedVitals or {}
    state.assessedRegions = state.assessedRegions or {}
    state.xabcde = state.xabcde or {}
    state.timeline = state.timeline or {}
    state.clinical = state.clinical or {triage='UNASSESSED'}
    return state
end

function M.addTimeline(state, eventType, label, data)
    if not state then return end
    ensureStateFields(state)
    table.insert(state.timeline, {
        at = os.time(),
        type = tostring(eventType or 'note'),
        label = tostring(label or ''),
        data = type(data)=='table' and data or {},
    })
    while #state.timeline > 120 do table.remove(state.timeline, 1) end
end

local function resolveTargetState(ref, npcSnapshot)
    local target = normalizeTarget(ref)
    if not target then return nil, nil, 'Paciente invalido.' end

    if target.kind == 'player' then
        if not GetPlayerName(target.serverId) then return nil,nil,'Player nao encontrado.' end
        local state = M.getState(target.serverId)
        if not state then return nil,nil,'Estado medico indisponivel.' end
        ensureStateFields(state)
        state.patientKind = 'player'
        state.patientRef = target
        if F and F.getPlayerIdentity then state.identity = F.getPlayerIdentity(target.serverId) end
        return target, state
    end

    local entity = NetworkGetEntityFromNetworkId(target.netId)
    if entity == 0 or not DoesEntityExist(entity) or GetEntityType(entity) ~= 1 then
        return nil,nil,'NPC nao esta sincronizado no servidor.'
    end

    local identityArgs = {
        persistir=true,
        source='fiveems_clinical',
        sexo=type(npcSnapshot)=='table' and npcSnapshot.sexo or nil,
        idade=type(npcSnapshot)=='table' and npcSnapshot.idade or nil,
        idade_min=type(npcSnapshot)=='table' and npcSnapshot.idade_min or nil,
        idade_max=type(npcSnapshot)=='table' and npcSnapshot.idade_max or nil,
        age_group=type(npcSnapshot)=='table' and npcSnapshot.age_group or nil,
        archetype=type(npcSnapshot)=='table' and npcSnapshot.archetype or nil,
        model_hash=type(npcSnapshot)=='table' and (npcSnapshot.model_hash or npcSnapshot.model) or nil,
    }
    local identity = F and F.getNpcIdentity and F.getNpcIdentity(target.netId, identityArgs) or nil
    if type(identity) ~= 'table' or not identity.framework_key then
        return nil,nil,'Nao foi possivel resolver a identidade do NPC.'
    end

    local state = M.loadStateByIdentifier(identity.framework_key)
    ensureStateFields(state)
    state.identity = identity
    state.patientKind = 'npc'
    state.patientRef = target
    state.npcNetworkId = target.netId

    if not state.npcPresentationInitialized and type(npcSnapshot) == 'table' then
        local health = tonumber(npcSnapshot.health) or 200
        local maxHealth = math.max(100, tonumber(npcSnapshot.maxHealth) or 200)
        local loss = clamp(((maxHealth - health) / maxHealth) * 100.0, 0, 100)
        if npcSnapshot.dead == true then loss = math.max(loss, 88) end
        if loss >= 4 then
            local severity = clamp(loss * 0.92 + (npcSnapshot.dead and 18 or 0), 5, 100)
            local region = tostring(npcSnapshot.region or 'chest')
            local category = tostring(npcSnapshot.category or 'blunt')
            local injury = {
                id=('npc-%s-%s'):format(target.netId, os.time()),
                region=region, category=category, severity=severity,
                bleeding=clamp(severity * (category=='gunshot' and 0.20 or category=='stabbing' and 0.16 or 0.05), 0, 28),
                pain=clamp(severity * 0.78,0,100), weapon=tonumber(npcSnapshot.weapon) or 0,
                bone=tonumber(npcSnapshot.bone) or 0, createdAt=os.time(), treated={}
            }
            table.insert(state.injuries, injury)
            state.bleedingRate = (tonumber(state.bleedingRate) or 0) + injury.bleeding
            state.pain = math.max(tonumber(state.pain) or 0, injury.pain)
            if npcSnapshot.dead == true then
                state.vitals.gcs = 3
                state.vitals.sys = math.min(tonumber(state.vitals.sys) or 120, 58)
                state.vitals.spo2 = math.min(tonumber(state.vitals.spo2) or 98, 72)
            end
            M.addTimeline(state, 'injury', ('Paciente NPC admitido com trauma em %s'):format(region), {severity=severity,category=category})
        end
        state.npcPresentationInitialized = true
        M.saveState(state)
    end

    return target, state
end

local function patientPayload(target, state, providerSrc)
    local bag=CR.getBag(providerSrc)
    local FE=FiveEMS.FieldEquipment
    if FE and FE.getUsableSnapshot then bag=FE.getUsableSnapshot(providerSrc) end
    return {
        targetRef = target,
        state = state,
        bag = bag,
        treatmentCatalog = FiveEMS.Treatments,
        clinicalCatalog = FiveEMS.Clinical,
    }
end

local bagCache = {}

local function bagIdentifier(src)
    return Server.getPrimaryIdentifier(src)
end

function CR.getBagByIdentifier(identifier)
    identifier = tostring(identifier or '')
    if identifier == '' then return {} end
    if bagCache[identifier] then return bagCache[identifier] end
    local row = DB.single('SELECT contents FROM fiveems_medical_bags WHERE identifier=?', {identifier})
    local contents = row and DB.jsonDecode(row.contents, {}) or {}
    if type(contents) ~= 'table' then contents = {} end
    bagCache[identifier] = contents
    return contents
end

function CR.getBag(src)
    local identifier = bagIdentifier(src)
    if not identifier then return {} end
    return CR.getBagByIdentifier(identifier)
end

function CR.saveBagByIdentifier(identifier, bag)
    identifier = tostring(identifier or '')
    if identifier == '' then return end
    bagCache[identifier] = bag
    DB.query([[
        INSERT INTO fiveems_medical_bags (identifier, contents)
        VALUES (?, ?)
        ON DUPLICATE KEY UPDATE contents=VALUES(contents), updated_at=CURRENT_TIMESTAMP
    ]], {identifier, DB.jsonEncode(bag)})
end

local function saveBag(src, bag)
    local identifier = bagIdentifier(src)
    if not identifier then return end
    CR.saveBagByIdentifier(identifier, bag)
end

local function bagHas(src, itemName, amount)
    if not itemName then return true end
    amount = math.max(1, math.floor(tonumber(amount) or 1))
    local FE = FiveEMS.FieldEquipment
    if FE and FE.hasUsableItem and FE.hasUsableItem(src, itemName, amount) then return true end
    local bag = CR.getBag(src)
    return (tonumber(bag[itemName]) or 0) >= amount
end

local function consumeBag(src, itemName, amount)
    if not itemName then return true end
    amount = math.max(1, math.floor(tonumber(amount) or 1))
    local FE = FiveEMS.FieldEquipment
    if FiveEMS.Clinical.nonConsumableItems[itemName] then
        if FE and FE.hasUsableItem and FE.hasUsableItem(src, itemName, 1) then return true end
        return bagHas(src,itemName,1)
    end
    if FE and FE.consumeUsableItem and FE.consumeUsableItem(src, itemName, amount) then return true end
    local bag = CR.getBag(src)
    local have = tonumber(bag[itemName]) or 0
    if have < amount then return false end
    bag[itemName] = have - amount
    saveBag(src, bag)
    return true
end

local function appendEncounter(providerSrc, state, target)
    local provider = Server.getPrimaryIdentifier(providerSrc)
    if not provider or not state or not state.identifier then return end
    local existing = DB.single([[
        SELECT id FROM fiveems_encounters
        WHERE patient_identifier=? AND provider_identifier=? AND status='active'
        ORDER BY id DESC LIMIT 1
    ]], {state.identifier, provider})
    if existing then return tonumber(existing.id) end
    local member = Server.getMember(providerSrc)
    return DB.insert([[
        INSERT INTO fiveems_encounters (patient_identifier, provider_identifier, department_id, patient_kind, payload)
        VALUES (?, ?, ?, ?, ?)
    ]], {state.identifier, provider, member and member.department_id or nil, target.kind, DB.jsonEncode({identity=state.identity})})
end

local function sendState(src, target, state)
    TriggerClientEvent('fiveems:client:clinicalStateUpdated', src, patientPayload(target, state, src))
end

local function sendMonitorState(src, target, state)
    TriggerClientEvent('fiveems:client:monitorStateUpdated', src, patientPayload(target, state, src))
end

local regionLabels = {
    head='cabeca', neck='pescoco', chest='torax', abdomen='abdome', pelvis='pelve',
    left_arm='braco esquerdo', right_arm='braco direito', left_leg='perna esquerda', right_leg='perna direita',
    left_foot='pe esquerdo', right_foot='pe direito'
}

local function canonicalRegion(region)
    region = tostring(region or '')
    if region == 'left_foot' then return 'left_leg' end
    if region == 'right_foot' then return 'right_leg' end
    return region
end

local categoryLabels = {
    gunshot='ferimento por projetil', stabbing='ferimento perfurante', blunt='trauma contuso',
    vehicle='trauma veicular', fall='trauma por queda', explosion='trauma por explosao', burn='queimadura', drowning='afogamento', unknown='trauma'
}

local function makeFindings(state, region)
    local findings = {}
    local canonical = canonicalRegion(region)
    for _, injury in ipairs(state.injuries or {}) do
        if canonicalRegion(injury.region) == canonical then
            local severity = tonumber(injury.severity) or 0
            local level = severity >= 70 and 'grave' or severity >= 40 and 'moderado' or 'leve'
            findings[#findings+1] = {
                injuryId=injury.id,
                title=categoryLabels[injury.category] or tostring(injury.category or 'trauma'),
                region=region,
                severity=severity,
                level=level,
                bleeding=tonumber(injury.bleeding) or 0,
                pain=tonumber(injury.pain) or 0,
                treated=injury.treated or {},
            }
        end
    end
    return findings
end

local recalcBleeding, updateTriage

local function treatmentAllowedForRegion(key, region)
    local list = FiveEMS.Clinical.treatmentRegions[key]
    if not list then return true end
    for _, r in ipairs(list) do if r == region then return true end end
    return false
end

local function treatmentFindInjury(state, injuryId, region, treatmentKey)
    local found
    if injuryId then
        for _, injury in ipairs(state.injuries or {}) do
            if tostring(injury.id) == tostring(injuryId) then found=injury break end
        end
    elseif region ~= '' then
        local searchRegion = canonicalRegion(region)
        local worst = -1
        for _, injury in ipairs(state.injuries or {}) do
            local already=false
            for _,applied in ipairs(injury.treated or {}) do
                if tostring(applied)==tostring(treatmentKey or '') then already=true break end
            end
            if not already and canonicalRegion(injury.region) == searchRegion and (tonumber(injury.severity) or 0) > worst then
                found=injury; worst=tonumber(injury.severity) or 0
            end
        end
    end
    return found
end

local function validateTreatment(src, ref, injuryId, treatmentKey, region, requireHand, npcSnapshot)
    if not Server.hasPermission(src, 'patient.treat') then return nil,nil,nil,nil,_L('no_permission') end
    local target, state, err = resolveTargetState(ref, npcSnapshot)
    if not target then return nil,nil,nil,nil,err or 'Paciente invalido.' end
    if not providerNearTarget(src,target,8.0) then return nil,nil,nil,nil,'Aproxime-se do paciente.' end

    treatmentKey=tostring(treatmentKey or '')
    region=tostring(region or '')
    local def=FiveEMS.Treatments[treatmentKey]
    if not def then return nil,nil,nil,nil,'Tratamento desconhecido.' end
    if tostring(def.skill or 'basic') == 'advanced' and not Server.hasPermission(src, 'patient.advanced') then
        return nil,nil,nil,nil,'Seu cargo nao possui autorizacao para este procedimento avancado.'
    end
    if region ~= '' and not treatmentAllowedForRegion(treatmentKey,region) then
        return nil,nil,nil,nil,'Tratamento incompativel com esta regiao.'
    end
    if def.extremityOnly and region ~= '' and region ~= 'left_arm' and region ~= 'right_arm' and region ~= 'left_leg' and region ~= 'right_leg' and region ~= 'left_foot' and region ~= 'right_foot' then
        return nil,nil,nil,nil,'Este procedimento exige um membro.'
    end
    if def.region and region ~= '' and region ~= def.region then
        return nil,nil,nil,nil,'Tratamento incompativel com esta regiao.'
    end

    local found=treatmentFindInjury(state,injuryId,region,treatmentKey)
    if def.requiresInjury and not found then
        return nil,nil,nil,nil,'Nenhuma lesao compativel foi identificada nessa regiao.'
    end
    if found then
        for _,applied in ipairs(found.treated or {}) do
            if applied==treatmentKey then return nil,nil,nil,nil,'Este procedimento ja foi aplicado nesta lesao.' end
        end
    end

    if requireHand and def.item then
        local FE=FiveEMS.FieldEquipment
        if not FE or not FE.hasHandItem or not FE.hasHandItem(src,def.item,1) then
            return nil,nil,nil,nil,('Pegue %s na bolsa antes de aplicar o procedimento.'):format(tostring(def.item))
        end
    end
    return target,state,def,found,nil
end

local function applyTreatmentState(src,target,state,def,found,treatmentKey,region,extra,consumeMode)
    local FE=FiveEMS.FieldEquipment
    if def.item then
        if consumeMode=='hand' then
            if FiveEMS.Clinical.nonConsumableItems[def.item] then
                if not FE or not FE.hasHandItem or not FE.hasHandItem(src,def.item,1) then return false,'Equipamento nao esta mais em suas maos.' end
            elseif not FE or not FE.consumeHandItem or not FE.consumeHandItem(src,def.item,1) then
                return false,'O item nao esta mais em suas maos.'
            end
        elseif not consumeBag(src,def.item,1) then
            return false,('Falta %s na bolsa medica.'):format(def.item)
        end
    end

    if found then
        found.treated=found.treated or {}
        local exists=false
        for _,key in ipairs(found.treated) do if key==treatmentKey then exists=true break end end
        if not exists then table.insert(found.treated,treatmentKey) end
    end

    state.treatments[treatmentKey]={by=Server.getPrimaryIdentifier(src),at=os.time(),region=region,extra=extra or {}}
    if treatmentKey=='airway_opa' or treatmentKey=='suction' then state.airway=clamp((state.airway or 1)+0.25,0,1) end
    if treatmentKey=='chest_seal' then state.ventilation=clamp((state.ventilation or 1)+0.18,0,1) end
    if treatmentKey=='thermal_blanket' then state.vitals.temp=clamp((state.vitals.temp or 36.8)+0.2,34,39.5) end
    if treatmentKey=='splint' then state.pain=clamp((state.pain or 0)-10,0,100) end
    if treatmentKey=='c_collar' then state.spinalPrecautions=true end
    if treatmentKey=='iv_access' then state.ivAccess={at=os.time(),by=Server.getPrimaryIdentifier(src),region=region} end
    recalcBleeding(state)
    updateTriage(state)

    if target.kind=='player' and F and F.applyPhysicalTreatment and found then
        local amount=({direct_pressure=8,wound_pack=16,tourniquet=22,pressure_bandage=14,chest_seal=10,splint=12,c_collar=8,burn_dressing=10})[treatmentKey] or 6
        F.applyPhysicalTreatment(target.serverId,found.region,amount)
    end

    M.addTimeline(state,'treatment',('Tratamento: %s'):format(def.label or treatmentKey),{region=region,injuryId=found and found.id or nil,physical=consumeMode=='hand'})
    M.saveState(state)
    if def.xp then P.addXp(src,Config.Progression.treatment,'clinical:'..treatmentKey) end
    sendState(src,target,state)
    return true
end

recalcBleeding = function(state)
    local total = 0.0
    for _, injury in ipairs(state.injuries or {}) do
        local mult = 1.0
        for _, treatment in ipairs(injury.treated or {}) do
            local def = FiveEMS.Treatments[treatment]
            if def and def.bleedingMultiplier then mult = math.min(mult, def.bleedingMultiplier) end
        end
        total = total + ((tonumber(injury.bleeding) or 0) * mult)
    end
    state.bleedingRate = total
end

local function xabcdeFinding(state, step)
    local v=state.vitals or {}
    local bleeding=tonumber(state.bleedingRate) or 0
    local airway=tonumber(state.airway) or 1.0
    local ventilation=tonumber(state.ventilation) or 1.0
    local pain=tonumber(state.pain) or 0
    local injuries=state.injuries or {}

    if step=='X' then
        if bleeding >= 12 then return 'Hemorragia externa importante / controle imediato indicado' end
        if bleeding > 2 then return 'Sangramento identificado / manter controle e reavaliar' end
        return 'Sem hemorragia exsanguinante evidente na avaliacao atual'
    elseif step=='A' then
        if airway < 0.55 then return 'Via aerea criticamente comprometida' end
        if airway < 0.85 then return 'Via aerea parcialmente comprometida / requer intervencao' end
        return 'Via aerea aparentemente patente'
    elseif step=='B' then
        if ventilation < 0.65 or (tonumber(v.spo2) or 100) < 88 then return 'Ventilacao gravemente comprometida / sinais respiratorios importantes' end
        if ventilation < 0.85 or (tonumber(v.rr) or 16) > 24 then return 'Respiracao alterada / investigar torax e oxigenacao' end
        return 'Respiracao sem alteracao critica evidente na avaliacao primaria'
    elseif step=='C' then
        if (tonumber(v.sys) or 120) < 90 or (tonumber(v.hr) or 80) > 120 then return 'Perfusao comprometida / suspeita de choque' end
        if bleeding > 2 then return 'Circulacao com perda sanguinea ativa / reavaliar perfusao' end
        return 'Perfusao periferica sem sinal critico evidente'
    elseif step=='D' then
        local gcs=tonumber(v.gcs) or 15
        if gcs <= 8 then return 'Rebaixamento grave do nivel de consciencia' end
        if gcs < 15 then return ('Alteracao neurologica / GCS clinicamente reduzido (%d)'):format(gcs) end
        return 'Resposta neurologica preservada na avaliacao atual'
    elseif step=='E' then
        local severe=0
        for _,injury in ipairs(injuries) do if (tonumber(injury.severity) or 0)>=40 then severe=severe+1 end end
        if (tonumber(v.temp) or 36.8) < 35.5 then return 'Risco de hipotermia / proteger do ambiente' end
        if severe>0 then return ('%d lesao(oes) moderada(s)/grave(s) exigem exposicao dirigida e exame secundario'):format(severe) end
        return 'Exposicao dirigida sem novo risco critico evidente'
    end
    return 'Avaliado'
end

updateTriage = function(state)
    local v=state.vitals or {}
    local worst=0
    for _,injury in ipairs(state.injuries or {}) do worst=math.max(worst,tonumber(injury.severity) or 0) end
    local critical = (tonumber(v.gcs) or 15)<=8 or (tonumber(v.sys) or 120)<80 or (tonumber(v.spo2) or 98)<85 or (tonumber(state.bleedingRate) or 0)>=15 or worst>=85
    local high = (tonumber(v.gcs) or 15)<13 or (tonumber(v.sys) or 120)<95 or (tonumber(v.spo2) or 98)<92 or (tonumber(state.bleedingRate) or 0)>=6 or worst>=60
    local moderate = worst>=30 or (tonumber(state.pain) or 0)>=50
    state.clinical=state.clinical or {}
    state.clinical.triage=critical and 'CRITICAL' or high and 'HIGH' or moderate and 'MODERATE' or 'LOW'
end

RegisterNetEvent('fiveems:server:clinicalRequestState', function(ref, snapshot)
    local src = source
    if not Server.hasPermission(src, 'patient.assess') then return Server.notify(src, _L('no_permission')) end
    local target, state, err = resolveTargetState(ref, snapshot)
    if not target then return Server.notify(src, err or 'Paciente invalido.') end
    if not providerNearTarget(src, target, 8.0) then return Server.notify(src, 'Aproxime-se do paciente.') end

    appendEncounter(src, state, target)
    if target.kind == 'player' and F and F.claimPatient then F.claimPatient(src, target.serverId, true) end
    sendState(src, target, state)
end)

RegisterNetEvent('fiveems:server:monitorRequestState', function(ref, snapshot)
    local src = source
    if not Server.hasPermission(src, 'monitor.use') and not Server.hasPermission(src, 'patient.assess') then
        return Server.notify(src, _L('no_permission'))
    end

    local target, state, err = resolveTargetState(ref, snapshot)
    if not target then return Server.notify(src, err or 'Paciente invalido.') end
    if not providerNearTarget(src, target, 10.0) then return Server.notify(src, 'Aproxime o monitor do paciente.') end

    appendEncounter(src, state, target)
    sendMonitorState(src, target, state)
end)

RegisterNetEvent('fiveems:server:clinicalAssessRegion', function(ref, region)
    local src = source
    if not Server.hasPermission(src, 'patient.assess') then return end
    local target, state = resolveTargetState(ref)
    if not target or not providerNearTarget(src,target,8.0) then return end
    region = tostring(region or '')
    if not FiveEMS.Clinical.regions[region] then return end

    state.assessedRegions[region] = {at=os.time(), by=Server.getPrimaryIdentifier(src), findings=makeFindings(state,region)}
    M.addTimeline(state, 'assessment', ('Regiao avaliada: %s'):format(regionLabels[region] or region), {region=region})
    M.saveState(state)
    sendState(src,target,state)
end)

RegisterNetEvent('fiveems:server:clinicalAssessXABCDE', function(ref, step)
    local src = source
    if not Server.hasPermission(src, 'patient.assess') then return end
    local target, state = resolveTargetState(ref)
    if not target or not providerNearTarget(src,target,8.0) then return end
    step = tostring(step or ''):upper()
    local def = FiveEMS.Clinical.xabcde[step]
    if not def then return end
    local finding=xabcdeFinding(state,step)
    state.xabcde[step] = {at=os.time(),by=Server.getPrimaryIdentifier(src),status='ASSESSED',finding=finding}
    updateTriage(state)
    M.addTimeline(state,'assessment',('XABCDE %s - %s: %s'):format(step,def.label,finding),{step=step,finding=finding})

    local complete=true
    for _,required in ipairs({'X','A','B','C','D','E'}) do
        if not state.xabcde[required] then complete=false break end
    end
    if complete and not state.clinical.primaryAssessmentXp then
        state.clinical.primaryAssessmentXp=true
        P.addXp(src,Config.Progression.completedAssessment,'clinical:xabcde')
        M.addTimeline(state,'assessment','Avaliacao primaria XABCDE concluida',{})
    end

    M.saveState(state)
    sendState(src,target,state)
end)

RegisterNetEvent('fiveems:server:clinicalMeasureVital', function(ref, measurementKey)
    local src = source
    if not Server.hasPermission(src, 'patient.assess') then return end
    local target, state = resolveTargetState(ref)
    if not target or not providerNearTarget(src,target,8.0) then return end
    local def = FiveEMS.Clinical.vitalMeasurements[tostring(measurementKey or '')]
    if not def then return end

    if def.equipment and not bagHas(src, def.equipment, 1) then
        return Server.notify(src, ('Falta %s na bolsa medica.'):format(def.equipment))
    end

    local observed = {at=os.time(),by=Server.getPrimaryIdentifier(src),measurement=measurementKey}
    for _, vitalKey in ipairs(def.values or {}) do observed[vitalKey] = state.vitals[vitalKey] end
    if measurementKey == 'auscultation' then
        local chest = makeFindings(state,'chest')
        local compromised = (tonumber(state.ventilation) or 1) < 0.78 or #chest > 0
        observed.finding = compromised and 'Murmurio vesicular reduzido / avaliar assimetria' or 'Murmurio vesicular presente bilateralmente'
    end
    state.observedVitals[measurementKey] = observed
    M.addTimeline(state,'vital',('Aferido: %s'):format(def.label),observed)
    M.saveState(state)
    sendState(src,target,state)
end)

RegisterNetEvent('fiveems:server:clinicalApplyTreatment', function(ref, injuryId, treatmentKey, region, extra)
    local src=source
    treatmentKey=tostring(treatmentKey or '')
    region=tostring(region or '')
    local target,state,def,found,err=validateTreatment(src,ref,injuryId,treatmentKey,region,false)
    if not target then return Server.notify(src,err or 'Tratamento nao autorizado.') end
    local ok,applyErr=applyTreatmentState(src,target,state,def,found,treatmentKey,region,extra or {},'bag')
    if not ok and applyErr then Server.notify(src,applyErr) end
end)

RegisterNetEvent('fiveems:server:clinicalBeginHandTreatment', function(ref, injuryId, treatmentKey, region, snapshot)
    local src=source
    treatmentKey=tostring(treatmentKey or '')
    region=tostring(region or '')
    local target,state,def,found,err=validateTreatment(src,ref,injuryId,treatmentKey,region,true,snapshot)
    if not target then return Server.notify(src,err or 'Nao foi possivel iniciar o tratamento.') end

    local token=('%d:%d:%d'):format(src,os.time(),math.random(100000,999999))
    pendingHandTreatments[src]={
        token=token,
        target=target,
        injuryId=found and found.id or injuryId,
        treatmentKey=treatmentKey,
        region=region,
        extra={source='ox_target_hand'},
        expiresAt=os.time()+30,
    }
    TriggerClientEvent('fiveems:client:handTreatmentApproved',src,{
        token=token,
        targetRef=target,
        treatmentKey=treatmentKey,
        region=region,
        label=def.label or treatmentKey,
        progressLabel=def.progressLabel or def.label or treatmentKey,
        durationMs=math.max(1200,math.floor(tonumber(def.durationMs) or 4500)),
    })
end)

RegisterNetEvent('fiveems:server:clinicalCancelHandTreatment', function(token)
    local src=source
    local row=pendingHandTreatments[src]
    if row and tostring(row.token)==tostring(token or '') then pendingHandTreatments[src]=nil end
end)

RegisterNetEvent('fiveems:server:clinicalCompleteHandTreatment', function(token)
    local src=source
    local row=pendingHandTreatments[src]
    if not row or tostring(row.token)~=tostring(token or '') then return end
    pendingHandTreatments[src]=nil
    if os.time()>(tonumber(row.expiresAt) or 0) then return Server.notify(src,'O tratamento expirou. Tente novamente.') end

    local target,state,def,found,err=validateTreatment(src,row.target,row.injuryId,row.treatmentKey,row.region,true)
    if not target then return Server.notify(src,err or 'Nao foi possivel concluir o tratamento.') end
    local ok,applyErr=applyTreatmentState(src,target,state,def,found,row.treatmentKey,row.region,row.extra or {},'hand')
    if not ok then return Server.notify(src,applyErr or 'Nao foi possivel concluir o tratamento.') end
    Server.notify(src,('%s concluido.'):format(tostring(def.label or row.treatmentKey)))
end)

RegisterNetEvent('fiveems:server:clinicalSetOxygen', function(ref, device, flow)
    local src=source
    if not Server.hasPermission(src,'patient.treat') then return end
    local target,state=resolveTargetState(ref)
    if not target or not providerNearTarget(src,target,8.0) then return end
    local cfg=Config.Oxygen.devices[device]
    if not cfg then return end
    local required = ({nasal_cannula='nasal_cannula', simple_mask='oxygen_mask', non_rebreather='non_rebreather', bvm='bvm'})[device]
    if required and not bagHas(src,required,1) then return Server.notify(src,('Falta %s na bolsa medica.'):format(required)) end
    flow=clamp(flow,cfg.minFlow,cfg.maxFlow)
    state.oxygenDevice=device; state.oxygenFlow=flow; state.oxygenStartedAt=os.time()
    M.addTimeline(state,'treatment',('Oxigenio: %s a %.0f L/min'):format(device,flow),{device=device,flow=flow})
    M.saveState(state); sendState(src,target,state)
end)

RegisterNetEvent('fiveems:server:clinicalStopOxygen', function(ref)
    local src=source
    if not Server.hasPermission(src,'patient.treat') then return end
    local target,state=resolveTargetState(ref)
    if not target then return end
    state.oxygenDevice=nil; state.oxygenFlow=0; state.oxygenStartedAt=nil
    M.addTimeline(state,'treatment','Oxigenoterapia interrompida',{})
    M.saveState(state); sendState(src,target,state)
end)

RegisterNetEvent('fiveems:server:clinicalRestockBag', function()
    local src=source
    if not Server.canUseOperational(src,'supplies.use') then return Server.notify(src,_L('no_permission')) end
    local member=Server.getMember(src)
    if not member or not member.department_id then return end

    local providerPed=GetPlayerPed(src)
    if providerPed==0 then return end
    local providerCoords=GetEntityCoords(providerPed)
    local supplyPoints=DB.query('SELECT x,y,z FROM fiveems_points WHERE department_id=? AND type=?',{member.department_id,FiveEMS.PointTypes.SUPPLY}) or {}
    local nearSupply=false
    for _,point in ipairs(supplyPoints) do
        local coords=vector3(tonumber(point.x) or 0.0,tonumber(point.y) or 0.0,tonumber(point.z) or 0.0)
        if #(providerCoords-coords)<=6.0 then nearSupply=true break end
    end
    if not nearSupply then return Server.notify(src,'Aproxime-se do ponto de medicamentos/equipamentos para reabastecer a bolsa.') end

    local bag=CR.getBag(src)
    local changed=0

    for itemName,targetQty in pairs(FiveEMS.Clinical.bagLoadout or {}) do
        local have=tonumber(bag[itemName]) or 0
        local need=math.max(0,(tonumber(targetQty) or 0)-have)
        if need > 0 then
            local row=DB.single('SELECT id,quantity FROM fiveems_supplies WHERE department_id=? AND item_name=? LIMIT 1',{member.department_id,itemName})
            if row and tonumber(row.quantity or 0) > 0 then
                local take=math.min(need,tonumber(row.quantity))
                DB.update('UPDATE fiveems_supplies SET quantity=GREATEST(0,quantity-?) WHERE id=?',{take,row.id})
                bag[itemName]=have+take
                changed=changed+take
            end
        end
    end

    saveBag(src,bag)
    Server.notify(src,('Bolsa medica reabastecida: %d item(ns).'):format(changed))
    TriggerClientEvent('fiveems:client:medicalBagUpdated',src,bag)
end)

RegisterNetEvent('fiveems:server:clinicalSubmitReport', function(ref, form)
    local src=source
    if not Server.hasPermission(src,'reports.create') then return Server.notify(src,_L('no_permission')) end
    local target,state=resolveTargetState(ref)
    if not target then return end
    form=type(form)=='table' and form or {}
    form.timeline=state.timeline
    form.injuries=state.injuries
    form.observedVitals=state.observedVitals
    form.xabcde=state.xabcde
    form.identity=state.identity
    local member=Server.getMember(src)
    DB.insert([[
        INSERT INTO fiveems_reports (patient_identifier,provider_identifier,department_id,report_type,payload)
        VALUES (?,?,?,?,?)
    ]],{state.identifier,Server.getPrimaryIdentifier(src),member and member.department_id or nil,'patient_care',DB.jsonEncode(form)})
    M.addTimeline(state,'report','ePCR enviado',{by=Server.getPrimaryIdentifier(src)})
    M.saveState(state)
    DB.update([[UPDATE fiveems_encounters SET status='completed', closed_at=CURRENT_TIMESTAMP WHERE patient_identifier=? AND provider_identifier=? AND status='active']],{state.identifier,Server.getPrimaryIdentifier(src)})
    if target.kind=='player' and F and F.claimPatient then F.claimPatient(src,target.serverId,false) end
    P.addXp(src,Config.Progression.reportSubmitted,'reportSubmitted')
    Server.notify(src,_L('report_submitted'))
    sendState(src,target,state)
end)

-- V0.5.1 — Hospital Bed Chart / ficha de leito.
-- A ficha e' deliberadamente separada da auditoria de cena: ela resolve o ocupante
-- real do leito e retorna somente dados desse paciente, sem scripted camera.
local function targetCarePointId(target)
    if not target then return 0 end
    if target.kind == 'player' then
        local ok, value = pcall(function()
            local player = Player(target.serverId)
            local fromPlayer = player and player.state and player.state['fiveems:carePointId'] or 0
            if tonumber(fromPlayer) and tonumber(fromPlayer) > 0 then return fromPlayer end
            local ped = GetPlayerPed(target.serverId)
            if ped and ped ~= 0 and DoesEntityExist(ped) then
                return Entity(ped).state['fiveems:carePointId'] or 0
            end
            return 0
        end)
        return ok and (tonumber(value) or 0) or 0
    end
    local entity = NetworkGetEntityFromNetworkId(tonumber(target.netId) or 0)
    if entity == 0 or not DoesEntityExist(entity) then return 0 end
    local ok, value = pcall(function() return Entity(entity).state['fiveems:carePointId'] end)
    return ok and (tonumber(value) or 0) or 0
end

local function compactReportHistory(identifier)
    local rows = DB.query([[
        SELECT id, report_type, payload, created_at
        FROM fiveems_reports
        WHERE patient_identifier=?
        ORDER BY id DESC LIMIT 12
    ]], {identifier}) or {}
    local out = {}
    local background = {allergies=nil, medications=nil, history=nil}
    for _,row in ipairs(rows) do
        local form = DB.jsonDecode(row.payload, {})
        local item = {
            id=tonumber(row.id), type=tostring(row.report_type or 'patient_care'), created_at=row.created_at,
            mechanism=form.mechanism, signs=form.signs, treatment=form.treatment,
            allergies=form.allergies, medications=form.medications, history=form.history,
            handover=form.handover,
        }
        out[#out+1]=item
        for _,key in ipairs({'allergies','medications','history'}) do
            local value = form[key]
            if not background[key] and value and tostring(value):match('%S') then background[key]=tostring(value) end
        end
    end
    return out, background
end

local function compactEncounterHistory(identifier)
    local rows = DB.query([[
        SELECT id, status, patient_kind, started_at, closed_at
        FROM fiveems_encounters
        WHERE patient_identifier=?
        ORDER BY id DESC LIMIT 12
    ]], {identifier}) or {}
    local out = {}
    for _,row in ipairs(rows) do
        out[#out+1] = {
            id=tonumber(row.id), status=tostring(row.status or ''), patient_kind=tostring(row.patient_kind or ''),
            started_at=row.started_at, closed_at=row.closed_at,
        }
    end
    return out
end

RegisterNetEvent('fiveems:server:bedChartRequest', function(ref, pointId, snapshot)
    local src = source
    if not Server.hasPermission(src, 'patient.assess') then return Server.notify(src, _L('no_permission')) end
    pointId = tonumber(pointId)
    if not pointId then return Server.notify(src, 'Leito invalido.') end

    local member = Server.getMember(src)
    local point = DB.single('SELECT id, department_id, type, label, x, y, z, heading FROM fiveems_points WHERE id=?', {pointId})
    if not point then return Server.notify(src, 'Leito nao encontrado.') end
    if not Server.isAdmin(src) and (not member or tonumber(member.department_id) ~= tonumber(point.department_id)) then
        return Server.notify(src, 'Este leito pertence a outro departamento.')
    end

    local target, state, err = resolveTargetState(ref, snapshot)
    if not target then return Server.notify(src, err or 'Paciente do leito invalido.') end
    if targetCarePointId(target) ~= pointId then
        return Server.notify(src, 'O paciente nao esta mais neste leito.')
    end
    if not providerNearTarget(src, target, 10.0) then return Server.notify(src, 'Aproxime-se do leito.') end

    appendEncounter(src, state, target)
    if target.kind == 'player' and F and F.claimPatient then F.claimPatient(src, target.serverId, true) end

    local reports, background = compactReportHistory(state.identifier)
    local encounters = compactEncounterHistory(state.identifier)
    TriggerClientEvent('fiveems:client:bedChartData', src, {
        targetRef=target,
        state=state,
        carePoint={id=tonumber(point.id), department_id=tonumber(point.department_id), type=point.type, label=point.label},
        chart={reports=reports, encounters=encounters, background=background, generatedAt=os.time()},
        clinicalCatalog=FiveEMS.Clinical,
        treatmentCatalog=FiveEMS.Treatments,
    })
end)

RegisterNetEvent('fiveems:server:clinicalClose', function(ref)
    local src=source
    local target=normalizeTarget(ref)
    if target and target.kind=='player' and F and F.claimPatient then F.claimPatient(src,target.serverId,false) end
end)


AddEventHandler('playerDropped',function()
    pendingHandTreatments[source]=nil
end)
