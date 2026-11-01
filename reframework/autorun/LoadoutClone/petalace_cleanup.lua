-- 花链清理：独立预览，提交前重扫；先迁移引用，最后清空重复库存。
local N=require("LoadoutClone.native")
local W=require("LoadoutClone.writer")
local T=require("LoadoutClone.transaction")
local P=require("LoadoutClone.petalace_cleanup_plan")
local Scan=require("LoadoutClone.petalace_cleanup_scan")
local Identity=require("LoadoutClone.character_identity")
local Layout=require("LoadoutClone.petalace_layout")
local M={}
local journal="LoadoutClone/petalace-cleanup-transaction.json"
local visibility="LoadoutClone/appearance-visibility.json"
local function clone(v) if type(v)~="table" then return v end;local o={};for k,x in pairs(v)do o[k]=clone(x)end;return o end
local function save(path,value) assert(json.dump_file(path,value)==true,"无法保存清理记录，停止操作") end
local function busy(path) local v=json.load_file(path);return v and (v.status=="in_progress" or v.status=="recovery_failed") end
local function cached_flower(set)
 local _,get=N.array_access(N.field(set,"<InventoryDataList>k__BackingField"),16)
 return get(6)
end
-- 仅为不一致提供证据，不放宽判断、不改变提交或恢复顺序。
local function differences(expected,actual,path,out,depth)
 if #out>=8 then return end
 if type(expected)=="table" and type(actual)=="table" and depth<12 then
  local keys,seen={},{}
  for k in pairs(expected)do keys[#keys+1]=k;seen[k]=true end
  for k in pairs(actual)do if not seen[k]then keys[#keys+1]=k end end
  table.sort(keys,function(a,b)return tostring(a)<tostring(b)end)
  for _,k in ipairs(keys)do differences(expected[k],actual[k],path.."."..tostring(k),out,depth+1);if #out>=8 then break end end
 elseif not W.equal(expected,actual) then
  out[#out+1]={path=path,expected=expected,actual=actual,expected_type=type(expected),actual_type=type(actual)}
 end
end
function M:check(e,expected,message,phase)
 local actual=self:state(e)
 if W.equal(actual,expected) then return end
 local diff={};differences(expected,actual,"$",diff,0)
 local failure={phase=phase,kind=e.kind,index=e.index,differences=diff,expected=clone(expected),actual=clone(actual)}
 if phase=="restore" then self.recovery_failure=failure else self.failure=failure end
 local label=e.kind..(e.index~=nil and " #"..e.index or "")
 error(message.." ["..label.."; "..(diff[1]and diff[1].path or "unknown").."]",0)
end
function M.new()
 local self=setmetatable({writer=W.new({}),locked=false},{__index=M});self.transaction=T.new(self);return self
end
function M:scan()
 local r={items={},references={},writes=0,character=Identity.current()}
 Scan.run(N,P,r)
 assert(r.character==Identity.current(),"角色已变化")
 return r
end
function M:prepare(preview)
 assert(Layout.replacement_schema==1,"清理模块版本不一致，请完整覆盖补丁并重启游戏")
 local now=self:scan();assert(W.equal(now,preview),"花链或组合已变化，请重新扫描")
 assert(#now.plan.remove>0 or now.plan.needs_layout,"没有重复花链或待整理空位")
 assert(not now.backup.pack and #(now.backup.BackupLvBuffCageInventoryList or {})==0 and #(now.backup.BackupLvBuffCageInventoryRef or {})==0,"请先关闭原生装备菜单，再扫描清理")
 local manager=assert(sdk.get_managed_singleton("snow.data.EquipDataManager"))
 local data=assert(sdk.get_managed_singleton("snow.data.DataManager"))
 local inventory=N.field(N.field(data,"_PlEquipBox"),"_LvBuffCageInventoryList")
 local _,get=N.array_access(N.field(inventory,"mItems"),5000)
 local by_index={};for _,i in ipairs(now.items)do by_index[i.index]=get(i.position)end
 local _,sets=N.array_access(N.field(manager,"_PlEquipMySetList"),1024)
 local plan={entries={},preview=now,manager=manager,character=now.character,current=now.current_indices,sets={}}
 local removed={};for _,index in ipairs(now.plan.remove)do removed[index]=true end
 -- 只比较将删除对象与保留对象，原对象全程保留供回滚；不再 copy 空对象到旧对象。
 for _,index in ipairs(now.plan.remove)do
  assert(W.equal(W.equipment_state(by_index[index]),W.equipment_state(by_index[now.plan.redirect[index]])),"同 ID 花链属性不同，停止清理")
 end
 local layout=Layout.prepare(inventory,removed,self.writer)
 local references={}
 for _,ref in ipairs(now.references)do
  if ref.index~=-1 then
   local source=now.plan.redirect[ref.index] or ref.index
   local after=assert(layout.final[source])
   if after~=ref.index or source~=ref.index then references[#references+1]={owner=ref.owner,before=ref.index,after=after,source=source}end
  end
 end
 plan.updated=#references;plan.moved=layout.moved
 plan.current_object=by_index[now.current]
 if plan.current_object then plan.current_state=W.equipment_state(plan.current_object)end
 for _,ref in ipairs(references)do
  self.writer.native.game_method_calls=0
  local slot=assert(tonumber(ref.owner:match("^equipment:(%d+)$")))
  local dest=sets(slot)
  local indices=N.field(dest,"_InventoryIndexList")
  local refs=N.field(dest,"<InventoryDataList>k__BackingField")
  local before=W.set_state(dest);local expected=clone(before);expected.arrays._InventoryIndexList[7]=ref.after
  local e={kind="set",dest=dest,before=before,expected=expected,index=slot,flower=ref.after,
   indices=indices,refs=refs,index_setter=assert(indices:get_type_definition():get_method("Set")),ref_setter=assert(refs:get_type_definition():get_method("Set")),
   cached_before=cached_flower(dest),cached_expected=by_index[ref.source]}
  plan.entries[#plan.entries+1]=e;plan.sets[slot]=e
 end
 local doc=json.load_file(visibility)
 if doc then
  assert(doc.schema==1 and type(doc.record_count)=="number","显示绑定格式无效")
  local after=clone(doc);after.records=after.records or {};assert(#after.records==after.record_count,"显示绑定数量无效")
  for _,row in ipairs(after.records)do
   if row.character==now.character and type(row.fingerprint)=="table" then
    local fp=row.fingerprint;local h=fp.hunter
    local e=h and plan.sets[h._EquipMysetIndex]
    if e and W.equal(fp.equipment,e.before) then fp.equipment=clone(e.expected) end
   end
  end
  if not W.equal(doc,after) then plan.entries[#plan.entries+1]={kind="visibility",before=doc,expected=after} end
 end
 plan.entries[#plan.entries+1]=layout
 plan.current=clone(now.current_indices)
 if now.current~=-1 then
  local final=assert(layout.final[now.plan.redirect[now.current] or now.current])
  if final~=now.current then
   local arr=N.field(N.field(manager,"_PlEquipPack"),"_InventoryIndexList")
   local expected=clone(now.current_indices);expected[7]=final
   plan.entries[#plan.entries+1]={kind="current",dest=arr,before=clone(now.current_indices),expected=expected,
    setter=assert(arr:get_type_definition():get_method("Set"))}
   plan.current=expected
  end
 end
 return plan
end
function M:state(e)
 if e.kind=="layout" then return Layout.state(e) end
 if e.kind=="current" then return N.array(e.dest) end
 if e.kind=="visibility" then return json.load_file(visibility) end
 return e.kind=="set" and W.set_state(e.dest) or W.equipment_state(e.dest)
end
function M:assert_context(plan)
 assert(Identity.current()==plan.character and sdk.get_managed_singleton("snow.data.EquipDataManager")==plan.manager,"角色已变化")
 local now=self:scan();assert(W.equal(now,plan.preview),"清理前数据已变化")
end
function M:apply(e)
 self:check(e,e.before,"清理目标已变化","before")
 e.write_started=true
 if e.kind=="layout" then Layout.write(e,false)
 elseif e.kind=="current" then e.setter:call(e.dest,6,e.expected[7])
 elseif e.kind=="set" and e.indices then
  e.index_setter:call(e.indices,6,e.expected.arrays._InventoryIndexList[7])
  e.ref_setter:call(e.refs,6,e.cached_expected)
 elseif e.kind=="visibility" then save(visibility,e.expected)
 else
  self.writer.native.game_method_calls=0
  self.writer:copy(e.kind=="set" and "snow.equip.PlEquipMySetData" or "snow.data.EquipmentInventoryData",e.dest,e.object)
  if e.kind=="flower" then assert(N.field(e.dest,"<InventoryIndex>k__BackingField")==e.index,"清理改变库存索引") end
 end
 self:check(e,e.expected,"清理结果回读不一致","apply")
 if e.cached_expected then assert(cached_flower(e.dest)==e.cached_expected,"组合缓存回读不一致")end
 self.writes=self.writes+1
 if self.fault_after==self.writes then error("cleanup injected failure") end
end
function M:verify(plan)
 for _,e in ipairs(plan.entries)do self:check(e,e.expected,"清理回读不一致","verify") end
 assert(Identity.current()==plan.character,"角色已变化")
 assert(W.equal(N.array(N.field(N.field(plan.manager,"_PlEquipPack"),"_InventoryIndexList")),plan.current),"当前穿着已变化")
 if plan.current_object then
  assert(W.equal(W.equipment_state(plan.current_object),plan.current_state),"当前花链属性变化")
  assert(N.field(plan.current_object,"<InventoryIndex>k__BackingField")==plan.current[7],"当前花链索引未同步")
 end
 if self.fault_on_verify then error("cleanup verification failure") end
 return {removed=#plan.preview.plan.remove,updated=plan.updated or #plan.preview.plan.references,moved=plan.moved or 0}
end
function M:restore(e)
 if not e.write_started then return end
 if e.kind=="layout" then Layout.write(e,true)
 elseif e.kind=="current" then e.setter:call(e.dest,6,e.before[7])
 elseif e.kind=="set" and e.indices then
  e.index_setter:call(e.indices,6,e.before.arrays._InventoryIndexList[7])
  e.ref_setter:call(e.refs,6,e.cached_before)
 elseif e.kind=="visibility" then save(visibility,e.before)
 else
  self.writer.native.game_method_calls=0
  self.writer:copy(e.kind=="set" and "snow.equip.PlEquipMySetData" or "snow.data.EquipmentInventoryData",e.dest,e.backup)
 end
 self.restores=self.restores+1
end
function M:verify_restored(e)
 if e.write_started then
  self:check(e,e.before,"清理恢复失败","restore")
  if e.cached_before then assert(cached_flower(e.dest)==e.cached_before,"组合缓存恢复失败")end
 end
end
function M:execute(preview)
 if self.locked or busy(journal) or busy("LoadoutClone/transaction.json") then return {ok=false,error="存在未确认恢复的操作，清理已锁定"} end
 self.writes=0;self.restores=0;self.failure=nil;self.recovery_failure=nil
 save(journal,{status="in_progress",preview=preview,cleanup_build="petalace-replacement-1"})
 local result=self.transaction:execute(preview)
 local status=result.ok and "complete" or result.code=="recovery_failed" and "recovery_failed" or "restored"
 self.locked=result.code=="recovery_failed"
 local ok=pcall(save,journal,{status=status,cleanup_build="petalace-replacement-1",preview=preview,result=result,writes=self.writes,restores=self.restores,failure=self.failure,recovery_failure=self.recovery_failure})
 if not ok then self.locked=true;return {ok=false,error="清理结果无法保存，已锁定，请保留记录检查；勿重复操作"} end
 return result
end
return M
