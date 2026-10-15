-- Run with Lua 5.4 from FiveEMS/: lua tests/garage_server_test.lua
local file=assert(io.open('server/departments.lua'));local code=file:read('*a');file:close()
local handlers={}
lib={callback={register=function(name,fn)handlers[name]=fn end}}
function RegisterNetEvent(name,fn) handlers[name]=fn end
local admin, member, permission, point, vehicle, affected
local notices, events, writes
source=1
FiveEMS={PointTypes={GARAGE='garage'}}
function _L(key)return key end
Server={isAdmin=function()return admin end,getMember=function()return member end,
 hasPermission=function()return permission end,notify=function(_,msg)notices[#notices+1]=msg end,audit=function()end}
DB={single=function(sql,args)
 if sql:find('fiveems_points') then return point end
 if sql:find('fiveems_vehicles') then
  if vehicle and args[2]==vehicle.department_id then return vehicle end
 end
end,jsonDecode=function(v)return v end,jsonEncode=function(v)return v end,
 update=function(sql,args)writes[#writes+1]={sql,args};return affected end,
 insert=function(sql,args)writes[#writes+1]={sql,args};return 10 end}
D={getFull=function(id)return {id=id} end,broadcastWorldDepartments=function()end}
function TriggerClientEvent(...)events[#events+1]={...}end
local function section(start,stop)
 local a=assert(code:find(start,1,true));local b=assert(code:find(stop,a+#start,true))
 assert(load(code:sub(a,b-1)))()
end
section('-- Mutate the persisted slot list',"RegisterNetEvent('fiveems:server:savePoint'")
section("RegisterNetEvent('fiveems:server:savePoint'", "RegisterNetEvent('fiveems:server:createCarePoint'")
section('local function canManageFleet','RegisterNetEvent(\'fiveems:server:saveSupply\'')
section("RegisterNetEvent('fiveems:server:requestVehicle'","RegisterNetEvent('fiveems:server:initStretcherState'")
local count=0
local function reset()
 admin=false;permission=true;member={department_id=2,level=5}
 point={id=8,department_id=2,data={spawns={{x=1,y=2,z=3}}}}
 vehicle={id=3,department_id=2,model='ambulance',min_level=1}
 affected=1;notices={};events={};writes={}
end
local function test(name,fn)reset();fn();count=count+1;print('PASS '..name)end
local request=handlers['fiveems:server:requestVehicle']
test('spawn receives saved garage slots',function()request(3,8);assert(events[1][4].data.spawns[1].x==1)end)
test('admin can test another department without membership',function()admin=true;member=nil;request(3,8);assert(#events==1)end)
test('cross department spawn denied',function()member.department_id=9;request(3,8);assert(#events==0 and #notices==1)end)
test('missing point rejected',function()request(3,nil);assert(#events==0 and #notices==1)end)
test('missing slots rejected',function()point.data.spawns={};request(3,8);assert(#events==0 and #notices==1)end)
test('level restriction',function()vehicle.min_level=10;request(3,8);assert(#events==0)end)
test('vehicle from another department rejected',function()vehicle.department_id=9;request(3,8);assert(#events==0)end)
local save=handlers['fiveems:server:saveVehicle'];local delete=handlers['fiveems:server:deleteVehicle']
test('edit uses update and preserves settings',function()save(2,{id=3,label='EMS',model='ambulance',settings={extras={1}}});assert(writes[1][1]:find('UPDATE'));assert(writes[1][2][4].extras[1]==1)end)
test('delete scoped to department and refreshes catalog',function()delete(2,3);assert(writes[1][2][1]==3 and writes[1][2][2]==2);assert(events[1][3].id==2)end)
test('cross department edits denied',function()save(9,{id=3,label='EMS',model='ambulance'});delete(9,3);assert(#writes==0)end)
test('permission required',function()permission=false;save(2,{label='EMS',model='ambulance'});delete(2,3);request(3,8);assert(#writes==0 and #events==0)end)
test('empty model rejected',function()save(2,{label='EMS',model='  '});assert(#writes==0)end)
local deleteSlot=handlers['fiveems:server:deleteGarageSpawn']
test('slot deletion persists only the current slot list',function()
 point.data.interaction={kind='ped'};point.data.spawns[2]={x=4,y=5,z=6}
 local result=deleteSlot(1,2,8,1,{x=1,y=2,z=3})
 assert(result.ok and result.department.id==2)
 assert(writes[1][2][1].spawns[1].x==4 and #writes[1][2][1].spawns==1)
 assert(writes[1][2][1].interaction.kind=='ped')
end)
test('last slot clears configured state',function()
 local result=deleteSlot(1,2,8,1,{x=1,y=2,z=3})
 assert(result.ok and #writes[1][2][1].spawns==0 and not writes[1][2][1].garage_configured)
end)
test('invalid slot index rejected',function()
 assert(not deleteSlot(1,2,8,0,{}).ok);assert(not deleteSlot(1,2,8,1.5,{}).ok);assert(#writes==0)
end)
test('stale slot coordinates rejected',function()
 assert(not deleteSlot(1,2,8,1,{x=4,y=5,z=6}).ok);assert(#writes==0)
end)
test('slot deletion cross department denied',function()
 assert(not deleteSlot(1,9,8,1,{x=1,y=2,z=3}).ok);assert(#writes==0)
end)
test('slot deletion requires management permission',function()
 permission=false;assert(not deleteSlot(1,2,8,1,{x=1,y=2,z=3}).ok);assert(#writes==0)
end)
test('failed or concurrent write never confirms deletion',function()
 affected=0;assert(not deleteSlot(1,2,8,1,{x=1,y=2,z=3}).ok)
end)
test('saving garage metadata preserves persisted slots over stale UI data',function()
 handlers['fiveems:server:savePoint'](2,{id=8,type='garage',label='EMS',x=1,y=2,z=3,
  preserveGarageSpawns=true,data={spawns={},blip={sprite=225}}})
 assert(writes[1][2][7].spawns[1].x==1)
 assert(writes[1][2][7].garage_configured and writes[1][2][7].blip.sprite==225)
end)
print(('%d tests passed'):format(count))
