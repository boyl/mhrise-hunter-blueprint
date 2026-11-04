local M={}
function M.new(service)
 return setmetatable({service=service,entries={},name='',page=1,page_size=4,include_weapon=true,copy_weapon_visibility=false,copy_augments=true,allow_illegal_augments=true,copy_appearance=true,appearance_only=false,ready=false},{__index=M})
end
function M:queue(action)
 if self.pending or self.external_busy then return false end
 self.pending={action=action,id=self.selected,name=self.name,include_weapon=self.include_weapon,copy_weapon_visibility=self.copy_weapon_visibility,copy_augments=self.copy_augments,allow_illegal_augments=self.allow_illegal_augments,copy_appearance=self.copy_appearance,appearance_only=self.appearance_only}
 self.error=nil;self.message=nil;return true
end
function M:is_full()
 for _,entry in ipairs(self.entries)do if entry.id==self.selected then return entry.equipment~=nil and not self.appearance_only end end
 return false
end
function M:normalize_options()
 local full=self:is_full()
 if (full and not self.copy_appearance) or (not full and not self.include_weapon)then self.copy_weapon_visibility=false end
end
function M:select(id)
 if self.pending then return end
 self.selected=id;self.preview=nil;self.delete_id=nil
 for _,e in ipairs(self.entries)do if e.id==id then self.name=e.name end end
 self:normalize_options()
 self:queue('preview')
end
function M:set_option(key,value)
 if self.pending then return end
 assert(({include_weapon=true,copy_weapon_visibility=true,copy_augments=true,allow_illegal_augments=true,copy_appearance=true,appearance_only=true})[key])
 self[key]=value;self:normalize_options()
 self.preview=nil;if self.selected then self:queue('preview')end
end
function M:refresh()
 if self.job then return end
 local ok,err=pcall(function()
  self.entries=self.service.library:load().entries
  self:normalize_options()
  self.page=math.max(1,math.min(self.page,math.max(1,math.ceil(#self.entries/self.page_size))))
  local current=self.service.native:capture()
  if self.identity and self.identity~=current.identity then self.preview=nil;self.delete_id=nil;self.message=nil end
  self.identity=current.identity;self.current=current;self.ready=true;self.context_error=nil
 end)
 if not ok then self.ready=false;self.preview=nil;self.context_error=tostring(err)end
end
function M:execute_request(req)
 local ok,err=pcall(function()
  if req.action=='save' then
   local entry=self.service:save(req.name);self.selected=entry.id;self.name=entry.name;self.preview=nil
   self.message='已保存蓝图「'..entry.name..'」，其他角色可直接读取。'
  elseif req.action=='preview' then
   self.preview=self.service:preview(req.id,req)
  elseif req.action=='import' then
   assert(self.preview and self.preview.entry.id==req.id,'请先选择蓝图并完成预览')
   local result=self.service:import(self.preview)
   assert(result.ok,result.error or result.code)
   local r=result.result
   self.message='已新增「'..r.name..'」：猎人个人组合 '..r.hunter_slot..(r.overwear_slot and '，外观组合 '..r.overwear_slot or '')..'。请到道具箱应用。'
   self.preview=nil
  elseif req.action=='rename' then self.service.library:rename(req.id,req.name);self.preview=nil;self.message='蓝图已重命名。'
  elseif req.action=='delete' then
   assert(self.delete_id==req.id,'请确认删除这条蓝图')
   self.service.library:remove(req.id);self.selected=nil;self.preview=nil;self.delete_id=nil;self.message='蓝图已删除，游戏中的已导入组合保留。'
  elseif req.action~='refresh' then error('未知蓝图操作')end
 end)
 if not ok then self.error=tostring(err);self.preview=nil end
 self.operation_count=(self.operation_count or 0)+1
 self.last_operation={number=self.operation_count,action=req.action,id=req.id,ok=ok,error=not ok and tostring(err) or nil,message=self.message}
 self.pending=nil;self.job=nil;self:refresh()
 if ok and req.action=='save' then
  for i,e in ipairs(self.entries)do if e.id==self.selected then self.page=math.ceil(i/self.page_size)end end
 end
end
function M:step()
 if not self.pending then return end
 if not self.job then local req=self.pending;self.job=coroutine.create(function()self:execute_request(req)end)end
 local job=self.job;local ok,progress=coroutine.resume(job)
 if not ok then
  self.error=tostring(progress);self.preview=nil;self.pending=nil;self.job=nil
  self.operation_count=(self.operation_count or 0)+1
  self.last_operation={number=self.operation_count,ok=false,error=self.error}
 elseif coroutine.status(job)~='dead' then self.progress=progress end
end
return M
