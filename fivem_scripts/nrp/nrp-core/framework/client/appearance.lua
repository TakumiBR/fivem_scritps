-- NRP Appearance Manager
-- Bridge para sistema de aparência (illenium-appearance ou outro)

local AppearanceSystem = nil

-- Detectar qual sistema de aparência está disponível
function DetectAppearanceSystem()
    if GetResourceState('illenium-appearance') == 'started' then
        AppearanceSystem = 'illenium'
        print('[NRP] Sistema de aparência detectado: illenium-appearance')
    elseif GetResourceState('fivem-appearance') == 'started' then
        AppearanceSystem = 'fivem'
        print('[NRP] Sistema de aparência detectado: fivem-appearance')
    else
        AppearanceSystem = 'native'
        print('[NRP] Usando sistema nativo de aparência')
    end
    
    return AppearanceSystem
end

-- Inicializar sistema de aparência
Citizen.CreateThread(function()
    Wait(5000)
    DetectAppearanceSystem()
end)

-- Função para definir modelo do jogador
function NRP.Player.SetModel(source, model)
    local ped = GetPlayerPed(source)
    
    -- Carregar modelo
    RequestModel(model)
    while not HasModelLoaded(model) do
        Wait(10)
    end
    
    SetPlayerModel(source, model)
    SetModelAsNoLongerNeeded(model)
    
    return true
end

-- Função para salvar aparência
function NRP.Player.SaveAppearance(source, appearanceData)
    local playerData = NRP.Player.GetPlayer(source)
    if not playerData then
        return false
    end
    
    playerData.appearance = appearanceData
    
    -- Salvar no banco de dados
    MySQL.update.await(
        'UPDATE nrp_players SET appearance = ? WHERE id = ?',
        {json.encode(appearanceData), playerData.id}
    )
    
    return true
end

-- Função para carregar aparência
function NRP.Player.LoadAppearance(source, appearanceData)
    if not appearanceData then
        return false
    end
    
    local ped = GetPlayerPed(source)
    
    if AppearanceSystem == 'illenium' then
        -- Usar illenium-appearance
        exports['illenium-appearance']:setPlayerAppearance(appearanceData)
    elseif AppearanceSystem == 'fivem' then
        -- Usar fivem-appearance
        exports['fivem-appearance']:setPlayerAppearance(ped, appearanceData)
    else
        -- Sistema nativo (básico)
        if appearanceData.model then
            NRP.Player.SetModel(source, appearanceData.model)
        end
        
        if appearanceData.components then
            for componentId, drawable in pairs(appearanceData.components) do
                SetPedComponentVariation(ped, tonumber(componentId), drawable.drawable, drawable.texture, 0)
            end
        end
        
        if appearanceData.props then
            for propId, drawable in pairs(appearanceData.props) do
                SetPedPropIndex(ped, tonumber(propId), drawable.drawable, drawable.texture, true)
            end
        end
        
        if appearanceData.headBlend then
            local blend = appearanceData.headBlend
            SetPedHeadBlendData(ped, 
                blend.skinFirst, blend.skinSecond, blend.skinThird,
                blend.shapeFirst, blend.shapeSecond, blend.shapeThird,
                blend.skinMix, blend.shapeMix, blend.thirdMix,
                blend.parentHeight, 0
            )
        end
    end
    
    return true
end

-- Evento para carregar aparência no cliente
RegisterNetEvent('nrp:client:loadAppearance', function(appearanceData)
    NRP.Player.LoadAppearance(PlayerId(), appearanceData)
end)

-- Export functions
exports('SetModel', NRP.Player.SetModel)
exports('SaveAppearance', NRP.Player.SaveAppearance)
exports('LoadAppearance', NRP.Player.LoadAppearance)
exports('GetAppearanceSystem', function()
    return AppearanceSystem
end)
