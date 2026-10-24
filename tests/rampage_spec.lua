local N=require("LoadoutClone.native")
local values={0,0,0,0,0,0}
local a={add_ref=function() end,get_type_definition=function() return {get_full_name=function() return "Enum[]" end,is_array=function() return true end,get_method=function() return {call=function(_,_,i) return values[i+1] end} end} end}
sdk={find_type_definition=function() return {get_method=function() return {call=function() return #values end} end} end}
local obj={get_field=function() return a end}
local n=N.new();local cheat=false;local writes=0
function n:call(_,method,_,i,id)
 if method=="setHyakuryuSkill" then writes=writes+1;values[i+1]=id
 elseif method=="checkWeaponHyakuryuSkillCheat()" then return cheat
 elseif method=="get_HyakuryuSkillIdList()" then return a else error(method) end
end
local out=n:restore_rampage(obj,{2});assert(out[1]==2 and out[6]==0)
cheat=true;assert(not pcall(n.restore_rampage,n,obj,{2}))
cheat=false;values={0,0,0,0,0,0};n:restore_rampage(obj,{})
for _,bad in ipairs({{[1]=2,[3]=4},{"2"},{1,2,3,4,5,6,7}}) do
 local before=writes;assert(not pcall(n.restore_rampage,n,obj,bad) and writes==before)
end
print("PASS 百龙强化还原、游戏拒绝、无强化及三种畸形输入（6 项）")
