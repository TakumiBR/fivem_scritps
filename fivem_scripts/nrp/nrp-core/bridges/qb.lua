-- NRP Bridge: QB-Core Compatibility Layer
-- Esta camada permite que scripts feitos para QB-Core funcionem na NRP Core
-- sem necessidade de modificação no código fonte original.

-- Criar tabela global QBCore (proxy)
QBCore = setmetatable({}, {
    __index = function(self, key)
        -- Redirecionar chamadas para a NRP Core
        if key == 'Functions' then
            return {
                GetPlayer = function(source)
                    local playerData = NRP.Player.GetPlayer(source)
                    if not playerData then
                        return nil
                    end
                    
                    -- Retornar objeto compatível com QB-Core
                    local qbPlayer = {
                        PlayerData = {
                            citizenid = playerData.citizenid or ('NRP' .. playerData.id),
                            cid = playerData.id,
                            license = playerData.identifier,
                            name = playerData.firstname .. ' ' .. playerData.lastname,
                            firstname = playerData.firstname,
                            lastname = playerData.lastname,
                            nationalid = playerData.nationalid,
                            dob = playerData.dob,
                            gender = playerData.gender,
                            job = playerData.job or {name = 'unemployed', label = 'Civil', grade = {level = 0}},
                            gang = playerData.gang or {name = 'none', label = 'No Gang', grade = {level = 0}},
                            metadata = playerData.metadata or {},
                            charinfo = {
                                firstname = playerData.firstname,
                                lastname = playerData.lastname,
                                nationalid = playerData.nationalid,
                                birthdate = playerData.dob,
                                gender = playerData.gender,
                                account = 'NRP' .. math.random(100000, 999999)
                            },
                            money = {
                                cash = NRP.Economy.GetMoney(source, 'cash'),
                                bank = NRP.Economy.GetMoney(source, 'bank'),
                                crypto = 0
                            }
                        },
                        
                        Functions = {
                            AddMoney = function(moneyType, amount, reason)
                                if moneyType == 'cash' then
                                    return NRP.Economy.AddMoney(source, 'cash', amount)
                                elseif moneyType == 'bank' then
                                    return NRP.Economy.AddMoney(source, 'bank', amount)
                                elseif moneyType == 'crypto' then
                                    return true -- Placeholder para crypto
                                end
                                return false
                            end,
                            
                            RemoveMoney = function(moneyType, amount, reason)
                                if moneyType == 'cash' then
                                    return NRP.Economy.RemoveMoney(source, 'cash', amount)
                                elseif moneyType == 'bank' then
                                    return NRP.Economy.RemoveMoney(source, 'bank', amount)
                                elseif moneyType == 'crypto' then
                                    return true -- Placeholder para crypto
                                end
                                return false
                            end,
                            
                            GetMoney = function(moneyType)
                                if moneyType == 'cash' then
                                    return NRP.Economy.GetMoney(source, 'cash')
                                elseif moneyType == 'bank' then
                                    return NRP.Economy.GetMoney(source, 'bank')
                                elseif moneyType == 'crypto' then
                                    return 0
                                end
                                return 0
                            end,
                            
                            SetMetaData = function(meta, value)
                                playerData.metadata = playerData.metadata or {}
                                playerData.metadata[meta] = value
                                return true
                            end,
                            
                            GetMetaData = function(meta)
                                return playerData.metadata and playerData.metadata[meta] or nil
                            end,
                            
                            AddItem = function(item, amount, slot, info)
                                -- Placeholder para inventário
                                return true
                            end,
                            
                            RemoveItem = function(item, amount, slot)
                                -- Placeholder para inventário
                                return true
                            end,
                            
                            GetItemByName = function(item)
                                -- Placeholder para inventário
                                return nil
                            end,
                            
                            GetItemsByName = function(item)
                                -- Placeholder para inventário
                                return {}
                            end,
                            
                            ClearInventory = function(filter)
                                -- Placeholder para inventário
                                return true
                            end,
                            
                            SetInventory = function(inventory)
                                -- Placeholder para inventário
                                return true
                            end,
                            
                            AddWeapon = function(weapon, ammo, attach)
                                -- Placeholder para armas
                                return true
                            end,
                            
                            RemoveWeapon = function(weapon)
                                -- Placeholder para armas
                                return true
                            end,
                            
                            HasWeapon = function(weapon)
                                -- Placeholder para armas
                                return false
                            end,
                            
                            ClearWeapons = function()
                                -- Placeholder para armas
                                return true
                            end,
                            
                            AddMethod = function(name, cb)
                                -- Placeholder para métodos
                            end,
                            
                            AddJob = function(jobName, grade)
                                playerData.job = {name = jobName, grade = grade}
                                return true
                            end,
                            
                            SetJob = function(job, grade)
                                playerData.job = {name = job, grade = {level = grade or 0}}
                                TriggerClientEvent('QBCore:Client:SetPlayerJob', source, playerData.job)
                                return true
                            end,
                            
                            SetGang = function(gang, grade)
                                playerData.gang = {name = gang, grade = {level = grade or 0}}
                                TriggerClientEvent('QBCore:Client:SetPlayerGang', source, playerData.gang)
                                return true
                            end,
                            
                            ShowNotification = function(msg)
                                TriggerClientEvent('QBCore:Notify', source, msg)
                            end,
                            
                            TriggerEvent = function(eventName, ...)
                                TriggerClientEvent(eventName, source, ...)
                            end
                        }
                    }
                    
                    return qbPlayer
                end,
                
                GetPlayers = function()
                    local players = {}
                    for _, player in ipairs(GetPlayers()) do
                        local source = tonumber(player)
                        local playerData = NRP.Player.GetPlayer(source)
                        if playerData then
                            table.insert(players, source)
                        end
                    end
                    return players
                end,
                
                GetPlayerByCitizenId = function(citizenid)
                    for _, player in ipairs(GetPlayers()) do
                        local source = tonumber(player)
                        local playerData = NRP.Player.GetPlayer(source)
                        if playerData and (playerData.citizenid == citizenid or ('NRP' .. playerData.id) == citizenid) then
                            return QBCore.Functions.GetPlayer(source)
                        end
                    end
                    return nil
                end,
                
                GetPlayerByLicense = function(license)
                    for _, player in ipairs(GetPlayers()) do
                        local source = tonumber(player)
                        local playerData = NRP.Player.GetPlayer(source)
                        if playerData and playerData.identifier == license then
                            return QBCore.Functions.GetPlayer(source)
                        end
                    end
                    return nil
                end,
                
                GetPlayerByName = function(name)
                    for _, player in ipairs(GetPlayers()) do
                        local source = tonumber(player)
                        local playerData = NRP.Player.GetPlayer(source)
                        if playerData and string.find(playerData.firstname .. ' ' .. playerData.lastname, name) then
                            return QBCore.Functions.GetPlayer(source)
                        end
                    end
                    return nil
                end,
                
                Notify = function(msg, type, length)
                    -- Notificação global
                    for _, player in ipairs(GetPlayers()) do
                        local source = tonumber(player)
                        TriggerClientEvent('QBCore:Notify', source, msg, type, length)
                    end
                end,
                
                Callback = {
                    RegisterCallback = function(key, cb)
                        -- Placeholder para callbacks
                    end,
                    
                    TriggerCallback = function(key, cb, ...)
                        -- Placeholder para callbacks
                        cb(nil)
                    end
                }
            }
        elseif key == 'Config' then
            return {
                Server = {
                    Name = Config.ServerName
                }
            }
        end
        
        return rawget(self, key)
    end
})

-- Eventos de compatibilidade QB-Core
RegisterNetEvent('QBCore:SetPlayerJob', function(job, grade)
    local source = source
    local playerData = NRP.Player.GetPlayer(source)
    if playerData then
        playerData.job = {name = job, grade = {level = grade or 0}}
    end
end)

RegisterNetEvent('QBCore:SetPlayerGang', function(gang, grade)
    local source = source
    local playerData = NRP.Player.GetPlayer(source)
    if playerData then
        playerData.gang = {name = gang, grade = {level = grade or 0}}
    end
end)

print('[NRP Bridge] QB-Core compatibility layer loaded')
