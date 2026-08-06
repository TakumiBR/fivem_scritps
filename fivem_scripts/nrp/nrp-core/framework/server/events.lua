-- NRP Events Manager
-- Gerenciamento de eventos nativos do FiveM e eventos da framework

-- Evento para spawnar jogador após seleção/criação
RegisterNetEvent('nrp:spawnPlayer', function(spawnCoords)
    local source = source
    local playerPed = GetPlayerPed(source)
    
    if spawnCoords then
        SetEntityCoords(playerPed, spawnCoords.x, spawnCoords.y, spawnCoords.z)
    else
        local spawn = Config.DefaultSpawn
        SetEntityCoords(playerPed, spawn.x, spawn.y, spawn.z)
    end
    
    FreezeEntityPosition(playerPed, false)
    TriggerClientEvent('nrp:client:spawnComplete', source)
end)

-- Evento para fechar NUI e entrar no jogo
RegisterNetEvent('nrp:enterGame', function()
    local source = source
    TriggerClientEvent('nrp:client:hideNUI', source)
end)

-- Callbacks para comunicação client-server
RegisterNUICallback('getCharacters', function(data, cb)
    local source = source
    local characters = NRP.Player.GetCharacters(source)
    cb(characters)
end)

RegisterNUICallback('createCharacter', function(data, cb)
    local source = source
    local success, result = NRP.Player.CreateCharacter(source, data)
    cb({success = success, message = result})
end)

RegisterNUICallback('selectCharacter', function(data, cb)
    local source = source
    local charId = data.charId
    
    local success = NRP.Player.LoadPlayer(source, charId)
    if success then
        -- Carregar aparência
        if Config.Appearance.Enabled then
            local playerData = NRP.Player.GetPlayer(source)
            if playerData and playerData.appearance then
                TriggerClientEvent('nrp:client:loadAppearance', source, playerData.appearance)
            end
        end
        
        -- Solicitar atualização da economia
        TriggerClientEvent('nrp:economy:requestUpdate', source)
        
        cb({success = true})
    else
        cb({success = false, message = 'Erro ao carregar personagem'})
    end
end)

RegisterNUICallback('deleteCharacter', function(data, cb)
    local source = source
    local charId = data.charId
    local license = NRP.GetIdentifier(source, 'license')
    
    -- Verificar se o personagem pertence ao jogador
    local owner = MySQL.scalar.await('SELECT identifier FROM nrp_players WHERE id = ?', {charId})
    
    if owner ~= license then
        cb({success = false, message = 'Personagem não encontrado'})
        return
    end
    
    -- Deletar personagem
    MySQL.query.await('DELETE FROM nrp_players WHERE id = ? AND identifier = ?', {charId, license})
    
    cb({success = true})
end)

RegisterNUICallback('saveAppearance', function(data, cb)
    local source = source
    local appearanceData = data.appearance
    
    local playerData = NRP.Player.GetPlayer(source)
    if playerData then
        playerData.appearance = appearanceData
        
        -- Salvar no banco
        MySQL.update.await(
            'UPDATE nrp_players SET appearance = ? WHERE id = ?',
            {json.encode(appearanceData), playerData.id}
        )
        
        cb({success = true})
    else
        cb({success = false, message = 'Jogador não encontrado'})
    end
end)

RegisterNUICallback('closeNUI', function(data, cb)
    local source = source
    TriggerClientEvent('nrp:client:hideNUI', source)
    cb('ok')
end)

-- Evento para salvar jogador periodicamente (a cada 5 minutos)
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(300000) -- 5 minutos
        
        for source, _ in pairs(NRP.Player.GetPlayers()) do
            if GetPlayerPed(source) ~= 0 then
                NRP.Player.SavePlayer(source)
            end
        end
    end
end)

-- Helper para obter todos os jogadores (precisa ser adicionado no player.lua)
function NRP.Player.GetPlayers()
    local players = {}
    for source, data in pairs(Players) do
        players[source] = data
    end
    return players
end
