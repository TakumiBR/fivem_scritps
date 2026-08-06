-- NRP Bridge: QBox Compatibility Layer
-- Esta camada permite que scripts feitos para QBox funcionem na NRP Core
-- sem necessidade de modificação no código fonte original.

-- Criar tabela global QB (proxy para QBox)
QB = setmetatable({}, {
    __index = function(self, key)
        -- Redirecionar chamadas para a NRP Core (similar ao QB-Core)
        if key == 'Functions' then
            return {
                GetPlayer = function(source)
                    local playerData = NRP.Player.GetPlayer(source)
                    if not playerData then
                        return nil
                    end
                    
                    -- Retornar objeto compatível com QBox
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
                                return NRP.Economy.AddMoney(source, moneyType, amount)
                            end,
                            
                            RemoveMoney = function(moneyType, amount, reason)
                                return NRP.Economy.RemoveMoney(source, moneyType, amount)
                            end,
                            
                            GetMoney = function(moneyType)
                                return NRP.Economy.GetMoney(source, moneyType)
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
                                -- Placeholder para inventário QBox
                                return true
                            end,
                            
                            RemoveItem = function(item, amount, slot)
                                -- Placeholder para inventário QBox
                                return true
                            end,
                            
                            GetItemByName = function(item)
                                -- Placeholder para inventário QBox
                                return nil
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
                            return QB.Functions.GetPlayer(source)
                        end
                    end
                    return nil
                end,
                
                Notify = function(msg, type, length)
                    for _, player in ipairs(GetPlayers()) do
                        local source = tonumber(player)
                        TriggerClientEvent('QBCore:Notify', source, msg, type, length)
                    end
                end
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

print('[NRP Bridge] QBox compatibility layer loaded')
