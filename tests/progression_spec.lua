local P=require("LoadoutClone.planner")
local function status(mr)
 return {isMRRelease=mr,switchActionId={54},switchActionId_MR_1=mr and {49,51,125,54,128} or {},switchActionId_MR_2=mr and {49,51,125,54,128} or {}}
end
local a,red,blue=P.validate_actions(status(false),false)
assert(a[1]==54 and a[2]==0 and a[3]==0 and red==nil and blue==nil)
a,red,blue=P.validate_actions(status(true),true)
assert(#red==5 and #blue==5)
for _,pair in ipairs({{true,false},{false,true}}) do
 local ok,err=pcall(P.validate_actions,status(pair[1]),pair[2])
 assert(not ok and tostring(err):find("开放状态不同",1,true))
end
local s=status(true);s.switchActionId_MR_1={}
assert(not pcall(P.validate_actions,s,true))
s=status(false);s.switchActionId_MR_1={49,51,125,54,128}
assert(not pcall(P.validate_actions,s,false))
assert(not pcall(P.validate_actions,status(false),nil))
print("PASS 大师等级开放状态两种同类、两种跨类、缺失及矛盾配置（7 项）")
