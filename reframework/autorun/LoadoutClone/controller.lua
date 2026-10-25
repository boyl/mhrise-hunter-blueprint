-- debug 库在部分运行环境不可用；错误处理自身不能阻断绘制或回滚。
local native_traceback=type(debug)=="table" and type(debug.traceback)=="function" and debug.traceback
local function traceback(value,message)
    if native_traceback then
        if type(value)=="thread" then return native_traceback(value,message) end
        return native_traceback(value)
    end
    return tostring(type(value)=="thread" and message or value)
end
local M={}
function M.new(adapter)
    local appearance_available=type(adapter.supports_appearance)=="function" and adapter:supports_appearance()==true
    return setmetatable({adapter=adapter,members={},state="initial",copy_augments=true,allow_illegal_augments=true,appearance_only=false,copy_appearance=false,copy_weapon_visibility=false,appearance_available=appearance_available},{__index=M})
end
function M:clear_selection()
    self.selected=nil;self.pending=nil;self.snapshot=nil;self.error=nil;self.job=nil;self.result=nil;self.progress=nil
end
function M:refresh()
    local ok,data=xpcall(function() return self.adapter:list_members() end,traceback)
    if not ok then
        self:clear_selection();self.members={};self.state="error";self.error=tostring(data);return
    end
    if data.session~=self.session then self:clear_selection() end
    self.session=data.session;self.members=data.members
    local found=false
    for _,member in ipairs(self.members) do if member.key==self.selected then found=true end end
    if not found then self:clear_selection() end
    if #self.members==0 then self.state="empty"
    elseif not self.pending and not self.snapshot and not self.error and not self.result then self.state="ready" end
end
function M:select(key)
    if self.selected==key then return end
    for _,member in ipairs(self.members) do
        if member.key==key then self:clear_selection();self.selected=key;self.state="ready";return end
    end
end
function M:set_copy_augments(value)
    assert(type(value)=="boolean","copy_augments must be boolean")
    if value==self.copy_augments then return end
    self.copy_augments=value
    if not value then self.allow_illegal_augments=false end
    self.pending=nil;self.snapshot=nil;self.error=nil;self.job=nil;self.result=nil;self.progress=nil
    self.state=#self.members==0 and "empty" or "ready"
end
function M:set_allow_illegal_augments(value)
    assert(type(value)=="boolean","allow_illegal_augments must be boolean")
    if value and not self.copy_augments then return false end
    if value==self.allow_illegal_augments then return true end
    self.allow_illegal_augments=value
    self.pending=nil;self.snapshot=nil;self.error=nil;self.job=nil;self.result=nil;self.progress=nil
    self.state=#self.members==0 and "empty" or "ready"
    return true
end
function M:request_capture()
    if not self.selected or self.pending then return false end
    self.pending={key=self.selected,session=self.session,options={appearance_only=self.appearance_only,copy_augments=self.copy_augments,allow_illegal_augments=self.allow_illegal_augments,copy_appearance=self.copy_appearance,copy_weapon_visibility=self.copy_weapon_visibility}};self.snapshot=nil;self.error=nil;self.result=nil;self.state="reading"
    return true
end
function M:request_copy()
    if not self.selected or self.pending then return false end
    local request={key=self.selected,session=self.session,action="copy",options={appearance_only=self.appearance_only,copy_augments=self.copy_augments,allow_illegal_augments=self.allow_illegal_augments,copy_appearance=self.copy_appearance,copy_weapon_visibility=self.copy_weapon_visibility}}
    self.pending=request;self.snapshot=nil;self.error=nil;self.result=nil;self.state="preparing"
    self.job=coroutine.create(function()
        local plan=self.adapter:prepare(request.key,request.options)
        if request.options.copy_appearance or request.options.copy_weapon_visibility then
            assert(plan.options and plan.options.copy_appearance==request.options.copy_appearance
                and plan.options.copy_weapon_visibility==request.options.copy_weapon_visibility
                and (plan.options.appearance_only==true)==(request.options.appearance_only==true),"复制选项在准备期间丢失，已停止写入")
        end
        coroutine.yield({phase="ready_to_commit"})
        assert(request.key==self.selected and request.session==self.session,"复制目标已变化")
        return self.adapter:commit(plan)
    end)
    return true
end
function M:step()
    local request=self.pending
    if not request then return end
    if request.action=="copy" then
        if request.key~=self.selected or request.session~=self.session then self.pending=nil;self.job=nil;return end
        local ok,value=coroutine.resume(self.job)
        if not ok then
            self.error=traceback(self.job,tostring(value));self.state="error";self.pending=nil;self.job=nil;return
        end
        if coroutine.status(self.job)=="dead" then
            self.pending=nil;self.job=nil
            if value.ok then self.result=value.result;self.state="success"
            else self.error=value.error or value.code;self.state="error" end
        else self.progress=value end
        return
    end
    self.pending=nil
    if request.key~=self.selected or request.session~=self.session then return end
    local ok,result=xpcall(function() return self.adapter:capture(request.key) end,traceback)
    if not ok then self.state="error";self.error=tostring(result);self.snapshot=nil;return end
    result.options={appearance_only=request.options.appearance_only,copy_augments=request.options.copy_augments,allow_illegal_augments=request.options.allow_illegal_augments,copy_appearance=request.options.copy_appearance,copy_weapon_visibility=request.options.copy_weapon_visibility}
    self.snapshot=result;self.state="inspected"
end
function M:set_copy_appearance(value)
    assert(type(value)=="boolean","copy_appearance must be boolean")
    if value==self.copy_appearance then return end
    if self.appearance_only and not value then return false end
    self.copy_appearance=value
    if not value then self.copy_weapon_visibility=false end
    self.pending=nil;self.snapshot=nil;self.error=nil;self.job=nil;self.result=nil;self.progress=nil
    self.state=#self.members==0 and "empty" or "ready"
end
function M:set_copy_weapon_visibility(value)
    assert(type(value)=="boolean","copy_weapon_visibility must be boolean")
    if value and not self.copy_appearance then return false end
    if value==self.copy_weapon_visibility then return true end
    self.copy_weapon_visibility=value
    self.pending=nil;self.snapshot=nil;self.error=nil;self.job=nil;self.result=nil;self.progress=nil
    self.state=#self.members==0 and "empty" or "ready"
    return true
end
function M:set_appearance_only(value)
    assert(type(value)=="boolean")
    if value==self.appearance_only then return end
    self.appearance_only=value
    if value then self.copy_appearance=true end
    self.pending=nil;self.snapshot=nil;self.error=nil;self.job=nil;self.result=nil;self.progress=nil
    self.state=#self.members==0 and "empty" or "ready"
end
return M
