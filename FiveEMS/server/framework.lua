FiveEMS = FiveEMS or {}
FiveEMS.Framework = FiveEMS.Framework or {}

local F = FiveEMS.Framework
local cfg = Config.Framework or {}
local resources = cfg.resources or {}
F._sourceKeys = F._sourceKeys or {}
F._identityCache = F._identityCache or {}

local function res(key, fallback)
    return tostring(resources[key] or fallback or key)
end

local function started(name)
    return GetResourceState(name) == 'started'
end

local function safe(callable, fallback)
    local ok, a, b, c = pcall(callable)
    if not ok then return fallback, tostring(a) end
    return a, b, c
end

function F.resourceStarted(key)
    return started(res(key, key))
end

function F.status()
    local out = {mode = cfg.mode or 'standalone', strict = cfg.strict == true, resources = {}}
    for key, name in pairs(resources) do out.resources[key] = {name=name, state=GetResourceState(name)} end
    out.ready = out.resources.core and out.resources.core.state == 'started'
        and out.resources.records and out.resources.records.state == 'started'
        and out.resources.inventory and out.resources.inventory.state == 'started'
        and out.resources.injuries and out.resources.injuries.state == 'started'
        and out.resources.death and out.resources.death.state == 'started'
        and out.resources.admin and out.resources.admin.state == 'started'
        and out.resources.ui and out.resources.ui.state == 'started'
    return out
end

function F.getSession(src)
    src = tonumber(src)
    if not src or not started(res('core','fivepd_sp_core')) then return nil end
    return safe(function() return exports[res('core','fivepd_sp_core')]:ObterSessao(src) end, nil)
end

function F.getCharacterId(src)
    src = tonumber(src)
    if not src or not started(res('core','fivepd_sp_core')) then return nil end
    local value = safe(function() return exports[res('core','fivepd_sp_core')]:ObterPersonagemId(src) end, nil)
    return tonumber(value)
end

function F.getFixedId(src)
    src = tonumber(src)
    if not src or not started(res('core','fivepd_sp_core')) then return nil end
    return safe(function() return exports[res('core','fivepd_sp_core')]:ObterIdFixo(src) end, nil)
end

function F.getCharacterType(src)
    src = tonumber(src)
    if not src or not started(res('core','fivepd_sp_core')) then return nil end
    return safe(function() return exports[res('core','fivepd_sp_core')]:ObterTipoPersonagem(src) end, nil)
end

function F.playerKey(src)
    src = tonumber(src)
    if not src then return nil end
    local characterId = F.getCharacterId(src)
    if characterId then
        local key = ('char:%d'):format(characterId)
        F._sourceKeys[src] = key
        return key
    end
    return F._sourceKeys[src]
end

function F.getPlayerIdentity(src)
    local characterId = F.getCharacterId(src)
    if not characterId or not started(res('records','fivepd_sp_records')) then return nil end
    if F._identityCache[characterId] then return F._identityCache[characterId] end
    local person = safe(function() return exports[res('records','fivepd_sp_records')]:PessoaPorPersonagem(characterId) end, nil)
    if type(person) ~= 'table' then return nil end
    person.character_id = tonumber(person.character_id or characterId)
    person.framework_key = ('char:%d'):format(person.character_id)
    person.fixed_id = F.getFixedId(src)
    person.character_type = F.getCharacterType(src)
    F._identityCache[characterId] = person
    return person
end

function F.getNpcIdentity(networkId, data)
    networkId = tonumber(networkId)
    if not networkId or networkId <= 0 or not started(res('records','fivepd_sp_records')) then return nil end
    data = type(data) == 'table' and data or {}
    if data.persistir == nil then data.persistir = true end
    local person = safe(function() return exports[res('records','fivepd_sp_records')]:ObterOuCriarNPC(networkId, data) end, nil)
    if type(person) ~= 'table' then return nil end
    person.framework_key = person.record_id and ('record:%d'):format(tonumber(person.record_id)) or ('npc:%s'):format(tostring(person.npc_key or networkId))
    return person
