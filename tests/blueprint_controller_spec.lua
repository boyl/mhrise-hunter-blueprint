local C=require('LoadoutClone.blueprint_controller')
local deleted=0
local service={library={load=function()return {entries={{id=1,name='one'}}}end,remove=function()deleted=deleted+1 end},native={capture=function()return {identity='a'}end}}
local c=C.new(service);c:refresh();assert(c.ready)
c.selected=1;c:queue('delete');c:step();assert(deleted==0 and c.error)
c.delete_id=1;c:queue('delete');c:step();assert(deleted==1 and c.selected==nil)
c.external_busy=true;assert(not c:queue('save'))
c.external_busy=false;c.selected=1;c.copy_weapon_visibility=true;c:set_option('include_weapon',false);assert(not c.copy_weapon_visibility and c.pending)
print('PASS 蓝图删除需明确确认、外部事务互斥、关闭武器取消显示依赖')

local refreshes=0
local slow={library={load=function()refreshes=refreshes+1;return {entries={}}end},native={capture=function()return {identity='a'}end},save=function()coroutine.yield({phase='read'});return {id=1,name='完整'}end}
local c2=C.new(slow);assert(c2:queue('save'));c2:step();assert(c2.pending and c2.job)
c2:refresh();assert(refreshes==0 and not c2:queue('save'))
c2:step();assert(not c2.pending and not c2.job and c2.last_operation.ok and refreshes==1)
print('PASS 蓝图分帧任务保持互斥、处理中不刷新上下文、结束后恢复交互')

local options=C.new(service)
options.entries={{id=1,equipment={}},{id=2}};options.selected=1
options.include_weapon=false
options:set_option('copy_weapon_visibility',true)
assert(options.copy_weapon_visibility,'完整配装模式不能受仅外观的隐藏武器选项影响')
options.pending=nil;options.selected=2;options.include_weapon=true;options.copy_appearance=false
options:set_option('copy_weapon_visibility',true)
assert(options.copy_weapon_visibility,'旧外观蓝图不受完整配装的外观复选框影响')
options.pending=nil;options.selected=1;options.copy_appearance=true;options.include_weapon=true;options.copy_weapon_visibility=true
options:set_option('copy_appearance',false);assert(not options.copy_weapon_visibility)
print('PASS 完整配装与仅外观的隐藏选项隔离、真实依赖关闭时取消显示同步')

local updated={library={load=function()return {entries={{id=2,equipment={}}}}end},native={capture=function()return {identity='same'}end}}
local c3=C.new(updated);c3.selected=2;c3.copy_appearance=false;c3.copy_weapon_visibility=true
c3:refresh();assert(not c3.copy_weapon_visibility,'保存新完整蓝图后刷新必须清理隐藏依赖')
