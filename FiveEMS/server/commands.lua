FiveEMS = FiveEMS or {}
FiveEMS.Commands = FiveEMS.Commands or {}

local Commands = FiveEMS.Commands
local Server = FiveEMS.Server
local Calls = FiveEMS.Calls

local registered = {}

local function parseAliases(value)
    local aliases = {}
    local seen = {}

    if type(value) == 'table' then
        for _, item in ipairs(value) do
            for _, alias in ipairs(parseAliases(item)) do
                if not seen[alias] then seen[alias] = true aliases[#aliases+1] = alias end
            end
        end
        return aliases
    end

    value = tostring(value or '')
    for raw in value:gmatch('[^,%s]+') do
        local alias = raw:gsub('^/+', ''):lower()
        if #alias > 0 and #alias <= 32 and alias:match('^[%w_%-]+$') and not seen[alias] then
            seen[alias] = true
            aliases[#aliases+1] = alias
        end
    end
    return aliases
end

local function aliasesFor(kind)
    return parseAliases((Config.Commands or {})[kind])
end

local function isActiveAlias(kind, alias)
    alias = tostring(alias or ''):lower()
    for _, current in ipairs(aliasesFor(kind)) do
        if current == alias then return true end
    end
    return false
end

local function commandFromRaw(raw)
    return tostring(raw or ''):match('^/?([^%s]+)') or ''
end

local function denyOperational(src)
    return Server.notify(src, 'Voce precisa ser membro do FiveEMS em servico para usar este recurso.')
end

local handlers = {}

handlers.emergency = function(src, args, raw)
    if src == 0 then return end
    Calls.createFromPlayer(src, args, commandFromRaw(raw))
end

handlers.help = function(src)
    local lines = {}
    local function first(kind)
        return aliasesFor(kind)[1]
    end
    local function add(kind, suffix, description)
        local name = first(kind)
        if name then lines[#lines+1] = ('/%s%s - %s'):format(name, suffix or '', description) end
    end

    add('emergency', ' <texto>', 'solicita atendimento EMS na sua posicao')

    if src == 0 then
        add('admin', '', 'painel Admin')
        add('creator', '', 'Criador de Departamentos')
    else
        if Server.canUseOperational(src) then
            add('launcher', '', 'launcher FiveEMS')
            add('computer', '', 'fallback do computador')
            add('tablet', '', 'fallback do tablet')
            add('exam', '', 'atendimento do player mais proximo')
            add('patient', ' <id>', 'atendimento por Server ID')
            add('monitor', '', 'monitor do paciente proximo')
        end
        if Server.hasPermission(src, 'department.manage') then
            add('director', '', 'Mesa do Diretor')
        end
        if Server.isAdmin(src) then
            add('admin', '', 'painel Admin')
            add('creator', '', 'Criador de Departamentos')
            lines[#lines+1] = '/fiveemstest - diagnostico geral (admin)'
            lines[#lines+1] = '/fiveemsframework - diagnostico FivePD SP (admin)'
            lines[#lines+1] = '/fiveemsdb - diagnostico banco (admin)'
        end
    end

    if src == 0 then
        print('^5[FiveEMS]^7 Comandos configurados')
        for _, line in ipairs(lines) do print('  '..line) end
    else
        TriggerClientEvent('fiveems:client:consoleReport', src, 'FiveEMS - Comandos configurados', lines)
        Server.notify(src, 'Lista de comandos enviada para o F8.')
    end
end

handlers.launcher = function(src)
    if src == 0 then return end
    if not Server.canUseOperational(src) then return denyOperational(src) end
    TriggerClientEvent('fiveems:client:openUi', src, 'os')
end

handlers.computer = function(src)
    if src == 0 then return end
    if not Server.canUseOperational(src) then return denyOperational(src) end
    TriggerClientEvent('fiveems:client:openUi', src, 'computer')
end

handlers.tablet = function(src)
    if src == 0 then return end
    if not Server.canUseOperational(src) then return denyOperational(src) end
    TriggerClientEvent('fiveems:client:openUi', src, 'tablet')
end

handlers.exam = function(src)
    if src == 0 then return end
    if not Server.canUseOperational(src, 'patient.assess') then return denyOperational(src) end
    TriggerClientEvent('fiveems:client:commandNearestPatient', src, 'patient')
end

handlers.patient = function(src, args)
    if src == 0 then return end
    if not Server.canUseOperational(src, 'patient.assess') then return denyOperational(src) end
    local target = tonumber(args[1])
    if not target then return Server.notify(src, 'Informe o Server ID do paciente.') end
    TriggerClientEvent('fiveems:client:openPatientFromCommand', src, target)
end

handlers.monitor = function(src)
    if src == 0 then return end
    if not Server.canUseOperational(src, 'monitor.use') then return denyOperational(src) end
    TriggerClientEvent('fiveems:client:commandNearestPatient', src, 'monitor')
end

handlers.director = function(src)
    if src == 0 then return end
    if not Server.hasPermission(src, 'department.manage') then return Server.notify(src, _L('no_permission')) end
    TriggerClientEvent('fiveems:client:openUi', src, 'director')
end

handlers.admin = function(src)
    if src == 0 then return end
    if not Server.isAdmin(src) then return Server.notify(src, _L('no_permission')) end
    TriggerClientEvent('fiveems:client:openUi', src, 'admin')
end

handlers.creator = function(src)
    if src == 0 then return end
    if not Server.isAdmin(src) then return Server.notify(src, _L('no_permission')) end
    TriggerClientEvent('fiveems:client:openUi', src, 'creator')
end

local orderedKinds = {
    'emergency','help','launcher','computer','tablet','exam','patient','monitor',
    'director','admin','creator'
}

local function registerAlias(kind, alias)
    registered[kind] = registered[kind] or {}
    if registered[kind][alias] then return end
    registered[kind][alias] = true

    RegisterCommand(alias, function(src, args, raw)
        -- RegisterCommand nao possui unregister. Um alias antigo fica registrado,
        -- mas se for removido do Admin torna-se inativo imediatamente.
        if not isActiveAlias(kind, alias) then return end
        local handler = handlers[kind]
        if handler then handler(src, args or {}, raw or ('/'..alias)) end
    end, false)
end

function Commands.refresh()
    local claimed = {}

    for _, kind in ipairs(orderedKinds) do
        for _, alias in ipairs(aliasesFor(kind)) do
            if not claimed[alias] then
                claimed[alias] = kind
                registerAlias(kind, alias)
            else
                print(('^3[FiveEMS]^7 Alias /%s ignorado em %s: ja pertence a %s.'):format(alias, kind, claimed[alias]))
            end
        end
    end
end

function Commands.validate(value)
    if type(value) ~= 'table' then return false, 'Configuracao invalida.' end
    local claimed = {}

    for _, kind in ipairs(orderedKinds) do
        local raw = value[kind]
        if raw ~= nil then
            local aliases = parseAliases(raw)
            if #aliases == 0 then return false, ('Informe pelo menos um comando para %s.'):format(kind) end
            for _, alias in ipairs(aliases) do
                if claimed[alias] and claimed[alias] ~= kind then
                    return false, ('O comando /%s esta repetido em %s e %s.'):format(alias, claimed[alias], kind)
                end
                claimed[alias] = kind
            end
        end
    end
    return true
end

if FiveEMS.SetCommandRefresh then
    FiveEMS.SetCommandRefresh(Commands.refresh)
end

CreateThread(function()
    -- Espera admin.lua carregar configuracoes persistidas do banco.
    Wait(1200)
    Commands.refresh()
end)