end

function F.isAdmin(src)
    if tonumber(src) == 0 then return true end
    if not started(res('admin','fivepd_sp_admin')) then return false end
    local permission = tostring(cfg.adminPermission or 'abrir')
    return safe(function() return exports[res('admin','fivepd_sp_admin')]:TemPermissao(src, permission) end, false) == true
end

function F.getAdminRank(src)
    if not started(res('admin','fivepd_sp_admin')) then return nil end
    return safe(function() return exports[res('admin','fivepd_sp_admin')]:ObterCargo(src) end, nil)
end

local function inventoryBaseItem(itemName, category)
    local map = cfg.inventoryMap or {}
    if map[itemName] then return map[itemName] end
    if tostring(category or '') == 'ppe' and tostring(itemName):find('glove') then return map.csi_gloves or 'luvas' end
    if tostring(category or '') == 'oxygen' or tostring(itemName):find('mask') or tostring(itemName):find('cannula') then return map.oxygen_mask or 'mascara' end
    if tostring(itemName or ''):sub(1,4) == 'csi_' or tostring(category or ''):find('csi') then return map.defaultCsi or 'documento' end
    return map.defaultMedical or 'medicamento'
end

function F.addInventoryItem(src, itemName, count, metadata)
    if not started(res('inventory','fivepd_sp_inventory')) then return false, 'fivepd_sp_inventory nao esta iniciado.' end
    count = math.max(1, math.floor(tonumber(count) or 1))
    metadata = type(metadata) == 'table' and metadata or {}
    local baseItem = inventoryBaseItem(itemName, metadata.category)
    metadata.fiveems_item = tostring(itemName or '')
    metadata.fiveems_label = metadata.label or tostring(itemName or '')
    metadata.fiveems = true
    local ok, err = safe(function()
        return exports[res('inventory','fivepd_sp_inventory')]:AdicionarItemQuantidade(src, baseItem, count, metadata)
    end, false)
    return ok == true, err
end

function F.countInventoryItem(src, itemName)
    if not started(res('inventory','fivepd_sp_inventory')) then return 0 end
    local baseItem = inventoryBaseItem(itemName)
    return tonumber(safe(function() return exports[res('inventory','fivepd_sp_inventory')]:ContarItemJogador(src, baseItem) end, 0)) or 0
end

function F.getInventory(src)
    if not started(res('inventory','fivepd_sp_inventory')) then return nil end
    return safe(function()
        return exports[res('inventory','fivepd_sp_inventory')]:ObterInventarioJogador(src)
    end, nil)
end

local function decodeMaybeJson(value)
    if type(value) == 'table' then return value end
    if type(value) ~= 'string' or value == '' then return nil end
    local ok, decoded = pcall(json.decode, value)
    return ok and type(decoded) == 'table' and decoded or nil
end

local function countExactFiveEMSItemNode(node, wanted, seen)
    if type(node) ~= 'table' then return 0 end
    seen = seen or {}
    if seen[node] then return 0 end
    seen[node] = true

    local metadata = decodeMaybeJson(node.metadata or node.meta or node.info)
    if metadata and tostring(metadata.fiveems_item or '') == tostring(wanted or '') then
        local amount = tonumber(node.amount or node.count or node.quantity or node.quantidade or node.qtd or 1) or 1
        return math.max(1, math.floor(amount))
    end

    local total = 0
    for _, value in pairs(node) do
        if type(value) == 'table' then
            total = total + countExactFiveEMSItemNode(value, wanted, seen)
        end
    end
    return total
end

function F.countExactFiveEMSItem(src, itemName)
    local inventory = F.getInventory(src)
    if type(inventory) ~= 'table' then return 0 end
    return countExactFiveEMSItemNode(inventory, tostring(itemName or ''), {})
end

function F.hasExactFiveEMSItem(src, itemName, amount)
    amount = math.max(1, math.floor(tonumber(amount) or 1))
    return F.countExactFiveEMSItem(src, itemName) >= amount
