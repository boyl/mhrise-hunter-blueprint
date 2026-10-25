local hooks={};local current={};local errors={};local in_hook=false
thread={get_hook_storage=function() return current end}
log={error=function(e) errors[#errors+1]=e end}
local manager={list={{},{}}}
package.loaded["LoadoutClone.native"]={field=function(o) assert(not in_hook);return o.list end,array_access=function(v) assert(not in_hook);return #v,function(i)return v[i+1]end end}
sdk={find_type_definition=function()return {get_method=function(_,s)return s end}end,
 hook=function(name,pre,post)hooks[name]={pre=pre,post=post}end,
 to_int64=function(v)return v end,get_managed_singleton=function()assert(not in_hook);return manager end}
local tick
re={on_application_entry=function(name,fn)assert(name=="UpdateBehavior");tick=fn end}
local selected=true;local applied={};local character="a";local matches=true
local b={selection=function()assert(not in_hook);return selected end,
 character=function()assert(not in_hook);return character end,
 matches_current=function()assert(not in_hook);return matches end,
 apply_hidden=function(_,m,v)assert(not in_hook and m==manager);applied[#applied+1]=v end}
local M=require("LoadoutClone.appearance_hooks")
local co=coroutine.create(function()return M.install(b,false)end)
local ok,err=coroutine.resume(co)
assert(not ok and tostring(err):find("禁止从诊断协程注册",1,true) and next(hooks)==nil)
local state=M.install(b,false);tick()
local h=hooks["applyHunterMySet(System.Int32)"]
local function event(index,result)
 current={};in_hook=true;h.pre({nil,manager,index});assert(h.post(result)==result);in_hook=false
end
event(0,1);assert(#applied==0);tick();assert(#applied==1 and applied[1]==true)
tick();assert(#applied==1)
print("PASS 主线程注册且换装回调内零对象访问，下一更新仅应用一次")
selected=false;event(0,1);tick();assert(#applied==2 and applied[2]==false)
event(0,0);tick();assert(#applied==2)
selected=nil;event(0,1);tick();assert(#applied==2)
print("PASS 显示 false 被保留，失败切换与未绑定组合不写设置")
selected=true;event(0,1);character="b";tick();assert(#applied==2)
event(0,1);matches=false;tick();assert(#applied==2);matches=true
event(0,1);hooks["applyHunterMySet(snow.data.HunterMySetData)"].pre({});tick();assert(#applied==2)
event(0,1);event(1,0);tick();assert(#applied==2)
print("PASS 角色变化、当前装备不匹配、直接对象切换和后续失败事件使待办失效")
assert(M.install(b,true)==state);event(0,1);tick();assert(#applied==2 and state.last_hidden==true)
assert(#errors==0)
_G.HunterBlueprintAppearanceHookState=nil
