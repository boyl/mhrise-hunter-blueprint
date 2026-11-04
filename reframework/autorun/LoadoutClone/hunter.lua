-- 猎人个人组合只关联已验证的配装；-1 是游戏原生的“不关联”值。
local Native=require("LoadoutClone.native")
local M={type_name="snow.data.HunterMySetData"}
function M.state(obj)
    local out={}
    for _,key in ipairs({"_IsUsing","_ItemMysetIndex","_EquipMysetIndex","_OverwearMysetIndex"}) do out[key]=Native.field(obj,key) end
    out._Name=obj:get_field("_Name") or ""
    return out
end
function M.prepare(native,manager,equip_slot,overwear_slot,name)
    local list=Native.field(manager,"_HunterMySetList")
    assert(list:get_size()<=1024,"猎人组合数量超出范围")
    local slot
    for i=list:get_size()-1,0,-1 do if not Native.field(list:get_element(i),"_IsUsing") then slot=i;break end end
    assert(slot,"猎人个人组合没有空位")
    local dest=list:get_element(slot)
    local staged=assert(sdk.create_instance(M.type_name,true)):add_ref()
    native:call(M.type_name,".ctor()",staged)
    native:call(M.type_name,"setupParam",staged,-1,equip_slot,overwear_slot or -1)
    staged:set_field("_Name",sdk.create_managed_string(name or ("大厅复制 "..(slot+1))))
    local expected=M.state(staged)
    assert(expected._IsUsing and expected._ItemMysetIndex==-1 and expected._EquipMysetIndex==equip_slot and expected._OverwearMysetIndex==(overwear_slot or -1),"猎人组合关联验证失败")
    return {kind="hunter",dest=dest,object=staged,before=M.state(dest),expected=expected,slot=slot,type_name=M.type_name}
end
return M
