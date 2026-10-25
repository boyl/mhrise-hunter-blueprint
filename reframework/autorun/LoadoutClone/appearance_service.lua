-- 外观用例与原生边界分离，由 Backend 的运行时工厂创建。
-- adapter 只由代码注入；不通过配置绕过原生验收。其状态快照必须为纯数据。
local Appearance=require("LoadoutClone.appearance")
local M={}
local function clone(value)
 if type(value)~="table" then
  assert(value==nil or type(value)=="boolean" or type(value)=="number" or type(value)=="string","外观状态必须为纯数据")
  return value
 end
 local out={};for k,v in pairs(value) do out[k]=clone(v) end;return out
end
function M.new(reader,adapter)
 for _,method in ipairs({"capture","validate","prepare","state","apply","restore","current"}) do
  assert(adapter and type(adapter[method])=="function","外观适配器缺少 "..method)
 end
 return setmetatable({reader=reader,adapter=adapter,tracks_weapon_color=adapter.tracks_weapon_color==true},{__index=M})
end
function M:prepare_equipment(source)
 if self.tracks_weapon_color then self.adapter:prepare_equipment(source) end
end
function M:prepare_binding(plan)
 if self.adapter.binding then return self.adapter.binding:prepare(plan) end
end
function M:apply_binding(entry) self.adapter.binding:apply(entry) end
function M:verify_binding(entry) self.adapter.binding:verify(entry) end
function M:restore_binding(entry) self.adapter.binding:restore(entry) end
function M:verify_binding_restored(entry) self.adapter.binding:verify_restored(entry) end
function M:member(source,session)
 local list=self.reader:list_members()
 assert(list.session==session,"外观读取期间会话已变化")
 for _,member in ipairs(list.members) do if member.key==source.key then return member end end
 error("外观来源猎人已离开")
end
function M:capture(source,session)
 local member=self:member(source,session)
 local snapshot=clone(self.adapter:capture(member.index))
 assert(snapshot.schema==1,"外观快照版本不支持")
 assert(self.adapter:validate(snapshot,member)==true,"外观 ID 或颜色不符合原生约束")
 local after=self:member(source,session)
 assert(after.index==member.index,"大厅成员位置已变化，请重新读取")
 return {snapshot=snapshot,source={key=member.key,index=member.index},session=session}
end
function M:prepare(candidate,plan)
 local current=clone(self.adapter:current(plan))
 assert(type(current)=="table","当前外观快照缺失")
 local entry=self.adapter:prepare(candidate.snapshot,plan)
 assert(type(entry)=="table" and type(entry.slot)=="number" and entry.slot%1==0 and entry.slot>=0 and entry.slot<1024,"外观组合槽无效")
 assert(entry.before and entry.expected and entry.backup,"外观备份或校验数据缺失")
 assert(entry.before.used==false and entry.expected.used==true,"外观目标必须是空组合槽")
 entry.kind="appearance"
 entry.before=clone(entry.before);entry.expected=clone(entry.expected)
 plan.appearance_current=current
 assert(Appearance.same(self.adapter:current(plan),current),"准备外观时当前穿着已变化")
 return entry
end
function M:assert_context(candidate,plan)
 local current=self:capture(candidate.source,candidate.session)
 assert(Appearance.same(current.snapshot,candidate.snapshot),"目标外观或染色已变化，请重试")
 self:verify_current(plan)
end
function M:apply(entry)
 assert(Appearance.same(self.adapter:state(entry),entry.before),"预留外观槽或颜色备份已变化")
    entry.write_started=true
 self.adapter:apply(entry)
end
function M:verify(entry)
 assert(Appearance.same(self.adapter:state(entry),entry.expected),"外观与染色回读不一致")
end
function M:restore(entry)
 if entry.write_started then self.adapter:restore(entry) end
end
function M:verify_restored(entry)
 if not entry.write_started then return end -- 拒绝阶段未写入，不用旧备份覆盖外部更新。
 assert(Appearance.same(self.adapter:state(entry),entry.before),"外观与染色恢复回读失败")
end
function M:verify_current(plan)
 assert(Appearance.same(self.adapter:current(plan),plan.appearance_current),"当前外观被改变")
end
return M
