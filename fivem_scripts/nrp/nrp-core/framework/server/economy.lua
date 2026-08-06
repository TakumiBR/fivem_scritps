-- NRP Economy Manager
-- Gerenciamento de economia (Cash, Bank, Black Money)

-- Função para adicionar dinheiro
function NRP.Economy.AddMoney(source, type, amount)
    local playerData = NRP.Player.GetPlayer(source)
    if not playerData then
        return false, 'Jogador não encontrado'
    end
    
    amount = tonumber(amount)
    if not amount or amount <= 0 then
        return false, 'Valor inválido'
    end
    
    if type == 'cash' then
        playerData.cash = (playerData.cash or 0) + amount
    elseif type == 'bank' then
        playerData.bank = (playerData.bank or 0) + amount
    elseif type == 'black' then
        playerData.blackmoney = (playerData.blackmoney or 0) + amount
    else
        return false, 'Tipo de moeda inválido'
    end
    
    -- Notificar cliente para atualizar HUD
    TriggerClientEvent('nrp:economy:update', source, type, playerData[type])
    
    return true
end

-- Função para remover dinheiro
function NRP.Economy.RemoveMoney(source, type, amount)
    local playerData = NRP.Player.GetPlayer(source)
    if not playerData then
        return false, 'Jogador não encontrado'
    end
    
    amount = tonumber(amount)
    if not amount or amount <= 0 then
        return false, 'Valor inválido'
    end
    
    local currentAmount = 0
    if type == 'cash' then
        currentAmount = playerData.cash or 0
    elseif type == 'bank' then
        currentAmount = playerData.bank or 0
    elseif type == 'black' then
        currentAmount = playerData.blackmoney or 0
    else
        return false, 'Tipo de moeda inválido'
    end
    
    if currentAmount < amount then
        return false, 'Saldo insuficiente'
    end
    
    if type == 'cash' then
        playerData.cash = currentAmount - amount
    elseif type == 'bank' then
        playerData.bank = currentAmount - amount
    elseif type == 'black' then
        playerData.blackmoney = currentAmount - amount
    end
    
    -- Notificar cliente para atualizar HUD
    TriggerClientEvent('nrp:economy:update', source, type, playerData[type])
    
    return true
end

-- Função para obter saldo
function NRP.Economy.GetMoney(source, type)
    local playerData = NRP.Player.GetPlayer(source)
    if not playerData then
        return 0
    end
    
    if type == 'cash' then
        return playerData.cash or 0
    elseif type == 'bank' then
        return playerData.bank or 0
    elseif type == 'black' then
        return playerData.blackmoney or 0
    end
    
    return 0
end

-- Função para definir valor exato de dinheiro
function NRP.Economy.SetMoney(source, type, amount)
    local playerData = NRP.Player.GetPlayer(source)
    if not playerData then
        return false, 'Jogador não encontrado'
    end
    
    amount = tonumber(amount)
    if not amount or amount < 0 then
        return false, 'Valor inválido'
    end
    
    if type == 'cash' then
        playerData.cash = amount
    elseif type == 'bank' then
        playerData.bank = amount
    elseif type == 'black' then
        playerData.blackmoney = amount
    else
        return false, 'Tipo de moeda inválido'
    end
    
    -- Notificar cliente para atualizar HUD
    TriggerClientEvent('nrp:economy:update', source, type, playerData[type])
    
    return true
end

-- Função para transferir dinheiro entre jogadores
function NRP.Economy.TransferMoney(fromSource, toSource, type, amount)
    local success, err = NRP.Economy.RemoveMoney(fromSource, type, amount)
    if not success then
        return false, err
    end
    
    success, err = NRP.Economy.AddMoney(toSource, type, amount)
    if not success then
        -- Reembolsar em caso de falha
        NRP.Economy.AddMoney(fromSource, type, amount)
        return false, err
    end
    
    return true
end

-- Evento para solicitar atualização da HUD ao carregar jogador
RegisterNetEvent('nrp:economy:requestUpdate', function()
    local source = source
    local playerData = NRP.Player.GetPlayer(source)
    if playerData then
        TriggerClientEvent('nrp:economy:updateAll', source, {
            cash = playerData.cash,
            bank = playerData.bank,
            blackmoney = playerData.blackmoney
        })
    end
end)

-- Exports
exports('AddMoney', NRP.Economy.AddMoney)
exports('RemoveMoney', NRP.Economy.RemoveMoney)
exports('GetMoney', NRP.Economy.GetMoney)
exports('SetMoney', NRP.Economy.SetMoney)
exports('TransferMoney', NRP.Economy.TransferMoney)
