FiveEMS = FiveEMS or {}

local Server = FiveEMS.Server
local DB = FiveEMS.DB
local refreshConfiguredCommands

local function mergeInto(target, source)
    if type(target) ~= 'table' or type(source) ~= 'table' then return end
    for k,v in pairs(source) do
        if type(v) == 'table' and type(target[k]) == 'table' then
            mergeInto(target[k], v)
        else
            target[k] = v
        end
    end
end

local function applySetting(key, value)
    if key == 'calls' and type(value) == 'table' then
        mergeInto(Config.Calls, value)
    elseif key == 'xp' and type(value) == 'table' then
        mergeInto(Config.Progression, value)
    elseif key == 'damageMultipliers' and type(value) == 'table' then
        mergeInto(Config.DamageMultipliers, value)
    elseif key == 'oxygen' and type(value) == 'table' then
        mergeInto(Config.Oxygen, value)
    elseif key == 'monitor' and type(value) == 'table' then
        mergeInto(Config.Monitor, value)
    elseif key == 'stretcherCalibration' and type(value) == 'table' then
        Config.Stretcher = Config.Stretcher or {}
        if type(value.heightCalibration) == 'table' then
            Config.Stretcher.heightCalibration = Config.Stretcher.heightCalibration or {}
            mergeInto(Config.Stretcher.heightCalibration, value.heightCalibration)
        end
        if type(value.pushOffset) == 'table' then
            Config.Stretcher.pushOffset = Config.Stretcher.pushOffset or {}
            mergeInto(Config.Stretcher.pushOffset, value.pushOffset)
        end
        if type(value.patientPose) == 'table' then
            Config.Stretcher.patientPose = Config.Stretcher.patientPose or {}
            mergeInto(Config.Stretcher.patientPose, value.patientPose)
        end
    elseif key == 'npcPersistence' and type(value) == 'table' then
        Config.NpcPersistence = Config.NpcPersistence or {}
        mergeInto(Config.NpcPersistence, value)
    elseif key == 'commands' and type(value) == 'table' then
        Config.Commands = Config.Commands or {}
        mergeInto(Config.Commands, value)
        if refreshConfiguredCommands then refreshConfiguredCommands() end
    end
end

RegisterNetEvent('fiveems:server:getAdminSettings', function()
    local src = source
    if not Server.isAdmin(src) then return end
    local rows = DB.query('SELECT setting_key, setting_value FROM fiveems_settings ORDER BY setting_key') or {}
    local out = {}
    for _, row in ipairs(rows) do out[row.setting_key] = DB.jsonDecode(row.setting_value, row.setting_value) end
    TriggerClientEvent('fiveems:client:adminSettings', src, out)
end)

RegisterNetEvent('fiveems:server:saveAdminSetting', function(key, value)
    local src = source
    if not Server.isAdmin(src) then return Server.notify(src, _L('no_permission')) end
    key = tostring(key or '')
    if key == '' or #key > 80 then return end

    if key == 'commands' and FiveEMS.Commands and FiveEMS.Commands.validate then
        local ok, err = FiveEMS.Commands.validate(value)
        if not ok then return Server.notify(src, err or 'Configuracao de comandos invalida.') end
    end

    DB.query([[
        INSERT INTO fiveems_settings (setting_key, setting_value) VALUES (?, ?)
        ON DUPLICATE KEY UPDATE setting_value=VALUES(setting_value)
    ]], {key, DB.jsonEncode(value)})
    applySetting(key, value)

    -- Configuracoes que precisam chegar aos clients em runtime.
    if key == 'stretcherCalibration' then
        TriggerClientEvent('fiveems:client:applyStretcherConfig', -1, Config.Stretcher)
    elseif key == 'npcPersistence' then
        TriggerClientEvent('fiveems:client:applyNpcPersistenceConfig', -1, Config.NpcPersistence)
    elseif key == 'commands' then
        TriggerClientEvent('fiveems:client:commandsUpdated', -1, Config.Commands)
    end

    Server.audit(src, 'setting.save', 'setting', key, value)
end)

RegisterNetEvent('fiveems:server:requestRuntimeConfig', function()
    local src = source
    TriggerClientEvent('fiveems:client:applyStretcherConfig', src, Config.Stretcher)
    TriggerClientEvent('fiveems:client:applyNpcPersistenceConfig', src, Config.NpcPersistence)
    TriggerClientEvent('fiveems:client:commandsUpdated', src, Config.Commands)
end)

