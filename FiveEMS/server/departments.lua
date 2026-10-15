FiveEMS = FiveEMS or {}
FiveEMS.Departments = FiveEMS.Departments or {}

local D = FiveEMS.Departments
local Server = FiveEMS.Server
local DB = FiveEMS.DB
local F = FiveEMS.Framework

local function decodeDepartment(row)
    if not row then return nil end
    row.settings = DB.jsonDecode(row.settings, {})
    return row
end


local function catalogGroupsForDepartment(departmentType)
    if departmentType == FiveEMS.DepartmentTypes.CSI then
        return {FiveEMS.Catalog.csi or {}}
    end
    return {FiveEMS.Catalog.equipment or {}, FiveEMS.Catalog.medications or {}}
end


local ALL_HOSPITAL_PERMISSIONS = {
    'department.manage','staff.manage','ranks.manage','garage.use','garage.manage','supplies.use','supplies.manage',
    'patient.assess','patient.treat','patient.advanced','reports.create','reports.view','stock.view','stock.manage',
    'monitor.use','defib.use'
}

local function hospitalRankTemplates()
    return {
        {name='Diretor Geral / Superintendente', grade=100, permissions=ALL_HOSPITAL_PERMISSIONS},
        {name='Diretor Medico', grade=95, permissions={'department.manage','staff.manage','ranks.manage','garage.use','supplies.use','supplies.manage','patient.assess','patient.treat','patient.advanced','reports.create','reports.view','stock.view','stock.manage','monitor.use','defib.use'}},
        {name='Diretor de Enfermagem', grade=90, permissions={'department.manage','staff.manage','garage.use','supplies.use','supplies.manage','patient.assess','patient.treat','patient.advanced','reports.create','reports.view','stock.view','stock.manage','monitor.use','defib.use'}},
        {name='Coordenador Medico', grade=80, permissions={'staff.manage','garage.use','supplies.use','patient.assess','patient.treat','patient.advanced','reports.create','reports.view','stock.view','monitor.use','defib.use'}},
        {name='Coordenador de Enfermagem', grade=75, permissions={'staff.manage','garage.use','supplies.use','patient.assess','patient.treat','patient.advanced','reports.create','reports.view','stock.view','monitor.use','defib.use'}},
        {name='Medico', grade=70, permissions={'garage.use','supplies.use','patient.assess','patient.treat','patient.advanced','reports.create','reports.view','stock.view','monitor.use','defib.use'}},
        {name='Medico Regulador', grade=68, permissions={'garage.use','supplies.use','patient.assess','patient.treat','patient.advanced','reports.create','reports.view','stock.view','monitor.use','defib.use'}},
        {name='Medico Intervencionista', grade=66, permissions={'garage.use','supplies.use','patient.assess','patient.treat','patient.advanced','reports.create','reports.view','stock.view','monitor.use','defib.use'}},
        {name='Enfermeiro', grade=60, permissions={'garage.use','supplies.use','patient.assess','patient.treat','patient.advanced','reports.create','reports.view','stock.view','monitor.use','defib.use'}},
        {name='Tecnico de Enfermagem', grade=50, permissions={'garage.use','supplies.use','patient.assess','patient.treat','reports.create','stock.view','monitor.use','defib.use'}},
        {name='Auxiliar de Enfermagem', grade=45, permissions={'garage.use','supplies.use','patient.assess','patient.treat','reports.create','stock.view','monitor.use'}},
        {name='Condutor Socorrista', grade=40, permissions={'garage.use','supplies.use','patient.assess','patient.treat','reports.create','stock.view','monitor.use'}},
        {name='Socorrista', grade=30, permissions={'garage.use','supplies.use','patient.assess','patient.treat','reports.create','stock.view','monitor.use'}},
    }
end

function D.ensureHospitalRanks(departmentId)
    departmentId = tonumber(departmentId)
    if not departmentId then return end
    local dtype = DB.scalar('SELECT type FROM fiveems_departments WHERE id=?', {departmentId})
    if dtype ~= FiveEMS.DepartmentTypes.HOSPITAL then return end

    local current = DB.query('SELECT id, name FROM fiveems_ranks WHERE department_id=?', {departmentId}) or {}
    local names = {}
    for _, row in ipairs(current) do names[string.lower(row.name or '')] = row end

    local legacy = names['diretor']
    if legacy and not names['diretor geral / superintendente'] then
        DB.update('UPDATE fiveems_ranks SET name=?, grade=?, permissions=? WHERE id=?', {
            'Diretor Geral / Superintendente', 100, DB.jsonEncode(ALL_HOSPITAL_PERMISSIONS), legacy.id
        })
        names['diretor geral / superintendente'] = legacy
    end

    for _, rank in ipairs(hospitalRankTemplates()) do
        if not names[string.lower(rank.name)] then
            DB.insert('INSERT INTO fiveems_ranks (department_id, name, grade, permissions) VALUES (?, ?, ?, ?)', {
                departmentId, rank.name, rank.grade, DB.jsonEncode(rank.permissions)
            })
        end
    end
end

