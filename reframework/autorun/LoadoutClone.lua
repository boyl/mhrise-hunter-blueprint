local Backend=require("LoadoutClone.backend")
local Controller=require("LoadoutClone.controller")
local View=require("LoadoutClone.view")
local ok,backend=pcall(function()
    return Backend.new(require("LoadoutClone.appearance_runtime").new)
end)
local appearance_error
if not ok then
    appearance_error=tostring(backend)
    log.error("[HunterBlueprint appearance init] "..appearance_error)
    backend=Backend.new()
end
local controller=Controller.new(backend)
controller.appearance_error=appearance_error
local view=View.new()
controller.cleanup=require("LoadoutClone.cleanup_controller").new(require("LoadoutClone.petalace_cleanup").new())
local next_refresh=0
local previous_error=nil
local last_runtime_state
re.on_application_entry("LateUpdateBehavior",function()
    controller.cleanup.external_busy=controller.pending~=nil
    controller.cleanup:step()
    if controller.cleanup.job then return end
    local observed=table.concat({tostring(controller.appearance_only),tostring(controller.copy_appearance),tostring(controller.copy_weapon_visibility),tostring(controller.selected),tostring(controller.state)},"/")
    if observed~=last_runtime_state then
        last_runtime_state=observed
        json.dump_file("LoadoutClone/runtime-state.json",{appearance_only=controller.appearance_only,copy_appearance=controller.copy_appearance,copy_weapon_visibility=controller.copy_weapon_visibility,selected=controller.selected,state=controller.state,pending_options=controller.pending and controller.pending.options})
    end
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
log.info("[LoadoutClone 1.1.1] loaded; panel closed until explicitly opened")
