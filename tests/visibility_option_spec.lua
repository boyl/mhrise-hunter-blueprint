local C=require("LoadoutClone.controller")
local commits=0
local c=C.new({supports_appearance=function()return true end,list_members=function()return {session="s",members={{key="a"}}}end,
 capture=function()return {}end,prepare=function(_,_,options)assert(options.copy_weapon_visibility==true);return {options=options}end,
 commit=function()commits=commits+1;return {ok=true}end})
assert(c.copy_weapon_visibility==false)
assert(c:set_copy_weapon_visibility(true)==false)
c:refresh();c:select("a");c:set_copy_appearance(true);assert(c:set_copy_weapon_visibility(true))
c:request_capture();c:step();assert(c.snapshot.options.copy_weapon_visibility==true)
c:request_copy();c:step();c:set_copy_weapon_visibility(false);c:step();assert(commits==0 and c.selected=="a")
c:set_copy_weapon_visibility(true);c:set_copy_appearance(false);assert(not c.copy_weapon_visibility)
c:request_capture();c:step();assert(c.snapshot.options.copy_weapon_visibility==false)
print("PASS 武器显示选项默认关闭、随请求固定、变更取消旧任务、关闭外观清除依赖选项")
local W=require("LoadoutClone.writer")
local ok,err=pcall(W.new({}).prepare,W.new({}),{options={copy_appearance=false,copy_weapon_visibility=true}})
assert(not ok and tostring(err):find("需要开启复制外观",1,true))
print("PASS 无外观的显示绑定请求在任何 SDK 写入之前拒绝")

c:set_copy_appearance(true);c:set_copy_weapon_visibility(true)
c.adapter.prepare=function()return {options={copy_appearance=false,copy_weapon_visibility=false}}end
c:request_copy();c:step();assert(c.state=="error" and commits==0 and c.error:find("复制选项在准备期间丢失",1,true))
print("PASS 准备层丢失勾选项时停止提交，不允许静默退化为普通配装")
