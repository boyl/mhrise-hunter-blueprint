local B=require('LoadoutClone.blueprints')
local A=require('LoadoutClone.appearance')
local M={}
function M.new(library,native,appearance,writer_factory)
 return setmetatable({library=library,native=native,appearance=appearance,writer_factory=writer_factory},{__index=M})
end
function M:save(name)
 local equipment,current=self.native:capture_loadout()
 return self.library:add(name~='' and name or current.origin.name..' · 配装',current.origin,current.snapshot,os.time(),equipment)
end
function M:preview(id,options)
 local entry=self.library:find(id)
 local current=self.native:capture()
 local full=entry.equipment~=nil and not options.appearance_only
 if full then require('LoadoutClone.planner').validate_actions(entry.equipment.data._equipStatusParam,self.native:progression_state())end
 local copy_appearance=not full or options.copy_appearance==true
 local snapshot,changes=B.copy(entry.snapshot),{}
 if copy_appearance then snapshot,changes=self.native:adapt(entry.snapshot,current.origin.sex)end
 if full then
  assert(not options.copy_weapon_visibility or (copy_appearance and self.appearance.weapon_visibility_available~=false),'武器显示状态需要启用外观复制')
  return {entry=entry,snapshot=snapshot,changes=changes,target=current,options=B.copy(options),full=true,description=copy_appearance and self.native:describe(snapshot) or nil}
 end
 if options.include_weapon then
  if snapshot.weapon_id~=134217728 then
   assert(self.native:weapon_type(snapshot.weapon_id)==current.origin.weapon_type,'武器类型不同；取消“包含武器外观”可只导入防具')
  end
  assert(not snapshot.weapon_color.enabled,'该蓝图含百龙武器染色，暂无法仅通过外观组合还原；可取消“包含武器外观”')
 else
  snapshot.weapon_id=current.snapshot.weapon_id;snapshot.weapon_color={enabled=false}
 end
 assert(not options.copy_weapon_visibility or (options.include_weapon and self.appearance.weapon_visibility_available~=false),'当前无法同步武器显示状态')
 return {entry=entry,snapshot=snapshot,changes=changes,target=current,options=B.copy(options),description=self.native:describe(snapshot)}
end
function M:import(preview)
 assert(A.same(self.library:find(preview.entry.id),preview.entry),'蓝图已更新，请重新选择')
 local current=self.native:capture()
 assert(A.same(current,preview.target),'角色或当前外观已变化，请重新预览')
 local adapter=require('LoadoutClone.appearance_adapter').new(self.appearance.adapter.binding)
 local native=self.native
 function adapter:current()return native:capture()end
 local service=require('LoadoutClone.appearance_service').new(nil,adapter)
 service.weapon_visibility_available=self.appearance.weapon_visibility_available
 local library=self.library
 function service:assert_context(candidate,plan)
  assert(A.same(library:find(preview.entry.id),preview.entry),'蓝图已更新')
  assert(A.same(native:capture(),preview.target),'当前角色或外观已变化')
  self:verify_current(plan)
 end
 local reader
 if preview.full then
  local target={key='blueprint:'..preview.entry.id,name=preview.entry.name}
  local function check()
   assert(A.same(library:find(preview.entry.id),preview.entry),'蓝图已更新')
   assert(A.same(native:capture(),preview.target),'当前角色或外观已变化')
  end
  reader={progression_state=function()check();return native:progression_state()end,
   list_members=function()check();return {session=preview.target.identity,members={target}}end,
   capture=function(_,key)check();assert(key==target.key,'蓝图选择已变化');return {schema=1,source=target,session=preview.target.identity,data=B.copy(preview.entry.equipment.data)}end}
  function service:capture()return {snapshot=B.copy(preview.snapshot)}end
 end
 local writer=self.writer_factory(service,reader)
 if preview.full then
  local options={copy_augments=preview.options.copy_augments==true,allow_illegal_augments=preview.options.allow_illegal_augments==true,
   copy_appearance=preview.options.copy_appearance==true,copy_weapon_visibility=preview.options.copy_weapon_visibility==true}
  local planner=require('LoadoutClone.planner').new(reader,service)
  local plan=planner:prepare('blueprint:'..preview.entry.id,options);plan.name=preview.entry.name
  return writer:execute(plan)
 end
 local source={mode='appearance_only',name=preview.entry.name,source={key='blueprint:'..preview.entry.id},key='blueprint:'..preview.entry.id,
  options={appearance_only=true,copy_appearance=true,copy_weapon_visibility=preview.options.copy_weapon_visibility==true},appearance={snapshot=preview.snapshot}}
 return writer:execute(source)
end
return M
