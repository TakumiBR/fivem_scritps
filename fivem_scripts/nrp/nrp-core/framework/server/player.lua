-- NRP Player Manager
-- Gerenciamento de dados do jogador (criação, carregamento, salvamento)

local Players = {} -- Tabela para armazenar dados dos jogadores conectados

-- Função para verificar se o jogador já tem personagem
function NRP.Player.HasCharacter(source)
    local license = NRP.GetIdentifier(source, 'license')
    if not license then
        return false
    end
    
    local result = MySQL.scalar.await('SELECT COUNT(*) as count FROM nrp_players WHERE identifier = ?', {license})
    return result > 0
end

-- Função para obter todos os personagens de um jogador (multichar)
function NRP.Player.GetCharacters(source)
    local license = NRP.GetIdentifier(source, 'license')
    if not license then
        return {}
    end
    
    local characters = MySQL.query.await('SELECT * FROM nrp_players WHERE identifier = ?', {license})
    return characters or {}
end

-- Função para criar novo personagem
function NRP.Player.CreateCharacter(source, data)
    local license = NRP.GetIdentifier(source, 'license')
    if not license then
        return false, 'Identificador não encontrado'
    end
    
    -- Validar nome e sobrenome
    local valid, err = NRP.ValidateName(data.firstname, false)
    if not valid then
        return false, err
    end
    
    valid, err = NRP.ValidateName(data.lastname, true)
    if not valid then
        return false, err
    end
    
    -- Verificar duplicidade de Nome + Sobrenome
    local duplicate = MySQL.scalar.await(
        'SELECT COUNT(*) as count FROM nrp_players WHERE firstname = ? AND lastname = ?',
        {data.firstname, data.lastname}
    )
    
    if duplicate > 0 then
        return false, 'Este nome já está em uso por outro jogador'
    end
    
    -- Inserir no banco de dados
    local result = MySQL.insert.await(
        'INSERT INTO nrp_players (identifier, firstname, lastname, nationalid, dob, gender, cash, bank, blackmoney) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        {
            license,
            data.firstname,
            data.lastname,
            data.nationalid,
            data.dob,
            data.gender,
            Config.Economy.DefaultCash,
            Config.Economy.DefaultBank,
            Config.Economy.DefaultBlackMoney
        }
    )
    
    if result then
        return true, result
    else
        return false, 'Erro ao criar personagem'
    end
end

-- Função para carregar dados do jogador
function NRP.Player.LoadPlayer(source, charId)
    local license = NRP.GetIdentifier(source, 'license')
    if not license then
        return false
    end
    
    local playerData = MySQL.single.await('SELECT * FROM nrp_players WHERE id = ? AND identifier = ?', {charId, license})
    
    if not playerData then
        return false
    end
    
    -- Armazenar dados na tabela Players
    Players[source] = {
        id = playerData.id,
        identifier = playerData.identifier,
        firstname = playerData.firstname,
        lastname = playerData.lastname,
        nationalid = playerData.nationalid,
        dob = playerData.dob,
        gender = playerData.gender,
        cash = playerData.cash,
        bank = playerData.bank,
        blackmoney = playerData.blackmoney,
        metadata = json.decode(playerData.metadata or '{}'),
        appearance = json.decode(playerData.appearance or '{}')
    }
    
    return true
end

-- Função para salvar dados do jogador
function NRP.Player.SavePlayer(source)
    if not Players[source] then
        return false
    end
    
    local playerData = Players[source]
    
    MySQL.update.await(
        'UPDATE nrp_players SET cash = ?, bank = ?, blackmoney = ?, metadata = ?, appearance = ? WHERE id = ?',
        {
            playerData.cash,
            playerData.bank,
            playerData.blackmoney,
            json.encode(playerData.metadata),
            json.encode(playerData.appearance),
            playerData.id
        }
    )
    
    return true
end

-- Função para obter dados do jogador
function NRP.Player.GetPlayer(source)
    return Players[source]
end

-- Função para remover jogador da memória (ao desconectar)
function NRP.Player.RemovePlayer(source)
    if Players[source] then
        -- Salvar antes de remover
        NRP.Player.SavePlayer(source)
        Players[source] = nil
    end
end

-- Evento de conexão
AddEventHandler('playerConnecting', function(name, setKickReason, deferrals)
    local source = source
    deferrals.defer()
    
    Wait(100)
    deferrals.update('Verificando dados do jogador...')
    
    Wait(100)
    local hasChar = NRP.Player.HasCharacter(source)
    
    if not hasChar then
        deferrals.done('create') -- Sinaliza que precisa criar personagem
    else
        deferrals.done('multichar') -- Sinaliza que deve mostrar tela de seleção
    end
end)

-- Evento de desconexão
AddEventHandler('playerDropped', function(reason)
    local source = source
    NRP.Player.RemovePlayer(source)
end)

-- Export para outros scripts acessarem dados do jogador
exports('GetPlayer', function(source)
    return Players[source]
end)

exports('HasCharacter', NRP.Player.HasCharacter)
exports('GetCharacters', NRP.Player.GetCharacters)
exports('CreateCharacter', NRP.Player.CreateCharacter)
exports('LoadPlayer', NRP.Player.LoadPlayer)
exports('SavePlayer', NRP.Player.SavePlayer)
