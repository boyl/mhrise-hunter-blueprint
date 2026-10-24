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
local function complete_fixture()
    local w,source,box,manager=fixture()
    manager._HunterMySetList=arr({object({_IsUsing=false,_Name="",_ItemMysetIndex=-1,_EquipMysetIndex=-1,_OverwearMysetIndex=-1})})
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
    return w,source
end
local w,s=complete_fixture()
s.items[8]={kind="talisman",empty=true,candidate={}}
s.snapshot={data={_talismanParam={empty=true}}}
local p=w:prepare(s)
assert(#p.allocated==7 and p.allocated[8]==nil and w.write_count==0)
s.snapshot.data._talismanParam={unavailable=true}
assert(not pcall(w.prepare,w,s))
print("PASS 未装备护石保留空槽，缺少明确空位证据时拒绝（2 项）")
