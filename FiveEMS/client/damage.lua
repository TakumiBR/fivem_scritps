FiveEMS = FiveEMS or {}
local C = FiveEMS.Client
local lastHealth = 200
local lastArmour = 0

local boneRegion = {
    [31086]='head', [39317]='neck',
    [24818]='chest', [24817]='chest', [24816]='chest', [57597]='chest',
    [11816]='pelvis', [23553]='pelvis',
    [28252]='right_arm', [57005]='right_arm', [58866]='right_arm', [40269]='right_arm', [64016]='right_arm', [64017]='right_arm',
    [61163]='left_arm', [18905]='left_arm', [26610]='left_arm', [26611]='left_arm', [26612]='left_arm', [26613]='left_arm', [26614]='left_arm',
    [51826]='right_leg', [36864]='right_leg', [52301]='right_leg', [20781]='right_leg', [35502]='right_leg',
    [58271]='left_leg', [63931]='left_leg', [14201]='left_leg', [2108]='left_leg', [65245]='left_leg',
}

local meleeWeapons = {
    [joaat('WEAPON_KNIFE')]=true, [joaat('WEAPON_DAGGER')]=true, [joaat('WEAPON_SWITCHBLADE')]=true,
    [joaat('WEAPON_BOTTLE')]=true,
}

local bluntWeapons = {
    [joaat('WEAPON_BAT')]=true, [joaat('WEAPON_CROWBAR')]=true, [joaat('WEAPON_HAMMER')]=true,
    [joaat('WEAPON_NIGHTSTICK')]=true, [joaat('WEAPON_UNARMED')]=true,
}

local function categoryFor(ped, weapon)
    local group = GetWeapontypeGroup(weapon)
    if meleeWeapons[weapon] then return 'stabbing' end
    if bluntWeapons[weapon] then return 'blunt' end
    if group == joaat('GROUP_PISTOL') or group == joaat('GROUP_RIFLE') or group == joaat('GROUP_SMG') or group == joaat('GROUP_SHOTGUN') or group == joaat('GROUP_SNIPER') or group == joaat('GROUP_MG') then
        return 'gunshot'
    end
    if group == joaat('GROUP_HEAVY') then return 'explosion' end
    if IsPedInAnyVehicle(ped, false) or IsPedBeingStunned(ped, 0) then return 'vehicle' end
    if IsPedFalling(ped) or IsPedRagdoll(ped) then return 'fall' end
    if IsEntityOnFire(ped) then return 'burn' end
    if IsPedSwimmingUnderWater(ped) then return 'drowning' end
    return 'unknown'
end

local function regionForBone(bone)
    return boneRegion[bone] or 'abdomen'
end

AddEventHandler('gameEventTriggered', function(name, args)
    if name ~= 'CEventNetworkEntityDamage' then return end
    local victim = args[1]
    if victim ~= PlayerPedId() then return end

    local ped = PlayerPedId()
    local health = GetEntityHealth(ped)
    local armour = GetPedArmour(ped)
    local previousCombined = lastHealth + lastArmour
    local currentCombined = health + armour
    local damage = math.max(1, previousCombined - currentCombined)
    lastHealth, lastArmour = health, armour

    local ok, bone = GetPedLastDamageBone(ped)
    if not ok then bone = 24818 end
    local weapon = GetPedCauseOfDeath(ped)
    if weapon == 0 then weapon = args[7] or 0 end
    local attacker = args[2]
    local attackerNetId = attacker and attacker ~= 0 and NetworkGetNetworkIdFromEntity(attacker) or 0
    local category = categoryFor(ped, weapon)
    local region = regionForBone(bone)
    local coords = GetEntityCoords(ped)

    local payload = {
        damage=damage, bone=bone, region=region, category=category, weapon=weapon,
        attackerNetId=attackerNetId,
        coords={x=coords.x,y=coords.y,z=coords.z}
    }
    TriggerServerEvent('fiveems:server:recordDamage', payload)
    if Config.CSI.createEvidenceFromPlayerDamage then TriggerServerEvent('fiveems:server:csiDamageEvidence', payload) end
end)

CreateThread(function()
    Wait(1200)
    local ped = PlayerPedId()
    lastHealth, lastArmour = GetEntityHealth(ped), GetPedArmour(ped)
    while true do
        Wait(500)
        ped = PlayerPedId()
        if not IsEntityDead(ped) then
            lastHealth = math.max(lastHealth, GetEntityHealth(ped))
            lastArmour = GetPedArmour(ped)
        end
    end
end)

AddEventHandler('fiveems:client:applyFunctionalEffects', function(state)
    if not state then return end
    local ped = PlayerPedId()
    local worstLeg, worstArm, head = 0, 0, 0
    for _, injury in ipairs(state.injuries or {}) do
        if injury.region == 'left_leg' or injury.region == 'right_leg' then worstLeg = math.max(worstLeg, injury.severity or 0) end
        if injury.region == 'left_arm' or injury.region == 'right_arm' then worstArm = math.max(worstArm, injury.severity or 0) end
        if injury.region == 'head' then head = math.max(head, injury.severity or 0) end
    end

    if worstLeg >= 55 then
        SetRunSprintMultiplierForPlayer(PlayerId(), 0.65)
        RequestAnimSet('move_m@injured')
        if HasAnimSetLoaded('move_m@injured') then SetPedMovementClipset(ped, 'move_m@injured', 0.35) end
    else
        SetRunSprintMultiplierForPlayer(PlayerId(), 1.0)
        ResetPedMovementClipset(ped, 0.25)
    end

    if head >= 50 then
        SetTimecycleModifier('spectator5')
        SetTimecycleModifierStrength(math.min(0.7, head / 130.0))
    else
        ClearTimecycleModifier()
    end

    C.functionalArmSeverity = worstArm
end)

CreateThread(function()
    while true do
        if (C.functionalArmSeverity or 0) >= 58 then
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 140, true)
            DisableControlAction(0, 141, true)
            DisableControlAction(0, 142, true)
            Wait(0)
        else
            Wait(500)
        end
    end
end)
