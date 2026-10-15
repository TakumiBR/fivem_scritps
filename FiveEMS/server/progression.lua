FiveEMS = FiveEMS or {}
FiveEMS.Progression = FiveEMS.Progression or {}

local P = FiveEMS.Progression
local DB = FiveEMS.DB
local Server = FiveEMS.Server

function P.levelForXp(xp)
    xp = math.max(0, tonumber(xp) or 0)
    local level = 1
    local needed = Config.Progression.levelBaseXp
    local remaining = xp
    while level < Config.Progression.maxLevel and remaining >= needed do
        remaining = remaining - needed
        level = level + 1
        needed = math.floor(needed * Config.Progression.levelGrowth)
    end
    return level
end

function P.addXp(src, amount, reason)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return end
    local member = Server.getMember(src)
    if not member then return end

    local newXp = (tonumber(member.xp) or 0) + amount
    local newLevel = P.levelForXp(newXp)
    DB.update('UPDATE fiveems_members SET xp=?, level=? WHERE identifier=?', {newXp, newLevel, member.identifier})
    Server.clearMemberCacheByIdentifier(member.identifier)
    DB.insert('INSERT INTO fiveems_xp_log (identifier, amount, reason) VALUES (?, ?, ?)', {member.identifier, amount, tostring(reason or 'unknown')})
    TriggerClientEvent('fiveems:client:xpUpdated', src, {xp=newXp, level=newLevel, amount=amount, reason=reason})
end

exports('AddXp', function(src, amount, reason) P.addXp(src, amount, reason) end)
