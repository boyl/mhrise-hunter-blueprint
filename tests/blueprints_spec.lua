local B=require('LoadoutClone.blueprints')
local data,backup,fail=nil,nil,false
local store=B.new({load=function()return B.copy(data)end,exists=function()return data~=nil end,
 backup=function(v)backup=B.copy(v);return true end,write=function(v)if fail then fail=false;data={broken=true};return false end;data=B.copy(v);return true end})
local s={schema=1,weapon_id=134217728,weapon_hidden=false,armor_ids={0,4096,8192,12288,16384},colors={{},{}} ,weapon_color={enabled=false}}
for c=1,2 do for p=1,5 do s.colors[c][p]={enabled=true,hsv={120,50,60}}end end
local origin={name='猎人',sex=0,weapon_type=3}
local a=store:add('暖暖',origin,s,100)
local b=store:add('暖暖',origin,s,101)
assert(a.id~=b.id and b.name=='暖暖 (2)' and store:load().count==2)
s.colors[1][1].hsv[1]=1;assert(store:find(a.id).snapshot.colors[1][1].hsv[1]==120)
store:rename(b.id,'换装');assert(store:find(b.id).name=='换装')
local before=B.copy(data);fail=true
assert(not pcall(store.remove,store,a.id));assert(require('LoadoutClone.appearance').same(data,before))
store:remove(a.id);assert(store:load().count==1 and store:find(b.id))
local corrupt=B.copy(data);corrupt.entries[1].snapshot.colors[1][1].hsv[1]=361
assert(not pcall(B.validate,corrupt))
corrupt=B.copy(data);corrupt.entries[1].origin.sex=3;assert(not pcall(B.validate,corrupt))
data={broken=true};assert(not pcall(store.add,store,'new',origin,s,102));assert(data.broken)
local missing=B.new({load=function()return nil end,exists=function()return true end});assert(not pcall(missing.load,missing))
assert(not pcall(B.name,'\n'));assert(not pcall(B.name,string.rep('名',49)))
print('PASS 蓝图库同名独立保存、隔离源数据、改名删除、部分写入恢复、损坏与无效输入拒绝')


data=nil
local payload={schema=1,data={_weaponParam={WeaponId=1},_armorParam={{ArmorId=1},{ArmorId=2},{ArmorId=3},{ArmorId=4},{ArmorId=5}},_lvBuffParam={id=1},_talismanParam={empty=true},_equipStatusParam={isMRRelease=true,switchActionId={1,2,3},switchActionId_MR_1={1,2,3,4,5},switchActionId_MR_2={1,2,3,4,5}}}}
local old=store:add('旧外观',origin,s,101)
local full=store:add('完整配装',origin,s,102,payload)
assert(store:load().schema==2 and store:find(full.id).equipment.data._weaponParam.WeaponId==1)
assert(store:find(old.id).equipment==nil)
payload.data._weaponParam.WeaponId=2;assert(store:find(full.id).equipment.data._weaponParam.WeaponId==1)
local broken=B.copy(data);broken.entries[2].equipment.data._weaponParam.WeaponId=0/0;assert(not pcall(B.validate,broken))
broken=B.copy(data);broken.entries[2].equipment.data._armorParam[5]=nil;assert(not pcall(B.validate,broken))
broken=B.copy(data);broken.entries[2].equipment.data._equipStatusParam.switchActionId_MR_1={1};assert(not pcall(B.validate,broken))
print('PASS 完整蓝图版本升级、旧外观共存、快照隔离、畸形装备及替换技拒绝')

local empty=B.copy(store:find(full.id).equipment);empty.data._weaponParam.EquipSkill={};empty.data._weaponParam.EquipSkillLv={}
local encoded=B.equipment(empty);assert(#encoded.empty_arrays==2)
encoded.data._weaponParam.EquipSkill=nil;encoded.data._weaponParam.EquipSkillLv=nil
local restored=B.equipment(encoded);assert(type(restored.data._weaponParam.EquipSkill)=='table' and #restored.data._weaponParam.EquipSkill==0)
encoded.data._weaponParam.EquipSkill={99};assert(not pcall(B.equipment,encoded))
print('PASS REFramework 空数组转 null 的回读恢复与伪造空数组标记拒绝')

-- 原生本机染色的两个标志独立，禁用通道也可能保存已调好的颜色。
local Color=require('LoadoutClone.appearance_color')
local Same=require('LoadoutClone.appearance').same
for _,enabled in ipairs({false,true})do for _,default in ipairs({false,true})do
 local input=B.copy(s)
 for ch=1,2 do for part=1,5 do input.colors[ch][part]={enabled=enabled,default=default,hsv={part*30,ch*40,80}}end end
 input.weapon_color={enabled=enabled,default=default,hsv={0,100,80}}
 local normalized=B.snapshot(input)
 assert(Same(normalized,input),'蓝图不得丢弃原生染色标志或禁用通道 HSV')
 assert(Same(B.snapshot(normalized),normalized),'染色规范化必须幂等')
 for ch=1,2 do for part=1,5 do
  assert(Same(Color.from_snapshot(normalized.colors[ch][part]),input.colors[ch][part]))
 end end
 assert(Same(Color.from_snapshot(normalized.weapon_color),input.weapon_color))
 data=nil
 local entry=store:add('染色回归',origin,input,103)
 assert(Same(store:find(entry.id).snapshot,input),'磁盘边界往返必须保留全部染色字段')
end end
local legacy=B.copy(s);legacy.weapon_color={enabled=false}
assert(Same(B.snapshot(legacy),legacy),'旧蓝图无新增字段时保持原有表示')
assert(Color.from_snapshot({enabled=false}).default==true)
assert(Color.from_snapshot({enabled=true,hsv={0,100,80}}).default==false)
assert(not pcall(Color.from_snapshot,{enabled=true,default='false',hsv={0,100,80}}))
assert(not pcall(Color.from_snapshot,{enabled=false,default=false}))
print('PASS 两种标志四组合、十通道与武器颜色无损往返、旧格式兼容及畸形标志拒绝')
