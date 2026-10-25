-- 原生外观事务适配器，由主线程运行时工厂注入。
local N=require("LoadoutClone.native")
local R=require("LoadoutClone.appearance_reader")
local O=require("LoadoutClone.appearance_objects")
local C=require("LoadoutClone.appearance_color")
local M={tracks_weapon_color=true}
function M.new(binding)
 local native=N.new()
 return setmetatable({native=native,objects=O.new(native),binding=binding},{__index=M})
end
function M:capture(index) self.native.game_method_calls=0;return R.capture(index,self.native) end
function M:validate(snapshot)
 self.objects:build(snapshot,"外观检查")
 C.from_snapshot(snapshot.weapon_color)
 assert(type(snapshot.weapon_hidden)=="boolean","武器显示状态缺失")
 return true
end
function M:prepare_equipment(source)
 local weapon=assert(source.items[1].object,"武器候选缺失")
 local color=self.objects:detach_weapon_color(weapon)
 C.write(color,C.from_snapshot(source.appearance.snapshot.weapon_color))
end
function M:prepare(snapshot,plan)
 self.native.game_method_calls=0
 local sets=N.field(plan.manager,"_PlOverwearMySetList")
 local count,get=N.array_access(sets,1024)
 local slot,dest
 for i=count-1,0,-1 do
  local item=get(i)
  if N.field(item,"_IsUsing")==false then slot=i;dest=item:add_ref();break end
 end
 assert(slot,"外观组合没有空位")
 local candidate=self.objects:build(snapshot,"猎人蓝图 "..(slot+1))
 return {slot=slot,dest=dest,object=candidate,before=self.objects:state(dest),
  expected=self.objects:state(candidate),backup=self.objects:clone(dest)}
end
function M:state(entry) return self.objects:state(entry.dest) end
function M:apply(entry) self.objects:copy(entry.dest,entry.object) end
function M:restore(entry) self.objects:copy(entry.dest,entry.backup) end
function M:current()
 local manager=assert(sdk.get_managed_singleton("snow.data.EquipDataManager"))
 local lobby=assert(sdk.get_managed_singleton("snow.LobbyManager"))
 local index=N.field(lobby,"_myselfIndex")
 return {appearance=R.capture(index,self.native),visible=N.scalar(N.field(manager,"_VisiblePartsFlag"))}
end
return M
