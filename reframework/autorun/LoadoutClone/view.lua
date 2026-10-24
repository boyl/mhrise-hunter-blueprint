local M={}
-- 当前 REFramework 所绑定 ImGui 的 FramePadding / ButtonTextAlign。
local STYLE_FRAME_PADDING,STYLE_BUTTON_TEXT_ALIGN=11,24
local COLOR={heading=0xFFEACB8B,muted=0xFFB5BCC7,success=0xFF91D9B3,error=0xFFFFA0A0}
local function space() imgui.spacing();imgui.spacing() end
local function wrapped(text,width,color)
    local line=""
    for _,cp in utf8.codes(tostring(text)) do
        local ch=utf8.char(cp)
        if ch=="\n" or imgui.calc_text_size(line..ch).x>width then
            if color then imgui.text_colored(line,color) else imgui.text(line) end
            line=ch=="\n" and "" or ch
        else line=line..ch end
    end
    if #line>0 then if color then imgui.text_colored(line,color) else imgui.text(line) end end
end
local function fitted(text,width)
    text=text:gsub("##","# #"):gsub("[\r\n]"," ")
    if imgui.calc_text_size(text).x<=width then return text end
    local out=""
    for _,cp in utf8.codes(text) do
        local next_text=out..utf8.char(cp)
        if imgui.calc_text_size(next_text.."…").x>width then break end
        out=next_text
    end
    return out.."…"
end
local function heading(text)
    space();imgui.text_colored(text,COLOR.heading);imgui.spacing()
end
function M.new() return setmetatable({open=false,collapsed=false,resize=true,font=nil,font_attempted=false},{__index=M}) end
function M:set_open(value)
    self.open=value
    if value then self.collapsed=false;self.resize=true end
end
function M:body(controller,width)
    wrapped("选择猎人，复制完整配装",width,COLOR.heading)
    wrapped("新增装备与珠子，保存为猎人个人组合。当前穿着不变。",width,COLOR.muted)
    heading("01  大厅猎人  ·  "..#controller.members.." 人")
    if #controller.members==0 then
        wrapped("暂无其他猎人，加入多人大厅后自动更新。",width,COLOR.muted)
    end
    for _,member in ipairs(controller.members) do
        imgui.push_id(member.key)
        local chosen=controller.selected==member.key
        local title=fitted((chosen and "已选中  |  " or "选择  |  ")..member.name,width-28)
        local label=title.."\nMR "..member.master_rank.."   /   HR "..member.rank
        imgui.push_style_var(STYLE_BUTTON_TEXT_ALIGN,Vector2f.new(0,0.5))
        imgui.push_style_var(STYLE_FRAME_PADDING,Vector2f.new(14,8))
        local ok,pressed=pcall(imgui.button,label,{width,64})
        imgui.pop_style_var(2);imgui.pop_id()
        if not ok then error(pressed) end
        if pressed then controller:select(member.key) end
        imgui.spacing()
    end
    heading("02  复制选项")
    local changed,value=imgui.checkbox("复制炼化（武器与防具）",controller.copy_augments)
    if changed then controller:set_copy_augments(value) end
    imgui.spacing()
    if controller.copy_augments then
        local changed_illegal,illegal=imgui.checkbox("允许非法炼化（不一定实际非法）",controller.allow_illegal_augments)
        if changed_illegal then controller:set_allow_illegal_augments(illegal) end
        wrapped(controller.allow_illegal_augments and "放宽生成规则，优先预算内还原；仍核对最终效果。" or "仅按正常生成规则还原，无解时停止。",width,COLOR.muted)
    else wrapped("保留基础装备；珠子须适配基础孔位。",width,COLOR.muted) end
    space();imgui.separator();space()
    if controller.selected and not controller.pending then
        if imgui.button("复制所选配装",{width,48}) then controller:request_copy() end
    else
        wrapped(controller.pending and "正在读取与校验，请稍候……" or "先在上方选择一位猎人",width,COLOR.muted)
    end
    if controller.pending then
        local p=controller.progress or {}
        local status="正在读取配装"
        if p.phase=="catalog" then status="正在读取珠子与炼化目录："..p.done
        elseif p.phase=="armor" then status="正在还原防具："..p.part
        elseif p.phase=="augment_search" then status="正在求解等效炼化"
        elseif p.phase=="ready_to_commit" then status="校验完成，正在登记组合" end
        space();wrapped(status,width,COLOR.heading)
    end
    if controller.result then
        heading("复制完成")
        local r=controller.result
        wrapped(r.hunter_slot and ("猎人个人组合："..r.name) or ("装备组合："..r.name),width,COLOR.success)
        wrapped("到道具箱选择该组合即可使用。",width,COLOR.muted)
    elseif controller.error then
        heading("本次复制未完成")
        local reason=controller.error:match("%.lua:%d+: ([^\n]+)") or controller.error:match("[^\n]+") or "未知错误"
        wrapped(reason,width,COLOR.error)
        if reason:find("正常生成",1,true) then
            wrapped("未找到正常生成方案，不代表来源一定非法。",width,COLOR.muted)
            wrapped("可勾选“允许非法炼化”后重试。",width,COLOR.muted)
        else wrapped("可重新选择猎人后重试。详情见 REFramework 日志。",width,COLOR.muted) end
    end
end
function M:ensure_font()
    if not self.font_attempted or self.font_size~=22 then
        self.font_attempted=true;self.font_size=22
        local ok,font=pcall(imgui.load_font,"NotoSansSC-Regular.otf",22,{0x20,0xFF,0x2000,0x206F,0x3000,0x30FF,0x4E00,0x9FFF,0xFF00,0xFFEF,0})
        if ok and font then
            imgui.push_font(font)
            local measured,size=pcall(imgui.calc_text_size,"大厅配装复制")
            imgui.pop_font()
            if measured and size.x>0 and size.y>0 then self.font=font else log.error("[LoadoutClone] Chinese font measurement failed") end
        else log.error("[LoadoutClone] Chinese font unavailable") end
    end
end
function M:draw(controller)
    if not self.open or not reframework:is_drawing_ui() then return end
    self:ensure_font()
    if self.font then imgui.push_font(self.font) end
    if self.layout_version~=2 then self.resize=true;self.layout_version=2 end
    if self.resize then
        imgui.set_next_window_size(self.collapsed and {320,110} or {620,680},1);self.resize=false
    end
    self.open=imgui.begin_window(self.font and "猎人蓝图" or "Hunter Blueprint",self.open,0)
    if self.open then
        if imgui.button(self.font and (self.collapsed and "展开" or "收起") or (self.collapsed and "Expand" or "Minimize"),{72,30}) then self.collapsed=not self.collapsed;self.resize=true end
        imgui.same_line()
        if imgui.button(self.font and "关闭" or "Close",{72,30}) then self:set_open(false) end
        if self.open and not self.collapsed then
            space();imgui.separator();space()
            if not self.font then imgui.text("Missing font: NotoSansSC-Regular.otf")
            else
                local width=math.max(160,imgui.get_window_size().x-36)
                local ok,err=xpcall(function() self:body(controller,width) end,debug.traceback)
                if not ok then
                    imgui.text_colored("界面显示异常，请查看日志。",COLOR.error)
                    if self.render_error~=err then self.render_error=err;log.error("[LoadoutClone UI] "..err) end
                end
            end
        end
    end
    imgui.end_window()
    if self.font then imgui.pop_font() end
end
return M
