FiveEMS = FiveEMS or {}
FiveEMS.FieldEquipment = FiveEMS.FieldEquipment or {}

local FE = FiveEMS.FieldEquipment
local Server = FiveEMS.Server
local F = FiveEMS.Framework
local DB = FiveEMS.DB
local CR = FiveEMS.ClinicalRuntime
local D = FiveEMS.Departments

FE.bags = FE.bags or {}
FE.bagByOwner = FE.bagByOwner or {}
FE.carriedBags = FE.carriedBags or {}
FE.fieldItems = FE.fieldItems or {}
FE.portableEquipment = FE.portableEquipment or {}
FE.portableEquipmentByOwner = FE.portableEquipmentByOwner or {}
FE.vehicleBagReservations = FE.vehicleBagReservations or {}
FE.vehicleBagContents = FE.vehicleBagContents or {}

local function cfg()
    return Config.FieldEquipment or {}
end

local function dist(a,b)
    if not a or not b then return 9999.0 end
    local dx,dy,dz=a.x-b.x,a.y-b.y,a.z-b.z
    return math.sqrt(dx*dx+dy*dy+dz*dz)
end

local function entityFromNet(netId)
    netId=tonumber(netId)
    if not netId or netId<=0 then return 0 end
    local e=NetworkGetEntityFromNetworkId(netId)
    if not e or e==0 or not DoesEntityExist(e) then return 0 end
    return e
end

local function sourceNearEntity(src,entity,maxDist)
    local ped=GetPlayerPed(src)
    if not ped or ped==0 or not DoesEntityExist(ped) then return false end
    return dist(GetEntityCoords(ped),GetEntityCoords(entity)) <= (tonumber(maxDist) or 4.0)
end

local function hasBagItem(src)
    local item=tostring((((cfg().medicalBag or {}).itemName) or 'medical_bag'))
    return F and F.hasExactFiveEMSItem and F.hasExactFiveEMSItem(src,item,1) or false
end

local function labelMap()
    local out={}
    for _,group in ipairs({FiveEMS.Catalog and FiveEMS.Catalog.equipment or {},FiveEMS.Catalog and FiveEMS.Catalog.medications or {}}) do
        for _,row in ipairs(group) do out[row.name]=row.label end
    end
    return out
end

local function bagPayload(bag,viewer)
    local labels=labelMap()
    local items={}
    local loadout=FiveEMS.Clinical and FiveEMS.Clinical.bagLoadout or {}
    local hand=FE.fieldItems[viewer] or {}
    for item,target in pairs(loadout) do
        items[#items+1]={
            name=item,
            label=labels[item] or item,
            bag=tonumber(bag.contents[item]) or 0,
            hand=tonumber(hand[item]) or 0,
            target=tonumber(target) or 0,
            durable=FiveEMS.Clinical and FiveEMS.Clinical.nonConsumableItems and FiveEMS.Clinical.nonConsumableItems[item] == true or false,
        }
    end
    table.sort(items,function(a,b) return tostring(a.label)<tostring(b.label) end)
    return {netId=bag.netId,owner=bag.ownerIdentifier,items=items}
end

local function sendBagData(src,bag)
    if not bag then return end
    TriggerClientEvent('fiveems:client:fieldBagOpenData',src,bagPayload(bag,src))
end

local function savePhysicalBag(bag)
    if bag and bag.ownerIdentifier and CR and CR.saveBagByIdentifier then
        CR.saveBagByIdentifier(bag.ownerIdentifier,bag.contents)
    end
end

local function handSnapshot(src)
    local hand=FE.fieldItems[tonumber(src)] or {}
    local out={}
    for item,count in pairs(hand) do
        count=math.max(0,math.floor(tonumber(count) or 0))
        if count>0 then out[tostring(item)]=count end
    end
    return out
end

local function syncFieldItems(src)
    src=tonumber(src)
    if not src then return end
    local snapshot=handSnapshot(src)
    local player=Player(src)
    if player and player.state then player.state:set('fiveemsFieldItems',snapshot,true) end
    TriggerClientEvent('fiveems:client:fieldItemsUpdated',src,snapshot)
end

function FE.getHandSnapshot(src)
    return handSnapshot(src)
end

function FE.hasHandItem(src,itemName,amount)
    amount=math.max(1,math.floor(tonumber(amount) or 1))
    return (tonumber((FE.fieldItems[tonumber(src)] or {})[tostring(itemName or '')]) or 0)>=amount
end

