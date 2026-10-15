FiveEMS = FiveEMS or {}
FiveEMS.DB = FiveEMS.DB or {}

local DB = FiveEMS.DB

DB._ready = false
DB._failed = false
DB._installing = false
DB._lastError = nil
DB._installedStatements = 0
DB.schemaVersion = '0.4.7-field-equipment'

local function log(message, color)
    print((color or '^5') .. '[FiveEMS][DB]^7 ' .. tostring(message))
end

local function splitSqlStatements(sql)
    local out = {}
    local buffer = {}
    local quote = nil
    local i = 1
    local len = #sql

    local function push()
        local stmt = table.concat(buffer):match('^%s*(.-)%s*$')
        buffer = {}
        if stmt and stmt ~= '' then out[#out + 1] = stmt end
    end

    while i <= len do
        local c = sql:sub(i, i)
        local n = i < len and sql:sub(i + 1, i + 1) or ''

        if quote then
            buffer[#buffer + 1] = c
            if c == '\\' and i < len then
                i = i + 1
                buffer[#buffer + 1] = sql:sub(i, i)
            elseif c == quote then
                if quote == "'" and n == "'" then
                    i = i + 1
                    buffer[#buffer + 1] = n
                else
                    quote = nil
                end
            end
        else
            if c == "'" or c == '"' or c == '`' then
                quote = c
                buffer[#buffer + 1] = c
            elseif c == '-' and n == '-' then
                i = i + 2
                while i <= len and sql:sub(i, i) ~= '\n' do i = i + 1 end
                buffer[#buffer + 1] = '\n'
            elseif c == '#' then
                while i <= len and sql:sub(i, i) ~= '\n' do i = i + 1 end
                buffer[#buffer + 1] = '\n'
            elseif c == '/' and n == '*' then
                i = i + 2
                while i <= len - 1 and not (sql:sub(i, i) == '*' and sql:sub(i + 1, i + 1) == '/') do i = i + 1 end
                i = i + 1
            elseif c == ';' then
                push()
            else
                buffer[#buffer + 1] = c
            end
        end
        i = i + 1
    end
    push()
    return out
end

function DB.awaitReady(timeoutMs)
    if DB._ready then return true end
    if DB._failed then return false, DB._lastError end

    local timeout = GetGameTimer() + (tonumber(timeoutMs) or ((Config.Database and Config.Database.startupTimeoutMs) or 30000))
    while not DB._ready and not DB._failed and GetGameTimer() < timeout do
        Wait(25)
    end

    if DB._ready then return true end
    return false, DB._lastError or 'Tempo limite aguardando inicializacao do banco.'
end

local function ensureReady()
    local ok, err = DB.awaitReady()
    if not ok then
        error('[FiveEMS] Banco indisponivel: ' .. tostring(err), 3)
    end
end

function DB.query(sql, params)
    ensureReady()
    return MySQL.query.await(sql, params or {})
end

function DB.single(sql, params)
    ensureReady()
    return MySQL.single.await(sql, params or {})
end

function DB.scalar(sql, params)
    ensureReady()
    return MySQL.scalar.await(sql, params or {})
end

function DB.insert(sql, params)
    ensureReady()
    return MySQL.insert.await(sql, params or {})
end

function DB.update(sql, params)
    ensureReady()
    return MySQL.update.await(sql, params or {})
end

function DB.transaction(queries)
    ensureReady()
    return MySQL.transaction.await(queries)
end

function DB.jsonDecode(value, fallback)
    if not value or value == '' then return fallback end
    local ok, decoded = pcall(json.decode, value)
    if ok and decoded ~= nil then return decoded end
    return fallback
end

function DB.jsonEncode(value)
    return json.encode(value or {})
end

function DB.getHealth()
    local ok, err = DB.awaitReady(1000)
    if not ok then
        return {ready=false, failed=DB._failed, error=err, schemaVersion=DB.schemaVersion, tableCount=0}
    end

    local count = MySQL.scalar.await([[
        SELECT COUNT(*) FROM information_schema.tables
        WHERE table_schema = DATABASE() AND table_name LIKE 'fiveems_%'
    ]]) or 0
    local migration = MySQL.single.await('SELECT version, applied_at FROM fiveems_schema_migrations ORDER BY id DESC LIMIT 1')
    return {
        ready = true,
        failed = false,
        schemaVersion = DB.schemaVersion,
        tableCount = tonumber(count) or 0,
        migration = migration,
        installedStatements = DB._installedStatements,
    }
end

local function installSchema()
    DB._installing = true
    local autoInstall = not Config.Database or Config.Database.autoInstall ~= false

    local schemaExists = MySQL.scalar.await([[
        SELECT COUNT(*) FROM information_schema.tables
        WHERE table_schema = DATABASE() AND table_name = 'fiveems_departments'
    ]])

    if tonumber(schemaExists or 0) == 0 and not autoInstall then
        error('Tabelas FiveEMS nao existem e Config.Database.autoInstall esta desativado.')
    end

    if autoInstall then
        local sql = LoadResourceFile(GetCurrentResourceName(), 'sql/fiveems.sql')
        if not sql or sql == '' then error('Nao foi possivel ler sql/fiveems.sql.') end
        sql = sql:gsub('^\239\187\191', '')
        local statements = splitSqlStatements(sql)
        log(('Instalacao/migracao automatica iniciada (%d comandos SQL).'):format(#statements), '^3')
        for index, statement in ipairs(statements) do
            local ok, result = pcall(function()
                return MySQL.query.await(statement)
            end)
            if not ok then
                error(('Falha no comando SQL %d/%d: %s'):format(index, #statements, tostring(result)))
            end
            DB._installedStatements = index
        end
    end

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS fiveems_schema_migrations (
            id INT UNSIGNED NOT NULL AUTO_INCREMENT,
            version VARCHAR(40) NOT NULL,
            applied_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (id),
            UNIQUE KEY uq_fiveems_schema_version (version)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])

    MySQL.query.await([[
        INSERT INTO fiveems_schema_migrations (version)
        VALUES (?) ON DUPLICATE KEY UPDATE version=VALUES(version)
    ]], {DB.schemaVersion})

    DB._installing = false
    DB._ready = true
    log('Banco pronto. Nao e mais necessario importar o SQL manualmente.', '^2')
end

CreateThread(function()
    -- Na base FivePD SP aguardamos primeiro o resource canonico de banco terminar suas migrations.
    if type(Config.Framework) == 'table' and Config.Framework.mode == 'fivepd_sp' then
        local dbResource = (Config.Framework.resources and Config.Framework.resources.database) or 'fivepd_sp_database'
        local frameworkTimeout = GetGameTimer() + ((Config.Database and Config.Database.startupTimeoutMs) or 30000)
        while GetResourceState(dbResource) == 'started' and GetGameTimer() < frameworkTimeout do
            local ok, ready = pcall(function() return exports[dbResource]:EstaPronto() end)
            if ok and ready == true then break end
            Wait(100)
        end
    end
    -- A dependencia do oxmysql no fxmanifest garante a ordem, mas aguardamos o handle MySQL por seguranca.
    local timeout = GetGameTimer() + ((Config.Database and Config.Database.startupTimeoutMs) or 30000)
    while (not MySQL or not MySQL.query) and GetGameTimer() < timeout do Wait(50) end

    if not MySQL or not MySQL.query then
        DB._failed = true
        DB._lastError = 'oxmysql/MySQL nao ficou disponivel dentro do tempo limite.'
        log(DB._lastError, '^1')
        return
    end

    local ok, err = pcall(installSchema)
    if not ok then
        DB._failed = true
        DB._installing = false
        DB._lastError = tostring(err)
        log('Falha ao preparar o banco: ' .. DB._lastError, '^1')
        if Config.DatabaseRequired then
            log('FiveEMS permanecerá indisponivel ate o problema do banco ser corrigido.', '^1')
        end
    end
end)
