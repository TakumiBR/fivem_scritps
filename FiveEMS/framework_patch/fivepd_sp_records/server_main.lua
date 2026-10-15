local npcPorRede = {}
local npcMemoriaPorRg = {}
local npcMemoriaPorRef = {}
local veiculosMemoria = {}
local sequenciaNpc = 0
local npcCriacaoPorRede = {}

local NPC_STATE_KEY = 'fivepd_sp:records:npcKey'
local NPC_STATE_RECORD = 'fivepd_sp:records:recordId'
local NPC_STATE_RG = 'fivepd_sp:records:rg'

math.randomseed(os.time() + GetGameTimer())

local function aguardarBanco()
    while GetResourceState('fivepd_sp_database') == 'started'
        and not exports.fivepd_sp_database:EstaPronto()
    do
        Wait(50)
    end
end

local function trim(v)
    v = tostring(v or '')
    return v:match('^%s*(.-)%s*$') or ''
end

local function jsonSeguro(valor, padrao)
    if type(valor) == 'table' then
        return valor
    end

    if type(valor) ~= 'string' or valor == '' then
        return padrao
    end

    local ok, resultado = pcall(json.decode, valor)
    if not ok or type(resultado) ~= 'table' then
        return padrao
    end

    return resultado
end


-- O oxmysql pode devolver campos DATE como string, timestamp Unix (inclusive
-- negativo para datas anteriores a 1970) ou milissegundos, dependendo da
-- configuração do driver. Toda data civil passa por esta normalização antes de
-- ser usada pela base.
local function normalizarDataIso(valor)
    if valor == nil then return nil end

    local texto = tostring(valor):match('^%s*(.-)%s*$') or ''
    if texto == '' then return nil end

    local ano, mes, dia = texto:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)')
    if ano then
        return ('%04d-%02d-%02d'):format(tonumber(ano), tonumber(mes), tonumber(dia))
    end

    dia, mes, ano = texto:match('^(%d%d)/(%d%d)/(%d%d%d%d)')
    if ano then
        return ('%04d-%02d-%02d'):format(tonumber(ano), tonumber(mes), tonumber(dia))
    end

    local compactoAno, compactoMes, compactoDia = texto:match('^(%d%d%d%d)(%d%d)(%d%d)$')
    if compactoAno then
        local y = tonumber(compactoAno)
        if y and y >= 1900 and y <= tonumber(os.date('%Y')) + 1 then
            return ('%04d-%02d-%02d'):format(y, tonumber(compactoMes), tonumber(compactoDia))
        end
    end

    local numero = tonumber(texto)
    if numero then
        local segundos = numero
        if math.abs(segundos) > 100000000000 then
            segundos = segundos / 1000
        end

        local ok, data = pcall(os.date, '!%Y-%m-%d', math.floor(segundos))
        if ok and type(data) == 'string' and data:match('^%d%d%d%d%-%d%d%-%d%d$') then
            local y = tonumber(data:sub(1, 4))
            if y and y >= 1900 and y <= tonumber(os.date('%Y')) + 1 then
                return data
            end
        end

        -- Alguns runtimes Windows não aceitam timestamp Unix negativo em
        -- os.date(). Faz a conversão civil matematicamente como fallback.
        local dias = math.floor(segundos / 86400)
        local z = dias + 719468
        local era = math.floor(z / 146097)
        local doe = z - era * 146097
        local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
        local y = yoe + era * 400
        local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
        local mp = math.floor((5 * doy + 2) / 153)
        local d = doy - math.floor((153 * mp + 2) / 5) + 1
        local m = mp + (mp < 10 and 3 or -9)
        if m <= 2 then y = y + 1 end
        if y >= 1900 and y <= tonumber(os.date('%Y')) + 1 then
            return ('%04d-%02d-%02d'):format(y, m, d)
        end
    end

    return nil
end

local function formatarDataBr(valor)
    local iso = normalizarDataIso(valor)
    if not iso then return nil end
    return ('%s/%s/%s'):format(iso:sub(9, 10), iso:sub(6, 7), iso:sub(1, 4))
end

local function normalizarPlaca(placa)
    placa = tostring(placa or ''):upper()
    placa = placa:gsub('[^A-Z0-9]', '')
    return placa:sub(1, 8)
end


local function formatarPlacaVisual(placa)
    placa = normalizarPlaca(placa)
    if #placa == 7 then
        return placa:sub(1, 3) .. ' ' .. placa:sub(4)
    end
    return placa
end

local function normalizarIdentificadorVeicular(valor)
    valor = tostring(valor or ''):upper():gsub('[^A-Z0-9%?%*]', '')
    return valor:sub(1, 32)
end

local function hashEstavel(texto)
    texto = tostring(texto or '')
    local h = 216613626
    for i = 1, #texto do
        h = (h * 131 + texto:byte(i)) % 2147483647
    end
    return h
end

local TOKEN_ALPHABET = '0123456789ABCDEFGHJKLMNPRSTUVWXYZ'
local function tokenEstavel(seed, tamanho)
    local n = hashEstavel(seed)
    local out = {}
    for i = 1, tamanho do
        n = (n * 1103515245 + 12345 + i * 97) % 2147483647
        local pos = (n % #TOKEN_ALPHABET) + 1
        out[i] = TOKEN_ALPHABET:sub(pos, pos)
    end
    return table.concat(out)
end

local function origemPorMarca(marca)
    local cfg = type(FSPRecords.VehicleIdentification) == 'table' and FSPRecords.VehicleIdentification or {}
    local map = type(cfg.originByMake) == 'table' and cfg.originByMake or {}
    local key = tostring(marca or ''):upper():gsub('^%s+', ''):gsub('%s+$', '')
    return tostring(map[key] or cfg.defaultOrigin or 'XX'):upper():sub(1, 2)
end

local function anoFabricacaoDeterministico(modelo, informado)
    local ano = tonumber(informado)
    if ano and ano >= 1980 and ano <= tonumber(os.date('%Y')) + 1 then return math.floor(ano) end
    -- O GTA não expõe ano de fabricação por native. Para a simulação, cada
    -- modelo recebe um ano estável, de forma que veículos do mesmo modelo
    -- compartilhem o mesmo bloco estrutural do chassi.
    return 2008 + (hashEstavel(tostring(modelo or 'unknown') .. ':ano') % 19)
end

local function formatarRg(digitos)
    digitos = tostring(digitos or ''):gsub('%D', '')
    digitos = digitos:sub(1, 9)
    if #digitos < 9 then return digitos end
    return ('%s%s.%s%s%s.%s%s%s-%s'):format(
        digitos:sub(1,1), digitos:sub(2,2),
        digitos:sub(3,3), digitos:sub(4,4), digitos:sub(5,5),
        digitos:sub(6,6), digitos:sub(7,7), digitos:sub(8,8),
        digitos:sub(9,9)
    )
end

local function rgExiste(rg)
    if npcMemoriaPorRg[rg] then
        return true
    end

    local existe = MySQL.scalar.await(
        'SELECT 1 FROM `fivepd_sp_records` PARTITION (`p_records_persons`) WHERE `rg` = ? LIMIT 1',
        { rg }
    )

    return existe ~= nil
end

local function gerarRg()
    for _ = 1, 80 do
        local digitos = ''
        for _ = 1, 9 do
            digitos = digitos .. tostring(math.random(0, 9))
        end

        local rg = formatarRg(digitos)
        if not rgExiste(rg) then
            return rg
        end
    end

    return formatarRg(('%09d'):format((os.time() + math.random(1, 999999)) % 1000000000))
end

local function telefoneNpc()
    return ('(11) 9%04d-%04d'):format(math.random(1000, 9999), math.random(1000, 9999))
end

local function idadeDeData(data)
    data = normalizarDataIso(data)
    if not data then return nil end
    local y, m, d = data:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)$')
    y, m, d = tonumber(y), tonumber(m), tonumber(d)
    if not y then return nil end

    local agora = os.date('*t')
    local idade = agora.year - y
    if agora.month < m or (agora.month == m and agora.day < d) then
        idade = idade - 1
    end
    return idade
end

local function nascimentoPorIdade(idade)
    local hoje = os.date('*t')
    local ano = hoje.year - idade
    local mes = math.random(1, 12)
    local maxDia = ({31,28,31,30,31,30,31,31,30,31,30,31})[mes]
    local dia = math.random(1, maxDia)
    return ('%04d-%02d-%02d'):format(ano, mes, dia)
end