function FE.consumeHandItem(src,itemName,amount)
    src=tonumber(src)
    itemName=tostring(itemName or '')
    amount=math.max(1,math.floor(tonumber(amount) or 1))
    if not src or itemName=='' then return false end
    local hand=FE.fieldItems[src] or {}
    local have=tonumber(hand[itemName]) or 0
    if have<amount then return false end
    hand[itemName]=have-amount
    FE.fieldItems[src]=hand
    syncFieldItems(src)
    return true
end

FE.syncFieldItems=syncFieldItems

local function copyTable(value)
    if type(value)~='table' then return value end
    local out={}
    for k,v in pairs(value) do out[k]=copyTable(v) end
    return out
end

local function setCarryState(src,enabled)
    local player=Player(src)
    if player and player.state then player.state:set('fiveems:carryingMedicalBag',enabled==true,true) end
end

local function saveCarriedBag(carried)
    if carried and carried.ownerIdentifier and CR and CR.saveBagByIdentifier then
        CR.saveBagByIdentifier(carried.ownerIdentifier,carried.contents or {})
    end
end

local function beginCarryingBag(src,bagData)
    src=tonumber(src)
    if not src then return false,'Player invalido.' end
    if FE.carriedBags[src] then
        TriggerClientEvent('fiveems:client:fieldBagCarryStart',src,FE.carriedBags[src].model)
        setCarryState(src,true)
        return true
    end
    local existing=FE.bagByOwner[src]
    if existing and FE.bags[existing] then return false,'Voce ja possui uma bolsa medica colocada na cena.' end
    local identifier=bagData and bagData.ownerIdentifier or Server.getPrimaryIdentifier(src)
    if not identifier then return false,'Nao foi possivel identificar o personagem.' end
    local contents=bagData and copyTable(bagData.contents or {}) or copyTable(CR.getBag(src) or {})
    FE.carriedBags[src]={
        owner=src,
        ownerIdentifier=identifier,
        contents=contents,
        model=tostring((bagData and bagData.model) or ''),
        originVehicleNetId=tonumber(bagData and bagData.originVehicleNetId),
        originDepartmentId=tonumber(bagData and bagData.originDepartmentId),
    }
    setCarryState(src,true)
    TriggerClientEvent('fiveems:client:fieldBagCarryStart',src,FE.carriedBags[src].model)
    return true
end
FE.beginCarryingBag=beginCarryingBag

local function nearestBag(src,maxDist)
    local ped=GetPlayerPed(src)
    if not ped or ped==0 or not DoesEntityExist(ped) then return nil end
    local pos=GetEntityCoords(ped)
    local limit=tonumber(maxDist) or tonumber(((cfg().medicalBag or {}).useDistance)) or 4.0
    local best,bestD
    for _,bag in pairs(FE.bags) do
        local e=bag.entity
        if e and e~=0 and DoesEntityExist(e) then
            local d=dist(pos,GetEntityCoords(e))
            if d<=limit and (not bestD or d<bestD) then best,bestD=bag,d end
        end
    end
    return best,bestD
end

function FE.getUsableSnapshot(src)
    local out={}
    local hand=FE.fieldItems[src] or {}
    local bag=nearestBag(src)
    local base=bag and bag.contents or {}
    for item,_ in pairs(FiveEMS.Clinical and FiveEMS.Clinical.bagLoadout or {}) do
        out[item]=(tonumber(base[item]) or 0)+(tonumber(hand[item]) or 0)
    end
    return out
end

function FE.hasUsableItem(src,itemName,amount)
    amount=math.max(1,math.floor(tonumber(amount) or 1))
    local hand=FE.fieldItems[src] or {}
    if (tonumber(hand[itemName]) or 0)>=amount then return true end
    local bag=nearestBag(src)
    return bag and (tonumber(bag.contents[itemName]) or 0)>=amount or false
end

function FE.consumeUsableItem(src,itemName,amount)
    amount=math.max(1,math.floor(tonumber(amount) or 1))
    local hand=FE.fieldItems[src] or {}
    local have=tonumber(hand[itemName]) or 0
    if have>=amount then
        hand[itemName]=have-amount
        FE.fieldItems[src]=hand
        syncFieldItems(src)
        return true
    end
    local bag=nearestBag(src)
    if not bag then return false end
    have=tonumber(bag.contents[itemName]) or 0
    if have<amount then return false end
    bag.contents[itemName]=have-amount
    savePhysicalBag(bag)
    return true
end

local function removeBag(netId)
    netId=tonumber(netId)
    local bag=netId and FE.bags[netId] or nil
    if not bag then return false end
    savePhysicalBag(bag)
    FE.bags[netId]=nil
    if bag.owner and FE.bagByOwner[bag.owner]==netId then FE.bagByOwner[bag.owner]=nil end
    -- Fecha a UI para qualquer profissional que esteja olhando a mesma bolsa,
    -- sem disparar notificacao global para todos os players.
    TriggerClientEvent('fiveems:client:fieldBagRemoved',-1,netId,nil)
    if bag.entity and bag.entity~=0 and DoesEntityExist(bag.entity) then DeleteEntity(bag.entity) end
    return true
