local View=require("LoadoutClone.view")
local texts,ended,fonts,logs={},0,0,{}
reframework={is_drawing_ui=function() return true end}
log={error=function(message) logs[#logs+1]=message end}
imgui={
 begin_window=function() return true end,
 end_window=function() ended=ended+1 end,
 push_font=function() fonts=fonts+1 end,
 pop_font=function() fonts=fonts-1 end,
 button=function() return false end,
 text=function(value) texts[#texts+1]=value end,
 get_display_size=function()return {x=2560,y=1440}end,
    get_scroll_max_y=function()return 0 end,
    get_window_size=function() error("window size unavailable") end,
}
for _,name in ipairs({"spacing","separator","same_line","set_next_window_size"}) do imgui[name]=function() end end
local view=View.new();view:set_open(true);view.font=1;view.font_attempted=true;view.font_size=22
local ok,err=pcall(function() view:draw({members={}}) end)
assert(ok,tostring(err))
assert(ended==1 and fonts==0,"异常必须结束窗口并恢复字体栈")
assert(table.concat(texts,"\n"):find("Hunter Blueprint UI error",1,true),"默认字体必须显示 ASCII 错误提示")
assert(#logs==1 and logs[1]:find("window size unavailable",1,true))
view:draw({members={}});assert(#logs==1,"同一故障不能每帧刷日志")
print("PASS 窗口尺寸异常可见提示、栈恢复与日志去重（3 项）")