end

function F.getDeathState(src)
    if not started(res('death','fivepd_sp_death')) then return nil end
    return safe(function() return exports[res('death','fivepd_sp_death')]:ObterEstado(src) end, nil)
end

function F.isDowned(src)
    local state = F.getDeathState(src)
    return type(state) == 'table' and state.status == 'downed'
end

function F.claimPatient(providerSrc, targetSrc, enabled)
    if not started(res('death','fivepd_sp_death')) then return false end
    local providerKey = F.playerKey(providerSrc) or ('src:%s'):format(tostring(providerSrc))
    local claimId = ('fiveems:%s'):format(providerKey)
    local result = safe(function()
        return exports[res('death','fivepd_sp_death')]:MarcarAtendimento(targetSrc, enabled == true, claimId)
    end, false)
    return result == true, claimId
end

function F.externalRevive(targetSrc)
    if not started(res('death','fivepd_sp_death')) then return false end
    TriggerClientEvent('fiveems:client:frameworkExternalRevive', targetSrc)
    return true
end

function F.applyPhysicalTreatment(targetSrc, region, amount)
    if not started(res('injuries','fivepd_sp_injuries')) then return false end
    TriggerClientEvent('fiveems:client:frameworkApplyTreatment', targetSrc, region, tonumber(amount) or 10)
    return true
end

RegisterNetEvent('fiveems:server:frameworkCharacterLoaded', function()
    local src = source
    local characterId = F.getCharacterId(src)
    if characterId then
        F._sourceKeys[src] = ('char:%d'):format(characterId)
        F._identityCache[characterId] = nil
        if FiveEMS.Cache and FiveEMS.Cache.members then FiveEMS.Cache.members[F._sourceKeys[src]] = nil end
    end
end)

RegisterNetEvent('fiveems:server:frameworkCharacterUnloaded', function()
    local src = source
    local key = F._sourceKeys[src]
    if key and FiveEMS.Cache and FiveEMS.Cache.members then FiveEMS.Cache.members[key] = nil end
    if key and FiveEMS.DB and FiveEMS.DB._ready then
        pcall(function() FiveEMS.DB.update('UPDATE fiveems_members SET on_duty=0 WHERE identifier=?', {key}) end)
    end
    local player = Player(src)
    if player and player.state then
        player.state:set('fiveems:onDuty', false, true)
        player.state:set('fiveems:departmentId', nil, true)
    end
    F._sourceKeys[src] = nil
end)

RegisterNetEvent('fiveems:server:testNpcIdentity', function(networkId, hints)
    local src = source
    hints = type(hints) == 'table' and hints or {}
    hints.persistir = true
    hints.source = 'fiveems_admin_debug'
    local person = F.getNpcIdentity(networkId, hints)
    if person then
        TriggerClientEvent('fiveems:client:consoleReport', src, 'FiveEMS - NPC Records Test', {
            ('Record ID: %s'):format(tostring(person.record_id)),
            ('Nome: %s'):format(tostring(person.nome_completo)),
            ('RG: %s'):format(tostring(person.rg)),
            ('Sexo: %s | Idade: %s | Sangue: %s'):format(tostring(person.sexo), tostring(person.idade), tostring(person.tipo_sanguineo)),
            ('Framework key: %s'):format(tostring(person.framework_key)),
        })
        TriggerClientEvent('fiveems:client:notify', src, 'NPC resolvido pelo fivepd_sp_records. Veja o F8.')
    else
        TriggerClientEvent('fiveems:client:notify', src, 'Nao foi possivel resolver o NPC no fivepd_sp_records.')
    end
end)

exports('FrameworkStatus', function() return F.status() end)
exports('ResolvePlayerIdentity', function(src) return F.getPlayerIdentity(src) end)
exports('ResolveNpcIdentity', function(networkId, data) return F.getNpcIdentity(networkId, data) end)
