-- NRP Bridge: ESX Compatibility Layer
-- Esta camada permite que scripts feitos para ESX funcionem na NRP Core
-- sem necessidade de modificação no código fonte original.

-- Criar tabela global ESX (proxy)
ESX = setmetatable({}, {
    __index = function(self, key)
        -- Redirecionar chamadas para a NRP Core
        if key == 'GetPlayerFromId' then
            return function(source)
                local playerData = NRP.Player.GetPlayer(source)
                if not playerData then
                    return nil
                end
                
                -- Retornar objeto compatível com ESX
                return {
                    identifier = playerData.identifier,
                    name = playerData.firstname .. ' ' .. playerData.lastname,
                    firstname = playerData.firstname,
                    lastname = playerData.lastname,
                    job = playerData.job or {label = 'Unemployed', grade = 0},
                    
                    -- Funções de economia compatíveis com ESX
                    addMoney = function(amount)
                        return NRP.Economy.AddMoney(source, 'cash', amount)
                    end,
                    
                    addAccountMoney = function(account, amount)
                        if account == 'bank' then
                            return NRP.Economy.AddMoney(source, 'bank', amount)
                        elseif account == 'black_money' then
                            return NRP.Economy.AddMoney(source, 'black', amount)
                        end
                        return NRP.Economy.AddMoney(source, 'cash', amount)
                    end,
                    
                    removeMoney = function(amount)
                        return NRP.Economy.RemoveMoney(source, 'cash', amount)
                    end,
                    
                    removeAccountMoney = function(account, amount)
                        if account == 'bank' then
                            return NRP.Economy.RemoveMoney(source, 'bank', amount)
                        elseif account == 'black_money' then
                            return NRP.Economy.RemoveMoney(source, 'black', amount)
                        end
                        return NRP.Economy.RemoveMoney(source, 'cash', amount)
                    end,
                    
                    getMoney = function()
                        return NRP.Economy.GetMoney(source, 'cash')
                    end,
                    
                    getAccount = function(account)
                        local amount = 0
                        if account == 'bank' then
                            amount = NRP.Economy.GetMoney(source, 'bank')
                        elseif account == 'black_money' then
                            amount = NRP.Economy.GetMoney(source, 'black')
                        else
                            amount = NRP.Economy.GetMoney(source, 'cash')
                        end
                        
                        return {money = amount}
                    end,
                    
                    getLoadout = function()
                        return playerData.loadout or {}
                    end,
                    
                    addInventoryItem = function(item, count)
                        -- Placeholder para inventário
                        return true
                    end,
                    
                    removeInventoryItem = function(item, count)
                        -- Placeholder para inventário
                        return true
                    end,
                    
                    getInventoryItem = function(item)
                        -- Placeholder para inventário
                        return {count = 0}
                    end,
                    
                    showNotification = function(msg)
                        TriggerClientEvent('esx:showNotification', source, msg)
                    end,
                    
                    showAdvancedNotification = function(title, subtitle, msg, icon)
                        TriggerClientEvent('esx:showAdvancedNotification', source, title, subtitle, msg, icon)
                    end,
                    
                    triggerEvent = function(eventName, ...)
                        TriggerClientEvent(eventName, source, ...)
                    end
                }
            end
        elseif key == 'GetPlayerFromIdentifier' then
            return function(identifier)
                -- Buscar jogador pelo identifier
                for _, player in ipairs(GetPlayers()) do
                    local source = tonumber(player)
                    local playerData = NRP.Player.GetPlayer(source)
                    if playerData and playerData.identifier == identifier then
                        return ESX.GetPlayerFromId(source)
                    end
                end
                return nil
            end
        elseif key == 'GetPlayers' then
            return function()
                local players = {}
                for _, player in ipairs(GetPlayers()) do
                    local source = tonumber(player)
                    local playerData = NRP.Player.GetPlayer(source)
                    if playerData then
                        table.insert(players, source)
                    end
                end
                return players
            end
        elseif key == 'RegisterUsableItem' then
            return function(item, cb)
                -- Placeholder para itens usáveis
            end
        elseif key == 'UseItem' then
            return function(source, item, data)
                -- Placeholder para uso de itens
            end
        end
        
        return rawget(self, key)
    end
})

-- Eventos de compatibilidade ESX
RegisterNetEvent('esx:setJob', function(jobName, grade)
    local source = source
    local playerData = NRP.Player.GetPlayer(source)
    if playerData then
        playerData.job = {name = jobName, grade = grade}
    end
end)

print('[NRP Bridge] ESX compatibility layer loaded')
