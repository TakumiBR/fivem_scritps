FiveEMS = FiveEMS or {}
FiveEMS.Medical = FiveEMS.Medical or {}

local M = FiveEMS.Medical
local DB = FiveEMS.DB
local F = FiveEMS.Framework
local Server = FiveEMS.Server
local P = FiveEMS.Progression

local active = {}
local playerByIdentifier = {}

local function clamp(v, a, b)
    v = tonumber(v) or 0
    if v < a then return a end
    if v > b then return b end
    return v
end

local function nowMs()
    return os.time() * 1000
end

local function defaultState(identifier)
    return {
        identifier = identifier,
        injuries = {},
        organs = {},
        treatments = {},
        bloodMl = Config.Physiology.normalBloodMl,
        bleedingRate = 0.0,
        pain = 0.0,
        airway = 1.0,
        ventilation = 1.0,
        oxygenDevice = nil,
        oxygenFlow = 0,
        oxygenStartedAt = nil,
        vitals = {
            hr = 78, rr = 16, sys = 120, dia = 78,
            spo2 = 98, temp = Config.Physiology.baseTemperature,
            gcs = 15, etco2 = 38, rhythm = FiveEMS.Rhythms.SINUS,
        },
        cardiacArrest = false,
        cprQuality = 0.0,
        lastUpdate = os.time(),
    }
end

local function loadState(identifier)
    if active[identifier] then return active[identifier] end
    local row = DB.single('SELECT medical_state FROM fiveems_patient_state WHERE identifier=?', {identifier})
    local state = row and DB.jsonDecode(row.medical_state, nil) or nil
    if type(state) ~= 'table' then state = defaultState(identifier) end
    state.identifier = identifier
    state.injuries = state.injuries or {}
    state.organs = state.organs or {}
    state.treatments = state.treatments or {}
    state.vitals = state.vitals or defaultState(identifier).vitals
    active[identifier] = state
    return state
end

local function saveState(state)
    if not state or not state.identifier then return end
    state.lastUpdate = os.time()
    DB.query([[
        INSERT INTO fiveems_patient_state (identifier, medical_state)
        VALUES (?, ?)
        ON DUPLICATE KEY UPDATE medical_state=VALUES(medical_state), updated_at=CURRENT_TIMESTAMP
    ]], {state.identifier, DB.jsonEncode(state)})
end

-- API interna usada pela camada clinica generica (Player + NPC).
M.defaultState = defaultState
M.loadStateByIdentifier = loadState
M.saveState = saveState


function M.getState(src)
    local identifier = Server.getPrimaryIdentifier(src)
    if not identifier then return nil end
    playerByIdentifier[identifier] = src
    local state = loadState(identifier)
    if F and F.getPlayerIdentity then state.identity = F.getPlayerIdentity(src) end
    return state
end

local function regionBleedFactor(region)
    if region == 'neck' or region == 'chest' or region == 'abdomen' or region == 'pelvis' then return 1.45 end
    if region == 'left_leg' or region == 'right_leg' then return 1.15 end
    if region == 'left_arm' or region == 'right_arm' then return 0.85 end
    if region == 'head' then return 1.10 end
    return 0.7
end

local function damageBleedFactor(category)
    if category == 'gunshot' then return 1.30 end
    if category == 'stabbing' then return 1.15 end
    if category == 'explosion' then return 1.40 end
    if category == 'vehicle' then return 0.55 end
    if category == 'fall' then return 0.45 end
    if category == 'blunt' then return 0.25 end
    return 0.35
end