local function generateDepartmentCode(name)
    local words = {}
    for w in tostring(name or 'Departamento'):gmatch('[%w]+') do
        words[#words+1] = w
    end
    local code = ''
    for i=1,math.min(#words,4) do code = code .. words[i]:sub(1,1):upper() end
    if code == '' then code = 'EMS' end
    local candidate, suffix = code, 1
    while DB.scalar('SELECT COUNT(*) FROM fiveems_departments WHERE code=?', {candidate}) and tonumber(DB.scalar('SELECT COUNT(*) FROM fiveems_departments WHERE code=?', {candidate})) > 0 do
        suffix = suffix + 1
        candidate = code .. tostring(suffix)
    end
    return candidate
end

function D.seedSupplies(departmentId, departmentType)
    departmentId = tonumber(departmentId)
    if not departmentId then return 0 end

    if not departmentType then
        departmentType = DB.scalar('SELECT type FROM fiveems_departments WHERE id=?', {departmentId})
    end

    local count = 0
    for _, group in ipairs(catalogGroupsForDepartment(departmentType)) do
        for _, item in ipairs(group) do
            DB.query([[
                INSERT INTO fiveems_supplies (department_id, item_name, label, category, quantity, min_level, advanced)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON DUPLICATE KEY UPDATE label=VALUES(label), category=VALUES(category), advanced=VALUES(advanced)
            ]], {departmentId, item.name, item.label, item.category, tonumber(item.stock) or 0, 1, item.advanced and 1 or 0})
            count = count + 1
        end
    end
    return count
end

function D.getAll()
    local rows = DB.query('SELECT * FROM fiveems_departments ORDER BY name ASC') or {}
    for _, row in ipairs(rows) do decodeDepartment(row) end
    return rows
end

local function normalizeStretcherPatientTransform(value)
    value = type(value) == 'table' and value or {}

    local defaults = (((Config or {}).Stretcher or {}).patientPose or {}).defaultTransform
        or {x=0.0,y=0.08,z=1.12,rx=0.0,ry=0.0,rz=180.0}

    if next(value) == nil then
        return {
            x=defaults.x, y=defaults.y, z=defaults.z,
            rx=defaults.rx, ry=defaults.ry, rz=defaults.rz
        }
    end

    -- Migra os baselines automaticos antigos do FiveEMS sem tocar em calibracoes manuais.
    -- Qualquer posicao que o usuario realmente calibrou no Gizmo e preservada.
    local x = tonumber(value.x) or 0.0
    local y = tonumber(value.y) or 0.0
    local z = tonumber(value.z) or 0.0
    local rx = tonumber(value.rx) or 0.0
    local ry = tonumber(value.ry) or 0.0
    local rz = tonumber(value.rz or value.heading) or 0.0

    local legacy075 =
        math.abs(x) < 0.02 and math.abs(y) < 0.02
        and math.abs(z - 0.75) < 0.03
        and math.abs(rx) < 0.5 and math.abs(ry) < 0.5
        and math.abs(math.abs(rz) - 180.0) < 1.0

    -- V0.3.1-V0.3.2 usavam Y=0.10 como baseline automatico.
    -- Ele nao representa uma calibracao manual do usuario e deve migrar para o
    -- SUPINE_NEUTRAL final do FiveFD, recentralizado em Y=0.00.
    local legacy031 =
        math.abs(x) < 0.02 and math.abs(y - 0.10) < 0.02
        and math.abs(z - 1.12) < 0.03
        and math.abs(rx) < 0.5 and math.abs(ry) < 0.5
        and math.abs(math.abs(rz) - 180.0) < 1.0

    -- V0.4.0 pre-release usou Y=0.00. Se existir esse baseline automatico,
    -- migra para a geometria final Y=0.08 sem tocar em calibracoes manuais.
    local legacy040 =
        math.abs(x) < 0.02 and math.abs(y) < 0.02
        and math.abs(z - 1.12) < 0.03
        and math.abs(rx) < 0.5 and math.abs(ry) < 0.5
        and math.abs(math.abs(rz) - 180.0) < 1.0

    if legacy075 or legacy031 or legacy040 then
        return {
            x=defaults.x, y=defaults.y, z=defaults.z,
            rx=defaults.rx, ry=defaults.ry, rz=defaults.rz
        }
    end

    return value
end

function D.getFull(id)
    id = tonumber(id)
    if not id then return nil end
    local department = decodeDepartment(DB.single('SELECT * FROM fiveems_departments WHERE id = ?', {id}))
    if not department then return nil end

    if department.type == FiveEMS.DepartmentTypes.HOSPITAL then D.ensureHospitalRanks(id) end
    department.ranks = DB.query('SELECT * FROM fiveems_ranks WHERE department_id = ? ORDER BY grade DESC', {id}) or {}
    for _, r in ipairs(department.ranks) do r.permissions = DB.jsonDecode(r.permissions, {}) end
    department.points = DB.query('SELECT * FROM fiveems_points WHERE department_id = ? ORDER BY type, id', {id}) or {}
    for _, p in ipairs(department.points) do p.data = DB.jsonDecode(p.data, {}) end
    department.vehicles = DB.query('SELECT * FROM fiveems_vehicles WHERE department_id = ? ORDER BY label ASC', {id}) or {}
    department.supplies = DB.query('SELECT * FROM fiveems_supplies WHERE department_id = ? ORDER BY category, label', {id}) or {}
    department.stretcherProfiles = DB.query('SELECT * FROM fiveems_stretcher_profiles WHERE department_id = ? ORDER BY vehicle_model', {id}) or {}
    department.vehicleEquipmentProfiles = DB.query('SELECT * FROM fiveems_vehicle_equipment_profiles WHERE department_id = ? ORDER BY vehicle_model', {id}) or {}
    for _, v in ipairs(department.vehicleEquipmentProfiles) do v.transform = DB.jsonDecode(v.transform, {}) end
    for _, s in ipairs(department.stretcherProfiles) do
        s.inside_transform = DB.jsonDecode(s.inside_transform, {})
        s.outside_transform = DB.jsonDecode(s.outside_transform, {})
        s.patient_transform = normalizeStretcherPatientTransform(DB.jsonDecode(s.patient_transform, {}))
    end
    return department
end


function D.getWorldDepartments()
    local rows = D.getAll()
    local result = {}
    for _, department in ipairs(rows) do
        local id = tonumber(department.id)
        if id then
            department.points = DB.query('SELECT * FROM fiveems_points WHERE department_id = ? ORDER BY type, id', {id}) or {}
            for _, point in ipairs(department.points) do
                point.data = DB.jsonDecode(point.data, {})
            end

            -- V0.4.10: os hotspots de equipamentos precisam existir no cliente
            -- independentemente do departamento atualmente aberto na NUI/Creator.
            -- Isso evita o ox_target desaparecer quando C.department esta nil,
            -- desatualizado ou apontando para outro departamento.
            department.vehicleEquipmentProfiles = DB.query(
                'SELECT * FROM fiveems_vehicle_equipment_profiles WHERE department_id = ? AND enabled = 1 ORDER BY vehicle_model',
                {id}
            ) or {}
            for _, profile in ipairs(department.vehicleEquipmentProfiles) do
                profile.transform = DB.jsonDecode(profile.transform, {})
            end

            -- Drafts totalmente vazios nao precisam ser enviados ao mundo. Um perfil
            -- de equipamento tambem torna o departamento relevante para o cache world.
            if (department.blip_x and department.blip_y and department.blip_z)
                or #department.points > 0
                or #department.vehicleEquipmentProfiles > 0 then
                result[#result + 1] = department
            end
        end
    end
    return result
end

function D.broadcastWorldDepartments(target)
    TriggerClientEvent('fiveems:client:worldDepartments', target or -1, D.getWorldDepartments())
end

RegisterNetEvent('fiveems:server:requestWorldDepartments', function()
    local src = source
    local ok = DB.awaitReady((Config.Database and Config.Database.startupTimeoutMs) or 30000)
    if not ok then return end
    D.broadcastWorldDepartments(src)
end)

RegisterNetEvent('fiveems:server:requestBootstrap', function(context, extra)
    local src = source
    extra = type(extra) == 'table' and extra or {}

    local member = Server.getMember(src)
    local departments = D.getAll()
    local selectedDepartmentId = member and tonumber(member.department_id) or nil

    -- Quando a UI nasce de um ponto fisico (principalmente a garagem),
    -- o proprio ponto e a fonte mais confiavel para saber qual departamento
    -- precisa ser carregado. Isso evita catalogo vazio apos restart/cache frio.
    local pointId = tonumber(extra.pointId)
    if pointId then
        local point = DB.single('SELECT id, department_id, type FROM fiveems_points WHERE id=? LIMIT 1', {pointId})
        if point then
            local pointDepartmentId = tonumber(point.department_id)
            local allowed = Server.isAdmin(src)
                or (member and tonumber(member.department_id) == pointDepartmentId)

            if allowed then
                selectedDepartmentId = pointDepartmentId
            end
        end
    end

    local requestedDepartmentId = tonumber(extra.departmentId)
    if context == 'creator' and requestedDepartmentId and
        (Server.isAdmin(src) or (member and tonumber(member.department_id) == requestedDepartmentId)) then
        selectedDepartmentId = requestedDepartmentId
    end

    local selected = selectedDepartmentId and D.getFull(selectedDepartmentId) or nil

    TriggerClientEvent('fiveems:client:bootstrap', src, {
        context = context,
        resourceVersion = Server.getResourceVersion and Server.getResourceVersion() or 'dev',
        locale = Config.Locale,
        isAdmin = Server.isAdmin(src),
        member = member,
        departments = departments,
        department = selected,
        catalog = FiveEMS.Catalog,
        treatments = FiveEMS.Treatments,
        identity = F and F.getPlayerIdentity and F.getPlayerIdentity(src) or nil,
        framework = F and F.status and F.status() or {mode='standalone', ready=false},
        config = {
            progression = Config.Progression,
            monitor = Config.Monitor,
            oxygen = Config.Oxygen,
            defibrillator = Config.Defibrillator,
            calls = Config.Calls,
            damageMultipliers = Config.DamageMultipliers,
            stretcher = Config.Stretcher,
            npcPersistence = Config.NpcPersistence,
            commands = Config.Commands,
        }
    })
end)

RegisterNetEvent('fiveems:server:requestGarageCatalog', function(pointId)
    local src = source
    pointId = tonumber(pointId)
    if not pointId then return end

    local member = Server.getMember(src)
    local point = DB.single(
        'SELECT id, department_id, type FROM fiveems_points WHERE id=? AND type=? LIMIT 1',
        {pointId, FiveEMS.PointTypes.GARAGE}
    )
    if not point then
        return Server.notify(src, 'Ponto de garagem nao encontrado.')
    end

    local departmentId = tonumber(point.department_id)
    local allowed = Server.isAdmin(src)
        or (member and tonumber(member.department_id) == departmentId)

    if not allowed then
        return Server.notify(src, _L('no_permission'))
    end

    local department = D.getFull(departmentId)
    if not department then
        return Server.notify(src, 'Departamento da garagem nao encontrado.')
    end

    local count = #(department.vehicles or {})
    print(('[FiveEMS][Garage] catalogo hidratado: player=%s point=%s department=%s vehicles=%s')
        :format(src, pointId, departmentId, count))

    TriggerClientEvent('fiveems:client:garageCatalog', src, department)
end)

RegisterNetEvent('fiveems:server:getDepartment', function(id)
    local src = source
    local member = Server.getMember(src)
    local allowed = Server.isAdmin(src) or (member and tonumber(member.department_id) == tonumber(id))
    if not allowed then return end
    TriggerClientEvent('fiveems:client:departmentData', src, D.getFull(id))
end)

RegisterNetEvent('fiveems:server:saveDepartment', function(payload)
    local src = source
    if not Server.isAdmin(src) then return Server.notify(src, _L('no_permission')) end
    payload = payload or {}

    local id = tonumber(payload.id)
    local existingRow = id and DB.single('SELECT * FROM fiveems_departments WHERE id=?', {id}) or nil
    local existingSettings = existingRow and DB.jsonDecode(existingRow.settings, {}) or {}
    local settings = payload.settings or existingSettings or {}
    settings.blip = settings.blip or {}
    settings.defaultStretcherModel = settings.defaultStretcherModel or Config.Stretcher.defaultModel or 'strykerpro'
    if not id then
        settings.creator_configured = false
    elseif payload.markConfigured == true then
        settings.creator_configured = true
    elseif settings.creator_configured == nil then
        settings.creator_configured = existingSettings.creator_configured == true
    end

    local name = tostring(payload.name or (existingRow and existingRow.name) or 'FiveEMS Department')
    local dtype = tostring(payload.type or (existingRow and existingRow.type) or FiveEMS.DepartmentTypes.EMS)
    local code = tostring(payload.code or (existingRow and existingRow.code) or '')
    if code == '' then code = generateDepartmentCode(name) end

    local params = {
        name,
        code,
        dtype,
        payload.blip_x ~= nil and tonumber(payload.blip_x) or (existingRow and existingRow.blip_x or nil),
        payload.blip_y ~= nil and tonumber(payload.blip_y) or (existingRow and existingRow.blip_y or nil),
        payload.blip_z ~= nil and tonumber(payload.blip_z) or (existingRow and existingRow.blip_z or nil),
        DB.jsonEncode(settings)
    }

    if id then
        DB.update([[
            UPDATE fiveems_departments
            SET name=?, code=?, type=?, blip_x=?, blip_y=?, blip_z=?, settings=?
            WHERE id=?
        ]], {params[1],params[2],params[3],params[4],params[5],params[6],params[7],id})
        Server.audit(src, 'department.update', 'department', id, payload)
    else
        id = DB.insert([[
            INSERT INTO fiveems_departments (name, code, type, blip_x, blip_y, blip_z, settings)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        ]], params)
        Server.audit(src, 'department.create', 'department', id, payload)

        if dtype == FiveEMS.DepartmentTypes.HOSPITAL then
            D.ensureHospitalRanks(id)
        else
            DB.insert('INSERT INTO fiveems_ranks (department_id, name, grade, permissions) VALUES (?, ?, ?, ?)', {
                id, 'Diretor', 100, DB.jsonEncode({'department.manage','staff.manage','ranks.manage','garage.use','garage.manage','supplies.use','supplies.manage','patient.assess','patient.treat','patient.advanced','reports.create','reports.view','stock.view','stock.manage','monitor.use','defib.use','csi.scene','csi.collect','csi.lab'})
            })
        end

        if not Config.Database or Config.Database.autoSeedCatalogOnDepartmentCreate ~= false then
            D.seedSupplies(id, dtype)
        end
    end

    TriggerClientEvent('fiveems:client:departmentSaved', src, D.getFull(id))
    D.broadcastWorldDepartments(-1)
end)

RegisterNetEvent('fiveems:server:deleteDepartment', function(departmentId)
    local src = source
    if not Server.isAdmin(src) then
        Server.notify(src, _L('no_permission'))
        TriggerClientEvent('fiveems:client:departmentDeleteFailed', src, departmentId, _L('no_permission'))
        return
    end

    departmentId = tonumber(departmentId)
    if not departmentId then
        TriggerClientEvent('fiveems:client:departmentDeleteFailed', src, departmentId, 'Departamento invalido.')
        return
    end

    local row = DB.single('SELECT name FROM fiveems_departments WHERE id=?', {departmentId})
    if not row then
        TriggerClientEvent('fiveems:client:departmentDeleteFailed', src, departmentId, 'Departamento nao encontrado.')
        return
    end

    -- V0.5.1a: nao dependemos somente dos ON DELETE CASCADE.
    -- Bases antigas podem ter sido criadas antes das constraints atuais.
    -- A transacao limpa/solta todas as referencias conhecidas e so entao
    -- remove o departamento.
    local okCall, deleted = pcall(function()
        return DB.transaction({
            {query='UPDATE fiveems_members SET department_id=NULL, rank_id=NULL WHERE department_id=?', values={departmentId}},
            {query='UPDATE fiveems_reports SET department_id=NULL WHERE department_id=?', values={departmentId}},
            {query='UPDATE fiveems_csi_cases SET department_id=NULL WHERE department_id=?', values={departmentId}},
            {query='UPDATE fiveems_encounters SET department_id=NULL WHERE department_id=?', values={departmentId}},
            {query='DELETE FROM fiveems_vehicle_equipment_profiles WHERE department_id=?', values={departmentId}},
            {query='DELETE FROM fiveems_stretcher_profiles WHERE department_id=?', values={departmentId}},
            {query='DELETE FROM fiveems_supplies WHERE department_id=?', values={departmentId}},
            {query='DELETE FROM fiveems_vehicles WHERE department_id=?', values={departmentId}},
            {query='DELETE FROM fiveems_points WHERE department_id=?', values={departmentId}},
            {query='DELETE FROM fiveems_ranks WHERE department_id=?', values={departmentId}},
            {query='DELETE FROM fiveems_departments WHERE id=?', values={departmentId}},
        })
    end)

    if not okCall or deleted ~= true then
        local reason = okCall and 'A transacao de exclusao foi recusada pelo banco.' or tostring(deleted)
        print(('^1[FiveEMS][Departments]^7 Falha excluindo departamento %s: %s'):format(departmentId, reason))
        Server.notify(src, 'Nao foi possivel excluir o departamento. Veja o console do servidor.')
        TriggerClientEvent('fiveems:client:departmentDeleteFailed', src, departmentId, 'Falha ao excluir departamento no banco.')
        return
    end

    Server.audit(src, 'department.delete', 'department', departmentId, {name=row.name})
    Server.notify(src, ('Departamento "%s" excluido.'):format(tostring(row.name or departmentId)))
    TriggerClientEvent('fiveems:client:departmentDeleted', src, departmentId)
    D.broadcastWorldDepartments(-1)
end)

RegisterNetEvent('fiveems:server:saveRank', function(departmentId, rank)
    local src = source
    if not (Server.isAdmin(src) or Server.hasPermission(src, 'ranks.manage')) then return Server.notify(src, _L('no_permission')) end
    departmentId = tonumber(departmentId)
    rank = rank or {}
    local id = tonumber(rank.id)
    local permissions = DB.jsonEncode(rank.permissions or {})
    if id then
        DB.update('UPDATE fiveems_ranks SET name=?, grade=?, permissions=? WHERE id=? AND department_id=?', {rank.name, tonumber(rank.grade) or 0, permissions, id, departmentId})
    else
        id = DB.insert('INSERT INTO fiveems_ranks (department_id, name, grade, permissions) VALUES (?, ?, ?, ?)', {departmentId, rank.name or 'Novo Cargo', tonumber(rank.grade) or 0, permissions})
    end
    Server.audit(src, 'rank.save', 'rank', id, rank)
    TriggerClientEvent('fiveems:client:departmentData', src, D.getFull(departmentId))
end)

-- Mutate the persisted slot list, never a possibly stale client copy of the point.
lib.callback.register('fiveems:server:deleteGarageSpawn', function(src, departmentId, pointId, index, expected)
    departmentId, pointId, index = tonumber(departmentId), tonumber(pointId), tonumber(index)
    local member = Server.getMember(src)
    if not Server.isAdmin(src) and (not member or tonumber(member.department_id) ~= departmentId
        or not Server.hasPermission(src, 'department.manage')) then
        return {ok=false, message=_L('no_permission')}
    end
    if not departmentId or not pointId or not index or index % 1 ~= 0 then
        return {ok=false, message='Vaga invalida.'}
    end
    local point = DB.single('SELECT * FROM fiveems_points WHERE id=? AND department_id=? AND type=?',
        {pointId, departmentId, FiveEMS.PointTypes.GARAGE})
    if not point then return {ok=false, message='Garagem nao encontrada.'} end
    local data = DB.jsonDecode(point.data, {})
    local slots = data.spawns or {}
    local slot = slots[index]
    if not slot then return {ok=false, message='Vaga nao encontrada. Reabra a garagem para atualizar.'} end
    if type(expected) ~= 'table' then return {ok=false, message='Atualize a garagem antes de excluir.'} end
    for _, key in ipairs({'x','y','z'}) do
        if not tonumber(slot[key]) or not tonumber(expected[key]) or math.abs(tonumber(slot[key])-tonumber(expected[key])) > 0.001 then
            return {ok=false, message='A vaga mudou. Reabra a garagem antes de excluir.'}
        end
    end
    table.remove(slots, index)
    data.spawns = slots
    data.garage_configured = #slots > 0
    -- Compare-and-swap prevents overwriting another editor's concurrent save.
    local affected = DB.update('UPDATE fiveems_points SET data=? WHERE id=? AND department_id=? AND data=?',
        {DB.jsonEncode(data), pointId, departmentId, point.data})
    if not affected or affected == 0 then
        return {ok=false, message='A garagem mudou ou nao foi salva. Reabra e tente novamente.'}
    end
    Server.audit(src, 'garage.spawn.delete', 'point', pointId, {spawnIndex=index})
    local department = D.getFull(departmentId)
    D.broadcastWorldDepartments(-1)
    return {ok=true, department=department}
end)

RegisterNetEvent('fiveems:server:savePoint', function(departmentId, point)
    local src = source
    if not (Server.isAdmin(src) or Server.hasPermission(src, 'department.manage')) then return Server.notify(src, _L('no_permission')) end
    departmentId = tonumber(departmentId)
    point = point or {}
    local id = tonumber(point.id)
    local creating = id == nil
    if id and point.preserveGarageSpawns and point.type == FiveEMS.PointTypes.GARAGE then
        local current = DB.single('SELECT data FROM fiveems_points WHERE id=? AND department_id=? AND type=?',
            {id, departmentId, FiveEMS.PointTypes.GARAGE})
        if not current then return Server.notify(src, 'Garagem nao encontrada.') end
        local saved = DB.jsonDecode(current.data, {})
        point.data = point.data or {}
        point.data.spawns = saved.spawns or {}
        point.data.garage_configured = #point.data.spawns > 0
    end
    local data = DB.jsonEncode(point.data or {})
    if id then
        DB.update([[
            UPDATE fiveems_points SET type=?, label=?, x=?, y=?, z=?, heading=?, data=?
            WHERE id=? AND department_id=?
        ]], {point.type, point.label, tonumber(point.x), tonumber(point.y), tonumber(point.z), tonumber(point.heading) or 0.0, data, id, departmentId})
    else
        id = DB.insert([[
            INSERT INTO fiveems_points (department_id, type, label, x, y, z, heading, data)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ]], {departmentId, point.type, point.label or point.type, tonumber(point.x), tonumber(point.y), tonumber(point.z), tonumber(point.heading) or 0.0, data})
    end
    Server.audit(src, 'point.save', 'point', id, point)
    local fullDepartment = D.getFull(departmentId)
    TriggerClientEvent('fiveems:client:departmentData', src, fullDepartment)

    if creating and tostring(point.type) == tostring(FiveEMS.PointTypes.GARAGE) then
        TriggerClientEvent('fiveems:client:garagePointCreated', src, fullDepartment, id)
    end

    D.broadcastWorldDepartments(-1)
end)


RegisterNetEvent('fiveems:server:createCarePoint', function(departmentId, point)
    local src = source
    if not (Server.isAdmin(src) or Server.hasPermission(src, 'department.manage')) then return Server.notify(src, _L('no_permission')) end
    departmentId = tonumber(departmentId)
    point = point or {}
    local allowed = {
        [FiveEMS.PointTypes.BED] = true,
        [FiveEMS.PointTypes.SURGERY] = true,
        [FiveEMS.PointTypes.IML] = true,
        [FiveEMS.PointTypes.OTHER] = true,
    }
    if not departmentId or not allowed[tostring(point.type or '')] then return end
    local data = DB.jsonEncode(point.data or {})
    local id = DB.insert([[
        INSERT INTO fiveems_points (department_id, type, label, x, y, z, heading, data)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        departmentId, tostring(point.type), tostring(point.label or point.type),
        tonumber(point.x), tonumber(point.y), tonumber(point.z), tonumber(point.heading) or 0.0, data
    })
    if not id then return Server.notify(src, 'Nao foi possivel cadastrar o leito/outro.') end
    Server.audit(src, 'care_point.create', 'point', id, point)
    TriggerClientEvent('fiveems:client:carePointCreated', src, D.getFull(departmentId), id)
    D.broadcastWorldDepartments(-1)
end)

RegisterNetEvent('fiveems:server:deletePoint', function(departmentId, pointId)
    local src = source
    if not (Server.isAdmin(src) or Server.hasPermission(src, 'department.manage')) then return end
    DB.update('DELETE FROM fiveems_points WHERE id=? AND department_id=?', {tonumber(pointId), tonumber(departmentId)})
    TriggerClientEvent('fiveems:client:departmentData', src, D.getFull(departmentId))
    D.broadcastWorldDepartments(-1)
end)

local function canManageFleet(src, departmentId)
    if Server.isAdmin(src) then return true end
    local member = Server.getMember(src)
    return member and tonumber(member.department_id) == tonumber(departmentId)
        and Server.hasPermission(src, 'garage.manage')
end

RegisterNetEvent('fiveems:server:deleteVehicle', function(departmentId, vehicleId)
    local src = source
    departmentId, vehicleId = tonumber(departmentId), tonumber(vehicleId)
    if not departmentId or not vehicleId or not canManageFleet(src, departmentId) then
        return Server.notify(src, _L('no_permission'))
    end
    local affected = DB.update('DELETE FROM fiveems_vehicles WHERE id=? AND department_id=?', {vehicleId, departmentId})
    if not affected or affected == 0 then return Server.notify(src, 'Viatura nao encontrada.') end
    Server.audit(src, 'vehicle.delete', 'vehicle', vehicleId, {departmentId=departmentId})
    TriggerClientEvent('fiveems:client:departmentData', src, D.getFull(departmentId))
end)

RegisterNetEvent('fiveems:server:saveVehicle', function(departmentId, vehicle)
    local src = source
    departmentId = tonumber(departmentId)
    if not departmentId or not canManageFleet(src, departmentId) then return Server.notify(src, _L('no_permission')) end
    vehicle = type(vehicle) == 'table' and vehicle or {}
    vehicle.label = tostring(vehicle.label or ''):match('^%s*(.-)%s*$')
    vehicle.model = tostring(vehicle.model or ''):match('^%s*(.-)%s*$')
    if vehicle.label == '' or vehicle.model == '' then return Server.notify(src, 'Informe nome e modelo da viatura.') end
    vehicle.min_level = math.max(1, math.floor(tonumber(vehicle.min_level) or 1))
    local id = tonumber(vehicle.id)
    if id then
        DB.update('UPDATE fiveems_vehicles SET label=?, model=?, min_level=?, settings=? WHERE id=? AND department_id=?', {
            vehicle.label, vehicle.model, tonumber(vehicle.min_level) or 1, DB.jsonEncode(vehicle.settings or {}), id, tonumber(departmentId)
        })
    else
        id = DB.insert('INSERT INTO fiveems_vehicles (department_id, label, model, min_level, settings) VALUES (?, ?, ?, ?, ?)', {
            tonumber(departmentId), vehicle.label, vehicle.model, tonumber(vehicle.min_level) or 1, DB.jsonEncode(vehicle.settings or {})
        })
    end
    Server.audit(src, 'vehicle.save', 'vehicle', id, vehicle)
    TriggerClientEvent('fiveems:client:departmentData', src, D.getFull(departmentId))
end)

RegisterNetEvent('fiveems:server:saveSupply', function(departmentId, item)
    local src = source
    if not (Server.isAdmin(src) or Server.hasPermission(src, 'supplies.manage')) then return Server.notify(src, _L('no_permission')) end
    item = item or {}
    local id = tonumber(item.id)
    if id then
        DB.update('UPDATE fiveems_supplies SET item_name=?, label=?, category=?, quantity=?, min_level=?, advanced=? WHERE id=? AND department_id=?', {
            item.item_name, item.label, item.category, tonumber(item.quantity) or 0, tonumber(item.min_level) or 1, item.advanced and 1 or 0, id, tonumber(departmentId)
        })
    else
        id = DB.insert('INSERT INTO fiveems_supplies (department_id, item_name, label, category, quantity, min_level, advanced) VALUES (?, ?, ?, ?, ?, ?, ?)', {
            tonumber(departmentId), item.item_name, item.label, item.category, tonumber(item.quantity) or 0, tonumber(item.min_level) or 1, item.advanced and 1 or 0
        })
    end
    Server.audit(src, 'supply.save', 'supply', id, item)
    TriggerClientEvent('fiveems:client:departmentData', src, D.getFull(departmentId))
end)

RegisterNetEvent('fiveems:server:seedSupplies', function(departmentId)
    local src = source
    if not (Server.isAdmin(src) or Server.hasPermission(src, 'supplies.manage')) then return end
    departmentId = tonumber(departmentId)
    if not departmentId then return end

    local count = D.seedSupplies(departmentId)
    Server.notify(src, ('Catalogo padrao atualizado: %d itens.'):format(count))
    TriggerClientEvent('fiveems:client:departmentData', src, D.getFull(departmentId))
end)

RegisterNetEvent('fiveems:server:saveStretcherProfile', function(departmentId, profile)
    local src = source
    if not (Server.isAdmin(src) or Server.hasPermission(src, 'department.manage')) then return end
    departmentId = tonumber(departmentId)
    profile = profile or {}
    DB.query([[
        INSERT INTO fiveems_stretcher_profiles
        (department_id, vehicle_model, stretcher_model, inside_transform, outside_transform, patient_transform)
        VALUES (?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE stretcher_model=VALUES(stretcher_model), inside_transform=VALUES(inside_transform),
            outside_transform=VALUES(outside_transform), patient_transform=VALUES(patient_transform)
    ]], {
        departmentId,
        tostring(profile.vehicle_model or ''),
        tostring(profile.stretcher_model or ''),
        DB.jsonEncode(profile.inside_transform or {}),
        DB.jsonEncode(profile.outside_transform or {}),
        DB.jsonEncode(profile.patient_transform or {})
    })
    TriggerClientEvent('fiveems:client:departmentData', src, D.getFull(departmentId))
end)

RegisterNetEvent('fiveems:server:saveVehicleEquipmentProfile', function(departmentId, profile)
    local src = source
    if not (Server.isAdmin(src) or Server.hasPermission(src, 'department.manage')) then return end
    departmentId = tonumber(departmentId)
    profile = type(profile) == 'table' and profile or {}
    local vehicleModel = tostring(profile.vehicle_model or '')
    if not departmentId or vehicleModel == '' then return end
    DB.query([[
        INSERT INTO fiveems_vehicle_equipment_profiles (department_id, vehicle_model, transform, enabled)
        VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE transform=VALUES(transform), enabled=VALUES(enabled)
    ]], {departmentId, vehicleModel, DB.jsonEncode(profile.transform or {}), profile.enabled == false and 0 or 1})
    TriggerClientEvent('fiveems:client:departmentData', src, D.getFull(departmentId))
    -- Atualiza tambem o cache de hotspots usado pelo ox_target de todos os clientes.
    D.broadcastWorldDepartments(-1)
end)

RegisterNetEvent('fiveems:server:setDuty', function(onDuty)
    local src = source
    local member = Server.getMember(src)
    if not member then return Server.notify(src, _L('no_department')) end
    if onDuty == true then
        local player = Player(src)
        if player and player.state and player.state['fivepd_sp:pmEmServico'] == true then
            return Server.notify(src, 'Saia do servico policial antes de entrar em servico pelo FiveEMS.')
        end
    end
    local identifier = Server.getPrimaryIdentifier(src)
    DB.update('UPDATE fiveems_members SET on_duty=? WHERE identifier=?', {onDuty and 1 or 0, identifier})
    Server.clearMemberCacheByIdentifier(identifier)
    local player = Player(src)
    if player and player.state then
        player.state:set('fiveems:onDuty', onDuty == true, true)
        player.state:set('fiveems:departmentId', tonumber(member.department_id), true)
    end
    Server.notify(src, onDuty and _L('on_duty') or _L('off_duty'))
end)

RegisterNetEvent('fiveems:server:assignMember', function(targetServerId, departmentId, rankId)
    local src = source
    if not (Server.isAdmin(src) or Server.hasPermission(src, 'staff.manage')) then return Server.notify(src, _L('no_permission')) end
    targetServerId = tonumber(targetServerId)
    if not targetServerId then return end
    local identifier = Server.getPrimaryIdentifier(targetServerId)
    if not identifier then return end
    local identity = F and F.getPlayerIdentity and F.getPlayerIdentity(targetServerId) or nil
    local name = identity and identity.nome_completo or GetPlayerName(targetServerId) or 'Unknown'
    DB.query([[
        INSERT INTO fiveems_members (identifier, display_name, department_id, rank_id, xp, level, on_duty)
        VALUES (?, ?, ?, ?, 0, 1, 0)
        ON DUPLICATE KEY UPDATE display_name=VALUES(display_name), department_id=VALUES(department_id), rank_id=VALUES(rank_id)
    ]], {identifier, name, tonumber(departmentId), tonumber(rankId)})
    Server.clearMemberCacheByIdentifier(identifier)
    Server.audit(src, 'member.assign', 'member', identifier, {target=targetServerId, departmentId=departmentId, rankId=rankId})
end)

local function addInventoryItem(src, row, count)
    count = math.max(1, math.floor(tonumber(count) or 1))
    if F and F.addInventoryItem then
        return F.addInventoryItem(src, row.item_name, count, {
            label = row.label,
            category = row.category,
            department_id = row.department_id,
            supply_id = row.id,
        })
    end
    return false, 'Adaptador fivepd_sp_inventory indisponivel.'
end

RegisterNetEvent('fiveems:server:takeSupply', function(supplyId, count)
    local src = source
    if not Server.hasPermission(src, 'supplies.use') then return Server.notify(src, _L('no_permission')) end
    local member = Server.getMember(src)
    if not member then return end
    local row = DB.single('SELECT * FROM fiveems_supplies WHERE id=? AND department_id=?', {tonumber(supplyId), tonumber(member.department_id)})
    if not row then return end
    count = math.max(1, math.floor(tonumber(count) or 1))
    local bagItem = tostring((Config.FieldEquipment and Config.FieldEquipment.medicalBag and Config.FieldEquipment.medicalBag.itemName) or 'medical_bag')
    if tostring(row.item_name or '') == bagItem then
        count = 1
        -- Evita duplicar a bolsa abstrata no inventario. Se ja existe uma reserva FiveEMS,
        -- apenas converte para o estado fisico "na mao".
        if F and F.hasExactFiveEMSItem and F.hasExactFiveEMSItem(src, bagItem, 1) then
            local FE = FiveEMS.FieldEquipment
            if FE and FE.beginCarryingBag then
                local carryOk, carryErr = FE.beginCarryingBag(src)
                if not carryOk and carryErr then Server.notify(src, carryErr) end
            else
                TriggerClientEvent('fiveems:client:useMedicalBag', src)
            end
            TriggerClientEvent('fiveems:client:departmentData', src, D.getFull(member.department_id))
            return
        end
    end
    if tonumber(row.quantity) < count then return Server.notify(src, 'Estoque insuficiente.') end
    if tonumber(member.level or 1) < tonumber(row.min_level or 1) then return Server.notify(src, 'Seu Level ainda nao libera este item.') end
    if row.advanced == 1 and not Server.hasPermission(src, 'patient.advanced') then return Server.notify(src, _L('no_permission')) end
    local ok, err = addInventoryItem(src, row, count)
    if not ok then return Server.notify(src, err or 'Falha ao entregar item.') end
    DB.update('UPDATE fiveems_supplies SET quantity=quantity-? WHERE id=? AND quantity>=?', {count, row.id, count})
    Server.audit(src, 'supply.take', 'supply', row.id, {item=row.item_name, count=count})
    if tostring(row.item_name or '') == bagItem then
        local FE = FiveEMS.FieldEquipment
        if FE and FE.beginCarryingBag then
            local carryOk, carryErr = FE.beginCarryingBag(src)
            if not carryOk and carryErr then Server.notify(src, carryErr) end
        else
            TriggerClientEvent('fiveems:client:useMedicalBag', src)
        end
    end
    TriggerClientEvent('fiveems:client:departmentData', src, D.getFull(member.department_id))
end)

RegisterNetEvent('fiveems:server:requestVehicle', function(vehicleId, garagePointId)
    local src = source
    if not Server.hasPermission(src, 'garage.use') then return Server.notify(src, _L('no_permission')) end
    local member = Server.getMember(src)
    garagePointId = tonumber(garagePointId)
    if not garagePointId then return Server.notify(src, 'Abra a garagem no ponto cadastrado para usar as vagas.') end
    local gp = DB.single('SELECT * FROM fiveems_points WHERE id=? AND type=?', {garagePointId, FiveEMS.PointTypes.GARAGE})
    if not gp then return Server.notify(src, 'Ponto de garagem nao encontrado.') end
    local departmentId = tonumber(gp.department_id)
    if not Server.isAdmin(src) and (not member or tonumber(member.department_id) ~= departmentId) then
        return Server.notify(src, _L('no_permission'))
    end
    local row = DB.single('SELECT * FROM fiveems_vehicles WHERE id=? AND department_id=?', {tonumber(vehicleId), departmentId})
    if not row then return Server.notify(src, 'Viatura nao encontrada nesta garagem.') end
    if not Server.isAdmin(src) and tonumber(member.level or 1) < tonumber(row.min_level or 1) then
        return Server.notify(src, 'Seu Level ainda nao libera esta viatura.')
    end
    gp.data = DB.jsonDecode(gp.data, {})
    if type(gp.data.spawns) ~= 'table' or #gp.data.spawns == 0 then
        return Server.notify(src, 'Esta garagem nao possui vagas. Configure as vagas no Criador.')
    end
    local garageData = gp
    TriggerClientEvent('fiveems:client:spawnAuthorizedVehicle', src, row.model, garageData)
end)


RegisterNetEvent('fiveems:server:initStretcherState', function(netId)
    netId = tonumber(netId)
    if not netId or netId <= 0 then return end
    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return end
    Entity(entity).state:set('fiveems:stretcher', true, true)
    Entity(entity).state:set('fiveems:stretcherHigh', true, true)
    Entity(entity).state:set('fiveems:attachedVehicle', 0, true)
end)

RegisterNetEvent('fiveems:server:setStretcherState', function(netId, key, value)
    netId = tonumber(netId)
    key = tostring(key or '')
    if not netId or netId <= 0 then return end
    if key ~= 'fiveems:stretcher' and key ~= 'fiveems:stretcherHigh' and key ~= 'fiveems:attachedVehicle' then return end
    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return end
    Entity(entity).state:set(key, value, true)
end)

RegisterNetEvent('fiveems:server:requestStretcher', function()
    local src = source
    if not (Server.isAdmin(src) or Server.hasPermission(src, 'garage.use')) then return Server.notify(src, _L('no_permission')) end
    local member = Server.getMember(src)
    local department = member and D.getFull(member.department_id) or nil
    local model = department and department.settings and department.settings.defaultStretcherModel or nil
    if not model or model == '' then model = Config.Stretcher.defaultModel or 'strykerpro' end
    TriggerClientEvent('fiveems:client:spawnAuthorizedStretcher', src, model)
end)

RegisterNetEvent('fiveems:server:placePatientAtCarePoint', function(targetSrc, pointId)
    local src = source
    targetSrc = tonumber(targetSrc)
    pointId = tonumber(pointId)
    if not targetSrc or not pointId or not Server.hasPermission(src, 'patient.treat') then return end
    local member = Server.getMember(src)
    if not member then return end
    local point = DB.single('SELECT * FROM fiveems_points WHERE id=? AND department_id=?', {pointId, tonumber(member.department_id)})
    if not point or (point.type ~= FiveEMS.PointTypes.BED and point.type ~= FiveEMS.PointTypes.SURGERY and point.type ~= FiveEMS.PointTypes.IML and point.type ~= FiveEMS.PointTypes.OTHER) then return end
    point.data = DB.jsonDecode(point.data, {})
    pcall(function()
        local player = Player(targetSrc)
        if player and player.state then
            player.state:set('fiveems:carePointId', pointId, true)
            player.state:set('fiveems:carePointDepartmentId', tonumber(point.department_id) or tonumber(member.department_id) or 0, true)
        end
        local ped = GetPlayerPed(targetSrc)
        if ped and ped ~= 0 and DoesEntityExist(ped) then
            Entity(ped).state:set('fiveems:carePointId', pointId, true)
            Entity(ped).state:set('fiveems:carePointDepartmentId', tonumber(point.department_id) or tonumber(member.department_id) or 0, true)
        end
    end)
    TriggerClientEvent('fiveems:client:placeOnCarePoint', targetSrc, point)
end)

RegisterNetEvent('fiveems:server:stretcherTransferNpc', function(npcNetId, pointId)
    local src = source
    npcNetId = tonumber(npcNetId)
    pointId = tonumber(pointId)

    if not npcNetId or npcNetId <= 0 or not pointId then return end
    if not Server.hasPermission(src, 'patient.treat') then
        return Server.notify(src, _L('no_permission'))
    end

    local member = Server.getMember(src)
    if not member then return end

    local point = DB.single(
        'SELECT * FROM fiveems_points WHERE id=? AND department_id=?',
        {pointId, tonumber(member.department_id)}
    )

    if not point or (
        point.type ~= FiveEMS.PointTypes.BED
        and point.type ~= FiveEMS.PointTypes.SURGERY
        and point.type ~= FiveEMS.PointTypes.IML
        and point.type ~= FiveEMS.PointTypes.OTHER
    ) then
        return Server.notify(src, 'Leito/local de transferencia invalido.')
    end

    local npc = NetworkGetEntityFromNetworkId(npcNetId)
    if npc == 0 or not DoesEntityExist(npc) or GetEntityType(npc) ~= 1 then
        return Server.notify(src, 'Paciente NPC nao esta sincronizado no servidor.')
    end

    local playerPed = GetPlayerPed(src)
    if playerPed == 0 then return end
    if #(GetEntityCoords(playerPed) - GetEntityCoords(npc)) > 25.0 then
        return Server.notify(src, 'Paciente esta longe demais para transferencia.')
    end

    point.data = DB.jsonDecode(point.data, {})
    TriggerClientEvent('fiveems:client:transferNpcAuthorized', src, npcNetId, point)
end)

RegisterNetEvent('fiveems:server:stretcherTransferPlayer', function(targetSrc, pointId)
    local src = source
    targetSrc = tonumber(targetSrc)
    pointId = tonumber(pointId)
    if not targetSrc or not pointId or not Server.hasPermission(src, 'patient.treat') then return end
    local member = Server.getMember(src)
    if not member then return end
    local point = DB.single('SELECT * FROM fiveems_points WHERE id=? AND department_id=?', {pointId, tonumber(member.department_id)})
    if not point or (point.type ~= FiveEMS.PointTypes.BED and point.type ~= FiveEMS.PointTypes.SURGERY and point.type ~= FiveEMS.PointTypes.IML and point.type ~= FiveEMS.PointTypes.OTHER) then return end
    point.data = DB.jsonDecode(point.data, {})
    pcall(function()
        local player = Player(targetSrc)
        if player and player.state then
            player.state:set('fiveems:carePointId', pointId, true)
            player.state:set('fiveems:carePointDepartmentId', tonumber(point.department_id) or tonumber(member.department_id) or 0, true)
        end
        local ped = GetPlayerPed(targetSrc)
        if ped and ped ~= 0 and DoesEntityExist(ped) then
            Entity(ped).state:set('fiveems:carePointId', pointId, true)
            Entity(ped).state:set('fiveems:carePointDepartmentId', tonumber(point.department_id) or tonumber(member.department_id) or 0, true)
        end
    end)
    TriggerClientEvent('fiveems:client:stretcherReleaseSelf', targetSrc)
    Wait(100)
    TriggerClientEvent('fiveems:client:placeOnCarePoint', targetSrc, point)
end)

RegisterNetEvent('fiveems:server:releasePatientFromCarePoint', function(targetSrc)
    local src = source
    targetSrc = tonumber(targetSrc)
    if not targetSrc or not Server.hasPermission(src, 'patient.treat') then return end
    pcall(function()
        local player = Player(targetSrc)
        if player and player.state then
            player.state:set('fiveems:carePointId', 0, true)
            player.state:set('fiveems:carePointDepartmentId', 0, true)
        end
        local ped = GetPlayerPed(targetSrc)
        if ped and ped ~= 0 and DoesEntityExist(ped) then
            Entity(ped).state:set('fiveems:carePointId', 0, true)
            Entity(ped).state:set('fiveems:carePointDepartmentId', 0, true)
        end
    end)
    TriggerClientEvent('fiveems:client:releaseCarePoint', targetSrc)
end)

RegisterNetEvent('fiveems:server:stretcherAttachPlayer', function(targetSrc, stretcherNetId, transform)
    local src = source
    targetSrc = tonumber(targetSrc)
    stretcherNetId = tonumber(stretcherNetId)
    if not targetSrc or not stretcherNetId or stretcherNetId <= 0 then return end
    if not Server.hasPermission(src, 'patient.treat') then return Server.notify(src, _L('no_permission')) end
    if not GetPlayerName(targetSrc) then return end
    pcall(function()
        local player = Player(targetSrc)
        if player and player.state then
            player.state:set('fiveems:carePointId', 0, true)
            player.state:set('fiveems:carePointDepartmentId', 0, true)
        end
        local ped = GetPlayerPed(targetSrc)
        if ped and ped ~= 0 and DoesEntityExist(ped) then
            Entity(ped).state:set('fiveems:carePointId', 0, true)
            Entity(ped).state:set('fiveems:carePointDepartmentId', 0, true)
        end
    end)
    TriggerClientEvent('fiveems:client:stretcherAttachSelf', targetSrc, stretcherNetId, transform or {})
end)

RegisterNetEvent('fiveems:server:stretcherReleasePlayer', function(targetSrc)
    local src = source
    targetSrc = tonumber(targetSrc)
    if not targetSrc or not Server.hasPermission(src, 'patient.treat') then return end
    if not GetPlayerName(targetSrc) then return end
    TriggerClientEvent('fiveems:client:stretcherReleaseSelf', targetSrc)
end)
