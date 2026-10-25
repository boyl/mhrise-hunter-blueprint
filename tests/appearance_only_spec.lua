package.loaded["LoadoutClone.native"]={new=function()return {}end}
local P=require("LoadoutClone.planner")
local calls=0
local reader={list_members=function()return {session="s",members={{key="a",index=1}}}end,
 capture=function()error("不能读取装备／珠子")end,progression_state=function()error("不能检查大师等级")end}
local service={capture=function(_,target,session)calls=calls+1;return {snapshot={weapon_color={enabled=false}},source=target,session=session}end}
local p=P.new(reader,service)
local plan=p:prepare("a",{appearance_only=true,copy_appearance=true,copy_weapon_visibility=true})
assert(plan.mode=="appearance_only" and plan.items==nil and plan.appearance and calls==1)
assert(not pcall(p.prepare,p,"missing",{appearance_only=true,copy_appearance=true}))
service.capture=function()return {snapshot={weapon_color={enabled=true}}}end
assert(not pcall(p.prepare,p,"a",{appearance_only=true,copy_appearance=true}))
print("PASS 仅外观跳过装备、珠子、进度和炼化，离开目标／未支持武器染色明确拒绝")
local C=require("LoadoutClone.controller")
local c=C.new({});c.members={{key="a"}};c.selected="a";c.session="s"
c:set_appearance_only(true);assert(c.copy_appearance)
c:set_copy_appearance(false);assert(c.copy_appearance)
c:request_capture();assert(c.pending.options.appearance_only)
c:set_appearance_only(false);assert(not c.pending)
print("PASS 仅外观模式强制外观、请求携带模式、切换模式取消旧任务")
