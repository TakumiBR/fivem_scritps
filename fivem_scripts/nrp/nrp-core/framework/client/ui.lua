-- NRP Client UI Manager
-- Controle da UI de criação e multicharacter

local isNUIOpen = false
local currentNUI = nil

-- Função para abrir a UI de Multicharacter
function OpenMultiChar()
    if isNUIOpen then
        return
    end
    
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'openMultichar',
        config = {
            serverName = Config.ServerName,
            maxCharacters = 5 -- Limite máximo de personagens por conta
        }
    })
    
    isNUIOpen = true
    currentNUI = 'multichar'
end

-- Função para abrir a UI de Criação de Personagem
function OpenCreation()
    if isNUIOpen then
        return
    end
    
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'openCreation',
        config = {
            nationalities = Config.Nationalities
        }
    })
    
    isNUIOpen = true
    currentNUI = 'creation'
end

-- Função para abrir a UI de Appearance (personalização visual)
function OpenAppearance()
    if isNUIOpen then
        return
    end
    
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'openAppearance'
    })
    
    isNUIOpen = true
    currentNUI = 'appearance'
end

-- Função para fechar qualquer NUI
function CloseNUI()
    if not isNUIOpen then
        return
    end
    
    SetNuiFocus(false, false)
    SendNUIMessage({
        action = 'closeNUI'
    })
    
    isNUIOpen = false
    currentNUI = nil
end

-- Evento para esconder NUI (chamado do server)
RegisterNetEvent('nrp:client:hideNUI', function()
    CloseNUI()
end)

-- Evento para mostrar multichar ao entrar no servidor
RegisterNetEvent('nrp:client:showMultichar', function()
    Wait(1000)
    OpenMultiChar()
end)

-- Evento para mostrar criação quando não tem personagem
RegisterNetEvent('nrp:client:showCreation', function()
    Wait(1000)
    OpenCreation()
end)

-- Callbacks da NUI
RegisterNUICallback('getCharacters', function(data, cb)
    TriggerServerEvent('nrp:server:getCharacters')
    -- Os caracteres serão retornados via outro callback
    cb('ok')
end)

RegisterNUICallback('selectCharacter', function(data, cb)
    TriggerServerEvent('nrp:server:selectCharacter', data.charId)
    cb('ok')
end)

RegisterNUICallback('createCharacter', function(data, cb)
    TriggerServerEvent('nrp:server:createCharacter', data)
    cb('ok')
end)

RegisterNUICallback('deleteCharacter', function(data, cb)
    TriggerServerEvent('nrp:server:deleteCharacter', data.charId)
    cb('ok')
end)

RegisterNUICallback('saveAppearance', function(data, cb)
    TriggerServerEvent('nrp:server:saveAppearance', data.appearance)
    cb('ok')
end)

RegisterNUICallback('finishCreation', function(data, cb)
    -- Após criar dados básicos, abrir appearance
    OpenAppearance()
    cb('ok')
end)

RegisterNUICallback('enterGame', function(data, cb)
    CloseNUI()
    TriggerServerEvent('nrp:enterGame')
    cb('ok')
end)

RegisterNUICallback('closeNUI', function(data, cb)
    CloseNUI()
    cb('ok')
end)

-- Ao carregar o script, verificar se deve mostrar alguma UI
Citizen.CreateThread(function()
    Wait(2000)
    
    -- Verifica se precisa mostrar multichar ou creation
    -- Isso será determinado pelo deferral no server-side
    local hasCharacter = exports['nrp-core']:HasCharacter(PlayerId())
    
    if not hasCharacter then
        TriggerEvent('nrp:client:showCreation')
    else
        TriggerEvent('nrp:client:showMultichar')
    end
end)
