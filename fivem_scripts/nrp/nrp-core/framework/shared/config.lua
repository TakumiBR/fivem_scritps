Config = {}

-- Configurações Gerais
Config.ServerName = 'Nação Roleplay'
Config.DebugMode = false

-- Configurações de Spawn
Config.DefaultSpawn = vector4(200.0, -950.0, 30.0, 0.0) -- Local padrão de spawn

-- Configurações de Economia
Config.Economy = {
    DefaultCash = 1000,      -- Dinheiro físico inicial
    DefaultBank = 5000,      -- Dinheiro no banco inicial
    DefaultBlackMoney = 0,   -- Dinheiro sujo inicial
}

-- Configurações de Nacionalidade
Config.Nationalities = {
    'Estados Unidos',
    'Brasil',
    'Canadá',
    'México',
    'Argentina',
    'Colômbia',
    'Portugal',
    'Espanha',
    'Itália',
    'França',
    'Alemanha',
    'Reino Unido',
    'Japão',
    'Coreia do Sul',
    'China',
    'Rússia',
    'Austrália'
}

-- Configurações de Validação de Nome
Config.NameValidation = {
    MinLength = 3,
    MaxLengthFirstName = 15,
    MaxLengthLastName = 20,
    AllowApostrophe = true,
}

-- Configurações de Appearance (illenium-appearance)
Config.Appearance = {
    Enabled = true,
    DefaultModelMale = 'a_m_y_genstreet_01',
    DefaultModelFemale = 'a_f_y_genhot_01',
}

-- Configurações de IDs Fixos para NUI
Config.NUI = {
    MultiChar = 'nrp-multichar',
    Creation = 'nrp-creation',
}