local function escolher(lista)
    if type(lista) ~= 'table' or #lista == 0 then return nil end
    return lista[math.random(1, #lista)]
end

local function gerarCnhNpc(idade)
    if idade < 18 or math.random(1,100) <= 7 then
        return {
            status = 'nao_emitida',
            categories = {},
            points = 0,
            issued_at = nil,
            expires_at = nil
        }
    end

    local rolagem = math.random(1,100)
    local categorias
    if rolagem <= 14 then
        categorias = { 'A' }
    elseif rolagem <= 32 then
        categorias = { 'A', 'B' }
    elseif rolagem <= 88 then
        categorias = { 'B' }
    elseif rolagem <= 95 then
        categorias = { 'C' }
    else
        categorias = { 'D' }
    end

    local statusRoll = math.random(1,100)
    local status = 'regular'
    if statusRoll <= 6 then status = 'suspensa'
    elseif statusRoll <= 8 then status = 'cassada'
    elseif statusRoll <= 13 then status = 'vencida' end

    local hoje = os.date('*t')
    local emitida = ('%04d-%02d-%02d'):format(
        math.max(hoje.year - math.random(1, 10), hoje.year - idade + 18),
        math.random(1,12),
        math.random(1,28)
    )

    local venceAno = hoje.year + (status == 'vencida' and -math.random(1,4) or math.random(1,5))
    local vence = ('%04d-%02d-%02d'):format(venceAno, math.random(1,12), math.random(1,28))

    return {
        status = status,
        categories = categorias,
        points = math.random(0, 18),
        issued_at = emitida,
        expires_at = vence
    }
end

local function garantirCnhBanco(personId, dados)
    dados = type(dados) == 'table' and dados or FSPRecords.PlayerLicenseDefault
    local categorias = dados.categories or { 'B' }
    local status = dados.status or 'regular'
    local pontos = tonumber(dados.points) or 0
    local emitida = dados.issued_at
    local expira = dados.expires_at

    if not emitida then
        local hoje = os.date('*t')
        emitida = ('%04d-%02d-%02d'):format(hoje.year, hoje.month, hoje.day)
    end

    if not expira then
        local hoje = os.date('*t')
        local anos = tonumber(dados.validityYears) or 5
        expira = ('%04d-%02d-%02d'):format(hoje.year + anos, hoje.month, hoje.day)
    end

    MySQL.query.await([[
        INSERT INTO `fivepd_sp_records` PARTITION (`p_driver_licenses`)
            (`entity`, `person_id`, `status`, `categories`, `points`, `issued_at`, `expires_at`, `metadata`)
        VALUES (0x6669766570645f73705f6472697665725f6c6963656e736573, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE `person_id` = VALUES(`person_id`)
    ]], {
        personId,
        status,
        json.encode(categorias),
        pontos,
        emitida,
        expira,
        json.encode({})
    })
end

local registrosPersonagemEmCriacao = {}

local function garantirRegistroPersonagem(characterId)
    aguardarBanco()

    characterId =
        tonumber(characterId)

    if not characterId then
        return nil
    end

    -- Evita que dois resources do telefone tentem criar o mesmo registro
    -- no mesmo frame durante o carregamento do personagem.
    while registrosPersonagemEmCriacao[characterId] do
        Wait(15)

        local existente =
            MySQL.single.await(
                'SELECT `id`, `subject_type`, `character_id`, `npc_key`, `rg`, `nome`, `sobrenome`, `nascimento`, `sexo`, `telefone`, `tipo_sanguineo`, `porte_arma`, `metadata`, `created_at`, `updated_at` FROM `fivepd_sp_records` PARTITION (`p_records_persons`) WHERE `character_id` = ? LIMIT 1',
                { characterId }
            )

        if existente then
            garantirCnhBanco(
                existente.id
            )

            return existente
        end
    end

    local existente =
        MySQL.single.await(
            'SELECT `id`, `subject_type`, `character_id`, `npc_key`, `rg`, `nome`, `sobrenome`, `nascimento`, `sexo`, `telefone`, `tipo_sanguineo`, `porte_arma`, `metadata`, `created_at`, `updated_at` FROM `fivepd_sp_records` PARTITION (`p_records_persons`) WHERE `character_id` = ? LIMIT 1',
            { characterId }
        )

    if existente then
        garantirCnhBanco(
            existente.id
        )

        return existente
    end

    registrosPersonagemEmCriacao[
        characterId
    ] = true

    local ok,
        resultado =
        pcall(
            function()
                local personagem =
                    MySQL.single.await([[
                        SELECT
                            `id`,
                            `nome`,
                            `sobrenome`,
                            DATE_FORMAT(`nascimento`, '%Y-%m-%d') AS `nascimento`,
                            `sexo`
                        FROM `fivepd_sp_character`
                        WHERE `id` = ?
                          AND `ativo` = 1
                        LIMIT 1
                    ]], {
                        characterId
                    })

                if not personagem then
                    return nil
                end

                -- Mesmo com o lock local, o banco continua sendo a autoridade.
                -- O ON DUPLICATE torna a operação segura caso outro resource/
                -- thread tenha criado o registro entre o SELECT e o INSERT.
                for _ = 1, 5 do
                    local rg =
                        gerarRg()

                    local sangue =
                        escolher(
                            FSPRecords.Npc.bloodTypes
                        )
                        or 'O+'

                    MySQL.query.await([[
                        INSERT INTO `fivepd_sp_records` PARTITION (`p_records_persons`)
                            (`entity`, `subject_type`,
                                `character_id`,
                                `npc_key`,
                                `rg`,
                                `nome`,
                                `sobrenome`,
                                `nascimento`,
                                `sexo`,
                                `telefone`,
                                `tipo_sanguineo`,
                                `porte_arma`,
                                `metadata`)
                        VALUES (0x6669766570645f73705f7265636f7264735f706572736f6e73, 
                            'player',
                            ?,
                            NULL,
                            ?,
                            ?,
                            ?,
                            ?,
                            ?,
                            NULL,
                            ?,
                            0,
                            ?
                        )
                        ON DUPLICATE KEY UPDATE
                            `nome` = IF(
                                `character_id` = VALUES(`character_id`),
                                VALUES(`nome`),
                                `nome`
                            ),
                            `sobrenome` = IF(
                                `character_id` = VALUES(`character_id`),
                                VALUES(`sobrenome`),
                                `sobrenome`
                            ),
                            `nascimento` = IF(
                                `character_id` = VALUES(`character_id`),
                                VALUES(`nascimento`),
                                `nascimento`
                            ),
                            `sexo` = IF(
                                `character_id` = VALUES(`character_id`),
                                VALUES(`sexo`),
                                `sexo`
                            )
                    ]], {
                        characterId,
                        rg,
                        personagem.nome,
                        personagem.sobrenome,
                        personagem.nascimento,
                        personagem.sexo,
                        sangue,
                        json.encode({})
                    })

                    local criado =
                        MySQL.single.await(
                            'SELECT `id`, `subject_type`, `character_id`, `npc_key`, `rg`, `nome`, `sobrenome`, `nascimento`, `sexo`, `telefone`, `tipo_sanguineo`, `porte_arma`, `metadata`, `created_at`, `updated_at` FROM `fivepd_sp_records` PARTITION (`p_records_persons`) WHERE `character_id` = ? LIMIT 1',
                            { characterId }
                        )

                    if criado then
                        garantirCnhBanco(
                            criado.id
                        )

                        return criado
                    end

                    -- Se o conflito foi apenas uma colisão rara de RG,
                    -- gera outro e tenta novamente.
                end

                error(
                    ('não foi possível garantir o registro do personagem %s após 5 tentativas')
                    :format(
                        tostring(characterId)
                    )
                )
            end
        )

    registrosPersonagemEmCriacao[
        characterId
    ] = nil

    if not ok then
        print(
            ('[fivepd_sp_records] Falha ao garantir registro do personagem %s: %s')
            :format(
                tostring(characterId),
                tostring(resultado)
            )
        )

        return nil
    end

    return resultado
end

local function pessoaBancoPorTermo(termo)
    termo = trim(termo)
    if termo == '' then return nil end

    local porRg = MySQL.single.await(
        'SELECT `id`, `subject_type`, `character_id`, `npc_key`, `rg`, `nome`, `sobrenome`, `nascimento`, `sexo`, `telefone`, `tipo_sanguineo`, `porte_arma`, `metadata`, `created_at`, `updated_at` FROM `fivepd_sp_records` PARTITION (`p_records_persons`) WHERE `rg` = ? LIMIT 1',
        { termo }
    )
    if porRg then return porRg end

    local somenteDigitos = termo:gsub('%D','')
    if #somenteDigitos == 9 then
        porRg = MySQL.single.await(
            "SELECT `id`, `subject_type`, `character_id`, `npc_key`, `rg`, `nome`, `sobrenome`, `nascimento`, `sexo`, `telefone`, `tipo_sanguineo`, `porte_arma`, `metadata`, `created_at`, `updated_at` FROM `fivepd_sp_records` PARTITION (`p_records_persons`) WHERE REPLACE(REPLACE(REPLACE(`rg`,'.',''),'-',''),' ','') = ? LIMIT 1",
            { somenteDigitos }
        )
        if porRg then return porRg end
    end

    local characterId = tonumber(termo)
    if characterId then
        local porChar = MySQL.single.await(
            'SELECT `id`, `subject_type`, `character_id`, `npc_key`, `rg`, `nome`, `sobrenome`, `nascimento`, `sexo`, `telefone`, `tipo_sanguineo`, `porte_arma`, `metadata`, `created_at`, `updated_at` FROM `fivepd_sp_records` PARTITION (`p_records_persons`) WHERE `character_id` = ? LIMIT 1',
            { characterId }
        )
        if porChar then return porChar end

        return garantirRegistroPersonagem(characterId)
    end

    return nil
end

local function cnhBanco(personId)
    local row = MySQL.single.await(
        'SELECT `person_id`, `status`, `categories`, `points`, `issued_at`, `expires_at`, `metadata`, `updated_at` FROM `fivepd_sp_records` PARTITION (`p_driver_licenses`) WHERE `person_id` = ? LIMIT 1',
        { personId }
    )

    if not row then return nil end

    return {
        status = tostring(row.status or 'nao_emitida'),
        categories = jsonSeguro(row.categories, {}),
        points = tonumber(row.points) or 0,
        issued_at = row.issued_at and tostring(row.issued_at):sub(1,10) or nil,
        expires_at = row.expires_at and tostring(row.expires_at):sub(1,10) or nil
    }
end

local function antecedentesBanco(personId)
    return MySQL.query.await([[
        SELECT `id`, `kind`, `description`, `fine_amount`, `arrest_minutes`, UNIX_TIMESTAMP(`created_at`) AS `created_at`
        FROM `fivepd_sp_records` PARTITION (`p_criminal_records`)
        WHERE `person_id` = ?
        ORDER BY `id` DESC
        LIMIT 100
    ]], { personId }) or {}
end


local function garantirMatriculaPrisional(personId)
    personId = tonumber(personId)
    if not personId then return nil end

    local row = MySQL.single.await([[
        SELECT `id`, `person_id`, `prison_number`, UNIX_TIMESTAMP(`created_at`) AS `created_at`
        FROM `fivepd_sp_records` PARTITION (`p_prison_profiles`)
        WHERE `person_id` = ?
        LIMIT 1
    ]], { personId })

    if not row then
        MySQL.insert.await([[
            INSERT IGNORE INTO `fivepd_sp_records` PARTITION (`p_prison_profiles`) (`entity`, `person_id`)
            VALUES (0x6669766570645f73705f707269736f6e5f70726f66696c6573, ?)
        ]], { personId })
        row = MySQL.single.await([[
            SELECT `id`, `person_id`, `prison_number`, UNIX_TIMESTAMP(`created_at`) AS `created_at`
            FROM `fivepd_sp_records` PARTITION (`p_prison_profiles`)
            WHERE `person_id` = ?
            LIMIT 1
        ]], { personId })
    end

    if not row then return nil end
    local numero = trim(row.prison_number)
    if numero == '' then
        numero = ('MP-%08d'):format(tonumber(row.id) or 0)
        MySQL.update.await([[
            UPDATE `fivepd_sp_records` PARTITION (`p_prison_profiles`)
            SET `prison_number` = ?
            WHERE `id` = ? AND (`prison_number` IS NULL OR `prison_number` = '')
        ]], { numero, tonumber(row.id) })
        row.prison_number = numero
    end

    return {
        id = tonumber(row.id),
        person_id = personId,
        prison_number = tostring(row.prison_number or numero),
        created_at = tonumber(row.created_at)
    }
end

local function matriculaPrisionalExistente(personId, antecedentes)
    personId = tonumber(personId)
    if not personId then return nil end
    local row = MySQL.single.await([[
        SELECT `id`, `person_id`, `prison_number`, UNIX_TIMESTAMP(`created_at`) AS `created_at`
        FROM `fivepd_sp_records` PARTITION (`p_prison_profiles`)
        WHERE `person_id` = ?
        LIMIT 1
    ]], { personId })
    if row and trim(row.prison_number) ~= '' then
        return {
            id = tonumber(row.id), person_id = personId,
            prison_number = tostring(row.prison_number), created_at = tonumber(row.created_at)
        }
    end

    local hasArrest = false
    for _, registro in ipairs(type(antecedentes) == 'table' and antecedentes or {}) do
        if tostring(registro.kind or ''):lower() == 'prisao' then
            hasArrest = true
            break
        end
    end
    if hasArrest then return garantirMatriculaPrisional(personId) end
    return nil
end

local function normalizarMatriculaPrisional(value)
    value = trim(value):upper():gsub('%s+', '')
    value = value:gsub('[^A-Z0-9%-]', '')
    if value:match('^%d+$') then
        value = 'MP-' .. value
    elseif value:match('^MP%d+$') then
        value = 'MP-' .. value:sub(3)
    end
    local prefix, digits = value:match('^(MP%-)(%d+)$')
    if prefix and digits then
        value = prefix .. string.format('%08d', tonumber(digits) or 0)
    end
    return value
end


local function mandadosBanco(personId)
    return MySQL.query.await([[
        SELECT `id`, `reason`, `status`, `expires_at`, UNIX_TIMESTAMP(`created_at`) AS `created_at`
        FROM `fivepd_sp_records` PARTITION (`p_warrants`)
        WHERE `person_id` = ? AND `status` = 'ativo'
          AND (`expires_at` IS NULL OR `expires_at` > NOW())
        ORDER BY `id` DESC
    ]], { personId }) or {}
end

local function multasBanco(personId)
    return MySQL.query.await([[
        SELECT `id`, `reason`, `amount`, `paid`, `paid_at`, UNIX_TIMESTAMP(`created_at`) AS `created_at`
        FROM `fivepd_sp_records` PARTITION (`p_fines`)
        WHERE `person_id` = ?
        ORDER BY `id` DESC
        LIMIT 100
    ]], { personId }) or {}
end

local function veiculosBancoPorPessoa(personId)
    return MySQL.query.await([[
        SELECT `id`, `plate`, `model`, `make_name`, `manufacture_year`, `origin_code`,
               `chassis_number`, `engine_number`, `glass_number`,
               `display_name`, `vehicle_class`, `color_primary`, `color_secondary`,
               `stolen`, `impounded`, `impound_until`, `tax_due_at`, `metadata`
        FROM `fivepd_sp_records` PARTITION (`p_vehicle_records`)
        WHERE `owner_person_id` = ?
        ORDER BY `id` DESC
    ]], { personId }) or {}
end

local function escolhaCivil(lista, seed, salt)
    if type(lista) ~= 'table' or #lista == 0 then return nil end
    local index = (hashEstavel(('%s:%s'):format(tostring(seed or ''), tostring(salt or ''))) % #lista) + 1
    return lista[index]
end

local function numeroCivil(seed, salt, minimo, maximo)
    minimo, maximo = tonumber(minimo) or 0, tonumber(maximo) or 0
    if maximo < minimo then minimo, maximo = maximo, minimo end
    return minimo + (hashEstavel(('%s:%s'):format(tostring(seed or ''), tostring(salt or ''))) % (maximo - minimo + 1))
end

local function preencherPerfilCivil(seed, sexo, sobrenome, existente)
    local cfg = type(FSPRecords.CivilProfile) == 'table' and FSPRecords.CivilProfile or {}
    local civil = type(existente) == 'table' and existente or {}
    local alterado = false

    local function garantir(chave, valor)
        if civil[chave] == nil or trim(civil[chave]) == '' then
            civil[chave] = valor
            alterado = true
        end
    end

    local sobrenomeBase = trim(sobrenome)
    if sobrenomeBase == '' then sobrenomeBase = escolhaCivil(FSPRecords.Npc.surnames, seed, 'sobrenome') or 'Silva' end
    local sobrenomeMae = escolhaCivil(FSPRecords.Npc.surnames, seed, 'sobrenome-mae') or 'Santos'
    local sobrenomePai = escolhaCivil(FSPRecords.Npc.surnames, seed, 'sobrenome-pai') or 'Oliveira'
    local nomeMae = escolhaCivil(FSPRecords.Npc.femaleNames, seed, 'nome-mae') or 'Maria'
    local nomePai = escolhaCivil(FSPRecords.Npc.maleNames, seed, 'nome-pai') or 'José'

    local municipio = escolhaCivil(cfg.municipios, seed, 'municipio') or 'São Paulo/SP'
    local logradouro = escolhaCivil(cfg.logradouros, seed, 'logradouro') or 'Rua das Flores'
    local bairro = escolhaCivil(cfg.bairros, seed, 'bairro') or 'Centro'
    local numero = numeroCivil(seed, 'numero-endereco', 12, 1899)

    garantir('naturalidade', escolhaCivil(cfg.naturalidades, seed, 'naturalidade') or 'São Paulo/SP')
    garantir('nacionalidade', 'Brasileira')
    garantir('mae', ('%s %s %s'):format(nomeMae, sobrenomeMae, sobrenomeBase))
    garantir('pai', ('%s %s %s'):format(nomePai, sobrenomePai, sobrenomeBase))
    garantir('cor_olhos', escolhaCivil(cfg.coresOlhos, seed, 'olhos') or 'Castanhos')
    garantir('cor_pele', escolhaCivil(cfg.coresPele, seed, 'pele') or 'Parda')
    garantir('tipo_cabelo', escolhaCivil(cfg.tiposCabelo, seed, 'cabelo') or 'Castanho')
    garantir('profissao', escolhaCivil(cfg.profissoes, seed, 'profissao') or 'Autônomo(a)')
    garantir('estado_civil', escolhaCivil(cfg.estadosCivis, seed, 'estado-civil') or 'Solteiro(a)')
    garantir('escolaridade', escolhaCivil(cfg.escolaridades, seed, 'escolaridade') or 'Ensino médio completo')
    garantir('municipio', municipio)
    garantir('endereco', ('%s, %d - %s'):format(logradouro, numero, bairro))

    local sexoNormalizado = tostring(sexo or ''):lower()
    local alturaMin, alturaMax = 156, 190
    if sexoNormalizado == 'feminino' then alturaMin, alturaMax = 150, 181 end
    local alturaCm = numeroCivil(seed, 'altura', alturaMin, alturaMax)
    garantir('altura', ('%.2f m'):format(alturaCm / 100.0):gsub('%.', ','))
    garantir('origem', 'cadastro_simulado_persistente')

    return civil, alterado
end

local function perfilCivilBanco(row)
    if type(row) ~= 'table' then return {} end

    local metadata = jsonSeguro(row.metadata, {})
    local existente = type(metadata.civil_profile) == 'table' and metadata.civil_profile or {}

    -- Compatibilidade com dados complementares que eventualmente já tenham
    -- sido gravados diretamente no metadata por outro resource.
    local chaves = {
        'naturalidade','nacionalidade','mae','pai','cor_olhos','cor_pele','altura',
        'tipo_cabelo','profissao','estado_civil','escolaridade','municipio','endereco'
    }
    for _, chave in ipairs(chaves) do
        if (existente[chave] == nil or trim(existente[chave]) == '') and metadata[chave] ~= nil then
            existente[chave] = metadata[chave]
        end
    end

    local seed = ('registro:%s:%s:%s'):format(tostring(row.id or ''), tostring(row.rg or ''), tostring(row.character_id or row.npc_key or ''))
    local civil, alterado = preencherPerfilCivil(seed, row.sexo, row.sobrenome, existente)
    if metadata.civil_profile == nil then alterado = true end
    metadata.civil_profile = civil

    if alterado and tonumber(row.id) then
        MySQL.update.await('UPDATE `fivepd_sp_records` PARTITION (`p_records_persons`) SET `metadata` = ? WHERE `id` = ?', {
            json.encode(metadata), tonumber(row.id)
        })
        row.metadata = metadata
    end

    return civil
end

local function aplicarPerfilCivil(destino, civil)
    civil = type(civil) == 'table' and civil or {}
    destino.naturalidade = civil.naturalidade
    destino.nacionalidade = civil.nacionalidade
    destino.mae = civil.mae
    destino.pai = civil.pai
    destino.cor_olhos = civil.cor_olhos
    destino.cor_pele = civil.cor_pele
    destino.altura = civil.altura
    destino.tipo_cabelo = civil.tipo_cabelo
    destino.profissao = civil.profissao
    destino.estado_civil = civil.estado_civil
    destino.escolaridade = civil.escolaridade
    destino.municipio = civil.municipio
    destino.endereco = civil.endereco
    destino.dados_civis_origem = civil.origem
    return destino
end

local function montarPessoaBanco(row)
    if not row then return nil end

    local mandados = mandadosBanco(row.id)
    local veiculos = veiculosBancoPorPessoa(row.id)
    local antecedentes = antecedentesBanco(row.id)
    local perfilPrisional = matriculaPrisionalExistente(row.id, antecedentes)
    local nascimentoIso = normalizarDataIso(row.nascimento)
    local civil = perfilCivilBanco(row)

    local pessoa = {
        encontrado = true,
        tipo = row.subject_type,
        record_id = tonumber(row.id),
        character_id = tonumber(row.character_id),
        npc_key = row.npc_key,
        rg = row.rg,
        nome = row.nome,
        sobrenome = row.sobrenome,
        nome_completo = (tostring(row.nome or '') .. ' ' .. tostring(row.sobrenome or '')):gsub('%s+$',''),
        nascimento = formatarDataBr(nascimentoIso) or '—',
        nascimento_iso = nascimentoIso,
        idade = idadeDeData(nascimentoIso),
        sexo = row.sexo,
        telefone = row.telefone,
        tipo_sanguineo = row.tipo_sanguineo,
        porte_arma = tonumber(row.porte_arma) == 1,
        cnh = cnhBanco(row.id) or {
            status = 'nao_emitida', categories = {}, points = 0
        },
        procurado = #mandados > 0,
        mandados = mandados,
        antecedentes = antecedentes,
        matricula_prisional = perfilPrisional and perfilPrisional.prison_number or nil,
        multas = multasBanco(row.id),
        veiculos = veiculos
    }

    return aplicarPerfilCivil(pessoa, civil)
end

local function montarPessoaMemoria(registro)
    if not registro then return nil end
    local nascimentoIso = normalizarDataIso(registro.nascimento)
    local civil = type(registro.perfil_civil) == 'table' and registro.perfil_civil or {}
    if next(civil) == nil then
        local seed = ('npc-mem:%s:%s'):format(tostring(registro.npc_key or ''), tostring(registro.rg or ''))
        civil = select(1, preencherPerfilCivil(seed, registro.sexo, registro.sobrenome, civil))
        registro.perfil_civil = civil
    end

    local pessoa = {
        encontrado = true,
        tipo = 'npc',
        record_id = registro.record_id,
        character_id = nil,
        npc_key = registro.npc_key,
        model_hash = tonumber(registro.model_hash),
        rg = registro.rg,
        nome = registro.nome,
        sobrenome = registro.sobrenome,
        nome_completo = registro.nome_completo,
        nascimento = formatarDataBr(nascimentoIso) or '—',
        nascimento_iso = nascimentoIso,
        idade = idadeDeData(nascimentoIso) or registro.idade,
        sexo = registro.sexo,
        telefone = registro.telefone,
        tipo_sanguineo = registro.tipo_sanguineo,
        porte_arma = registro.porte_arma == true,
        cnh = registro.cnh,
        procurado = registro.procurado == true or #(registro.mandados or {}) > 0,
        mandados = registro.mandados or {},
        antecedentes = registro.antecedentes or {},
        multas = registro.multas or {},
        veiculos = registro.veiculos or {}
    }

    return aplicarPerfilCivil(pessoa, civil)
end

local function corrigirSexoRegistroNpc(registro, sexoEsperado)
    if type(registro) ~= 'table' then return registro end
    sexoEsperado = tostring(sexoEsperado or ''):lower()
    if sexoEsperado ~= 'masculino' and sexoEsperado ~= 'feminino' then return registro end
    if tostring(registro.sexo or ''):lower() == sexoEsperado then return registro end

    local lista = sexoEsperado == 'feminino' and FSPRecords.Npc.femaleNames or FSPRecords.Npc.maleNames
    local novoNome = escolher(lista) or (sexoEsperado == 'feminino' and 'Ana' or 'João')
    local sobrenome = trim(registro.sobrenome)
    if sobrenome == '' then sobrenome = escolher(FSPRecords.Npc.surnames) or 'Silva' end

    registro.sexo = sexoEsperado
    registro.nome = novoNome
    registro.sobrenome = sobrenome
    registro.nome_completo = (novoNome .. ' ' .. sobrenome):gsub('%s+$', '')

    local id = tonumber(registro.record_id)
    if id then
        MySQL.update.await([[
            UPDATE `fivepd_sp_records` PARTITION (`p_records_persons`)
            SET `sexo` = ?, `nome` = ?
            WHERE `id` = ? AND `subject_type` = 'npc'
        ]], { sexoEsperado, novoNome, id })
    end

    local key = trim(registro.npc_key)
    if key ~= '' and npcMemoriaPorRef[key] then
        npcMemoriaPorRef[key].sexo = sexoEsperado
        npcMemoriaPorRef[key].nome = novoNome
        npcMemoriaPorRef[key].sobrenome = sobrenome
        npcMemoriaPorRef[key].nome_completo = registro.nome_completo
    end
    if registro.rg and npcMemoriaPorRg[registro.rg] then
        npcMemoriaPorRg[registro.rg].sexo = sexoEsperado
        npcMemoriaPorRg[registro.rg].nome = novoNome
        npcMemoriaPorRg[registro.rg].sobrenome = sobrenome
        npcMemoriaPorRg[registro.rg].nome_completo = registro.nome_completo
    end

    return registro
end

local function corrigirIdadeRegistroNpc(registro, dados)
    if type(registro) ~= 'table' or type(dados) ~= 'table' then return registro end

    local minAge = tonumber(dados.idade_min)
    local maxAge = tonumber(dados.idade_max)
    if not minAge or not maxAge then return registro end
    if maxAge < minAge then minAge, maxAge = maxAge, minAge end

    local atual = tonumber(registro.idade)
    if not atual and registro.nascimento_iso then atual = idadeDeData(registro.nascimento_iso) end
    if atual and atual >= minAge and atual <= maxAge then return registro end

    local novaIdade = tonumber(dados.idade)
    if not novaIdade then
        novaIdade = math.floor((minAge + maxAge) * 0.5)
    end
    novaIdade = math.max(minAge, math.min(maxAge, math.floor(novaIdade)))

    local nascimentoIso = nascimentoPorIdade(novaIdade)
    registro.nascimento_iso = nascimentoIso
    registro.nascimento = formatarDataBr(nascimentoIso) or nascimentoIso
    registro.idade = idadeDeData(nascimentoIso) or novaIdade

    local id = tonumber(registro.record_id)
    if id then
        MySQL.update.await([[
            UPDATE `fivepd_sp_records` PARTITION (`p_records_persons`)
            SET `nascimento` = ?
            WHERE `id` = ? AND `subject_type` = 'npc'
        ]], { nascimentoIso, id })
    end

    local key = trim(registro.npc_key)
    if key ~= '' and npcMemoriaPorRef[key] then
        npcMemoriaPorRef[key].nascimento = nascimentoIso
        npcMemoriaPorRef[key].nascimento_iso = nascimentoIso
        npcMemoriaPorRef[key].idade = registro.idade
    end
    if registro.rg and npcMemoriaPorRg[registro.rg] then
        npcMemoriaPorRg[registro.rg].nascimento = nascimentoIso
        npcMemoriaPorRg[registro.rg].nascimento_iso = nascimentoIso
        npcMemoriaPorRg[registro.rg].idade = registro.idade
    end

    return registro
end

local function corrigirApresentacaoRegistroNpc(registro, dados)
    dados = type(dados) == 'table' and dados or {}
    registro = corrigirSexoRegistroNpc(registro, dados.sexo)
    registro = corrigirIdadeRegistroNpc(registro, dados)
    return registro
end


local function consultarPessoa(termo)
    aguardarBanco()
    termo = trim(termo)

    if npcMemoriaPorRg[termo] then
        return montarPessoaMemoria(npcMemoriaPorRg[termo])
    end

    if npcMemoriaPorRef[termo] then
        return montarPessoaMemoria(npcMemoriaPorRef[termo])
    end

    local row = pessoaBancoPorTermo(termo)
    if not row then
        return { encontrado = false }
    end

    return montarPessoaBanco(row)
end

local function registrarNpc(dados)
    aguardarBanco()
    dados = type(dados) == 'table' and dados or {}
    if dados.persistir == nil then
        dados.persistir = FSPRecords.Npc and FSPRecords.Npc.persistentByDefault == true
    end

    local key = trim(dados.npc_key or dados.key or dados.ref)
    if key ~= '' and npcMemoriaPorRef[key] then
        return corrigirApresentacaoRegistroNpc(montarPessoaMemoria(npcMemoriaPorRef[key]), dados)
    end

    if key ~= '' and dados.persistir == true then
        local existente = MySQL.single.await(
            'SELECT `id`, `subject_type`, `character_id`, `npc_key`, `rg`, `nome`, `sobrenome`, `nascimento`, `sexo`, `telefone`, `tipo_sanguineo`, `porte_arma`, `metadata`, `created_at`, `updated_at` FROM `fivepd_sp_records` PARTITION (`p_records_persons`) WHERE `npc_key` = ? LIMIT 1',
            { key }
        )
        if existente then
            return corrigirApresentacaoRegistroNpc(montarPessoaBanco(existente), dados)
        end
    end

    local sexo = tostring(dados.sexo or ''):lower()
    if sexo ~= 'feminino' and sexo ~= 'masculino' then
        sexo = math.random(0,1) == 1 and 'masculino' or 'feminino'
    end

    local idade = tonumber(dados.idade)
    if not idade then
        idade = math.random(FSPRecords.Npc.minAge, FSPRecords.Npc.maxAge)
    end

    local nome = trim(dados.nome)
    if nome == '' then
        nome = escolher(sexo == 'feminino' and FSPRecords.Npc.femaleNames or FSPRecords.Npc.maleNames) or 'Pessoa'
    end

    local sobrenome = trim(dados.sobrenome)
    if sobrenome == '' then
        sobrenome = escolher(FSPRecords.Npc.surnames) or 'Silva'
        if math.random(1,100) <= 35 then
            sobrenome = sobrenome .. ' ' .. (escolher(FSPRecords.Npc.surnames) or 'Santos')
        end
    end

    local nascimento = normalizarDataIso(dados.nascimento)
    if not nascimento then
        nascimento = nascimentoPorIdade(idade)
    end

    local rg = trim(dados.rg)
    if rg == '' or rgExiste(rg) then
        rg = gerarRg()
    end

    local cnh = type(dados.cnh) == 'table' and dados.cnh or gerarCnhNpc(idade)
    cnh.categories = cnh.categories or {}
    cnh.points = tonumber(cnh.points) or 0
    cnh.status = cnh.status or 'regular'

    local registro = {
        record_id = nil,
        npc_key = key ~= '' and key or nil,
        model_hash = tonumber(dados.model_hash),
        rg = rg,
        nome = nome,
        sobrenome = sobrenome,
        nome_completo = nome .. ' ' .. sobrenome,
        nascimento = nascimento,
        idade = idadeDeData(nascimento) or idade,
        sexo = sexo,
        telefone = trim(dados.telefone) ~= '' and trim(dados.telefone) or telefoneNpc(),
        tipo_sanguineo = dados.tipo_sanguineo or escolher(FSPRecords.Npc.bloodTypes) or 'O+',
        porte_arma = dados.porte_arma == true,
        cnh = cnh,
        perfil_civil = select(1, preencherPerfilCivil(
            ('npc:%s:%s'):format(key ~= '' and key or rg, rg),
            sexo,
            sobrenome,
            type(dados.perfil_civil) == 'table' and dados.perfil_civil or {}
        )),
        mandados = type(dados.mandados) == 'table' and dados.mandados or {},
        antecedentes = type(dados.antecedentes) == 'table' and dados.antecedentes or {},
        multas = type(dados.multas) == 'table' and dados.multas or {},
        veiculos = {},
        procurado = dados.procurado == true
    }

    if registro.procurado and #registro.mandados == 0 then
        registro.mandados[1] = {
            id = 0,
            reason = tostring(dados.motivo_procurado or 'Mandado em aberto'),
            status = 'ativo',
            created_at = os.time()
        }
    end

    if dados.persistir == true then
        if key == '' then
            sequenciaNpc = sequenciaNpc + 1
            key = ('npc-persistente:%s:%s'):format(os.time(), sequenciaNpc)
            registro.npc_key = key
        end

        local id = MySQL.insert.await([[
            INSERT INTO `fivepd_sp_records` PARTITION (`p_records_persons`)
                (`entity`, `subject_type`, `character_id`, `npc_key`, `rg`, `nome`, `sobrenome`, `nascimento`, `sexo`, `telefone`, `tipo_sanguineo`, `porte_arma`, `metadata`)
            VALUES (0x6669766570645f73705f7265636f7264735f706572736f6e73, 'npc', NULL, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ]], {
            key,
            registro.rg,
            registro.nome,
            registro.sobrenome,
            registro.nascimento,
            registro.sexo,
            registro.telefone,
            registro.tipo_sanguineo,
            registro.porte_arma and 1 or 0,
            json.encode({ civil_profile = registro.perfil_civil, model_hash = registro.model_hash })
        })

        registro.record_id = id
        garantirCnhBanco(id, cnh)

        for _, antecedente in ipairs(registro.antecedentes) do
            MySQL.insert.await([[
                INSERT INTO `fivepd_sp_records` PARTITION (`p_criminal_records`)
                    (`entity`, `person_id`, `kind`, `description`, `fine_amount`, `arrest_minutes`, `source_ref`)
                VALUES (0x6669766570645f73705f6372696d696e616c5f7265636f726473, ?, ?, ?, ?, ?, ?)
            ]], {
                id,
                antecedente.kind or 'registro',
                antecedente.description or antecedente.reason or 'Registro',
                tonumber(antecedente.fine_amount or antecedente.fine) or 0,
                tonumber(antecedente.arrest_minutes or antecedente.arrest_time) or 0,
                dados.source_ref
            })
        end

        for _, mandado in ipairs(registro.mandados) do
            MySQL.insert.await([[
                INSERT INTO `fivepd_sp_records` PARTITION (`p_warrants`)
                    (`entity`, `person_id`, `reason`, `status`, `source_ref`, `expires_at`)
                VALUES (0x6669766570645f73705f77617272616e7473, ?, ?, 'ativo', ?, ?)
            ]], {
                id,
                mandado.reason or 'Mandado em aberto',
                dados.source_ref,
                mandado.expires_at
            })
        end

        local persisted = MySQL.single.await(
            'SELECT `id`, `subject_type`, `character_id`, `npc_key`, `rg`, `nome`, `sobrenome`, `nascimento`, `sexo`, `telefone`, `tipo_sanguineo`, `porte_arma`, `metadata`, `created_at`, `updated_at` FROM `fivepd_sp_records` PARTITION (`p_records_persons`) WHERE `id` = ? LIMIT 1',
            { id }
        )
        return montarPessoaBanco(persisted)
    end

    sequenciaNpc = sequenciaNpc + 1
    registro.record_id = ('mem:%s'):format(sequenciaNpc)

    npcMemoriaPorRg[registro.rg] = registro
    if registro.npc_key then
        npcMemoriaPorRef[registro.npc_key] = registro
    end

    return montarPessoaMemoria(registro)
end

local function gerarChaveNpc(networkId)
    sequenciaNpc = sequenciaNpc + 1
    return ('npc:%s:%s:%s:%06d'):format(
        os.time(),
        tonumber(networkId) or 0,
        sequenciaNpc,
        math.random(0, 999999)
    )
end

local function registroNpcPorRef(ref)
    ref = trim(ref)
    if ref == '' then return nil end

    if npcMemoriaPorRef[ref] then
        return montarPessoaMemoria(npcMemoriaPorRef[ref])
    end

    local row = MySQL.single.await(
        'SELECT `id`, `subject_type`, `character_id`, `npc_key`, `rg`, `nome`, `sobrenome`, `nascimento`, `sexo`, `telefone`, `tipo_sanguineo`, `porte_arma`, `metadata`, `created_at`, `updated_at` FROM `fivepd_sp_records` PARTITION (`p_records_persons`) WHERE `npc_key` = ? LIMIT 1',
        { ref }
    )
    return row and montarPessoaBanco(row) or nil
end

local function obterOuCriarNpc(networkId, dados)
    networkId = tonumber(networkId)
    if not networkId or networkId <= 0 then return nil end
    dados = type(dados) == 'table' and dados or {}

    local entity = NetworkGetEntityFromNetworkId(networkId)
    if not entity or entity == 0 or not DoesEntityExist(entity) then
        npcPorRede[networkId] = nil
        return nil
    end
    if not tonumber(dados.model_hash) then
        dados.model_hash = GetEntityModel(entity)
    end

    local state = Entity(entity).state
    local stateKey = state and trim(state[NPC_STATE_KEY]) or ''

    -- O state bag pertence à entidade, então ele é a autoridade para impedir que
    -- a reutilização de um netId entregue os documentos de um NPC antigo.
    if stateKey ~= '' then
        local existente = registroNpcPorRef(stateKey)
        if existente then
            npcPorRede[networkId] = stateKey
            return corrigirApresentacaoRegistroNpc(existente, dados)
        end
    elseif npcPorRede[networkId] then
        npcPorRede[networkId] = nil
    end

    local emCriacao = npcCriacaoPorRede[networkId]
    if emCriacao then
        return Citizen.Await(emCriacao)
    end

    local aguardando = promise.new()
    npcCriacaoPorRede[networkId] = aguardando

    local ok, registro = pcall(function()
        if dados.persistir == nil then
            dados.persistir = FSPRecords.Npc and FSPRecords.Npc.persistentByDefault == true
        end

        local key = stateKey
        if key == '' then
            key = gerarChaveNpc(networkId)
            -- Marcamos a entidade antes do primeiro await de banco. Assim, se o
            -- netId for reciclado enquanto a gravação acontece, a entidade nova
            -- não recebe por engano a identidade que estava sendo criada.
            if state then state:set(NPC_STATE_KEY, key, true) end
        end
        dados.npc_key = key

        local criado = registrarNpc(dados)
        if not criado then return nil end

        local canonicalKey = trim(criado.npc_key or key)
        npcPorRede[networkId] = canonicalKey ~= '' and canonicalKey or criado.rg

        -- A criação pode ter aguardado o banco. Revalidamos a entidade antes de
        -- gravar o state bag para nunca aplicar a identidade a um netId reciclado.
        local atual = NetworkGetEntityFromNetworkId(networkId)
        if atual and atual ~= 0 and DoesEntityExist(atual) and GetEntityType(atual) == 1 then
            local atualState = Entity(atual).state
            local atualKey = atualState and trim(atualState[NPC_STATE_KEY]) or ''
            if atualKey == canonicalKey then
                if criado.record_id then atualState:set(NPC_STATE_RECORD, criado.record_id, true) end
                if criado.rg then atualState:set(NPC_STATE_RG, criado.rg, true) end
            elseif atualKey ~= '' then
                npcPorRede[networkId] = atualKey
            else
                npcPorRede[networkId] = nil
            end
        end

        return criado
    end)

    npcCriacaoPorRede[networkId] = nil
    if not ok then
        print(('[fivepd_sp_records] Falha ao criar/obter NPC %s: %s'):format(networkId, tostring(registro)))
        aguardando:resolve(nil)
        return nil
    end

    aguardando:resolve(registro)
    return registro
end

local function pessoaPorCharacterId(characterId)
    local row = garantirRegistroPersonagem(characterId)
    return montarPessoaBanco(row)
end

local function pessoaPorRecordId(recordId)
    recordId = tonumber(recordId)
    if not recordId then return nil end
    local row = MySQL.single.await(
        'SELECT `id`, `subject_type`, `character_id`, `npc_key`, `rg`, `nome`, `sobrenome`, `nascimento`, `sexo`, `telefone`, `tipo_sanguineo`, `porte_arma`, `metadata`, `created_at`, `updated_at` FROM `fivepd_sp_records` PARTITION (`p_records_persons`) WHERE `id` = ? LIMIT 1',
        { recordId }
    )
    return montarPessoaBanco(row)
end

local function consultarMatriculaPrisional(numero)
    aguardarBanco()
    numero = normalizarMatriculaPrisional(numero)
    if numero == '' then return nil end

    local profile = MySQL.single.await([[
        SELECT `id`, `person_id`, `prison_number`, UNIX_TIMESTAMP(`created_at`) AS `created_at`
        FROM `fivepd_sp_records` PARTITION (`p_prison_profiles`)
        WHERE UPPER(`prison_number`) = ?
        LIMIT 1
    ]], { numero })
    if not profile then return nil end

    local personId = tonumber(profile.person_id)
    local pessoa = personId and pessoaPorRecordId(personId) or nil

    local prisoes = MySQL.query.await([[
        SELECT `id`, `kind`, `description`, `arrest_minutes`, `source_ref`, UNIX_TIMESTAMP(`created_at`) AS `created_at`
        FROM `fivepd_sp_records` PARTITION (`p_criminal_records`)
        WHERE `person_id` = ? AND LOWER(`kind`) = 'prisao'
        ORDER BY `id` DESC
        LIMIT 100
    ]], { personId }) or {}

    return {
        encontrado = true,
        matricula = tostring(profile.prison_number or numero),
        criado_em = tonumber(profile.created_at),
        pessoa = pessoa,
        prisoes = prisoes,
        total_prisoes = #prisoes
    }
end

local function buscarVeiculoPorPlacaNormalizada(placa)
    placa = normalizarPlaca(placa)
    if placa == '' then return nil end

    local row = MySQL.single.await(
        'SELECT `id`, `plate`, `owner_person_id`, `model`, `display_name`, `vehicle_class`, `color_primary`, `color_secondary`, `stolen`, `impounded`, `impound_until`, `tax_due_at`, `metadata`, `created_at`, `updated_at`, `make_name`, `manufacture_year`, `origin_code`, `chassis_number`, `engine_number`, `glass_number`, `physical_chassis_number`, `physical_engine_number`, `physical_glass_number` FROM `fivepd_sp_records` PARTITION (`p_vehicle_records`) WHERE `plate` = ? LIMIT 1',
        { placa }
    )
    if row then return row end

    -- Compatibilidade com registros antigos que possam ter sido persistidos
    -- como "AAA 1111", "AAA-1111" ou "AAA 1A11".
    return MySQL.single.await([[
        SELECT `id`, `plate`, `owner_person_id`, `model`, `display_name`, `vehicle_class`, `color_primary`, `color_secondary`, `stolen`, `impounded`, `impound_until`, `tax_due_at`, `metadata`, `created_at`, `updated_at`, `make_name`, `manufacture_year`, `origin_code`, `chassis_number`, `engine_number`, `glass_number`, `physical_chassis_number`, `physical_engine_number`, `physical_glass_number` FROM `fivepd_sp_records` PARTITION (`p_vehicle_records`)
        WHERE UPPER(REPLACE(REPLACE(REPLACE(TRIM(`plate`), ' ', ''), '-', ''), '.', '')) = ?
        LIMIT 1
    ]], { placa })
end

local function serialVeicularUnico(prefixoChassi, placa, currentId)
    local candidato = hashEstavel(placa .. ':serial') % 10000
    for tentativa = 0, 9999 do
        local serial = (candidato + tentativa) % 10000
        local sufixo = ('%04d'):format(serial)
        local chassi = prefixoChassi .. sufixo
        local currentNumeric = tonumber(currentId)
        local existente
        if currentNumeric then
            existente = MySQL.scalar.await(
                'SELECT `id` FROM `fivepd_sp_records` PARTITION (`p_vehicle_records`) WHERE `chassis_number` = ? AND `id` <> ? LIMIT 1',
                { chassi, currentNumeric }
            )
        else
            existente = MySQL.scalar.await(
                'SELECT `id` FROM `fivepd_sp_records` PARTITION (`p_vehicle_records`) WHERE `chassis_number` = ? LIMIT 1',
                { chassi }
            )
        end
        if not existente then return sufixo end
    end
    return ('%04d'):format(candidato)
end

local function donoEhNpc(ownerPersonId)
    ownerPersonId = tonumber(ownerPersonId)
    if not ownerPersonId then return false end
    local tipo = MySQL.scalar.await(
        'SELECT `subject_type` FROM `fivepd_sp_records` PARTITION (`p_records_persons`) WHERE `id` = ? LIMIT 1',
        { ownerPersonId }
    )
    return tostring(tipo or '') == 'npc'
end

local function montarFamiliaIdentificacao(row)
    local modelo = trim(row.model)
    if modelo == '' then modelo = 'unknown' end
    local marca = trim(row.make_name)
    if marca == '' then marca = 'GENERIC' end
    local ano = anoFabricacaoDeterministico(modelo, row.manufacture_year)
    local origem = trim(row.origin_code)
    if origem == '' then origem = origemPorMarca(marca) end
    origem = origem:upper():sub(1, 2)
    local inicialMarca = marca:upper():match('[A-Z0-9]') or 'X'
    local familia = table.concat({ origem, marca:upper(), modelo:upper(), tostring(ano) }, '|')
    local chassiPrefixo = origem .. inicialMarca .. tokenEstavel(familia .. ':chassi', 8) .. tostring(ano):sub(-2)
    local motorPrefixo = 'M' .. inicialMarca .. tokenEstavel(familia .. ':motor', 6)
    local vidroPrefixo = 'V' .. tokenEstavel(familia .. ':vidro', 5)
    return {
        marca = marca,
        ano = ano,
        origem = origem,
        familia = familia,
        chassiPrefixo = chassiPrefixo,
        motorPrefixo = motorPrefixo,
        vidroPrefixo = vidroPrefixo
    }
end

local function garantirIdentificadoresVeiculo(row)
    if type(row) ~= 'table' then return row end
    local cfg = type(FSPRecords.VehicleIdentification) == 'table' and FSPRecords.VehicleIdentification or {}
    if cfg.enabled == false then return row end

    local familia = montarFamiliaIdentificacao(row)
    local persistente = tonumber(row.id) ~= nil
    local serial = nil

    local chassiAtual = normalizarIdentificadorVeicular(row.chassis_number)
    if #chassiAtual >= 4 then serial = chassiAtual:sub(-4) end
    if not serial or not serial:match('^%d%d%d%d$') then
        if persistente then
            serial = serialVeicularUnico(familia.chassiPrefixo, normalizarPlaca(row.plate), row.id)
        else
            serial = ('%04d'):format(hashEstavel(normalizarPlaca(row.plate) .. ':serial') % 10000)
        end
    end

    local chassi = chassiAtual ~= '' and chassiAtual or (familia.chassiPrefixo .. serial)
    local motor = normalizarIdentificadorVeicular(row.engine_number)
    if motor == '' then motor = familia.motorPrefixo .. serial end
    local vidro = normalizarIdentificadorVeicular(row.glass_number)
    if vidro == '' then vidro = familia.vidroPrefixo .. serial end

    local fisicoChassi = normalizarIdentificadorVeicular(row.physical_chassis_number)
    local fisicoMotor = normalizarIdentificadorVeicular(row.physical_engine_number)
    local fisicoVidro = normalizarIdentificadorVeicular(row.physical_glass_number)
    local fisicoJaPersistido = fisicoChassi ~= '' or fisicoMotor ~= '' or fisicoVidro ~= ''
    local persistirFisico = fisicoJaPersistido or tonumber(row.owner_person_id) ~= nil

    if persistente and (fisicoChassi == '' or fisicoMotor == '' or fisicoVidro == '') and tonumber(row.owner_person_id) then
        fisicoChassi, fisicoMotor, fisicoVidro = chassi, motor, vidro
        if donoEhNpc(row.owner_person_id) then
            local chance = math.max(0, math.min(100, tonumber(cfg.npcAdulterationChance) or 0))
            local roll = hashEstavel(normalizarPlaca(row.plate) .. ':adulteracao') % 100
            if roll < chance then
                local outroSerial = ('%04d'):format((tonumber(serial) + 137 + (hashEstavel(row.plate .. ':alt') % 7000)) % 10000)
                if outroSerial == serial then outroSerial = ('%04d'):format((tonumber(serial) + 1) % 10000) end
                local modo = hashEstavel(row.plate .. ':modo') % 5
                if modo == 0 then
                    fisicoChassi = 'RASPADO'
                elseif modo == 1 then
                    fisicoMotor = 'RASPADO'
                elseif modo == 2 then
                    fisicoMotor = familia.motorPrefixo .. outroSerial
                elseif modo == 3 then
                    fisicoVidro = familia.vidroPrefixo .. outroSerial
                else
                    fisicoChassi = familia.chassiPrefixo .. outroSerial
                    fisicoMotor = familia.motorPrefixo .. outroSerial
                end
            end
        end
    end

    if fisicoChassi == '' then fisicoChassi = chassi end
    if fisicoMotor == '' then fisicoMotor = motor end
    if fisicoVidro == '' then fisicoVidro = vidro end

    row.make_name = familia.marca
    row.manufacture_year = familia.ano
    row.origin_code = familia.origem
    row.chassis_number = chassi
    row.engine_number = motor
    row.glass_number = vidro
    row.physical_chassis_number = fisicoChassi
    row.physical_engine_number = fisicoMotor
    row.physical_glass_number = fisicoVidro

    if persistente then
        MySQL.update.await([[
            UPDATE `fivepd_sp_records` PARTITION (`p_vehicle_records`)
            SET `make_name` = ?, `manufacture_year` = ?, `origin_code` = ?,
                `chassis_number` = ?, `engine_number` = ?, `glass_number` = ?,
                `physical_chassis_number` = ?, `physical_engine_number` = ?, `physical_glass_number` = ?
            WHERE `id` = ?
        ]], {
            row.make_name, row.manufacture_year, row.origin_code,
            row.chassis_number, row.engine_number, row.glass_number,
            persistirFisico and row.physical_chassis_number or nil,
            persistirFisico and row.physical_engine_number or nil,
            persistirFisico and row.physical_glass_number or nil,
            tonumber(row.id)
        })
    end

    return row
end

local function montarVeiculoResultado(row, placaConsultada)
    if not row then return nil end
    row = garantirIdentificadoresVeiculo(row)

    local proprietario = nil
    if row.owner_snapshot then
        proprietario = row.owner_snapshot
    elseif row.owner_person_id then
        proprietario = pessoaPorRecordId(row.owner_person_id)
    end

    local placa = normalizarPlaca(row.plate or placaConsultada)
    local impounded = row.impounded == true or tonumber(row.impounded) == 1
    local stolen = row.stolen == true or tonumber(row.stolen) == 1

    return {
        encontrado = true,
        placa = placa,
        placa_formatada = formatarPlacaVisual(placa),
        id = row.id,
        model = row.model,
        modelo = row.display_name or row.model,
        marca = row.make_name,
        ano_fabricacao = tonumber(row.manufacture_year),
        origem = row.origin_code,
        chassi = row.chassis_number,
        motor = row.engine_number,
        vidros = row.glass_number,
        -- Os campos físicos são consumidos apenas pela inspeção local do veículo.
        physical_chassis_number = row.physical_chassis_number,
        physical_engine_number = row.physical_engine_number,
        physical_glass_number = row.physical_glass_number,
        vehicle_class = tonumber(row.vehicle_class),
        color_primary = tonumber(row.color_primary),
        color_secondary = tonumber(row.color_secondary),
        roubado = stolen,
        apreendido = impounded,
        impound_until = row.impound_until,
        tax_due_at = row.tax_due_at,
        proprietario = proprietario,
        metadata = jsonSeguro(row.metadata, {})
    }
end

local function consultarIdentificadorVeiculo(tipo, termo)
    aguardarBanco()
    tipo = tostring(tipo or ''):lower()
    termo = normalizarIdentificadorVeicular(termo)
    if termo == '' then return {} end

    local coluna
    if tipo == 'chassis' or tipo == 'chassi' then coluna = 'chassis_number'
    elseif tipo == 'engine' or tipo == 'motor' then coluna = 'engine_number'
    elseif tipo == 'glass' or tipo == 'vidros' or tipo == 'vidro' then coluna = 'glass_number'
    else return {} end

    -- Se a parte final estiver raspada/ilegível, o policial pode consultar
    -- somente o prefixo visível. Também aceitamos ???? ou ****.
    local prefixo = termo:gsub('[%?%*]+$', '')
    local tamanhoEsperado = coluna == 'chassis_number' and 17 or (coluna == 'engine_number' and 12 or 10)
    local parcial = prefixo ~= termo or (#prefixo >= 6 and #prefixo < tamanhoEsperado)
    local rows
    if parcial then
        rows = MySQL.query.await(
            ('SELECT `id`, `plate`, `owner_person_id`, `model`, `display_name`, `vehicle_class`, `color_primary`, `color_secondary`, `stolen`, `impounded`, `impound_until`, `tax_due_at`, `metadata`, `created_at`, `updated_at`, `make_name`, `manufacture_year`, `origin_code`, `chassis_number`, `engine_number`, `glass_number`, `physical_chassis_number`, `physical_engine_number`, `physical_glass_number` FROM `fivepd_sp_records` PARTITION (`p_vehicle_records`) WHERE `%s` LIKE ? ORDER BY `id` DESC LIMIT 25'):format(coluna),
            { prefixo .. '%' }
        ) or {}
    else
        rows = MySQL.query.await(
            ('SELECT `id`, `plate`, `owner_person_id`, `model`, `display_name`, `vehicle_class`, `color_primary`, `color_secondary`, `stolen`, `impounded`, `impound_until`, `tax_due_at`, `metadata`, `created_at`, `updated_at`, `make_name`, `manufacture_year`, `origin_code`, `chassis_number`, `engine_number`, `glass_number`, `physical_chassis_number`, `physical_engine_number`, `physical_glass_number` FROM `fivepd_sp_records` PARTITION (`p_vehicle_records`) WHERE `%s` = ? ORDER BY `id` DESC LIMIT 25'):format(coluna),
            { termo }
        ) or {}
    end

    if #rows == 0 then
        local pendentes = MySQL.query.await([[
            SELECT `id`, `plate`, `owner_person_id`, `model`, `display_name`, `vehicle_class`, `color_primary`, `color_secondary`, `stolen`, `impounded`, `impound_until`, `tax_due_at`, `metadata`, `created_at`, `updated_at`, `make_name`, `manufacture_year`, `origin_code`, `chassis_number`, `engine_number`, `glass_number`, `physical_chassis_number`, `physical_engine_number`, `physical_glass_number` FROM `fivepd_sp_records` PARTITION (`p_vehicle_records`)
            WHERE `chassis_number` IS NULL OR `engine_number` IS NULL OR `glass_number` IS NULL
            ORDER BY `id` ASC LIMIT 250
        ]]) or {}
        for _, pendingRow in ipairs(pendentes) do garantirIdentificadoresVeiculo(pendingRow) end
        if #pendentes > 0 then
            if parcial then
                rows = MySQL.query.await(
                    ('SELECT `id`, `plate`, `owner_person_id`, `model`, `display_name`, `vehicle_class`, `color_primary`, `color_secondary`, `stolen`, `impounded`, `impound_until`, `tax_due_at`, `metadata`, `created_at`, `updated_at`, `make_name`, `manufacture_year`, `origin_code`, `chassis_number`, `engine_number`, `glass_number`, `physical_chassis_number`, `physical_engine_number`, `physical_glass_number` FROM `fivepd_sp_records` PARTITION (`p_vehicle_records`) WHERE `%s` LIKE ? ORDER BY `id` DESC LIMIT 25'):format(coluna),
                    { prefixo .. '%' }
                ) or {}
            else
                rows = MySQL.query.await(
                    ('SELECT `id`, `plate`, `owner_person_id`, `model`, `display_name`, `vehicle_class`, `color_primary`, `color_secondary`, `stolen`, `impounded`, `impound_until`, `tax_due_at`, `metadata`, `created_at`, `updated_at`, `make_name`, `manufacture_year`, `origin_code`, `chassis_number`, `engine_number`, `glass_number`, `physical_chassis_number`, `physical_engine_number`, `physical_glass_number` FROM `fivepd_sp_records` PARTITION (`p_vehicle_records`) WHERE `%s` = ? ORDER BY `id` DESC LIMIT 25'):format(coluna),
                    { termo }
                ) or {}
            end
        end
    end

    local out = {}
    for _, row in ipairs(rows) do
        out[#out + 1] = montarVeiculoResultado(row)
    end
    return out
end

local function registrarVeiculo(dados)
    aguardarBanco()
    dados = type(dados) == 'table' and dados or {}
    local placa = normalizarPlaca(dados.plate or dados.placa)
    if placa == '' then return nil, 'Placa inválida.' end

    local ownerRaw = dados.owner_person_id or dados.proprietario_record_id
    local ownerId = tonumber(ownerRaw)
    local ownerSnapshot = type(dados.proprietario) == 'table' and dados.proprietario or nil
    local modelo = trim(dados.model or dados.modelo)
    if modelo == '' then modelo = 'unknown' end
    local marca = trim(dados.make_name or dados.marca)

    if dados.persistir == false then
        local registro = {
            id = ('mem:%s'):format(placa),
            plate = placa,
            owner_person_id = ownerId,
            owner_snapshot = ownerSnapshot,
            model = modelo,
            make_name = marca ~= '' and marca or 'GENERIC',
            manufacture_year = tonumber(dados.manufacture_year or dados.ano_fabricacao),
            origin_code = dados.origin_code or dados.origem,
            display_name = dados.display_name or dados.nome_modelo or modelo,
            vehicle_class = tonumber(dados.vehicle_class or dados.classe),
            color_primary = tonumber(dados.color_primary),
            color_secondary = tonumber(dados.color_secondary),
            stolen = dados.stolen == true or dados.roubado == true,
            impounded = dados.impounded == true or dados.apreendido == true,
            tax_due_at = dados.tax_due_at,
            metadata = dados.metadata or {}
        }
        garantirIdentificadoresVeiculo(registro)
        veiculosMemoria[placa] = registro
        return registro
    end

    -- Antes do UPSERT exato, procuramos registros legados cuja placa tenha
    -- sido persistida com espaço/hífen. Assim não criamos duplicata só porque
    -- a representação visual da placa mudou.
    local existente = buscarVeiculoPorPlacaNormalizada(placa)
    if existente and tonumber(existente.id) then
        MySQL.update.await([[
            UPDATE `fivepd_sp_records` PARTITION (`p_vehicle_records`)
            SET `plate` = ?,
                `owner_person_id` = COALESCE(?, `owner_person_id`),
                `model` = ?,
                `make_name` = COALESCE(NULLIF(?, ''), `make_name`),
                `manufacture_year` = COALESCE(?, `manufacture_year`),
                `origin_code` = COALESCE(NULLIF(?, ''), `origin_code`),
                `display_name` = ?, `vehicle_class` = ?, `color_primary` = ?, `color_secondary` = ?,
                `stolen` = ?, `impounded` = ?, `impound_until` = ?, `tax_due_at` = ?, `metadata` = ?
            WHERE `id` = ?
        ]], {
            placa, ownerId, modelo, marca, tonumber(dados.manufacture_year or dados.ano_fabricacao),
            trim(dados.origin_code or dados.origem), dados.display_name or dados.nome_modelo,
            tonumber(dados.vehicle_class or dados.classe), tonumber(dados.color_primary), tonumber(dados.color_secondary),
            (dados.stolen == true or dados.roubado == true) and 1 or 0,
            (dados.impounded == true or dados.apreendido == true) and 1 or 0,
            dados.impound_until, dados.tax_due_at, json.encode(dados.metadata or {}), tonumber(existente.id)
        })
    else
        MySQL.query.await([[
            INSERT INTO `fivepd_sp_records` PARTITION (`p_vehicle_records`)
                (`entity`, `plate`, `owner_person_id`, `model`, `make_name`, `manufacture_year`, `origin_code`, `display_name`,
                 `vehicle_class`, `color_primary`, `color_secondary`, `stolen`, `impounded`, `impound_until`, `tax_due_at`, `metadata`)
            VALUES (0x6669766570645f73705f76656869636c655f7265636f726473, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE
                `owner_person_id` = COALESCE(VALUES(`owner_person_id`), `owner_person_id`),
                `model` = VALUES(`model`),
                `make_name` = COALESCE(NULLIF(VALUES(`make_name`), ''), `make_name`),
                `manufacture_year` = COALESCE(VALUES(`manufacture_year`), `manufacture_year`),
                `origin_code` = COALESCE(NULLIF(VALUES(`origin_code`), ''), `origin_code`),
                `display_name` = VALUES(`display_name`),
                `vehicle_class` = VALUES(`vehicle_class`),
                `color_primary` = VALUES(`color_primary`),
                `color_secondary` = VALUES(`color_secondary`),
                `stolen` = VALUES(`stolen`),
                `impounded` = VALUES(`impounded`),
                `impound_until` = VALUES(`impound_until`),
                `tax_due_at` = VALUES(`tax_due_at`),
                `metadata` = VALUES(`metadata`)
        ]], {
            placa, ownerId, modelo, marca ~= '' and marca or nil,
            tonumber(dados.manufacture_year or dados.ano_fabricacao), trim(dados.origin_code or dados.origem) ~= '' and trim(dados.origin_code or dados.origem) or nil,
            dados.display_name or dados.nome_modelo, tonumber(dados.vehicle_class or dados.classe),
            tonumber(dados.color_primary), tonumber(dados.color_secondary),
            (dados.stolen == true or dados.roubado == true) and 1 or 0,
            (dados.impounded == true or dados.apreendido == true) and 1 or 0,
            dados.impound_until, dados.tax_due_at, json.encode(dados.metadata or {})
        })
    end

    local row = buscarVeiculoPorPlacaNormalizada(placa)
    return row and garantirIdentificadoresVeiculo(row) or nil
end

local function consultarPlaca(placa)
    aguardarBanco()
    placa = normalizarPlaca(placa)
    if placa == '' then return { encontrado = false } end

    local row = veiculosMemoria[placa]
    if not row then row = buscarVeiculoPorPlacaNormalizada(placa) end
    if not row then return { encontrado = false, placa = placa, placa_formatada = formatarPlacaVisual(placa) } end

    return montarVeiculoResultado(row, placa)
end

local function veiculosDoPersonagem(characterId)
    local pessoa = pessoaPorCharacterId(characterId)
    if not pessoa then return {} end
    return veiculosBancoPorPessoa(pessoa.record_id)
end


local function transferirVeiculoPersonagem(placa, characterId)
    aguardarBanco()

    placa =
        normalizarPlaca(placa)

    characterId =
        tonumber(characterId)

    if placa == ''
        or not characterId
    then
        return false
    end

    local pessoa =
        pessoaPorCharacterId(
            characterId
        )

    if not pessoa
        or not pessoa.encontrado
        or not tonumber(pessoa.record_id)
    then
        return false
    end

    local changed =
        MySQL.update.await([[
            UPDATE `fivepd_sp_records` PARTITION (`p_vehicle_records`)
            SET `owner_person_id` = ?
            WHERE `plate` = ?
        ]], {
            tonumber(
                pessoa.record_id
            ),
            placa
        })

    return tonumber(changed or 0) > 0
end

local function atualizarVeiculo(placa, alteracoes)
    placa = normalizarPlaca(placa)
    alteracoes = type(alteracoes) == 'table' and alteracoes or {}

    local sets = {}
    local params = {}
    local mapa = {
        stolen = 'stolen',
        roubado = 'stolen',
        impounded = 'impounded',
        apreendido = 'impounded',
        impound_until = 'impound_until',
        tax_due_at = 'tax_due_at'
    }

    local usados = {}
    for chave, coluna in pairs(mapa) do
        if alteracoes[chave] ~= nil and not usados[coluna] then
            usados[coluna] = true
            sets[#sets+1] = ('`%s` = ?'):format(coluna)
            local v = alteracoes[chave]
            if coluna == 'stolen' or coluna == 'impounded' then
                v = v == true and 1 or (v == false and 0 or tonumber(v) or 0)
            end
            params[#params+1] = v
        end
    end

    if tonumber(alteracoes.tax_due_days) then
        sets[#sets+1] = '`tax_due_at` = DATE_ADD(NOW(), INTERVAL ? DAY)'
        params[#params+1] = math.max(1, math.floor(tonumber(alteracoes.tax_due_days)))
    end

    if #sets == 0 then return false end
    params[#params+1] = placa

    local changed = MySQL.update.await(
        ('UPDATE `fivepd_sp_records` PARTITION (`p_vehicle_records`) SET %s WHERE `plate` = ?'):format(table.concat(sets, ', ')),
        params
    )
    return tonumber(changed) and tonumber(changed) > 0
end

local function resolverPessoa(valor)
    if type(valor) == 'table' and valor.encontrado then
        return valor
    end

    if type(valor) == 'table' then
        if valor.rg then return consultarPessoa(valor.rg) end
        if valor.character_id then return pessoaPorCharacterId(valor.character_id) end
    end

    return consultarPessoa(valor)
end

local function adicionarAntecedente(alvo, dados)
    dados = type(dados) == 'table' and dados or {}
    local pessoa = resolverPessoa(alvo)
    if not pessoa or not pessoa.encontrado then return false end

    local registro = {
        kind = tostring(dados.kind or dados.tipo or 'registro'),
        description = tostring(dados.description or dados.descricao or dados.reason or 'Registro'),
        fine_amount = tonumber(dados.fine_amount or dados.multa) or 0,
        arrest_minutes = tonumber(dados.arrest_minutes or dados.prisao_minutos) or 0,
        created_at = os.time()
    }

    if tonumber(pessoa.record_id) then
        local criminalId = MySQL.insert.await([[
            INSERT INTO `fivepd_sp_records` PARTITION (`p_criminal_records`)
                (`entity`, `person_id`, `kind`, `description`, `fine_amount`, `arrest_minutes`, `source_ref`)
            VALUES (0x6669766570645f73705f6372696d696e616c5f7265636f726473, ?, ?, ?, ?, ?, ?)
        ]], {
            tonumber(pessoa.record_id),
            registro.kind,
            registro.description,
            registro.fine_amount,
            registro.arrest_minutes,
            dados.source_ref
        })
        if not criminalId then return false end
        if tostring(registro.kind or ''):lower() == 'prisao' then
            garantirMatriculaPrisional(tonumber(pessoa.record_id))
        end
        return true
    end

    local mem = pessoa.rg and npcMemoriaPorRg[pessoa.rg] or nil
    if mem then
        mem.antecedentes[#mem.antecedentes + 1] = registro
        return true
    end

    return false
end

local function adicionarMandado(alvo, dados)
    dados = type(dados) == 'table' and dados or {}
    local pessoa = resolverPessoa(alvo)
    if not pessoa or not pessoa.encontrado then return false end

    local registro = {
        id = 0,
        reason = tostring(dados.reason or dados.motivo or 'Mandado em aberto'),
        status = 'ativo',
        created_at = os.time(),
        expires_at = dados.expires_at
    }

    if tonumber(pessoa.record_id) then
        MySQL.insert.await([[
            INSERT INTO `fivepd_sp_records` PARTITION (`p_warrants`)
                (`entity`, `person_id`, `reason`, `status`, `source_ref`, `expires_at`)
            VALUES (0x6669766570645f73705f77617272616e7473, ?, ?, 'ativo', ?, ?)
        ]], {
            tonumber(pessoa.record_id),
            registro.reason,
            dados.source_ref,
            dados.expires_at
        })
        return true
    end

    local mem = pessoa.rg and npcMemoriaPorRg[pessoa.rg] or nil
    if mem then
        mem.mandados[#mem.mandados + 1] = registro
        mem.procurado = true
        return true
    end

    return false
end

local function adicionarMulta(alvo, dados)
    dados = type(dados) == 'table' and dados or {}
    local pessoa = resolverPessoa(alvo)
    if not pessoa or not pessoa.encontrado then return false end

    local amount = math.max(0, math.floor(tonumber(dados.amount or dados.valor) or 0))
    local reason = tostring(dados.reason or dados.motivo or 'Infração')

    if tonumber(pessoa.record_id) then
        MySQL.insert.await([[
            INSERT INTO `fivepd_sp_records` PARTITION (`p_fines`)
                (`entity`, `person_id`, `reason`, `amount`, `paid`, `source_ref`)
            VALUES (0x6669766570645f73705f66696e6573, ?, ?, ?, 0, ?)
        ]], {
            tonumber(pessoa.record_id),
            reason,
            amount,
            dados.source_ref
        })
        return true
    end

    local mem = pessoa.rg and npcMemoriaPorRg[pessoa.rg] or nil
    if mem then
        mem.multas[#mem.multas + 1] = {
            id = 0,
            reason = reason,
            amount = amount,
            paid = 0,
            created_at = os.time()
        }
        return true
    end

    return false
end

local function registrarArma(dados)
    dados = type(dados) == 'table' and dados or {}
    local serial = trim(dados.serial):upper()
    if serial == '' then return false end

    local ownerId = tonumber(dados.owner_person_id)
    if not ownerId and dados.proprietario then
        local pessoa = resolverPessoa(dados.proprietario)
        ownerId = pessoa and tonumber(pessoa.record_id) or nil
    end

    MySQL.query.await([[
        INSERT INTO `fivepd_sp_records` PARTITION (`p_weapon_records`)
            (`entity`, `serial`, `owner_person_id`, `weapon_name`, `status`, `metadata`)
        VALUES (0x6669766570645f73705f776561706f6e5f7265636f726473, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            `owner_person_id` = VALUES(`owner_person_id`),
            `weapon_name` = VALUES(`weapon_name`),
            `status` = VALUES(`status`),
            `metadata` = VALUES(`metadata`)
    ]], {
        serial,
        ownerId,
        tostring(dados.weapon_name or dados.nome or dados.weapon or 'Arma'),
        tostring(dados.status or 'regular'),
        json.encode(dados.metadata or {})
    })

    return true
end

local function consultarArma(serial)
    serial = trim(serial):upper()
    if serial == '' then return { encontrado = false } end

    local row = MySQL.single.await(
        'SELECT `id`, `serial`, `owner_person_id`, `weapon_name`, `status`, `metadata`, `created_at`, `updated_at` FROM `fivepd_sp_records` PARTITION (`p_weapon_records`) WHERE `serial` = ? LIMIT 1',
        { serial }
    )
    if not row then return { encontrado = false } end

    return {
        encontrado = true,
        serial = row.serial,
        weapon_name = row.weapon_name,
        status = row.status,
        proprietario = row.owner_person_id and pessoaPorRecordId(row.owner_person_id) or nil,
        metadata = jsonSeguro(row.metadata, {})
    }
end

local function listarProcurados(limite)
    limite = math.max(1, math.min(100, tonumber(limite) or 20))
    local rows = MySQL.query.await([[
        SELECT DISTINCT p.*
        FROM `fivepd_sp_records` PARTITION (`p_records_persons`) p
        INNER JOIN `fivepd_sp_records` PARTITION (`p_warrants`) w ON w.`person_id` = p.`id`
        WHERE w.`status` = 'ativo' AND (w.`expires_at` IS NULL OR w.`expires_at` > NOW())
        ORDER BY p.`updated_at` DESC
        LIMIT ?
    ]], { limite }) or {}

    local out = {}
    for _, row in ipairs(rows) do
        out[#out+1] = montarPessoaBanco(row)
    end

    for _, mem in pairs(npcMemoriaPorRg) do
        if mem.procurado == true or #(mem.mandados or {}) > 0 then
            out[#out+1] = montarPessoaMemoria(mem)
            if #out >= limite then break end
        end
    end

    return out
end

local function registrarVeiculoPersonagem(characterId, dados)
    local pessoa = pessoaPorCharacterId(characterId)
    if not pessoa then return nil, 'Personagem não encontrado.' end

    dados = type(dados) == 'table' and dados or {}
    dados.owner_person_id = pessoa.record_id
    dados.persistir = dados.persistir ~= false
    return registrarVeiculo(dados)
end

local function registrarVeiculoNpc(npc, dados)
    if type(npc) ~= 'table' then
        return nil, 'Registro de NPC inválido.'
    end

    dados = type(dados) == 'table' and dados or {}
    dados.proprietario = npc

    if tonumber(npc.record_id) then
        dados.owner_person_id = tonumber(npc.record_id)
        if dados.persistir == nil then dados.persistir = true end
    else
        dados.persistir = false
    end

    local veiculo, erro = registrarVeiculo(dados)
    if veiculo and type(npc.veiculos) == 'table' then
        npc.veiculos[#npc.veiculos + 1] = veiculo
    end
    return veiculo, erro
end


local BICYCLE_STATE_REGISTRATION = 'fivepd_sp:records:bicycleRegistration'

local function normalizarRegistroBicicleta(value)
    value = trim(value):upper():gsub('%s+', '')
    value = value:gsub('[^A-Z0-9%-]', '')
    if value:match('^%d+$') then
        value = 'BI-' .. value
    elseif value:match('^BI%d+$') then
        value = 'BI-' .. value:sub(3)
    end
    local prefix, digits = value:match('^(BI%-)(%d+)$')
    if prefix and digits then
        value = prefix .. string.format('%08d', tonumber(digits) or 0)
    end
    return value
end

local function montarBicicletaResultado(row)
    if type(row) ~= 'table' then return nil end
    local owner = tonumber(row.owner_person_id) and pessoaPorRecordId(row.owner_person_id) or nil
    return {
        encontrado = true,
        tipo = 'bicycle',
        id = tonumber(row.id),
        registro = tostring(row.registration or ''),
        model = row.model,
        modelo = row.display_name or row.model,
        color_primary = tonumber(row.color_primary),
        color_secondary = tonumber(row.color_secondary),
        roubada = tonumber(row.stolen) == 1,
        proprietario = owner,
        metadata = jsonSeguro(row.metadata, {}),
        created_at = row.created_at
    }
end

local function consultarBicicleta(registration)
    aguardarBanco()
    registration = normalizarRegistroBicicleta(registration)
    if registration == '' then return nil end
    local row = MySQL.single.await([[
        SELECT `id`, `registration`, `model`, `display_name`, `owner_person_id`, `color_primary`, `color_secondary`, `stolen`, `metadata`, `created_at`, `updated_at` FROM `fivepd_sp_records` PARTITION (`p_bicycle_records`)
        WHERE UPPER(`registration`) = ?
        LIMIT 1
    ]], { registration })
    return montarBicicletaResultado(row)
end

local function garantirBicicletaEntidade(entidade, dados)
    if not entidade or entidade == 0 or not DoesEntityExist(entidade) or GetEntityType(entidade) ~= 2 then return nil end
    dados = type(dados) == 'table' and dados or {}
    local state = Entity(entidade).state
    local existenteNumero = state and normalizarRegistroBicicleta(state[BICYCLE_STATE_REGISTRATION]) or ''
    if existenteNumero ~= '' then
        local existente = consultarBicicleta(existenteNumero)
        if existente then return existente end
    end

    local model = trim(dados.model)
    if model == '' then model = tostring(GetEntityModel(entidade) or 0) end
    local id = MySQL.insert.await([[
        INSERT INTO `fivepd_sp_records` PARTITION (`p_bicycle_records`)
            (`entity`, `stolen`, `model`, `display_name`, `color_primary`, `color_secondary`, `metadata`)
        VALUES (0x6669766570645f73705f62696379636c655f7265636f726473, 0, ?, NULLIF(?, ''), ?, ?, ?)
    ]], {
        model:sub(1,64), trim(dados.display_name):sub(1,96),
        tonumber(dados.color_primary), tonumber(dados.color_secondary),
        json.encode({ source = 'world_entity' })
    })
    if not id then return nil end

    local registration = ('BI-%08d'):format(tonumber(id) or 0)
    MySQL.update.await('UPDATE `fivepd_sp_records` PARTITION (`p_bicycle_records`) SET `registration`=? WHERE `id`=?', { registration, id })
    if state then state:set(BICYCLE_STATE_REGISTRATION, registration, true) end
    return consultarBicicleta(registration)
end

local function sincronizarIdentificacaoFisicaEntidade(entidade, registro)
    if not entidade or entidade == 0 or not DoesEntityExist(entidade) or type(registro) ~= 'table' then return end
    local state = Entity(entidade).state
    if not state then return end
    state:set('fivepd_sp:records:plate', registro.placa or registro.plate or '', true)
    state:set('fivepd_sp:records:chassisPhysical', registro.physical_chassis_number or registro.chassi or '', true)
    state:set('fivepd_sp:records:enginePhysical', registro.physical_engine_number or registro.motor or '', true)
    state:set('fivepd_sp:records:glassPhysical', registro.physical_glass_number or registro.vidros or '', true)
end


local bicicletaCriacaoPorRede = {}

RegisterNetEvent('fivepd_sp:records:solicitarBicicleta', function(requestId, networkId, dados)
    local src = source
    networkId = tonumber(networkId)
    local entidade = networkId and NetworkGetEntityFromNetworkId(networkId) or 0
    local playerPed = GetPlayerPed(src)
    if playerPed == 0 or entidade == 0 or not DoesEntityExist(entidade) or GetEntityType(entidade) ~= 2 then
        TriggerClientEvent('fivepd_sp:records:bicicletaResposta', src, requestId, nil)
        return
    end
    if type(GetVehicleClass) == 'function' then
        local okClass, vehicleClass = pcall(GetVehicleClass, entidade)
        if okClass and tonumber(vehicleClass) ~= 13 then
            TriggerClientEvent('fivepd_sp:records:bicicletaResposta', src, requestId, nil)
            return
        end
    end
    if #(GetEntityCoords(playerPed) - GetEntityCoords(entidade)) > 55.0 then
        TriggerClientEvent('fivepd_sp:records:bicicletaResposta', src, requestId, nil)
        return
    end

    -- Mais de um policial/jogador pode streamar a mesma bicicleta no mesmo
    -- instante. Serializamos a criação por netId para nunca gerar dois números
    -- de registro para a mesma entidade.
    local pending = bicicletaCriacaoPorRede[networkId]
    if pending then
        local record = Citizen.Await(pending)
        TriggerClientEvent('fivepd_sp:records:bicicletaResposta', src, requestId, record)
        return
    end

    local promiseRecord = promise.new()
    bicicletaCriacaoPorRede[networkId] = promiseRecord
    local ok, record = pcall(garantirBicicletaEntidade, entidade, dados)
    bicicletaCriacaoPorRede[networkId] = nil
    if not ok then
        print(('[fivepd_sp_records] Falha ao registrar bicicleta %s: %s'):format(tostring(networkId), tostring(record)))
        record = nil
    end
    promiseRecord:resolve(record)
    TriggerClientEvent('fivepd_sp:records:bicicletaResposta', src, requestId, record)
end)

RegisterNetEvent('fivepd_sp:records:solicitarVeiculo', function(requestId, networkId, dados)
    local src = source
    networkId = tonumber(networkId)
    if not networkId then
        TriggerClientEvent('fivepd_sp:records:veiculoResposta', src, requestId, nil)
        return
    end

    local playerPed = GetPlayerPed(src)
    local entidade = NetworkGetEntityFromNetworkId(networkId)
    if playerPed == 0 or entidade == 0 or not DoesEntityExist(entidade) or GetEntityType(entidade) ~= 2 then
        TriggerClientEvent('fivepd_sp:records:veiculoResposta', src, requestId, nil)
        return
    end

    if #(GetEntityCoords(playerPed) - GetEntityCoords(entidade)) > 35.0 then
        TriggerClientEvent('fivepd_sp:records:veiculoResposta', src, requestId, nil)
        return
    end

    dados = type(dados) == 'table' and dados or {}
    local placaFisica = normalizarPlaca(dados.plate or dados.placa)
    if placaFisica == '' then
        TriggerClientEvent('fivepd_sp:records:veiculoResposta', src, requestId, nil)
        return
    end

    -- Veículos adulterados pelo sistema ilegal preservam a identificação
    -- registral verdadeira no StateBag. A placa visível continua sendo a
    -- placa física do veículo, mas chassi/motor consultam o registro original.
    local state = Entity(entidade).state
    local placaVerdadeira = state and normalizarPlaca(state['fivepd_sp:records:truePlate']) or ''
    local placa = placaVerdadeira ~= '' and placaVerdadeira or placaFisica

    local existente = consultarPlaca(placa)
    if existente and existente.encontrado then
        -- Uma revista veicular pode cadastrar a placa antes de os documentos do
        -- condutor serem solicitados. Nesse caso vinculamos o proprietário depois,
        -- sem tocar em roubo, apreensão, tributos ou qualquer outro histórico.
        local ownerId = tonumber(dados.owner_person_id or dados.proprietario_record_id)
        if ownerId and not existente.proprietario then
            if veiculosMemoria[placa] then
                veiculosMemoria[placa].owner_person_id = ownerId
                veiculosMemoria[placa].owner_snapshot = pessoaPorRecordId(ownerId)
            else
                MySQL.update.await([[
                    UPDATE `fivepd_sp_records` PARTITION (`p_vehicle_records`)
                    SET `owner_person_id` = ?
                    WHERE `id` = ? AND `owner_person_id` IS NULL
                ]], { ownerId, tonumber(existente.id) })
            end
            existente = consultarPlaca(placa)
        end

        sincronizarIdentificacaoFisicaEntidade(entidade, existente)
        TriggerClientEvent('fivepd_sp:records:veiculoResposta', src, requestId, existente)
        return
    end

    dados.plate = placa
    if dados.persistir == nil then dados.persistir = true end
    local registro = registrarVeiculo(dados)
    local resposta = registro and consultarPlaca(placa) or nil
    if resposta then sincronizarIdentificacaoFisicaEntidade(entidade, resposta) end
    TriggerClientEvent('fivepd_sp:records:veiculoResposta', src, requestId, resposta)
end)

RegisterNetEvent('fivepd_sp:records:solicitarNpc', function(requestId, networkId, dados)
    local src = source
    networkId = tonumber(networkId)
    if not networkId then
        TriggerClientEvent('fivepd_sp:records:npcResposta', src, requestId, nil)
        return
    end

    local playerPed = GetPlayerPed(src)
    local entidade = NetworkGetEntityFromNetworkId(networkId)
    if playerPed == 0 or entidade == 0 or not DoesEntityExist(entidade) or GetEntityType(entidade) ~= 1 then
        TriggerClientEvent('fivepd_sp:records:npcResposta', src, requestId, nil)
        return
    end

    local pcoords = GetEntityCoords(playerPed)
    local ecoords = GetEntityCoords(entidade)
    if #(pcoords - ecoords) > 25.0 then
        TriggerClientEvent('fivepd_sp:records:npcResposta', src, requestId, nil)
        return
    end

    local registro = obterOuCriarNpc(networkId, dados)
    TriggerClientEvent('fivepd_sp:records:npcResposta', src, requestId, registro)
end)

AddEventHandler('fivepd_sp:personagem:criadoServidor', function(_, personagem)
    if personagem and personagem.id then
        garantirRegistroPersonagem(personagem.id)
    end
end)

AddEventHandler('fivepd_sp:server:personagemCarregado', function(_, personagem)
    if personagem and personagem.id then
        garantirRegistroPersonagem(personagem.id)
    end
end)

CreateThread(function()
    aguardarBanco()
    Wait(1000)

    -- Migração 25 adiciona as numerações oficiais. Registros antigos são
    -- preenchidos de forma determinística para continuarem consultáveis.
    local veiculosAntigos = MySQL.query.await([[
        SELECT `id`, `plate`, `owner_person_id`, `model`, `display_name`, `vehicle_class`, `color_primary`, `color_secondary`, `stolen`, `impounded`, `impound_until`, `tax_due_at`, `metadata`, `created_at`, `updated_at`, `make_name`, `manufacture_year`, `origin_code`, `chassis_number`, `engine_number`, `glass_number`, `physical_chassis_number`, `physical_engine_number`, `physical_glass_number` FROM `fivepd_sp_records` PARTITION (`p_vehicle_records`)
        WHERE `chassis_number` IS NULL OR `engine_number` IS NULL OR `glass_number` IS NULL
        ORDER BY `id` ASC
    ]]) or {}
    for _, row in ipairs(veiculosAntigos) do
        local ok, err = pcall(garantirIdentificadoresVeiculo, row)
        if not ok then
            print(('[fivepd_sp_records] Falha ao gerar identificação do veículo %s: %s'):format(tostring(row.plate), tostring(err)))
        end
        Wait(0)
    end

    for _, playerSource in ipairs(GetPlayers()) do
        local id = exports.fivepd_sp_core:ObterPersonagemId(tonumber(playerSource))
        if id then
            garantirRegistroPersonagem(id)
        end
    end
end)


local function bopmTexto(value, limite)
    local texto = tostring(value or '')
    texto = texto:gsub('%z', ''):gsub('^%s+', ''):gsub('%s+$', '')
    if limite and #texto > limite then texto = texto:sub(1, limite) end
    return texto
end


local function bopmLista(value, limiteItens, limiteTexto)
    local out = {}
    if type(value) ~= 'table' then return out end
    for _, item in ipairs(value) do
        if #out >= (limiteItens or 24) then break end
        local text = bopmTexto(item, limiteTexto or 64)
        if text ~= '' then out[#out + 1] = text end
    end
    return out
end

local function bopmEnum(value, permitidos, padrao)
    value = bopmTexto(value, 40):lower()
    return permitidos[value] and value or padrao
end

local function sanitizarBopmForm(value)
    value = type(value) == 'table' and value or {}
    return {
        recordType = bopmEnum(value.recordType, { bopm = true, tcopm = true }, 'bopm'),
        subtype = bopmEnum(value.subtype, { transito = true, ambiental = true, outros = true }, 'outros'),
        communicationTime = bopmTexto(value.communicationTime, 8),
        communicationOrigin = bopmEnum(value.communicationOrigin, {
            via_siopm = true, diretamente_us = true, us_deparou = true, via_sma = true
        }, 'us_deparou'),
        requesterName = bopmTexto(value.requesterName, 120),
        requesterQualified = bopmEnum(value.requesterQualified, { sim = true, nao = true }, 'nao'),
        providedAddress = bopmTexto(value.providedAddress, 180),
        providedCity = bopmTexto(value.providedCity, 120),
        requesterPhone = bopmTexto(value.requesterPhone, 40),
        requesterEmail = bopmTexto(value.requesterEmail, 120),
        nature = bopmTexto(value.nature, 180),
        occurrenceCode = bopmTexto(value.occurrenceCode, 64),
        legalBasis = bopmTexto(value.legalBasis, 300),
        legalComplement = bopmTexto(value.legalComplement, 300),
        serviceUnit = bopmTexto(value.serviceUnit, 120),
        factDate = bopmTexto(value.factDate, 10),
        weekDay = bopmTexto(value.weekDay, 32),
        factTime = bopmTexto(value.factTime, 8),
        localTime = bopmTexto(value.localTime, 8),
        endTime = bopmTexto(value.endTime, 8),
        placeType = bopmTexto(value.placeType, 80),
        street = bopmTexto(value.street, 180),
        addressComplement = bopmTexto(value.addressComplement, 180),
        municipality = bopmTexto(value.municipality, 120),
        cep = bopmTexto(value.cep, 12),
        referencePoint = bopmTexto(value.referencePoint, 180),
        latitude = tonumber(value.latitude),
        longitude = tonumber(value.longitude),
        otherLocation = bopmTexto(value.otherLocation, 250),
        relatedDocuments = bopmTexto(value.relatedDocuments, 250),
        placeCharacteristics = bopmLista(value.placeCharacteristics, 16, 64),
        environment = bopmEnum(value.environment, {
            externo = true, interno = true, preservado = true, nao_preservado = true
        }, 'externo'),
        lighting = bopmLista(value.lighting, 12, 64),
        weather = bopmLista(value.weather, 10, 64),
        attachments = bopmLista(value.attachments, 16, 64),
        crimes = bopmLista(value.crimes, 24, 64),
        sentenceMinutes = math.max(0, math.floor(tonumber(value.sentenceMinutes) or 0)),
        narrative = bopmTexto(value.narrative, 8000)
    }
end

local function registrarBopm(alvo, dados)
    aguardarBanco()
    dados = type(dados) == 'table' and dados or {}
    local form = sanitizarBopmForm(dados.form)
    local pessoa = resolverPessoa(alvo)
    if not pessoa or not pessoa.encontrado or not tonumber(pessoa.record_id) then
        return { ok = false, error = 'Registro civil do suspeito não encontrado.' }
    end

    local numero = bopmTexto(dados.number or dados.numero, 64)
    local natureza = bopmTexto(form.nature or form.natureza, 180)
    local enquadramento = bopmTexto(form.legalBasis or form.enquadramento_legal, 300)
    local historico = bopmTexto(form.narrative or form.historico, 8000)
    if numero == '' then return { ok = false, error = 'Número do BOPM inválido.' } end
    if natureza == '' then return { ok = false, error = 'Informe a natureza da ocorrência.' } end
    if enquadramento == '' then return { ok = false, error = 'Informe o enquadramento legal.' } end
    if historico == '' then return { ok = false, error = 'Preencha o histórico da ocorrência.' } end

    local officer = type(dados.officer) == 'table' and dados.officer or {}
    local suspectSnapshot = {
        record_id = tonumber(pessoa.record_id),
        rg = pessoa.rg,
        nome = pessoa.nome,
        sobrenome = pessoa.sobrenome,
        nome_completo = pessoa.nome_completo,
        nascimento = pessoa.nascimento,
        nascimento_iso = pessoa.nascimento_iso,
        idade = pessoa.idade,
        sexo = pessoa.sexo,
        telefone = pessoa.telefone,
        cnh = pessoa.cnh
    }

    local factDate = bopmTexto(form.factDate or form.data_fato, 10)
    if factDate == '' or not factDate:match('^%d%d%d%d%-%d%d%-%d%d$') then factDate = nil end
    local latitude = tonumber(form.latitude)
    local longitude = tonumber(form.longitude)

    local id = MySQL.insert.await([[
        INSERT INTO `fivepd_sp_records` PARTITION (`p_bopm_records`)
            (`entity`, `concluded_at`, `number`, `person_id`, `officer_character_id`, `officer_name`, `officer_prefix`,
             `corporation_code`, `corporation_label`, `unit_code`, `unit_label`, `record_type`,
             `subtype`, `communication_origin`, `nature`, `occurrence_code`, `legal_basis`,
             `service_unit`, `fact_date`, `fact_time`, `street`, `address_complement`,
             `municipality`, `reference_point`, `latitude`, `longitude`, `narrative`,
             `suspect_snapshot`, `form_payload`, `status`)
        VALUES (0x6669766570645f73705f626f706d5f7265636f726473, CURRENT_TIMESTAMP, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'concluido')
    ]], {
        numero,
        tonumber(pessoa.record_id),
        tonumber(officer.characterId),
        bopmTexto(officer.name, 120),
        bopmTexto(officer.prefix, 32) ~= '' and bopmTexto(officer.prefix, 32) or nil,
        bopmTexto(officer.corporationCode, 24) ~= '' and bopmTexto(officer.corporationCode, 24) or nil,
        bopmTexto(officer.corporationLabel, 120) ~= '' and bopmTexto(officer.corporationLabel, 120) or nil,
        bopmTexto(officer.unitCode, 24) ~= '' and bopmTexto(officer.unitCode, 24) or nil,
        bopmTexto(officer.unitLabel, 120) ~= '' and bopmTexto(officer.unitLabel, 120) or nil,
        bopmTexto(form.recordType, 16) ~= '' and bopmTexto(form.recordType, 16) or 'bopm',
        bopmTexto(form.subtype, 24) ~= '' and bopmTexto(form.subtype, 24) or 'outros',
        bopmTexto(form.communicationOrigin, 32) ~= '' and bopmTexto(form.communicationOrigin, 32) or 'us_deparou',
        natureza,
        bopmTexto(form.occurrenceCode, 64) ~= '' and bopmTexto(form.occurrenceCode, 64) or nil,
        enquadramento,
        bopmTexto(form.serviceUnit, 120) ~= '' and bopmTexto(form.serviceUnit, 120) or nil,
        factDate,
        bopmTexto(form.factTime, 8) ~= '' and bopmTexto(form.factTime, 8) or nil,
        bopmTexto(form.street, 180) ~= '' and bopmTexto(form.street, 180) or nil,
        bopmTexto(form.addressComplement, 180) ~= '' and bopmTexto(form.addressComplement, 180) or nil,
        bopmTexto(form.municipality, 120) ~= '' and bopmTexto(form.municipality, 120) or nil,
        bopmTexto(form.referencePoint, 180) ~= '' and bopmTexto(form.referencePoint, 180) or nil,
        latitude,
        longitude,
        historico,
        json.encode(suspectSnapshot),
        json.encode(form)
    })

    if not id then return { ok = false, error = 'Não foi possível gravar o BOPM.' } end

    local isTcopm = tostring(form.recordType or ''):lower() == 'tcopm'
    local arrestMinutes = isTcopm and 0 or math.max(0, math.floor(tonumber(dados.arrestMinutes or form.sentenceMinutes) or 0))
    local crimes = type(dados.crimes) == 'table' and dados.crimes or form.crimes or {}
    local crimeLabels = {}
    for _, crime in ipairs(crimes) do
        local label = type(crime) == 'table' and bopmTexto(crime.label or crime.id, 80) or bopmTexto(crime, 80)
        if label ~= '' then crimeLabels[#crimeLabels + 1] = label end
        if #crimeLabels >= 16 then break end
    end
    local crimeSuffix = #crimeLabels > 0 and (' • ' .. table.concat(crimeLabels, ', ')) or ''
    local procedureLabel = isTcopm and 'TCOPM' or 'BOPM'
    local kind = isTcopm and 'tcopm' or 'prisao'
    local actionLabel = isTcopm and 'Termo circunstanciado' or 'Prisão'
    local descricao = ('%s %s • %s • %s • %s%s'):format(procedureLabel, numero, actionLabel, natureza, enquadramento, crimeSuffix)
    if #descricao > 500 then descricao = descricao:sub(1, 500) end
    local criminalOk, criminalId = pcall(function()
        return MySQL.insert.await([[
            INSERT INTO `fivepd_sp_records` PARTITION (`p_criminal_records`)
                (`entity`, `person_id`, `kind`, `description`, `fine_amount`, `arrest_minutes`, `source_ref`)
            VALUES (0x6669766570645f73705f6372696d696e616c5f7265636f726473, ?, ?, ?, 0, ?, ?)
        ]], {
            tonumber(pessoa.record_id),
            kind,
            descricao,
            arrestMinutes,
            ('%s:%s'):format(procedureLabel, numero)
        })
    end)
    if not criminalOk or not criminalId then
        MySQL.query.await('DELETE FROM `fivepd_sp_records` PARTITION (`p_bopm_records`) WHERE `id` = ?', { id })
        return { ok = false, error = isTcopm and 'Não foi possível vincular o TCOPM ao histórico do RG.' or 'Não foi possível vincular a prisão ao histórico do RG.' }
    end

    local perfilPrisional = nil
    if not isTcopm then
        -- A matrícula prisional nasce na primeira prisão e permanece vinculada
        -- ao registro civil daquele jogador/NPC para prisões futuras.
        perfilPrisional = garantirMatriculaPrisional(tonumber(pessoa.record_id))
        if perfilPrisional then pessoa.matricula_prisional = perfilPrisional.prison_number end
    end

    return {
        ok = true,
        id = tonumber(id),
        number = numero,
        record_type = form.recordType,
        person = pessoa,
        matricula_prisional = perfilPrisional and perfilPrisional.prison_number or nil
    }
end


local function registrarBopmEvidencia(dados)
    aguardarBanco()
    dados = type(dados) == 'table' and dados or {}
    local form = sanitizarBopmForm(dados.form)
    local numero = bopmTexto(dados.number or dados.numero, 64)
    local natureza = bopmTexto(form.nature or form.natureza, 180)
    local enquadramento = bopmTexto(form.legalBasis or form.enquadramento_legal, 300)
    local historico = bopmTexto(form.narrative or form.historico, 8000)
    if numero == '' then return { ok = false, error = 'Número do BOPM inválido.' } end
    if natureza == '' then return { ok = false, error = 'Informe a natureza da ocorrência.' } end
    if enquadramento == '' then return { ok = false, error = 'Informe o enquadramento legal.' } end
    if historico == '' then return { ok = false, error = 'Preencha o histórico da ocorrência.' } end

    local officer = type(dados.officer) == 'table' and dados.officer or {}
    local evidence = type(dados.evidence) == 'table' and dados.evidence or {}
    local factDate = bopmTexto(form.factDate or form.data_fato, 10)
    if factDate == '' or not factDate:match('^%d%d%d%d%-%d%d%-%d%d$') then factDate = nil end
    local id = MySQL.insert.await([[
        INSERT INTO `fivepd_sp_records` PARTITION (`p_bopm_records`)
            (`entity`, `concluded_at`, `number`, `person_id`, `officer_character_id`, `officer_name`, `officer_prefix`,
             `corporation_code`, `corporation_label`, `unit_code`, `unit_label`, `record_type`,
             `subtype`, `communication_origin`, `nature`, `occurrence_code`, `legal_basis`,
             `service_unit`, `fact_date`, `fact_time`, `street`, `address_complement`,
             `municipality`, `reference_point`, `latitude`, `longitude`, `narrative`,
             `suspect_snapshot`, `form_payload`, `status`)
        VALUES (0x6669766570645f73705f626f706d5f7265636f726473, CURRENT_TIMESTAMP, ?, NULL, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'concluido')
    ]], {
        numero,
        tonumber(officer.characterId),
        bopmTexto(officer.name, 120),
        bopmTexto(officer.prefix, 32) ~= '' and bopmTexto(officer.prefix, 32) or nil,
        bopmTexto(officer.corporationCode, 24) ~= '' and bopmTexto(officer.corporationCode, 24) or nil,
        bopmTexto(officer.corporationLabel, 120) ~= '' and bopmTexto(officer.corporationLabel, 120) or nil,
        bopmTexto(officer.unitCode, 24) ~= '' and bopmTexto(officer.unitCode, 24) or nil,
        bopmTexto(officer.unitLabel, 120) ~= '' and bopmTexto(officer.unitLabel, 120) or nil,
        bopmTexto(form.recordType, 16) ~= '' and bopmTexto(form.recordType, 16) or 'bopm',
        bopmTexto(form.subtype, 24) ~= '' and bopmTexto(form.subtype, 24) or 'outros',
        bopmTexto(form.communicationOrigin, 32) ~= '' and bopmTexto(form.communicationOrigin, 32) or 'us_deparou',
        natureza,
        bopmTexto(form.occurrenceCode, 64) ~= '' and bopmTexto(form.occurrenceCode, 64) or nil,
        enquadramento,
        bopmTexto(form.serviceUnit, 120) ~= '' and bopmTexto(form.serviceUnit, 120) or nil,
        factDate,
        bopmTexto(form.factTime, 8) ~= '' and bopmTexto(form.factTime, 8) or nil,
        bopmTexto(form.street, 180) ~= '' and bopmTexto(form.street, 180) or nil,
        bopmTexto(form.addressComplement, 180) ~= '' and bopmTexto(form.addressComplement, 180) or nil,
        bopmTexto(form.municipality, 120) ~= '' and bopmTexto(form.municipality, 120) or nil,
        bopmTexto(form.referencePoint, 180) ~= '' and bopmTexto(form.referencePoint, 180) or nil,
        tonumber(form.latitude), tonumber(form.longitude), historico,
        json.encode({ evidence = evidence, kind = 'drug_bag_seizure' }),
        json.encode(form)
    })
    if not id then return { ok = false, error = 'Não foi possível gravar o BOPM de apreensão.' } end
    return { ok = true, id = tonumber(id), number = numero }
end

exports('GarantirRegistroPersonagem', garantirRegistroPersonagem)
exports('ConsultarPessoa', consultarPessoa)
exports('PessoaPorPersonagem', pessoaPorCharacterId)
exports('PessoaPorRecordId', pessoaPorRecordId)
exports('RegistrarNPC', registrarNpc)
exports('ObterOuCriarNPC', obterOuCriarNpc)
exports('ConsultarPlaca', consultarPlaca)
exports('ConsultarIdentificadorVeiculo', consultarIdentificadorVeiculo)
exports('ConsultarBicicleta', consultarBicicleta)
exports('ConsultarMatriculaPrisional', consultarMatriculaPrisional)
exports('GarantirMatriculaPrisional', garantirMatriculaPrisional)
exports('RegistrarVeiculo', registrarVeiculo)
exports('RegistrarVeiculoPersonagem', registrarVeiculoPersonagem)
exports('RegistrarVeiculoNPC', registrarVeiculoNpc)
exports('VeiculosDoPersonagem', veiculosDoPersonagem)
exports('TransferirVeiculoPersonagem', transferirVeiculoPersonagem)
exports('AtualizarVeiculo', atualizarVeiculo)
exports('AdicionarAntecedente', adicionarAntecedente)
exports('AdicionarMandado', adicionarMandado)
exports('AdicionarMulta', adicionarMulta)
exports('RegistrarArma', registrarArma)
exports('ConsultarArma', consultarArma)
exports('ListarProcurados', listarProcurados)
exports('RegistrarBOPM', registrarBopm)
exports('RegistrarBOPMEvidencia', registrarBopmEvidencia)