local function maybeInternalOrgan(state, region, severity, category)
    if severity < 28 then return end
    local organ
    if region == 'chest' then
        organ = category == 'gunshot' and 'lung' or (math.random() < 0.35 and 'lung' or nil)
    elseif region == 'abdomen' then
        local choices = {'liver','spleen','kidney','bowel'}
        organ = choices[math.random(1, #choices)]
    elseif region == 'head' then
        organ = 'brain'
    end
    if organ then
        state.organs[organ] = math.max(tonumber(state.organs[organ]) or 0, clamp(severity * 0.9, 1, 100))
    end
end

RegisterNetEvent('fiveems:server:recordDamage', function(payload)
    local src = source
    payload = payload or {}
    local state = M.getState(src)
    if not state then return end

    local region = tostring(payload.region or 'chest')
    local category = tostring(payload.category or 'unknown')
    local raw = clamp(payload.damage or 5, 1, 100)
    local multiplier = Config.DamageMultipliers[category] or 1.0
    local severity = clamp(raw * multiplier, 1, 100)
    local bleed = severity * regionBleedFactor(region) * damageBleedFactor(category) * Config.Physiology.bleedScale

    local injury = {
        id = ('inj-%s-%s-%s'):format(src, os.time(), math.random(1000,9999)),
        region = region,
        category = category,
        severity = severity,
        bleeding = bleed,
        pain = clamp(severity * 0.8, 0, 100),
        weapon = tonumber(payload.weapon) or 0,
        bone = tonumber(payload.bone) or 0,
        sourceNetId = tonumber(payload.attackerNetId) or 0,
        createdAt = os.time(),
        treated = {},
    }
    table.insert(state.injuries, injury)
    state.bleedingRate = (tonumber(state.bleedingRate) or 0) + bleed
    state.pain = clamp((tonumber(state.pain) or 0) + injury.pain * 0.35, 0, 100)

    if category == 'drowning' then state.ventilation = clamp(state.ventilation - 0.35, 0, 1) end
    if category == 'burn' then state.ventilation = clamp(state.ventilation - 0.08, 0, 1) end
    if region == 'chest' and severity > 45 then state.ventilation = clamp(state.ventilation - severity / 220, 0.15, 1) end
    if region == 'head' and severity > 50 then state.vitals.gcs = clamp(state.vitals.gcs - math.floor(severity / 25), 3, 15) end

    maybeInternalOrgan(state, region, severity, category)
    if M.addTimeline then
        M.addTimeline(state, 'injury', ('Nova lesao: %s / %s'):format(region, category), {
            region=region, category=category, severity=severity, bleeding=bleed
        })
    end
    saveState(state)
    TriggerClientEvent('fiveems:client:medicalState', src, state)
end)

local function recalcBleeding(state)
    local total = 0.0
    for _, injury in ipairs(state.injuries or {}) do
        local b = tonumber(injury.bleeding) or 0
        local mult = 1.0
        for _, treatment in ipairs(injury.treated or {}) do
            local def = FiveEMS.Treatments[treatment]
            if def and def.bleedingMultiplier then mult = math.min(mult, def.bleedingMultiplier) end
        end
        total = total + (b * mult)
    end
    state.bleedingRate = total
end

local function hasExtremity(region)
    return region == 'left_arm' or region == 'right_arm' or region == 'left_leg' or region == 'right_leg'
end

RegisterNetEvent('fiveems:server:applyTreatment', function(targetSrc, injuryId, treatmentKey, extra)
    local src = source
    targetSrc = tonumber(targetSrc)
    if not targetSrc or not GetPlayerName(targetSrc) then return end
    if not Server.hasPermission(src, 'patient.treat') then return Server.notify(src, _L('no_permission')) end
    local def = FiveEMS.Treatments[treatmentKey]
    if not def then return end

    local state = M.getState(targetSrc)
    if not state then return end
    local found
    if injuryId then
        for _, injury in ipairs(state.injuries or {}) do
            if injury.id == injuryId then found = injury break end
        end
    end
    if def.extremityOnly and found and not hasExtremity(found.region) then return end
    if def.region and found and found.region ~= def.region then return end

    if found then
        found.treated = found.treated or {}
        local exists = false
        for _, t in ipairs(found.treated) do if t == treatmentKey then exists = true end end
        if not exists then table.insert(found.treated, treatmentKey) end
    end
    state.treatments[treatmentKey] = {by=Server.getPrimaryIdentifier(src), at=os.time(), extra=extra or {}}

    if treatmentKey == 'airway_opa' or treatmentKey == 'suction' then state.airway = clamp(state.airway + 0.25, 0, 1) end
    if treatmentKey == 'chest_seal' then state.ventilation = clamp(state.ventilation + 0.18, 0, 1) end
    if treatmentKey == 'thermal_blanket' then state.vitals.temp = clamp(state.vitals.temp + 0.2, 34, 39.5) end

    recalcBleeding(state)
    if F and F.applyPhysicalTreatment and found then
        local amount = ({direct_pressure=8,wound_pack=16,tourniquet=22,pressure_bandage=14,chest_seal=10,splint=12,c_collar=8,burn_dressing=10})[treatmentKey] or 6
        F.applyPhysicalTreatment(targetSrc, found.region, amount)
    end
    saveState(state)
    TriggerClientEvent('fiveems:client:medicalState', targetSrc, state)
    TriggerClientEvent('fiveems:client:targetStateUpdated', src, targetSrc, state)
    if def.xp then P.addXp(src, Config.Progression.treatment, 'treatment:'..treatmentKey) end
end)

RegisterNetEvent('fiveems:server:setOxygen', function(targetSrc, device, flow)
    local src = source
    targetSrc = tonumber(targetSrc)
    if not targetSrc or not Server.hasPermission(src, 'patient.treat') then return end
    local cfg = Config.Oxygen.devices[device]
    if not cfg then return end
    flow = clamp(flow, cfg.minFlow, cfg.maxFlow)
    local state = M.getState(targetSrc)
    if not state then return end
    state.oxygenDevice = device
    state.oxygenFlow = flow
    state.oxygenStartedAt = os.time()
    saveState(state)
    TriggerClientEvent('fiveems:client:medicalState', targetSrc, state)
    TriggerClientEvent('fiveems:client:targetStateUpdated', src, targetSrc, state)
end)

RegisterNetEvent('fiveems:server:stopOxygen', function(targetSrc)
    local src = source
    targetSrc = tonumber(targetSrc)
    if not targetSrc or not Server.hasPermission(src, 'patient.treat') then return end
    local state = M.getState(targetSrc)
    if not state then return end
    state.oxygenDevice = nil
    state.oxygenFlow = 0
    state.oxygenStartedAt = nil
    saveState(state)
    TriggerClientEvent('fiveems:client:medicalState', targetSrc, state)
    TriggerClientEvent('fiveems:client:targetStateUpdated', src, targetSrc, state)
end)

RegisterNetEvent('fiveems:server:cprCycle', function(targetSrc, quality)
    local src = source
    targetSrc = tonumber(targetSrc)
    if not targetSrc or not Server.hasPermission(src, 'patient.treat') then return end
    local state = M.getState(targetSrc)
    if not state or not state.cardiacArrest then return end
    state.cprQuality = clamp(quality, 0, 1)
    state.vitals.etco2 = math.floor(8 + 18 * state.cprQuality)
    saveState(state)
end)

RegisterNetEvent('fiveems:server:defibAnalyze', function(targetSrc)
    local src = source
    targetSrc = tonumber(targetSrc)
    if not targetSrc or not Server.hasPermission(src, 'defib.use') then return end
    local state = M.getState(targetSrc)
    if not state then return end
    TriggerClientEvent('fiveems:client:defibAnalysis', src, targetSrc, state.vitals.rhythm, Config.Defibrillator.shockableRhythms[state.vitals.rhythm] == true)
end)

RegisterNetEvent('fiveems:server:defibShock', function(targetSrc, energy)
    local src = source
    targetSrc = tonumber(targetSrc)
    energy = tonumber(energy) or Config.Defibrillator.defaultEnergy
    if not targetSrc or not Server.hasPermission(src, 'defib.use') then return end
    local state = M.getState(targetSrc)
    if not state or not state.cardiacArrest then return end
    local shockable = Config.Defibrillator.shockableRhythms[state.vitals.rhythm] == true
    if shockable then
        local chance = 0.22 + (state.cprQuality or 0) * 0.38 + math.min(energy, 360) / 1800
        chance = math.min(chance, 0.86)
        if math.random() < chance then
            state.cardiacArrest = false
            state.vitals.rhythm = FiveEMS.Rhythms.SINUS
            state.vitals.hr = math.random(62, 96)
            state.vitals.sys = math.max(78, state.vitals.sys or 90)
            if F and F.isDowned and F.isDowned(targetSrc) then F.externalRevive(targetSrc) end
            if F and F.claimPatient then F.claimPatient(src, targetSrc, false) end
            P.addXp(src, Config.Progression.successfulDefib, 'successfulDefib')
        else
            state.vitals.rhythm = math.random() < 0.18 and FiveEMS.Rhythms.ASYSTOLE or state.vitals.rhythm
        end
    end
    saveState(state)
    TriggerClientEvent('fiveems:client:medicalState', targetSrc, state)
    TriggerClientEvent('fiveems:client:targetStateUpdated', src, targetSrc, state)
end)

RegisterNetEvent('fiveems:server:requestPatientState', function(targetSrc)
    local src = source
    targetSrc = tonumber(targetSrc)
    if not targetSrc or not Server.hasPermission(src, 'patient.assess') then return end
    local state = M.getState(targetSrc)
    if F and F.isDowned and F.isDowned(targetSrc) then F.claimPatient(src, targetSrc, true) end
    if state then TriggerClientEvent('fiveems:client:targetStateUpdated', src, targetSrc, state) end
end)

RegisterNetEvent('fiveems:server:submitAssessment', function(targetSrc, form)
    local src = source
    targetSrc = tonumber(targetSrc)
    if not targetSrc or not Server.hasPermission(src, 'reports.create') then return end
    local patientId = Server.getPrimaryIdentifier(targetSrc)
    local providerId = Server.getPrimaryIdentifier(src)
    form = type(form) == 'table' and form or {}
    if F and F.getPlayerIdentity then
        form.framework = form.framework or {}
        form.framework.patient = F.getPlayerIdentity(targetSrc)
        form.framework.provider = F.getPlayerIdentity(src)
    end
    DB.insert([[
        INSERT INTO fiveems_reports (patient_identifier, provider_identifier, department_id, report_type, payload)
        VALUES (?, ?, ?, 'patient_care', ?)
    ]], {patientId, providerId, (Server.getMember(src) or {}).department_id, DB.jsonEncode(form)})
    if F and F.claimPatient then F.claimPatient(src, targetSrc, false) end
    P.addXp(src, Config.Progression.reportSubmitted, 'reportSubmitted')
    Server.notify(src, _L('report_submitted'))
end)

RegisterNetEvent('fiveems:server:frameworkInjuriesSnapshot', function(injuries, bleeding)
    local src = source
    local state = M.getState(src)
    if not state then return end
    state.frameworkPhysical = {
        injuries = type(injuries) == 'table' and injuries or {},
        bleeding = bleeding == true,
        source = 'fivepd_sp_injuries',
        updatedAt = os.time(),
    }
    saveState(state)
end)

RegisterNetEvent('fiveems:server:releasePatientClaim', function(targetSrc)
    local src = source
    targetSrc = tonumber(targetSrc)
    if targetSrc and F and F.claimPatient then F.claimPatient(src, targetSrc, false) end
end)

RegisterNetEvent('fiveems:server:frameworkTreatmentComplete', function()
    local src = source
    local identifier = Server.getPrimaryIdentifier(src)
    if not identifier then return end
    active[identifier] = defaultState(identifier)
    playerByIdentifier[identifier] = src
    if F and F.getPlayerIdentity then active[identifier].identity = F.getPlayerIdentity(src) end
    saveState(active[identifier])
    TriggerClientEvent('fiveems:client:medicalState', src, active[identifier])
end)

RegisterNetEvent('fiveems:server:frameworkDeathStateChanged', function(deathState)
    local src = source
    local state = M.getState(src)
    if not state then return end
    state.frameworkDeathState = tostring(deathState or 'alive')
    saveState(state)
end)

function M.resetState(targetSrc)
    targetSrc = tonumber(targetSrc)
    if not targetSrc or not GetPlayerName(targetSrc) then return false end
    local identifier = Server.getPrimaryIdentifier(targetSrc)
    if not identifier then return false end
    active[identifier] = defaultState(identifier)
    playerByIdentifier[identifier] = targetSrc
    saveState(active[identifier])
    TriggerClientEvent('fiveems:client:medicalState', targetSrc, active[identifier])
    return true
end

RegisterNetEvent('fiveems:server:resetPatient', function(targetSrc)
    local src = source
    if not Server.isAdmin(src) then return end
    M.resetState(tonumber(targetSrc) or src)
end)

local function updatePhysiology(state)
    local dt = Config.Physiology.tickMs / 1000.0
    local bleed = math.max(0, tonumber(state.bleedingRate) or 0)
    state.bloodMl = clamp((tonumber(state.bloodMl) or Config.Physiology.normalBloodMl) - bleed * dt, 0, Config.Physiology.normalBloodMl)
    state.pain = clamp((tonumber(state.pain) or 0) - Config.Physiology.painDecayPerTick, 0, 100)

    local bloodRatio = state.bloodMl / Config.Physiology.normalBloodMl
    local painRatio = state.pain / 100.0
    local ventilation = clamp(state.ventilation or 1, 0, 1)
    local airway = clamp(state.airway or 1, 0, 1)
    local oxygenBoost = 0

    if state.oxygenDevice then
        local cfg = Config.Oxygen.devices[state.oxygenDevice]
        if cfg then
            local flowRatio = clamp((state.oxygenFlow or cfg.defaultFlow) / cfg.maxFlow, 0, 1)
            oxygenBoost = cfg.efficiency * flowRatio * 14
        end
    end

    local spo2 = 98 - ((1 - ventilation) * 38) - ((1 - airway) * 24) - math.max(0, 0.55 - bloodRatio) * 16 + oxygenBoost
    state.vitals.spo2 = math.floor(clamp(spo2, Config.Physiology.minSpo2, Config.Physiology.maxSpo2) + 0.5)

    local hr = 76 + painRatio * 28 + math.max(0, 0.90 - bloodRatio) * 95
    if bloodRatio < 0.36 then hr = 58 + bloodRatio * 80 end
    state.vitals.hr = math.floor(clamp(hr, 25, 190) + 0.5)

    local sys = 122 - math.max(0, 0.88 - bloodRatio) * 110 - math.max(0, 0.85 - ventilation) * 18
    state.vitals.sys = math.floor(clamp(sys, 35, 190) + 0.5)
    state.vitals.dia = math.floor(clamp(state.vitals.sys * 0.62, 20, 120) + 0.5)
    state.vitals.rr = math.floor(clamp(15 + painRatio * 8 + math.max(0, 0.95 - ventilation) * 20, 4, 44) + 0.5)

    local brain = tonumber(state.organs.brain) or 0
    local gcsPenalty = math.floor(brain / 18) + (state.vitals.spo2 < 82 and 2 or 0) + (state.vitals.sys < 65 and 2 or 0)
    state.vitals.gcs = clamp(15 - gcsPenalty, 3, 15)

    if Config.Oxygen.gameplayHyperoxiaEnabled and state.oxygenStartedAt and state.vitals.spo2 >= Config.Oxygen.hyperoxiaThreshold then
        if os.time() - state.oxygenStartedAt > Config.Oxygen.prolongedHighOxygenSeconds then
            state.pain = clamp(state.pain + 0.08, 0, 100)
        end
    end

    if not state.cardiacArrest and (state.bloodMl <= Config.Physiology.arrestBloodMl or state.vitals.spo2 <= 45 or state.vitals.sys <= 38) then
        state.cardiacArrest = true
        local r = math.random()
        if r < 0.38 then state.vitals.rhythm = FiveEMS.Rhythms.VF
        elseif r < 0.56 then state.vitals.rhythm = FiveEMS.Rhythms.PVT
        elseif r < 0.76 then state.vitals.rhythm = FiveEMS.Rhythms.PEA
        else state.vitals.rhythm = FiveEMS.Rhythms.ASYSTOLE end
        state.vitals.hr = 0
        state.vitals.sys = 0
        state.vitals.dia = 0
    elseif state.cardiacArrest then
        state.vitals.hr = 0
        state.vitals.sys = 0
        state.vitals.dia = 0
        state.vitals.rr = 0
    else
        if state.vitals.hr > 115 then state.vitals.rhythm = FiveEMS.Rhythms.TACHY
        elseif state.vitals.hr < 50 then state.vitals.rhythm = FiveEMS.Rhythms.BRADY
        else state.vitals.rhythm = FiveEMS.Rhythms.SINUS end
    end
end

CreateThread(function()
    while true do
        Wait(Config.Physiology.tickMs)
        for identifier, state in pairs(active) do
            updatePhysiology(state)
            local src = playerByIdentifier[identifier]
            if src and GetPlayerName(src) then TriggerClientEvent('fiveems:client:medicalState', src, state) end
        end
    end
end)

CreateThread(function()
    while true do
        Wait(15000)
        for _, state in pairs(active) do saveState(state) end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    local identifier = Server.getPrimaryIdentifier(src)
    if identifier then
        if active[identifier] then saveState(active[identifier]) end
        playerByIdentifier[identifier] = nil
    end
end)

exports('GetStateByIdentifier', function(identifier) return loadState(identifier) end)
