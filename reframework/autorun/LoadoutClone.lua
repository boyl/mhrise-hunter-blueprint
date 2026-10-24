local Backend=require("LoadoutClone.backend")
local Controller=require("LoadoutClone.controller")
local View=require("LoadoutClone.view")
local controller=Controller.new(Backend.new())
local view=View.new()
local next_refresh=0
local previous_error=nil
re.on_application_entry("LateUpdateBehavior",function()
    if not view.open and not controller.pending then return end
    if os.clock()>=next_refresh then controller:refresh();next_refresh=os.clock()+1 end
    controller:step()
    if controller.error and controller.error~=previous_error then
        previous_error=controller.error;log.error("[LoadoutClone] "..controller.error)
    end
end)
re.on_frame(function() view:draw(controller) end)
re.on_draw_ui(function()
    view:ensure_font()
    if view.font then imgui.push_font(view.font) end
    local changed,value=imgui.checkbox("猎人蓝图：显示面板",view.open)
    if changed then view:set_open(value) end
    if view.font then imgui.pop_font() end
end)
log.info("[LoadoutClone 1.0.0] loaded; panel closed until explicitly opened")
