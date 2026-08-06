-- NRP HUD Manager
-- Atualização da HUD de economia e status do jogador

local playerMoney = {
    cash = 0,
    bank = 0,
    blackmoney = 0
}

-- Função para atualizar dinheiro na HUD
function UpdateMoneyHUD(type, amount)
    if type == 'cash' then
        playerMoney.cash = amount
    elseif type == 'bank' then
        playerMoney.bank = amount
    elseif type == 'black' then
        playerMoney.blackmoney = amount
    end
    
    -- Enviar atualização para a HUD (se houver um script de HUD ativo)
    SendNUIMessage({
        action = 'updateMoney',
        type = type,
        amount = amount
    })
    
    -- Debug
    if Config.DebugMode then
        print('[NRP HUD] Dinheiro atualizado:', type, amount)
    end
end

-- Evento para atualizar um tipo específico de dinheiro
RegisterNetEvent('nrp:economy:update', function(type, amount)
    UpdateMoneyHUD(type, amount)
end)

-- Evento para atualizar todos os tipos de dinheiro
RegisterNetEvent('nrp:economy:updateAll', function(moneyData)
    playerMoney.cash = moneyData.cash or 0
    playerMoney.bank = moneyData.bank or 0
    playerMoney.blackmoney = moneyData.blackmoney or 0
    
    SendNUIMessage({
        action = 'updateAllMoney',
        data = moneyData
    })
    
    if Config.DebugMode then
        print('[NRP HUD] Todos os valores atualizados:', json.encode(moneyData))
    end
end)

-- Solicitar atualização ao conectar
Citizen.CreateThread(function()
    Wait(5000)
    TriggerServerEvent('nrp:economy:requestUpdate')
end)

-- Export functions
exports('GetMoney', function(type)
    return playerMoney[type] or 0
end)

exports('GetAllMoney', function()
    return playerMoney
end)

exports('UpdateMoneyHUD', UpdateMoneyHUD)
