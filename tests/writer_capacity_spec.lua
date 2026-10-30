local function object(fields)
    fields.get_field=function(self,key) return self[key] end
    return fields
end
local function arr(values)
    values.get_size=function(self) return #self end
    values.get_element=function(self,i) return self[i+1] end
    return values
end
local function equip(index)
    local obj=object({["<InventoryIndex>k__BackingField"]=index,_CustomBuildup={}})
    for _,key in ipairs({"_IdType","_IdVal","_BuildupPoint","_CustomEnable","_CustomCount","_CustomBuildupType","_BowgunCustomizeType","_PairInsectInventoryIndex","_HyakuryuDecoId","_IsLock","_IsSetGuildCard"}) do obj[key]=0 end
    for _,key in ipairs({"_DecoIdList","_CustomOpenIdArray","_TalismanDecoSlotNumList","_TalismanSkillIdList","_TalismanSkillLvList","_HyakuryuSkillIdList","_PrevHyakuryuSkillId"}) do obj[key]={0,0,0} end
    return obj
end
local Native={field=function(obj,key) assert(obj[key]~=nil,key);return obj[key] end,array=function(v) return v end,
    array_access=function(v,max) assert(#v<=max);return #v,function(i) return v[i+1] end end}
function Native.new() return {call=function(_,t,m,obj)
    if m=="isEmpty()" then return obj._IdType==0 or obj._Num==0 end
    if m=="get_MaxCountInBox()" then return 99 end
    error("unexpected native call "..m)
end} end
package.loaded["LoadoutClone.native"]=Native
local Writer=require("LoadoutClone.writer")
local function fixture()
    local items={};for i=1,7 do items[i]=equip(i-1) end
    local box={_WeaponArmorInventoryList={mItems=arr(items),mSize=7},_LvBuffCageInventoryList={mItems=arr({equip(0)}),mSize=1}}
    local deco={_InventoryDataList={mSize=1,mItems=arr({{_Id=1,_Num=99}})}}
    local set=object({_IsUsing=false,_Name="",_InventoryIndexList={},_ActionIdList={},_ActionIdListMR_Red={},_ActionIdListMR_Blue={},_BackupDataList={}})
    local manager={_PlEquipPack={_InventoryIndexList={}},_PlEquipMySetList={set},_HunterMySetList=arr({{_IsUsing=true}})}
    sdk={get_managed_singleton=function(name) if name=="snow.data.DataManager" then return {_PlEquipBox=box,_PlDecorationsBox=deco} end;return manager end}
    local source={items={}}
    for i=1,8 do source.items[i]={kind=i==7 and "petalace" or "armor",object=equip(-1),candidate={decorations={},target={HyakuryuDecorationsId=1048576}}} end
    local writer=Writer.new({});writer.backup=function(_,_,obj) return obj end
    return writer,source,box,manager,deco
end
local function reject(expected,mutate)
    local w,source,box,manager,deco=fixture();mutate(source,box,manager,deco)
    local ok,err=pcall(w.prepare,w,source)
    assert(not ok and tostring(err):find(expected,1,true),tostring(err))
    assert(w.write_count==0,"容量拒绝必须发生在任何写入之前")
end
reject("装备箱空间不足",function(_,box) for _,obj in ipairs(box._WeaponArmorInventoryList.mItems) do obj._IdType=1 end end)
reject("配装列表没有空位",function(_,_,manager) manager._PlEquipMySetList[1]._IsUsing=true end)
reject("猎人个人组合没有空位",function() end)
reject("珠子数量将超过上限",function(source) source.items[1].candidate.decorations={1} end)
reject("珠子箱空间不足",function(source,_,_,deco) source.items[1].candidate.decorations={2};deco._InventoryDataList.mItems[1]._Num=1 end)
print("PASS 装备箱/装备组合/猎人组合满位、珠子数量上限及珠子箱满位均零写入拒绝（5 项）")
local function appearance_fixture(enabled,full)
    local w,source,box,manager=fixture()
    manager._HunterMySetList=arr({object({_IsUsing=false,_Name="",_ItemMysetIndex=-1,_EquipMysetIndex=-1,_OverwearMysetIndex=-1})})
    source.options={copy_appearance=enabled};source.appearance=enabled and {snapshot={}} or nil
    local called=0
    w.appearance={prepare=function(_,candidate,plan)
        called=called+1;assert((plan.source.mode=="appearance_only" or #plan.allocated==8) and candidate==source.appearance)
        if full then error("外观组合没有空位") end
        return {kind="appearance",slot=0}
    end}
    sdk.create_instance=function()
        local o=object({})
        function o:add_ref() return self end
        function o:set_field(k,v) self[k]=v end
        return o
    end
    sdk.create_managed_string=function(v) return v end
    local original=w.native.call
    function w.native:call(t,m,obj,...)
        if m==".ctor()" then return end
        if m=="setupParam" then
            local args={...};obj._IsUsing=true;obj._ItemMysetIndex=args[1];obj._EquipMysetIndex=args[2];obj._OverwearMysetIndex=args[3];return
        end
        return original(self,t,m,obj,...)
    end
    return w,source,function() return called end
end
local w,s,calls=appearance_fixture(false)
local plan=w:prepare(s)
assert(calls()==0 and plan.entries[#plan.entries].expected._OverwearMysetIndex==-1)
print("PASS 关闭外观不触发外观适配器且猎人组合保留 -1")
w,s,calls=appearance_fixture(true)
plan=w:prepare(s)
assert(calls()==1 and plan.entries[#plan.entries-1].kind=="appearance")
assert(plan.entries[#plan.entries].expected._OverwearMysetIndex==0 and plan.overwear_slot==0)
assert(w.write_count==0)
print("PASS 开启外观在猎人组合之前登记并正确关联零号槽")
w,s,calls=appearance_fixture(true,true)
local ok,err=pcall(w.prepare,w,s)
assert(not ok and tostring(err):find("外观组合没有空位",1,true) and w.write_count==0)
print("PASS 外观满槽阻止整套入库，已有装备候选不写入")

local w,s=appearance_fixture(false)
s.items[8]={kind="talisman",empty=true,candidate={}}
s.snapshot={data={_talismanParam={empty=true}}}
local p=w:prepare(s)
assert(#p.allocated==7 and p.allocated[8]==nil and w.write_count==0)
s.snapshot.data._talismanParam={unavailable=true}
assert(not pcall(w.prepare,w,s))
print("PASS 未装备护石保留空槽，缺少明确空位证据时拒绝（2 项）")
for _,augment in ipairs({{false,false},{true,false},{true,true}}) do
 for _,visual in ipairs({{false,false},{true,false},{true,true}}) do
  local w,s=appearance_fixture(visual[1])
  s.options.copy_augments=augment[1];s.options.allow_illegal_augments=augment[2];s.options.copy_weapon_visibility=visual[2]
  local bindings=0
  w.appearance.prepare_binding=function(_,plan)
   bindings=bindings+1;assert(plan.source.options.copy_weapon_visibility==visual[2])
   return {kind="visibility",remove_old_binding=not visual[2]}
  end
  local p=w:prepare(s)
  assert(bindings==(visual[1] and 1 or 0) and w.write_count==0)
  if visual[1] then assert(p.entries[#p.entries].remove_old_binding==not visual[2]) end
 end
end
print("PASS 三种炼化模式 × 三种外观／显示选项的九组事务准备及关闭显示时旧绑定清理")

local w,s=appearance_fixture(true)
s.mode="appearance_only";s.options.appearance_only=true;s.items=nil
local original=sdk.get_managed_singleton
sdk.get_managed_singleton=function(name)assert(name~="snow.data.DataManager","仅外观不能访问装备箱");return original(name)end
local plan=w:prepare(s)
assert(#plan.entries==2 and plan.entries[1].kind=="appearance" and plan.entries[2].kind=="hunter")
assert(plan.entries[2].expected._EquipMysetIndex==-1 and plan.entries[2].expected._ItemMysetIndex==-1)
assert(w.write_count==0 and plan.slot==nil)
print("PASS 仅外观事务不访问装备箱，仅预留外观与猎人组合，装备和道具关联为 -1")

-- 花链已有同款时不应再分配独立库存。
local w,s=appearance_fixture(false)
local data=sdk.get_managed_singleton("snow.data.DataManager")
local cages=data._PlEquipBox._LvBuffCageInventoryList
s.items[7].object._IdType=4;s.items[7].object._IdVal=123
local existing=cages.mItems[1];existing._IdType=4;existing._IdVal=123
local p=w:prepare(s)
assert(p.allocated[7]==existing)
for _,entry in ipairs(p.entries) do assert(entry.dest~=existing,"已有花链不得写入或回滚") end
assert(w.write_count==0)
print("PASS 花链满箱仍复用同款，原对象不进入写入列表")
-- 先有空槽也必须优先复用后方同款；不同类型的相同数值 ID 不匹配。
for _,case in ipairs({"later_match","different_id","different_type","missing","duplicate"}) do
 local w,s=appearance_fixture(false)
 local cages=sdk.get_managed_singleton("snow.data.DataManager")._PlEquipBox._LvBuffCageInventoryList
 local empty,other=equip(0),equip(1)
 s.items[7].object._IdType=4;s.items[7].object._IdVal=123
 other._IdType=case=="different_type" and 2 or 4;other._IdVal=case=="different_id" and 456 or 123
 cages.mItems=arr({empty,other});cages.mSize=2
 if case=="missing" then other._IdType=0 end
 if case=="duplicate" then empty._IdType=4;empty._IdVal=123 end
 local p=w:prepare(s)
 local reused=case=="later_match" or case=="duplicate"
 assert(#p.reused==(reused and 1 or 0))
 assert(p.allocated[7]==(case=="later_match" and other or empty))
 local writes=0;for _,entry in ipairs(p.entries) do if entry.equipment_kind=="petalace" then writes=writes+1 end end
 assert(writes==(reused and 0 or 1))
 if reused then
  w:verify_reused(p)
  local ref=p.reused[1];ref.dest._IdVal=999
  local ok,err=pcall(w.verify_reused,w,p);assert(not ok and tostring(err):find("复用花链已变化",1,true))
  ref.dest._IdVal=123
  ref.dest["<InventoryIndex>k__BackingField"]=99
  assert(not pcall(w.verify_reused,w,p))
  ref.dest["<InventoryIndex>k__BackingField"]=ref.index
  cages.mItems[ref.position+1]=equip(ref.index)
  assert(not pcall(w.verify_reused,w,p))
 end
end
print("PASS 后方同款优先、异 ID/类型不复用、缺少时新增、重复同款选首项、引用/ID/索引变化拒绝")

-- 失败回滚仅处理新条目，原花链不得被复制或恢复。
local w,s=appearance_fixture(false)
local existing=sdk.get_managed_singleton("snow.data.DataManager")._PlEquipBox._LvBuffCageInventoryList.mItems[1]
existing._IdType=4;existing._IdVal=123;s.items[7].object._IdType=4;s.items[7].object._IdVal=123
local prepared=w:prepare(s)
w.prepare=function() return prepared end
w.assert_context=function(self,p) self:verify_reused(p) end
local touched=0
w.apply=function(_,entry) assert(entry.dest~=existing);entry.write_started=true;touched=touched+1;error("fault") end
w.restore=function(_,entry) assert(entry.dest~=existing);touched=touched-1 end
w.verify_restored=function() end
local result=w.transaction:execute(s)
assert(not result.ok and result.code=="failed" and touched==0 and existing._IdVal==123 and existing._IdType==4)
print("PASS 复用花链在写入失败及回滚期间不被修改")
