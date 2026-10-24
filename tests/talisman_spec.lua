local Planner=require("LoadoutClone.planner")
local skills=Planner.talisman_skills({137,22,17,135,0},{[22]=3,[137]=2})
assert(#skills==2 and skills[1].id==137 and skills[1].level==2 and skills[2].id==22 and skills[2].level==3,"必须保留主副技能顺序，不按 ID 排序")
assert(not pcall(Planner.talisman_skills,{137,22},{[99]=1}),"缺少原始顺序证据必须拒绝")
print("PASS 护石主副技能顺序保留与缺失顺序拒绝（2 项）")
local Native=require("LoadoutClone.native")
local function array(values) return {get_size=function() return #values end,get_element=function(_,i) return values[i+1] end,
    add_ref=function() end,get_type_definition=function() return {is_array=function() return true end,get_full_name=function() return "System.Int32[]" end,get_method=function() return {call=function(_,v,i) return v:get_element(i) end} end} end} end
sdk={find_type_definition=function() return {get_method=function() return {call=function(_,v) return v:get_size() end} end} end}
local raw={_TalismanDecoSlotNumList={0,2,0,0,1},_TalismanSkillIdList={137,22},_TalismanSkillLvList={2,3}}
local obj={get_field=function(_,key) return array(raw[key]) end}
local native=Native.new()
local checked,masked=false,false
local map={['getTalismanDecoSlotNumList()']="_TalismanDecoSlotNumList",['getTalismanSkillIdList()']="_TalismanSkillIdList",['getTalismanSkillLvList()']="_TalismanSkillLvList"}
function native:call(_,method)
    if method=="updateCheatBitFlag()" then checked=true;return end
    assert(checked,"必须先执行原生校验")
    local values=raw[assert(map[method])]
    if masked then local zeros={};for i=1,#values do zeros[i]=0 end;values=zeros end
    return array(values)
end
native:check_talisman(obj)
masked=true;assert(not pcall(function() native:check_talisman(obj) end),"不能将原生屏蔽的字段报为成功")
print("PASS 护石原生校验及有效字段屏蔽拒绝（2 项）")