CreateThread(function()
    local ok, err = DB.awaitReady((Config.Database and Config.Database.startupTimeoutMs) or 30000)
    if not ok then
        print('^1[FiveEMS]^7 Nao foi possivel carregar configuracoes: '..tostring(err))
        return
    end
    local rows = DB.query('SELECT setting_key, setting_value FROM fiveems_settings') or {}
    for _, row in ipairs(rows) do
        local value = DB.jsonDecode(row.setting_value, nil)
        if value ~= nil then applySetting(row.setting_key, value) end
    end
end)

local function denyOperational(src)
    return Server.notify(src, 'Voce precisa ser membro do FiveEMS em servico para usar este recurso.')
end

-- Estes comandos continuam fixos por serem ferramentas internas de debug/manutencao.
-- Comandos visiveis ao usuario/painel sao registrados dinamicamente em server/commands.lua.
RegisterCommand('fiveemsresetpatient', function(src, args)
    if src ~= 0 and not Server.isAdmin(src) then return Server.notify(src, _L('no_permission')) end
    local target = tonumber(args[1]) or src
    if target == 0 then return print('[FiveEMS] Use fiveemsresetpatient <serverId> no console.') end
    if FiveEMS.Medical and FiveEMS.Medical.resetState and FiveEMS.Medical.resetState(target) then
        TriggerClientEvent('fiveems:client:notify', target, 'Estado medico reiniciado.')
    end
end, false)

RegisterCommand('fiveemsstretcher', function(src)
    if src == 0 or not Server.isAdmin(src) then
        if src ~= 0 then Server.notify(src, _L('no_permission')) end
        return
    end
    TriggerClientEvent('fiveems:client:debugStretcherToggle', src)
end, false)

RegisterCommand('fiveemsstretcherin', function(src)
    if src == 0 or not Server.isAdmin(src) then
        if src ~= 0 then Server.notify(src, _L('no_permission')) end
        return
    end
    TriggerClientEvent('fiveems:client:debugStretcherIn', src)
end, false)

RegisterCommand('fiveemsstretcherout', function(src)
    if src == 0 or not Server.isAdmin(src) then
        if src ~= 0 then Server.notify(src, _L('no_permission')) end
        return
    end
    TriggerClientEvent('fiveems:client:debugStretcherOut', src)
end, false)

RegisterCommand('fiveemspatientstretcher', function(src, args)
    if src == 0 or not Server.isAdmin(src) then
        if src ~= 0 then Server.notify(src, _L('no_permission')) end
        return
    end
    local target = tonumber(args[1])
    if not target then return Server.notify(src, 'Use /fiveemspatientstretcher <serverId>.') end
    TriggerClientEvent('fiveems:client:debugPatientToStretcher', src, target)
end, false)

RegisterCommand('fiveemspatientrelease', function(src)
    if src == 0 or not Server.isAdmin(src) then
        if src ~= 0 then Server.notify(src, _L('no_permission')) end
        return
    end
    TriggerClientEvent('fiveems:client:debugPatientRelease', src)
end, false)

RegisterCommand('fiveemsnpctest', function(src)
    if src == 0 or not Server.isAdmin(src) then
        if src ~= 0 then Server.notify(src, _L('no_permission')) end
        return
    end
    TriggerClientEvent('fiveems:client:debugNpcIdentity', src)
end, false)