end

RegisterNetEvent('fiveems:server:fieldBagUseRequest',function()
    local src=source
    if not Server.hasPermission(src,'patient.treat') then return Server.notify(src,_L('no_permission')) end

    if FE.carriedBags[src] then
        return TriggerClientEvent('fiveems:client:fieldBagBeginPlacement',src)
    end

    local existing=FE.bagByOwner[src]
    if existing and FE.bags[existing] then
        return Server.notify(src,'Voce ja possui uma bolsa medica colocada na cena. Recolha ela com o ox_target.')
    end
    if not hasBagItem(src) then return Server.notify(src,'Retire uma Bolsa medica no estoque ou na ambulancia primeiro.') end

    local ok,err=beginCarryingBag(src)
    if not ok and err then Server.notify(src,err) end
end)

RegisterNetEvent('fiveems:server:fieldBagPlaceRequest',function()
    local src=source
    if not FE.carriedBags[src] then return Server.notify(src,'Voce nao esta carregando uma bolsa medica.') end
    TriggerClientEvent('fiveems:client:fieldBagBeginPlacement',src)
end)

RegisterNetEvent('fiveems:server:fieldBagPlaceBesideRequest',function(targetNetId)
    local src=source
    if not FE.carriedBags[src] then return Server.notify(src,'Voce nao esta carregando uma bolsa medica.') end
    local target=entityFromNet(targetNetId)
    if target==0 or GetEntityType(target)~=1 then return Server.notify(src,'Paciente nao encontrado.') end
    if not sourceNearEntity(src,target,4.0) then return Server.notify(src,'Aproxime-se do paciente.') end
    TriggerClientEvent('fiveems:client:fieldBagPlaceBeside',src,tonumber(targetNetId))
end)

RegisterNetEvent('fiveems:server:fieldBagRegister',function(netId,modelName)
    local src=source
    netId=tonumber(netId)
    local carried=FE.carriedBags[src]
    if not netId or not carried then
        if carried then TriggerClientEvent('fiveems:client:fieldBagCarryStart',src,carried.model) end
        return
    end
    if FE.bagByOwner[src] and FE.bags[FE.bagByOwner[src]] then
        local duplicate=entityFromNet(netId)
        if duplicate~=0 then DeleteEntity(duplicate) end
        TriggerClientEvent('fiveems:client:fieldBagCarryStart',src,carried.model)
        return Server.notify(src,'Voce ja possui uma bolsa medica colocada na cena.')
    end
    local entity=entityFromNet(netId)
    if entity==0 or not sourceNearEntity(src,entity,5.0) then
        if entity~=0 and DoesEntityExist(entity) then DeleteEntity(entity) end
        TriggerClientEvent('fiveems:client:fieldBagCarryStart',src,carried.model)
        return Server.notify(src,'Falha ao validar a bolsa na cena. Ela voltou para suas maos.')
    end
    pcall(function() SetEntityOrphanMode(entity,2) end)
    local bag={
        netId=netId,
        entity=entity,
        owner=src,
        ownerIdentifier=carried.ownerIdentifier,
        model=tostring(modelName or carried.model or ''),
        contents=copyTable(carried.contents or {}),
        originVehicleNetId=tonumber(carried.originVehicleNetId),
        originDepartmentId=tonumber(carried.originDepartmentId),
    }
    FE.bags[netId]=bag
    FE.bagByOwner[src]=netId
    FE.carriedBags[src]=nil
    setCarryState(src,false)
    TriggerClientEvent('fiveems:client:fieldBagCarryStop',src)
    local st=Entity(entity).state
    if st then
        st:set('fiveems:medicalBag',true,true)
        st:set('fiveems:medicalBagOwner',src,true)
    end
    savePhysicalBag(bag)
    Server.notify(src,'Bolsa medica colocada. Use o ox_target para abrir, retirar itens ou recolher.')
end)

RegisterNetEvent('fiveems:server:fieldBagOpen',function(netId)
    local src=source
    syncFieldItems(src)
    local bag=FE.bags[tonumber(netId)]
    if not bag then return Server.notify(src,'Bolsa medica nao encontrada.') end
    if not sourceNearEntity(src,bag.entity,tonumber(((cfg().medicalBag or {}).openDistance)) or 2.5) then return end
    sendBagData(src,bag)
end)

