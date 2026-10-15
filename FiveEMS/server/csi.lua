FiveEMS = FiveEMS or {}
FiveEMS.CSI = FiveEMS.CSI or {}

local CSI = FiveEMS.CSI
local DB = FiveEMS.DB
local Server = FiveEMS.Server
local P = FiveEMS.Progression
local nextEvidenceId = 1
local npcEvidenceLogged = {}

local function classifyInstrument(category, weapon)
    if category == 'gunshot' then return 'firearm', 'Padrao compativel com projetil de arma de fogo'
    elseif category == 'stabbing' then return 'sharp', 'Padrao compativel com instrumento perfurocortante'
    elseif category == 'blunt' then return 'blunt', 'Padrao compativel com instrumento contundente'
    elseif category == 'explosion' then return 'explosive', 'Padrao compativel com explosao/fragmentacao'
    elseif category == 'vehicle' then return 'vehicle', 'Padrao compativel com trauma contuso de alta energia'
    end
    return 'unknown', 'Padrao inconclusivo'
end

function CSI.createEvidence(payload)
    payload = payload or {}
    local id = nextEvidenceId
    nextEvidenceId = nextEvidenceId + 1
    local family, inference = classifyInstrument(payload.category, payload.weapon)
    local evidence = {
        id = id,
        type = payload.type or 'trace',
        x = tonumber(payload.x), y = tonumber(payload.y), z = tonumber(payload.z),
        category = payload.category or 'unknown',
        weapon = tonumber(payload.weapon) or 0,
        sourceIdentifier = payload.sourceIdentifier,
        victimIdentifier = payload.victimIdentifier,
        region = payload.region,
        bone = payload.bone,
        instrumentFamily = family,
        inference = inference,
        createdAt = os.time(),
        state = 'scene',
        chain = {},
        metadata = payload.metadata or {},
    }
    FiveEMS.Cache.evidence[id] = evidence
    DB.insert([[
        INSERT INTO fiveems_evidence (external_id, evidence_type, x, y, z, state, source_identifier, victim_identifier, payload)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {tostring(id), evidence.type, evidence.x, evidence.y, evidence.z, evidence.state, evidence.sourceIdentifier, evidence.victimIdentifier, DB.jsonEncode(evidence)})
    TriggerClientEvent('fiveems:client:csiEvidenceCreated', -1, evidence)
    return evidence
end

RegisterNetEvent('fiveems:server:csiDamageEvidence', function(payload)
    local src = source
    if not Config.CSI.createEvidenceFromPlayerDamage then return end
    payload = payload or {}
    local victimId = Server.getPrimaryIdentifier(src)
    local coords = payload.coords or {}
    CSI.createEvidence({
        type = payload.category == 'gunshot' and 'wound_trace' or 'injury_trace',
        x=coords.x, y=coords.y, z=coords.z,
        category=payload.category, weapon=payload.weapon, victimIdentifier=victimId,
        region=payload.region, bone=payload.bone,
        metadata={damage=payload.damage, attackerNetId=payload.attackerNetId}
    })
end)

RegisterNetEvent('fiveems:server:csiNpcEvidence', function(payload)
    local src = source
    if not Config.CSI.createEvidenceFromNpcDamage then return end
    payload = payload or {}

    local metadata = type(payload.metadata) == 'table' and payload.metadata or {}
    local netId = tonumber(metadata.networkId or 0) or 0
    local entity = netId > 0 and NetworkGetEntityFromNetworkId(netId) or 0

    -- Deduplicacao server-authoritative: evita dois clients ou o mesmo client
    -- criarem evidencia repetida antes da StateBag replicar.
    if netId > 0 then
        if npcEvidenceLogged[netId] then return end

        if entity ~= 0 and DoesEntityExist(entity) and GetEntityType(entity) == 1 then
            local state = Entity(entity).state
            if state.fiveemsCsiLogged == true then return end

            -- Validacao simples de proximidade para nao aceitar netIds arbitrarios.
            local playerPed = GetPlayerPed(src)
            if playerPed ~= 0 then
                local distance = #(GetEntityCoords(playerPed) - GetEntityCoords(entity))
                if distance > 60.0 then return end
            end

            npcEvidenceLogged[netId] = os.time()
            state:set('fiveemsCsiLogged', true, true)
        else
            -- Se a entidade ja saiu do scope, ainda evita flood pelo netId recebido.
            npcEvidenceLogged[netId] = os.time()
        end
    end

    CSI.createEvidence(payload)
end)

RegisterNetEvent('fiveems:server:csiCollect', function(evidenceId, notes)
    local src = source
    if not Server.hasPermission(src, 'csi.collect') then return Server.notify(src, _L('no_permission')) end
    local evidence = FiveEMS.Cache.evidence[tonumber(evidenceId)]
    if not evidence or evidence.state ~= 'scene' then return end
    evidence.state = 'bagged'
    evidence.bagId = ('FEMS-%06d'):format(evidence.id)
    table.insert(evidence.chain, {action='collected', by=Server.getPrimaryIdentifier(src), at=os.time(), notes=notes})
    DB.update('UPDATE fiveems_evidence SET state=?, collector_identifier=?, payload=? WHERE external_id=?', {
        evidence.state, Server.getPrimaryIdentifier(src), DB.jsonEncode(evidence), tostring(evidence.id)
    })
    P.addXp(src, Config.Progression.csiEvidenceBagged, 'csiEvidenceBagged')
    TriggerClientEvent('fiveems:client:csiEvidenceUpdated', -1, evidence)
end)

RegisterNetEvent('fiveems:server:csiAnalyze', function(evidenceId)
    local src = source
    if not Server.hasPermission(src, 'csi.lab') then return Server.notify(src, _L('no_permission')) end
    local evidence = FiveEMS.Cache.evidence[tonumber(evidenceId)]
    if not evidence or evidence.state ~= 'bagged' then return end
    evidence.state = 'analyzed'
    evidence.analysis = {
        instrumentFamily = evidence.instrumentFamily,
        conclusion = evidence.inference,
        confidence = evidence.category == 'unknown' and 0.35 or 0.82,
        weaponHash = evidence.weapon,
        region = evidence.region,
        generatedAt = os.time(),
    }
    table.insert(evidence.chain, {action='analyzed', by=Server.getPrimaryIdentifier(src), at=os.time()})
    DB.update('UPDATE fiveems_evidence SET state=?, payload=? WHERE external_id=?', {'analyzed', DB.jsonEncode(evidence), tostring(evidence.id)})
    TriggerClientEvent('fiveems:client:csiLabResult', src, evidence)
end)

RegisterNetEvent('fiveems:server:csiCreateCase', function(payload)
    local src = source
    if not Server.hasPermission(src, 'csi.scene') then return Server.notify(src, _L('no_permission')) end
    payload = payload or {}
    local member = Server.getMember(src)
    local id = DB.insert('INSERT INTO fiveems_csi_cases (department_id, title, status, lead_identifier, payload) VALUES (?, ?, ?, ?, ?)', {
        member and member.department_id or nil, payload.title or 'Caso pericial', 'open', Server.getPrimaryIdentifier(src), DB.jsonEncode(payload)
    })
    TriggerClientEvent('fiveems:client:csiCaseCreated', src, id)
end)

RegisterNetEvent('fiveems:server:csiCloseCase', function(caseId, report)
    local src = source
    if not Server.hasPermission(src, 'csi.scene') then return end
    DB.update('UPDATE fiveems_csi_cases SET status=?, final_report=?, closed_at=CURRENT_TIMESTAMP WHERE id=?', {'closed', DB.jsonEncode(report or {}), tonumber(caseId)})
    P.addXp(src, Config.Progression.csiCaseClosed, 'csiCaseClosed')
end)

CreateThread(function()
    Wait(2500)
    local rows = DB.query("SELECT payload FROM fiveems_evidence WHERE state IN ('scene','bagged','analyzed') ORDER BY id DESC LIMIT 1000") or {}
    for _, row in ipairs(rows) do
        local e = DB.jsonDecode(row.payload, nil)
        if e and e.id then
            FiveEMS.Cache.evidence[e.id] = e
            if e.id >= nextEvidenceId then nextEvidenceId = e.id + 1 end
        end
    end
end)

exports('CreateEvidence', function(payload) return CSI.createEvidence(payload) end)


CreateThread(function()
    while true do
        Wait(60000)
        local now = os.time()
        for netId, at in pairs(npcEvidenceLogged) do
            if now - (at or 0) > 1800 then
                npcEvidenceLogged[netId] = nil
            end
        end
    end
end)