RegisterCommand('fiveemsdb', function(src)
    if src ~= 0 and not Server.isAdmin(src) then return Server.notify(src, _L('no_permission')) end
    local health = DB.getHealth()
    local lines = {
        ('Ready: %s'):format(tostring(health.ready)),
        ('Schema esperado: %s'):format(tostring(health.schemaVersion)),
        ('Tabelas fiveems_*: %s'):format(tostring(health.tableCount or 0)),
        ('Ultima migracao: %s'):format(health.migration and tostring(health.migration.version) or 'nao encontrada'),
        ('Comandos SQL executados nesta inicializacao: %s'):format(tostring(health.installedStatements or 0)),
    }
    if health.error then lines[#lines+1] = 'Erro: '..tostring(health.error) end
    sendConsoleLines(src, 'FiveEMS - Database Health', lines)
    if src ~= 0 then Server.notify(src, health.ready and 'Banco FiveEMS OK. Veja o F8.' or 'Banco FiveEMS com erro. Veja o F8.') end
end, false)

RegisterCommand('fiveemstest', function(src)
    if src ~= 0 and not Server.isAdmin(src) then return Server.notify(src, _L('no_permission')) end
    local health = DB.getHealth()
    local oxState = GetResourceState('oxmysql')
    local invState = GetResourceState('fivepd_sp_inventory')
    local lines = {
        ('Resource: FiveEMS v%s'):format(Server.getResourceVersion and Server.getResourceVersion() or 'dev'),
        ('ox_target: %s'):format(GetResourceState('ox_target')),
        ('oxmysql: %s'):format(oxState),
        ('fivepd_sp_inventory: %s'):format(invState),
        ('Banco: %s | %d tabelas'):format(health.ready and 'OK' or 'ERRO', health.tableCount or 0),
        ('AutoInstall: %s'):format(tostring(not Config.Database or Config.Database.autoInstall ~= false)),
        ('AutoSeed catalogo: %s'):format(tostring(not Config.Database or Config.Database.autoSeedCatalogOnDepartmentCreate ~= false)),
    }
    if src ~= 0 then
        local member = Server.getMember(src)
        lines[#lines+1] = ('Admin ACE: %s'):format(tostring(Server.isAdmin(src)))
        lines[#lines+1] = ('Membro FiveEMS: %s'):format(member and 'SIM' or 'NAO')
        if member then
            lines[#lines+1] = ('Departamento: %s (#%s)'):format(tostring(member.department_name or '?'), tostring(member.department_id or '?'))
            lines[#lines+1] = ('Cargo: %s | Level %s | XP %s'):format(tostring(member.rank_name or '?'), tostring(member.level or 1), tostring(member.xp or 0))
            lines[#lines+1] = ('Duty: %s'):format(tostring(member.on_duty == true))
        else
            lines[#lines+1] = 'Proximo passo: /fiveemscreator -> crie/abra o departamento -> /fiveemsdirector -> atribua seu Server ID ao cargo Diretor.'
        end
    end
    sendConsoleLines(src, 'FiveEMS - Diagnostico', lines)
    if src ~= 0 then Server.notify(src, 'Diagnostico enviado para o console F8.') end
end, false)

RegisterCommand('fiveemsframework', function(src)
    if src ~= 0 and not Server.isAdmin(src) then return Server.notify(src, _L('no_permission')) end
    local F = FiveEMS.Framework
    local status = F and F.status and F.status() or {mode='unknown', ready=false, resources={}}
    local lines = {
        ('Modo: %s | Ready: %s | Strict: %s'):format(tostring(status.mode), tostring(status.ready), tostring(status.strict)),
    }
    for key, data in pairs(status.resources or {}) do
        lines[#lines+1] = ('%s => %s (%s)'):format(key, tostring(data.name), tostring(data.state))
    end
    if src ~= 0 and F then
        local session = F.getSession(src)
        local identity = F.getPlayerIdentity(src)
        local death = F.getDeathState(src)
        lines[#lines+1] = ('Character ID: %s | Fixed ID: %s | Tipo: %s'):format(tostring(F.getCharacterId(src)), tostring(F.getFixedId(src)), tostring(F.getCharacterType(src)))
        lines[#lines+1] = ('Chave FiveEMS: %s'):format(tostring(F.playerKey(src)))
        lines[#lines+1] = ('Records: %s | RG: %s | Sangue: %s'):format(identity and tostring(identity.nome_completo) or 'N/A', identity and tostring(identity.rg) or 'N/A', identity and tostring(identity.tipo_sanguineo) or 'N/A')
        lines[#lines+1] = ('Death state: %s'):format(type(death)=='table' and tostring(death.status) or 'alive/N/A')
        lines[#lines+1] = ('Admin FivePD SP: %s | Cargo: %s'):format(tostring(F.isAdmin(src)), tostring(F.getAdminRank(src)))
    end
    sendConsoleLines(src, 'FiveEMS - FivePD SP Bridge', lines)
    if src ~= 0 then Server.notify(src, status.ready and 'Bridge FivePD SP pronto. Veja o F8.' or 'Bridge incompleto. Veja o F8.') end
end, false)

RegisterCommand('fiveemsseed', function(src, args)
    if src ~= 0 and not Server.isAdmin(src) then return Server.notify(src, _L('no_permission')) end
    local departmentId = tonumber(args[1])
    if not departmentId then
        if src == 0 then return print('[FiveEMS] Uso: fiveemsseed <departmentId>') end
        local member = Server.getMember(src)
        departmentId = member and tonumber(member.department_id) or nil
    end
    if not departmentId then
        if src == 0 then
            print('[FiveEMS] Department ID obrigatorio.')
        else
            Server.notify(src, 'Informe o Department ID.')
        end
        return
    end
    local count = FiveEMS.Departments and FiveEMS.Departments.seedSupplies and FiveEMS.Departments.seedSupplies(departmentId) or 0
    if src == 0 then
        print(('[FiveEMS] Catalogo atualizado no departamento #%d: %d itens.'):format(departmentId, count))
    else
        Server.notify(src, ('Catalogo atualizado: %d itens.'):format(count))
    end
end, false)


-- server/commands.lua injeta esta funcao depois de carregar.
FiveEMS.SetCommandRefresh = function(fn)
    refreshConfiguredCommands = fn
end