RegisterNetEvent('fiveems:server:fieldBagTake',function(netId,itemName,count)
    local src=source
    local bag=FE.bags[tonumber(netId)]
    if not bag or not sourceNearEntity(src,bag.entity,3.0) then return end
    itemName=tostring(itemName or '')
    count=math.max(1,math.floor(tonumber(count) or 1))
    local loadout=FiveEMS.Clinical and FiveEMS.Clinical.bagLoadout or {}
    if not loadout[itemName] then return end
    local have=tonumber(bag.contents[itemName]) or 0
    if have<count then return Server.notify(src,'Quantidade insuficiente na bolsa.') end
    bag.contents[itemName]=have-count
    FE.fieldItems[src]=FE.fieldItems[src] or {}
    FE.fieldItems[src][itemName]=(tonumber(FE.fieldItems[src][itemName]) or 0)+count
    syncFieldItems(src)
    savePhysicalBag(bag)
    sendBagData(src,bag)
end)

RegisterNetEvent('fiveems:server:fieldBagReturn',function(netId,itemName,count)
    local src=source
    local bag=FE.bags[tonumber(netId)]
    if not bag or not sourceNearEntity(src,bag.entity,3.0) then return end
    itemName=tostring(itemName or '')
    count=math.max(1,math.floor(tonumber(count) or 1))
    local hand=FE.fieldItems[src] or {}
    local have=tonumber(hand[itemName]) or 0
    if have<count then return Server.notify(src,'Voce nao esta com esse item em maos.') end
    hand[itemName]=have-count
    FE.fieldItems[src]=hand
    syncFieldItems(src)
    bag.contents[itemName]=(tonumber(bag.contents[itemName]) or 0)+count
    savePhysicalBag(bag)
    sendBagData(src,bag)
end)

RegisterNetEvent('fiveems:server:fieldBagStore',function(netId)
    local src=source
    if FE.carriedBags[src] then return Server.notify(src,'Voce ja esta carregando uma bolsa medica.') end
    local own=FE.bagByOwner[src]
    if own and FE.bags[own] and tonumber(own)~=tonumber(netId) then
        return Server.notify(src,'Voce ja possui outra bolsa medica colocada na cena.')
    end
    local bag=FE.bags[tonumber(netId)]
    if not bag or not sourceNearEntity(src,bag.entity,3.0) then return end
    if tonumber(bag.owner)~=tonumber(src) then return Server.notify(src,'Somente o profissional que colocou esta bolsa pode recolhe-la.') end
    if not Server.hasPermission(src,'patient.treat') and not Server.hasPermission(src,'supplies.use') then return end
    local transfer={ownerIdentifier=bag.ownerIdentifier,contents=copyTable(bag.contents or {}),model=bag.model,originVehicleNetId=bag.originVehicleNetId,originDepartmentId=bag.originDepartmentId}
    removeBag(netId)
    local ok,err=beginCarryingBag(src,transfer)
    if not ok then
        if err then Server.notify(src,err) end
        return
    end
    Server.notify(src,'Bolsa medica recolhida. Ela esta novamente em suas maos.')
end)

local function setVehicleBagStored(vehicleNetId,stored,departmentId)
    vehicleNetId=tonumber(vehicleNetId)
    local vehicle=entityFromNet(vehicleNetId)
    if vehicle~=0 then
        local st=Entity(vehicle).state
        if st then
            st:set('fiveems:vehicleMedicalBagStored',stored==true,true)
            if departmentId then st:set('fiveems:vehicleMedicalBagDepartmentId',tonumber(departmentId),true) end
        end
    end
end

local function restoreOriginVehicleBag(carriedOrBag)
    local origin=tonumber(carriedOrBag and carriedOrBag.originVehicleNetId)
    if not origin then return end
    FE.vehicleBagReservations[origin]=nil
    if type(carriedOrBag.contents)=='table' then FE.vehicleBagContents[origin]=copyTable(carriedOrBag.contents) end
    setVehicleBagStored(origin,true,tonumber(carriedOrBag.originDepartmentId))
end

