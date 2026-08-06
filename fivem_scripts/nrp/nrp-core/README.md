# NRP Core - Nação Roleplay Framework

Framework FiveM independente, desenvolvida para o servidor **Nação Roleplay**. A `nrp-core` foi construída do zero sem depender de QB-Core, ESX ou QBox, e inclui um sistema de **Bridges/Adapters** que permite executar scripts feitos para essas frameworks sem necessidade de modificação no código fonte.

## 📋 Características Principais

- ✅ **Independente**: Não requer QB-Core, ESX ou QBox
- ✅ **Compatibilidade Total**: Bridges para ESX, QB-Core e QBox
- ✅ **Multicharacter**: Sistema de múltiplos personagens por conta
- ✅ **Criação de Personagem**: UI completa com validações
- ✅ **Sistema de Economia**: Cash, Bank e Black Money
- ✅ **Appearance System**: Integração com illenium-appearance
- ✅ **Banco de Dados**: MySQL via oxmysql

## 📁 Estrutura de Pastas

```
nrp-core/
├── framework/
│   ├── server/
│   │   ├── player.lua        # Gerenciamento de jogadores
│   │   ├── economy.lua       # Sistema de economia
│   │   └── events.lua        # Eventos e callbacks
│   ├── client/
│   │   ├── ui.lua            # Controle de NUIs
│   │   ├── appearance.lua    # Sistema de aparência
│   │   └── hud.lua           # Atualização de HUD
│   └── shared/
│       ├── main.lua          # Funções globais NRP
│       └── config.lua        # Configurações gerais
├── bridges/
│   ├── esx.lua               # Compatibilidade ESX
│   ├── qb.lua                # Compatibilidade QB-Core
│   └── qbox.lua              # Compatibilidade QBox
├── html/
│   ├── multichar/            # UI Multicharacter
│   │   ├── index.html
│   │   ├── style.css
│   │   └── script.js
│   └── creation/             # UI Criação de Personagem
│       ├── index.html
│       ├── style.css
│       └── script.js
├── fxmanifest.lua
└── nrp_database.sql
```

## 🚀 Instalação

### 1. Pré-requisitos

- **oxmysql**: Instale e configure o [oxmysql](https://github.com/overextended/oxmysql)
- **illenium-appearance** (Opcional): Para sistema de aparência

### 2. Banco de Dados

Execute o arquivo `nrp_database.sql` no seu banco de dados MySQL:

```sql
-- A tabela nrp_players será criada com todos os campos necessários
```

### 3. Instalação da Framework

1. Copie a pasta `nrp-core` para `resources/[nrp]/`
2. Adicione `ensure nrp-core` no seu `server.cfg`
3. Reinicie o servidor

## 🎮 Uso

### Módulo de Jogador

```lua
-- Verificar se jogador tem personagem
local hasChar = exports['nrp-core']:HasCharacter(source)

-- Obter dados do jogador
local playerData = exports['nrp-core']:GetPlayer(source)

-- Criar personagem
local success, result = exports['nrp-core']:CreateCharacter(source, {
    firstname = "João",
    lastname = "Silva",
    nationalid = "Brasil",
    dob = "2000-01-15",
    gender = "m"
})

-- Carregar personagem
exports['nrp-core']:LoadPlayer(source, charId)

-- Salvar personagem
exports['nrp-core']:SavePlayer(source)
```

### Módulo de Economia

```lua
-- Adicionar dinheiro
exports['nrp-core']:AddMoney(source, 'cash', 1000)
exports['nrp-core']:AddMoney(source, 'bank', 5000)
exports['nrp-core']:AddMoney(source, 'black', 500)

-- Remover dinheiro
exports['nrp-core']:RemoveMoney(source, 'cash', 100)

-- Obter saldo
local cash = exports['nrp-core']:GetMoney(source, 'cash')
local bank = exports['nrp-core']:GetMoney(source, 'bank')
local black = exports['nrp-core']:GetMoney(source, 'black')

-- Transferir dinheiro
exports['nrp-core']:TransferMoney(fromSource, toSource, 'cash', 500)
```

### Módulo de Aparência

```lua
-- Definir modelo
exports['nrp-core']:SetModel(source, 'a_m_y_genstreet_01')

-- Salvar aparência
exports['nrp-core']:SaveAppearance(source, appearanceData)

-- Carregar aparência
exports['nrp-core']:LoadAppearance(source, appearanceData)
```

## 🔌 Compatibilidade com Outras Frameworks

A `nrp-core` inclui bridges que permitem usar scripts de ESX, QB-Core e QBox sem modificação.

### ESX

```lua
-- Scripts ESX funcionam normalmente
ESX.GetPlayerFromId(source).addMoney(100)
ESX.GetPlayerFromId(source).addAccountMoney('bank', 500)
```

### QB-Core

```lua
-- Scripts QB-Core funcionam normalmente
QBCore.Functions.GetPlayer(source).Functions.AddMoney('cash', 100)
QBCore.Functions.GetPlayer(source).Functions.SetJob('police', 3)
```

### QBox

```lua
-- Scripts QBox funcionam normalmente
QB.Functions.GetPlayer(source).Functions.AddMoney('cash', 100)
```

## ⚙️ Configuração

Edite `framework/shared/config.lua` para personalizar:

```lua
Config.ServerName = 'Nação Roleplay'
Config.DebugMode = false

-- Economia inicial
Config.Economy = {
    DefaultCash = 1000,
    DefaultBank = 5000,
    DefaultBlackMoney = 0,
}

-- Nacionalidades disponíveis
Config.Nationalities = {
    'Brasil',
    'Estados Unidos',
    'Portugal',
    -- ...
}
```

## 📝 Validações de Nome

- **Primeiro Nome**: 3-15 caracteres, apenas letras e espaços
- **Sobrenome**: 3-20 caracteres, letras, espaços e apóstrofe (ex: O'Brien)
- **Duplicidade**: Não permite Nome + Sobrenome iguais

## 🎨 UIs Inclusas

### Multicharacter
- Grid de slots de personagens
- Visualização de informações do personagem selecionado
- Opção de deletar personagem
- Botão "Jogar" para entrar no servidor

### Criação de Personagem
- Campos: Nome, Sobrenome, Data de Nascimento, Nacionalidade, Gênero
- Validação em tempo real
- Design responsivo e tema escuro

## 🔧 Events da Framework

### Client → Server
- `nrp:server:getCharacters`
- `nrp:server:createCharacter`
- `nrp:server:selectCharacter`
- `nrp:server:deleteCharacter`
- `nrp:server:saveAppearance`

### Server → Client
- `nrp:client:showMultichar`
- `nrp:client:showCreation`
- `nrp:client:hideNUI`
- `nrp:client:loadAppearance`
- `nrp:economy:update`
- `nrp:economy:updateAll`

## 📄 Licença

Desenvolvido exclusivamente para **Nação Roleplay**.

## 👨‍💻 Desenvolvedor

Framework criada para o servidor Nação Roleplay, com foco em performance, compatibilidade e facilidade de uso.

---

**Nota**: Esta framework está em desenvolvimento contínuo. Novos módulos e melhorias serão adicionados conforme necessário.
