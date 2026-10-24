local View=require("LoadoutClone.view")
local menu=false
Vector2f={new=function(x,y) return {x=x,y=y} end}
reframework={is_drawing_ui=function() return menu end}
local calls,click,window_open={},nil,true
imgui={
    begin_window=function() calls.window=(calls.window or 0)+1;return window_open end,
    end_window=function() calls.ended=(calls.ended or 0)+1 end,
    button=function(label) calls[label]=true;return label==click or (click=="choose" and label:match("^选择  |")) end,
    text=function(text) calls[text]=true end,
    checkbox=function(_,value) return false,value end,
    calc_text_size=function(text) return {x=utf8.len(text)*12,y=22} end,
    get_window_size=function() return {x=620,y=680} end,
    text_colored=function(text) calls[text]=true end,
}
for _,name in ipairs({"push_font","pop_font","set_next_window_size","separator","same_line","push_id","pop_id","spacing","push_style_var","pop_style_var"}) do imgui[name]=function() end end
log={error=function(message) error(message) end}
local controller={members={},copy_augments=true}
local view=View.new();assert(not view.open);view:set_open(true);view.font=1;view.font_attempted=true;view.font_size=22
view:draw(controller)
assert(not calls.window,"REFramework 关闭时不能留下无法点击的面板")
menu=true;click="收起";view:draw(controller)
assert(view.collapsed and not calls["暂无可读取的其他大厅玩家"])
click="展开";view:draw(controller);assert(not view.collapsed)
click="关闭";view:draw(controller);assert(not view.open)
local before=calls.window;view:draw(controller);assert(calls.window==before)
view:set_open(true);assert(view.open and not view.collapsed)
click=nil;window_open=false;view:draw(controller);assert(not view.open and calls.window==calls.ended)
print("PASS 面板随框架隐藏、收起、展开、关闭、关闭后不绘制、重新打开及标题关闭（7 项）")
window_open=true;click="choose";view:set_open(true)
controller.members={{key="hunter-A",name="测试猎人",master_rank=50,rank=100}}
controller.select=function(self,key) self.selected=key end
view:draw(controller)
assert(controller.selected=="hunter-A" and calls["选择  |  测试猎人\nMR 50   /   HR 100"],"有成员且缺少 radio_button API 时必须可以选择")
assert(calls.window==calls.ended)
print("PASS 当前框架无 radio_button 时玩家列表仍可绘制与选择（1 项）")