local function memberAndVehicleProfile(src,vehicleNetId,requestedDepartmentId)
    local member=Server.getMember(src)
    local admin=Server.isAdmin(src)
    if not member and not admin then return nil,nil,'Sem departamento.' end
    if not admin and not Server.hasPermission(src,'supplies.use') then return nil,nil,_L('no_permission') end

    local vehicle=entityFromNet(vehicleNetId)
    if vehicle==0 or GetEntityType(vehicle)~=2 then return nil,nil,'Viatura nao encontrada.' end
    if not sourceNearEntity(src,vehicle,7.0) then return nil,nil,'Aproxime-se da viatura.' end

    local requested=tonumber(requestedDepartmentId)
    local selectedDepartmentId=member and tonumber(member.department_id) or nil

    -- O cliente informa qual hotspot configurado foi atingido. Um membro comum
    -- nunca pode saltar para outro departamento; admins podem testar o perfil
    -- que acabaram de criar mesmo sem estarem vinculados a ele.
    if requested then
        if not admin and selectedDepartmentId and requested~=selectedDepartmentId then
            return nil,nil,_L('no_permission')
        end
        if admin or not selectedDepartmentId then selectedDepartmentId=requested end
    end

    if not selectedDepartmentId then
        return nil,nil,'Nao foi possivel determinar o departamento do compartimento.'
    end

    local rows=DB.query(
        'SELECT * FROM fiveems_vehicle_equipment_profiles WHERE department_id=? AND enabled=1',
        {selectedDepartmentId}
    ) or {}
    local model=GetEntityModel(vehicle)
    for _,row in ipairs(rows) do
        if joaat(tostring(row.vehicle_model or ''))==model then
            row.transform=DB.jsonDecode(row.transform,{})
            local context={}
            for k,v in pairs(member or {}) do context[k]=v end
            context.department_id=selectedDepartmentId
            context.admin=admin
            return context,{row=row,entity=vehicle},nil
        end
    end
    return nil,nil,'Esta viatura nao possui compartimento EMS configurado para este departamento.'
end

