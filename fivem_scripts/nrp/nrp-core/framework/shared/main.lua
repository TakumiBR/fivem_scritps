-- NRP Core - Main Shared File
-- Este arquivo contém funções e constantes globais da framework

NRP = {}
NRP.Version = '1.0.0'

-- Funções utilitárias compartilhadas
function NRP.Debug(...)
    if Config.DebugMode then
        print('[NRP DEBUG]', ...)
    end
end

-- Validação de nome (não permite números ou caracteres especiais, exceto apóstrofe)
function NRP.ValidateName(name, isLastName)
    local maxLength = isLastName and Config.NameValidation.MaxLengthLastName or Config.NameValidation.MaxLengthFirstName
    
    if not name or #name < Config.NameValidation.MinLength then
        return false, 'Nome muito curto'
    end
    
    if #name > maxLength then
        return false, 'Nome muito longo'
    end
    
    -- Permite apenas letras, espaços e apóstrofe (para sobrenomes como O'Connel)
    local pattern = Config.NameValidation.AllowApostrophe and isLastName 
        and "^[%a%s']+$" 
        or "^[%a%s]+$"
    
    if not name:match(pattern) then
        return false, 'Nome contém caracteres inválidos'
    end
    
    return true
end

-- Função para gerar ID único baseado no identifier do jogador
function NRP.GetIdentifier(source, idType)
    local identifiers = GetPlayerIdentifiers(source)
    for _, identifier in ipairs(identifiers) do
        if string.find(identifier, idType) then
            return identifier
        end
    end
    return nil
end

-- Export functions (serão preenchidas pelos módulos)
NRP.Player = {}
NRP.Economy = {}
NRP.Appearance = {}

-- Eventos registrados
RegisterNetEvent('nrp:debug', function(...)
    NRP.Debug(...)
end)
