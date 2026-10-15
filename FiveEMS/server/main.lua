FiveEMS = FiveEMS or {}
FiveEMS.Server = FiveEMS.Server or {}
FiveEMS.Cache = FiveEMS.Cache or {
    departments = {},
    members = {},
    medical = {},
    calls = {},
    evidence = {},
}

local Server = FiveEMS.Server
local RESOURCE_NAME = GetCurrentResourceName()
Server.resourceVersion = GetResourceMetadata(RESOURCE_NAME, 'version', 0) or 'dev'

function Server.getResourceVersion()
    return tostring(Server.resourceVersion or 'dev')
end


local F = FiveEMS.Framework

function Server.getLegacyIdentifier(src)
    local ids = GetPlayerIdentifiers(src)
    for _, prefix in ipairs({'license:', 'license2:', 'fivem:', 'discord:'}) do
        for _, id in ipairs(ids) do
            if id:sub(1, #prefix) == prefix then return id end
        end
    end
    return ids[1]
end

function Server.getPrimaryIdentifier(src)
    if F and F.playerKey then
        local key = F.playerKey(src)
        if key then return key end
        if type(Config.Framework) == 'table' and Config.Framework.mode == 'fivepd_sp' and Config.Framework.strict == true then
            return nil
        end
    end
    return Server.getLegacyIdentifier(src)
end

function Server.isAdmin(src)
    if src == 0 then return true end
    if F and F.isAdmin and F.isAdmin(src) then return true end
    if IsPlayerAceAllowed(src, Config.AdminAce) then return true end
    local id = Server.getLegacyIdentifier(src)
    for _, allowed in ipairs(Config.AdminIdentifiers or {}) do if allowed == id then return true end end
    return false
end

function Server.getMember(src)
    local identifier = Server.getPrimaryIdentifier(src)
    if not identifier then return nil end
    local cached = FiveEMS.Cache.members[identifier]
    if cached then return cached end

    local row = FiveEMS.DB.single([[
        SELECT m.*, r.name AS rank_name, r.permissions, d.name AS department_name, d.type AS department_type
        FROM fiveems_members m
        LEFT JOIN fiveems_ranks r ON r.id = m.rank_id
        LEFT JOIN fiveems_departments d ON d.id = m.department_id
        WHERE m.identifier = ? LIMIT 1
    ]], {identifier})

    -- Migra automaticamente um vinculo antigo por license para o character_id da base.
    if not row and identifier:sub(1,5) == 'char:' then
        local legacy = Server.getLegacyIdentifier(src)
        if legacy and legacy ~= identifier then
            local old = FiveEMS.DB.single('SELECT * FROM fiveems_members WHERE identifier=? LIMIT 1', {legacy})
            if old then
                FiveEMS.DB.update('UPDATE fiveems_members SET identifier=? WHERE identifier=?', {identifier, legacy})
                row = FiveEMS.DB.single([[
                    SELECT m.*, r.name AS rank_name, r.permissions, d.name AS department_name, d.type AS department_type
                    FROM fiveems_members m
                    LEFT JOIN fiveems_ranks r ON r.id = m.rank_id
                    LEFT JOIN fiveems_departments d ON d.id = m.department_id
                    WHERE m.identifier = ? LIMIT 1
                ]], {identifier})
            end
        end
    end

    if row then
        row.permissions = FiveEMS.DB.jsonDecode(row.permissions, {})
        row.on_duty = row.on_duty == 1
        if F and F.getPlayerIdentity then row.identity = F.getPlayerIdentity(src) end
        FiveEMS.Cache.members[identifier] = row
    end
    return row
end

function Server.clearMemberCacheByIdentifier(identifier)
    if identifier then FiveEMS.Cache.members[identifier] = nil end
end

function Server.hasPermission(src, permission)
    if Server.isAdmin(src) then return true end
    local member = Server.getMember(src)
    if not member then return false end
    for _, p in ipairs(member.permissions or {}) do
        if p == '*' or p == permission then return true end
    end
    return false
end

function Server.canUseOperational(src, permission)
    if Server.isAdmin(src) then return true end

    local member = Server.getMember(src)
    if not member then return false end

    if not Config.CommandPolicy or Config.CommandPolicy.requireDutyForOperational ~= false then
        if member.on_duty ~= true then return false end
    end

    if permission and permission ~= '' then
        for _, p in ipairs(member.permissions or {}) do
            if p == '*' or p == permission then return true end
        end
        return false
    end

    return true
end

function Server.notify(src, message)
    TriggerClientEvent('fiveems:client:notify', src, message)
end

function Server.audit(src, action, entityType, entityId, payload)
    local identifier = src == 0 and 'console' or Server.getPrimaryIdentifier(src)
    FiveEMS.DB.insert([[
        INSERT INTO fiveems_audit_log (actor_identifier, action, entity_type, entity_id, payload)
        VALUES (?, ?, ?, ?, ?)
    ]], {identifier, action, entityType, tostring(entityId or ''), FiveEMS.DB.jsonEncode(payload or {})})
end

AddEventHandler('playerDropped', function()
    local src = source
    local id = Server.getPrimaryIdentifier(src)
    if id then
        FiveEMS.Cache.members[id] = nil
        FiveEMS.Cache.medical[id] = nil
        if FiveEMS.DB and FiveEMS.DB._ready then
            pcall(function() FiveEMS.DB.update('UPDATE fiveems_members SET on_duty=0 WHERE identifier=?', {id}) end)
        end
    end
    if F and F._sourceKeys then F._sourceKeys[src] = nil end
end)

CreateThread(function()
    local ok, err = FiveEMS.DB.awaitReady((Config.Database and Config.Database.startupTimeoutMs) or 30000)
    if not ok then
        print('^1[FiveEMS]^7 Banco indisponivel: '..tostring(err))
        return
    end
    local health = FiveEMS.DB.getHealth()
    print(('^2[FiveEMS]^7 FiveEMS v%s iniciado. Banco pronto (%d tabelas FiveEMS, DB schema %s).')
        :format(Server.getResourceVersion(), health.tableCount or 0, health.schemaVersion or '?'))

    -- Em restart apenas do FiveEMS os jogadores continuam conectados. Reenvia
    -- departamentos/pontos persistidos sem depender de abrir o Creator.
    Wait(500)
    if FiveEMS.Departments and FiveEMS.Departments.broadcastWorldDepartments then
        FiveEMS.Departments.broadcastWorldDepartments(-1)
    end
end)

exports('GetMember', function(src) return Server.getMember(src) end)
exports('HasPermission', function(src, permission) return Server.hasPermission(src, permission) end)
exports('GetMedicalState', function(src)
    if FiveEMS.Medical and FiveEMS.Medical.getState then return FiveEMS.Medical.getState(src) end
    return nil
end)