local function vehicleStockPayload(src,vehicleNetId,member)
    local supplies=DB.query('SELECT * FROM fiveems_supplies WHERE department_id=? ORDER BY category,label',{tonumber(member.department_id)}) or {}
    local bagItem=tostring((((cfg().medicalBag or {}).itemName) or 'medical_bag'))
    local filtered={}
    for _,row in ipairs(supplies) do
        if tostring(row.item_name or '')~=bagItem then filtered[#filtered+1]=row end
    end
    local bag=CR.getBag(src)
    return {vehicleNetId=tonumber(vehicleNetId),departmentId=tonumber(member.department_id),supplies=filtered,bag=bag,bagLoadout=FiveEMS.Clinical and FiveEMS.Clinical.bagLoadout or {}}
end

RegisterNetEvent('fiveems:server:vehicleEquipmentOpen',function(vehicleNetId,departmentId)
    local src=source
    local member,profile,err=memberAndVehicleProfile(src,vehicleNetId,departmentId)
    if not member then return Server.notify(src,err) end
    TriggerClientEvent('fiveems:client:vehicleEquipmentOpenData',src,vehicleStockPayload(src,vehicleNetId,member))
end)

local function takeDepartmentSupply(src,departmentId,supplyId,count)
    count=math.max(1,math.min(20,math.floor(tonumber(count) or 1)))
    local row=DB.single('SELECT * FROM fiveems_supplies WHERE id=? AND department_id=?',{tonumber(supplyId),tonumber(departmentId)})
    if not row then return false,'Item nao encontrado.' end
    if tonumber(row.quantity)<count then return false,'Estoque insuficiente.' end
    local ok,err=F.addInventoryItem(src,row.item_name,count,{label=row.label,category=row.category,advanced=tonumber(row.advanced)==1})
    if not ok then return false,err or 'Inventario indisponivel.' end
    DB.update('UPDATE fiveems_supplies SET quantity=quantity-? WHERE id=? AND quantity>=?',{count,row.id,count})
    return true,row
end

RegisterNetEvent('fiveems:server:vehicleEquipmentTakeBag',function(vehicleNetId,departmentId)
    local src=source
    vehicleNetId=tonumber(vehicleNetId)
    local member,profile,err=memberAndVehicleProfile(src,vehicleNetId,departmentId)
    if not member then return Server.notify(src,err) end
    if FE.carriedBags[src] then return Server.notify(src,'Voce ja esta carregando uma bolsa medica.') end
    local existing=FE.bagByOwner[src]
    if existing and FE.bags[existing] then return Server.notify(src,'Sua bolsa medica ja esta colocada na cena.') end

    local vehicle=entityFromNet(vehicleNetId)
    if vehicle==0 then return Server.notify(src,'Viatura nao encontrada.') end
    local state=Entity(vehicle).state
    if state and state['fiveems:vehicleMedicalBagStored']==false then
        return Server.notify(src,'A bolsa medica desta viatura ja foi retirada.')
    end
    local reservation=FE.vehicleBagReservations[vehicleNetId]
    if reservation and tonumber(reservation.owner)~=tonumber(src) then
        return Server.notify(src,'A bolsa medica desta viatura ja esta em uso.')
    end

    local vehicleContents=FE.vehicleBagContents[vehicleNetId]
    if type(vehicleContents)~='table' then vehicleContents=copyTable(CR.getBag(src) or {}) end
    local ok,carryErr=beginCarryingBag(src,{
        ownerIdentifier=Server.getPrimaryIdentifier(src),
        contents=copyTable(vehicleContents),
        originVehicleNetId=vehicleNetId,
        originDepartmentId=tonumber(member.department_id),
    })
    if not ok then return Server.notify(src,carryErr or 'Nao foi possivel retirar a bolsa medica.') end

    FE.vehicleBagContents[vehicleNetId]=nil
    FE.vehicleBagReservations[vehicleNetId]={owner=src,departmentId=tonumber(member.department_id)}
    setVehicleBagStored(vehicleNetId,false,tonumber(member.department_id))
    Server.notify(src,'Bolsa medica retirada da viatura e colocada em suas maos.')
end)

RegisterNetEvent('fiveems:server:vehicleEquipmentStoreBag',function(vehicleNetId,departmentId)
    local src=source
    vehicleNetId=tonumber(vehicleNetId)
    local member,profile,err=memberAndVehicleProfile(src,vehicleNetId,departmentId)
    if not member then return Server.notify(src,err) end
    local carried=FE.carriedBags[src]
    if not carried then return Server.notify(src,'Voce nao esta carregando uma bolsa medica.') end

    local vehicle=entityFromNet(vehicleNetId)
    if vehicle==0 then return Server.notify(src,'Viatura nao encontrada.') end
    local state=Entity(vehicle).state
    if not (state and state['fiveems:vehicleMedicalBagStored']==false) then
        return Server.notify(src,'O suporte desta viatura ja possui uma bolsa medica.')
    end

    local targetDept=tonumber(member.department_id)
    if carried.originDepartmentId and tonumber(carried.originDepartmentId)~=targetDept and not Server.isAdmin(src) then
        return Server.notify(src,'Esta bolsa pertence a outro departamento.')
    end

    saveCarriedBag(carried)
    local oldOrigin=tonumber(carried.originVehicleNetId)
    FE.carriedBags[src]=nil
    setCarryState(src,false)
    TriggerClientEvent('fiveems:client:fieldBagCarryStop',src)

    if oldOrigin then FE.vehicleBagReservations[oldOrigin]=nil end
    FE.vehicleBagReservations[vehicleNetId]=nil
    FE.vehicleBagContents[vehicleNetId]=copyTable(carried.contents or {})
    setVehicleBagStored(vehicleNetId,true,targetDept)
    Server.notify(src,'Bolsa medica guardada novamente na viatura.')
end)

RegisterNetEvent('fiveems:server:vehicleEquipmentTake',function(vehicleNetId,supplyId,count,departmentId)
    local src=source
    local member,profile,err=memberAndVehicleProfile(src,vehicleNetId,departmentId)
    if not member then return Server.notify(src,err) end
    local selected=DB.single('SELECT * FROM fiveems_supplies WHERE id=? AND department_id=?',{tonumber(supplyId),tonumber(member.department_id)})
    if not selected then return Server.notify(src,'Item nao encontrado.') end
    local bagItem=tostring((((cfg().medicalBag or {}).itemName) or 'medical_bag'))
    if tostring(selected.item_name or '')==bagItem then
        return Server.notify(src,'A bolsa medica agora e retirada fisicamente do suporte da viatura com o ox_target.')
    else
        local ok,rowOrErr=takeDepartmentSupply(src,member.department_id,supplyId,count)
        if not ok then return Server.notify(src,rowOrErr) end
        Server.notify(src,('Retirado da viatura: %s.'):format(rowOrErr.label or rowOrErr.item_name))
    end
    TriggerClientEvent('fiveems:client:vehicleEquipmentOpenData',src,vehicleStockPayload(src,vehicleNetId,member))
end)

RegisterNetEvent('fiveems:server:vehicleEquipmentLoadBag',function(vehicleNetId,supplyId,count,departmentId)
    local src=source
    local member,profile,err=memberAndVehicleProfile(src,vehicleNetId,departmentId)
    if not member then return Server.notify(src,err) end
    count=math.max(1,math.min(20,math.floor(tonumber(count) or 1)))
    local row=DB.single('SELECT * FROM fiveems_supplies WHERE id=? AND department_id=?',{tonumber(supplyId),tonumber(member.department_id)})
    if not row then return end
    local item=tostring(row.item_name or '')
    local target=FiveEMS.Clinical and FiveEMS.Clinical.bagLoadout and tonumber(FiveEMS.Clinical.bagLoadout[item]) or nil
    if not target then return Server.notify(src,'Esse item nao pertence ao loadout da bolsa medica.') end
    local bag=CR.getBag(src)
    local have=tonumber(bag[item]) or 0
    local add=math.min(count,math.max(0,target-have),tonumber(row.quantity) or 0)
    if add<=0 then return Server.notify(src,'Bolsa ja esta na quantidade alvo ou estoque insuficiente.') end
    DB.update('UPDATE fiveems_supplies SET quantity=quantity-? WHERE id=? AND quantity>=?',{add,row.id,add})
    bag[item]=have+add
    CR.saveBagByIdentifier(Server.getPrimaryIdentifier(src),bag)
    Server.notify(src,('Bolsa: +%d %s.'):format(add,row.label or item))
    TriggerClientEvent('fiveems:client:vehicleEquipmentOpenData',src,vehicleStockPayload(src,vehicleNetId,member))
end)

RegisterNetEvent('fiveems:server:vehicleEquipmentRestockBag',function(vehicleNetId,departmentId)
    local src=source
    local member,profile,err=memberAndVehicleProfile(src,vehicleNetId,departmentId)
    if not member then return Server.notify(src,err) end
    local bag=CR.getBag(src)
    local changed=0
    for item,target in pairs(FiveEMS.Clinical and FiveEMS.Clinical.bagLoadout or {}) do
        local have=tonumber(bag[item]) or 0
        local need=math.max(0,(tonumber(target) or 0)-have)
        if need>0 then
            local row=DB.single('SELECT * FROM fiveems_supplies WHERE department_id=? AND item_name=?',{tonumber(member.department_id),item})
            if row and tonumber(row.quantity)>0 then
                local add=math.min(need,tonumber(row.quantity) or 0)
                if add>0 then
                    DB.update('UPDATE fiveems_supplies SET quantity=quantity-? WHERE id=? AND quantity>=?',{add,row.id,add})
                    bag[item]=have+add
                    changed=changed+add
                end
            end
        end
    end
    CR.saveBagByIdentifier(Server.getPrimaryIdentifier(src),bag)
    Server.notify(src,('Bolsa reabastecida pela viatura: %d item(ns).'):format(changed))
    TriggerClientEvent('fiveems:client:vehicleEquipmentOpenData',src,vehicleStockPayload(src,vehicleNetId,member))
end)



-- V0.4.8 - Equipamentos portateis addon (LUCAS / CombiCarrier)
local function portableEquipmentDefinition(key)
    key=tostring(key or '')
    local defs=((cfg().portableEquipment) or {})
    local def=defs[key]
    if type(def)~='table' then return nil,key end
    return def,key
end

local function portableOwnerSlot(src,key)
    return ('%d:%s'):format(tonumber(src) or 0,tostring(key or ''))
end

local function hasPortableEquipmentItem(src,def)
    local itemName=tostring((def and def.itemName) or '')
    if itemName=='' then return false end
    return F and F.hasExactFiveEMSItem and F.hasExactFiveEMSItem(src,itemName,1) or false
end

local function removePortableEquipment(netId,reason)
    netId=tonumber(netId)
    local row=netId and FE.portableEquipment[netId] or nil
    if not row then return false end
    FE.portableEquipment[netId]=nil
    local slot=portableOwnerSlot(row.owner,row.key)
    if FE.portableEquipmentByOwner[slot]==netId then FE.portableEquipmentByOwner[slot]=nil end
    if row.entity and row.entity~=0 and DoesEntityExist(row.entity) then DeleteEntity(row.entity) end
    if row.owner and reason then Server.notify(row.owner,reason) end
    return true
end

RegisterNetEvent('fiveems:server:portableEquipmentUseRequest',function(key)
    local src=source
    local def,equipKey=portableEquipmentDefinition(key)
    if not def then return Server.notify(src,'Equipamento EMS desconhecido.') end
    if not Server.hasPermission(src,'patient.treat') and not Server.hasPermission(src,'supplies.use') then
        return Server.notify(src,_L('no_permission'))
    end
    if not hasPortableEquipmentItem(src,def) then
        return Server.notify(src,('Retire %s no estoque ou na ambulancia primeiro.'):format(tostring(def.label or equipKey)))
    end
    local slot=portableOwnerSlot(src,equipKey)
    local existing=FE.portableEquipmentByOwner[slot]
    if existing and FE.portableEquipment[existing] then
        return Server.notify(src,('Voce ja colocou %s na cena.'):format(tostring(def.label or equipKey)))
    end
    TriggerClientEvent('fiveems:client:portableEquipmentBeginPlacement',src,equipKey)
end)

RegisterNetEvent('fiveems:server:portableEquipmentDeploy',function(key,payload)
    local src=source
    local def,equipKey=portableEquipmentDefinition(key)
    if not def then return end
    if not hasPortableEquipmentItem(src,def) then return end
    local slot=portableOwnerSlot(src,equipKey)
    local existing=FE.portableEquipmentByOwner[slot]
    if existing and FE.portableEquipment[existing] then return end

    payload=type(payload)=='table' and payload or {}
    local x,y,z=tonumber(payload.x),tonumber(payload.y),tonumber(payload.z)
    local heading=tonumber(payload.heading) or 0.0
    if not x or not y or not z then return end
    local ped=GetPlayerPed(src)
    if not ped or ped==0 or not DoesEntityExist(ped) then return end
    if dist(GetEntityCoords(ped),vector3(x,y,z))>5.0 then
        return Server.notify(src,'Posicione o equipamento mais proximo de voce.')
    end

    local modelName=tostring(def.model or '')
    local model=joaat(modelName)
    local entity=CreateObject(model,x,y,z,true,true,false)
    if not entity or entity==0 then
        return Server.notify(src,('Nao foi possivel criar %s (%s).'):format(tostring(def.label or equipKey),modelName))
    end
    SetEntityHeading(entity,heading)
    FreezeEntityPosition(entity,true)
    pcall(function() SetEntityOrphanMode(entity,2) end)
    local deadline=GetGameTimer()+2500
    local netId=NetworkGetNetworkIdFromEntity(entity)
    while (not netId or netId==0) and GetGameTimer()<deadline do Wait(0); netId=NetworkGetNetworkIdFromEntity(entity) end
    if not netId or netId==0 then DeleteEntity(entity); return Server.notify(src,'Falha ao sincronizar equipamento EMS no OneSync.') end

    FE.portableEquipment[netId]={netId=netId,entity=entity,owner=src,key=equipKey,model=modelName}
    FE.portableEquipmentByOwner[slot]=netId
    local st=Entity(entity).state
    if st then
        st:set('fiveems:portableEquipment',true,true)
        st:set('fiveems:portableEquipmentType',equipKey,true)
        st:set('fiveems:portableEquipmentOwner',src,true)
    end
    Server.notify(src,('%s colocado na cena. Use o ox_target para recolher.'):format(tostring(def.label or equipKey)))
end)

RegisterNetEvent('fiveems:server:portableEquipmentStore',function(netId)
    local src=source
    netId=tonumber(netId)
    local row=netId and FE.portableEquipment[netId] or nil
    if not row then return end
    local def=portableEquipmentDefinition(row.key)
    local maxDist=tonumber(def and def.openDistance) or 2.8
    if not sourceNearEntity(src,row.entity,maxDist+0.8) then return end
    if not Server.hasPermission(src,'patient.treat') and not Server.hasPermission(src,'supplies.use') then return end
    removePortableEquipment(netId,nil)
    Server.notify(src,('%s recolhido da cena.'):format(tostring((def and def.label) or row.key)))
end)

AddEventHandler('playerDropped',function()
    local src=source
    FE.fieldItems[src]=nil
    local carried=FE.carriedBags[src]
    if carried then
        saveCarriedBag(carried)
        restoreOriginVehicleBag(carried)
        FE.carriedBags[src]=nil
    end
    setCarryState(src,false)
    local netId=FE.bagByOwner[src]
    if netId and FE.bags[netId] then
        local placed=FE.bags[netId]
        local originData={originVehicleNetId=placed.originVehicleNetId,originDepartmentId=placed.originDepartmentId}
        removeBag(netId)
        restoreOriginVehicleBag(originData)
    end
    local ids={}
    for id,row in pairs(FE.portableEquipment) do if row.owner==src then ids[#ids+1]=id end end
    for _,id in ipairs(ids) do removePortableEquipment(id,nil) end
end)

AddEventHandler('onResourceStop',function(resourceName)
    if resourceName~=GetCurrentResourceName() then return end
    for _,carried in pairs(FE.carriedBags) do
        saveCarriedBag(carried)
        restoreOriginVehicleBag(carried)
    end
    for vehicleNetId,reservation in pairs(FE.vehicleBagReservations) do
        setVehicleBagStored(vehicleNetId,true,reservation and reservation.departmentId)
    end
    for netId,bag in pairs(FE.bags) do
        savePhysicalBag(bag)
        if bag.entity and DoesEntityExist(bag.entity) then DeleteEntity(bag.entity) end
    end
    local portableIds={}
    for netId in pairs(FE.portableEquipment) do portableIds[#portableIds+1]=netId end
    for _,netId in ipairs(portableIds) do removePortableEquipment(netId,nil) end
end)
