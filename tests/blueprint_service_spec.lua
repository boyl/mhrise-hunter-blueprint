local B=require('LoadoutClone.blueprints')
local A=require('LoadoutClone.appearance')
local S=require('LoadoutClone.blueprint_service')
local snapshot={schema=1,weapon_id=134217729,weapon_hidden=true,armor_ids={0,4096,8192,12288,16384},colors={{},{}},weapon_color={enabled=false}}
for c=1,2 do for p=1,5 do snapshot.colors[c][p]={enabled=false}end end
local entry={id=1,name='暖暖',snapshot=snapshot,origin={name='A',sex=0,weapon_type=1},created=1}
local current={identity='b',origin={name='B',sex=1,weapon_type=2},snapshot=B.copy(snapshot)}
local lib={find=function()return B.copy(entry)end}
local n={capture=function()return B.copy(current)end,adapt=function(_,s)return B.copy(s),{}end,describe=function()return {}end}
n.weapon_type=function()return entry.origin.weapon_type end
local service=S.new(lib,n,{weapon_visibility_available=false},function()error('不应写入')end)
assert(not pcall(service.preview,service,1,{include_weapon=true}))
local preview=service:preview(1,{include_weapon=false})
assert(A.same(preview.snapshot.armor_ids,snapshot.armor_ids) and preview.snapshot.weapon_id==current.snapshot.weapon_id)
assert(not pcall(service.preview,service,1,{include_weapon=false,copy_weapon_visibility=true}))
current.identity='c';assert(not pcall(service.import,service,preview));current.identity='b'
entry.name='changed';assert(not pcall(service.import,service,preview));entry.name='暖暖'
entry.origin.weapon_type=2;snapshot.weapon_color={enabled=true,hsv={0,0,0}}
assert(not pcall(service.preview,service,1,{include_weapon=true}))
assert(service:preview(1,{include_weapon=false}))
print('PASS 蓝图武器类型与显示能力拒绝、只防具保留武器、身份变化与蓝图修改阻止导入、百龙染色不静默丢失')
