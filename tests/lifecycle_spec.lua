json={dump_file=function() return true end}
local callbacks,refreshes,steps={},0,0
local view={open=false,ensure_font=function() end,set_open=function(self,v) self.open=v end}
package.loaded["LoadoutClone.backend"]={new=function() return {} end}
package.loaded["LoadoutClone.controller"]={new=function() return {
    refresh=function() refreshes=refreshes+1 end,
    step=function() steps=steps+1 end,
} end}
package.loaded["LoadoutClone.view"]={new=function() return view end}
re={on_application_entry=function(_,fn) callbacks.update=fn end,on_frame=function(fn) callbacks.frame=fn end,on_draw_ui=function(fn) callbacks.ui=fn end}
log={info=function() end,error=function() end}
imgui={checkbox=function() return true,true end}
assert(loadfile(assert(package.searchpath("LoadoutClone",package.path))))()
for _=1,10 do callbacks.update() end
assert(refreshes==0 and steps==0,"启动后不打开面板，不得采样游戏")
callbacks.ui();callbacks.update();assert(refreshes==1 and steps==1)

local files,request={},nil
local clock=10
os.clock=function() return clock end
json={dump_file=function(path,data) files[path]=data end,load_file=function() return request end}
local reads=0
sdk={find_type_definition=function() reads=reads+1;return nil end}
assert(loadfile(assert(package.searchpath("LoadoutCloneProbe",package.path))))()
request={id="old",mode="metadata",types={"example.Type"},session_id="previous-process"}
callbacks.update();assert(reads==0 and not files["LoadoutClone-probe-report.json"])
clock=12
request={id="new",mode="metadata",types={"example.Type"},session_id=files["LoadoutClone-probe-session.json"].session_id}
callbacks.update();assert(reads==1 and files["LoadoutClone-probe-report.json"].id=="new")
print("PASS 启动不采样、显式打开后采样、过期探针拒绝、当次探针会话匹配（4 项）")
