local A=require("LoadoutClone.appearance")
local Service=require("LoadoutClone.appearance_service")
local function copy(v) if type(v)~="table" then return v end;local o={};for k,x in pairs(v) do o[k]=copy(x) end;return o end
package.loaded["LoadoutClone.native"]={new=function() return {} end,field=function(o,k) return o[k] end,array=function(v) return v end}
local Writer=require("LoadoutClone.writer")
json={load_file=function() return nil end,dump_file=function() return true end}
local total=0
local function test(name,fn) fn();total=total+1;print("PASS "..name) end
local function fixture(fault)
 local snapshot={schema=1,weapon_id=134217728,colors={{enabled=true,hsv={30,90,47}}}}
 local box={used=false,ids={0,4096},colors={0,0},hunter=-1}
 local initial=copy(box);local current={weapon=0,color=12}
 local reads=0;local calls={apply=0,restore=0}
 local reader={list_members=function() return {session="s",members={{key="a",index=0}}} end}
 local adapter={}
 function adapter:capture() reads=reads+1;local s=copy(snapshot);if fault=="changed" and reads>1 then s.weapon_id=1 end;return s end
 function adapter:validate() return fault~="invalid" end
 function adapter:current() return copy(current) end
 function adapter:prepare()
  if fault=="full" then error("外观组合没有空位") end
  return {slot=0,before=copy(box),backup=copy(box),expected={used=true,ids={1,4097},colors={47,90},hunter=0}}
 end
 function adapter:state() return copy(box) end
 function adapter:apply(e)
  calls.apply=calls.apply+1;box.used=true;box.colors[1]=47
  if fault=="partial" or fault=="restore" then error("partial") end
  box=copy(e.expected)
  if fault=="readback" then box.colors[2]=0 end
  if fault=="current" then current.color=99 end
 end
 function adapter:restore(e) calls.restore=calls.restore+1;if fault=="restore" then error("restore") end;box=copy(e.backup);current.color=12 end
 local service=Service.new(reader,adapter)
 local w=Writer.new(reader,service)
 local candidate
 function w:prepare()
  candidate=service:capture({key="a"},"s")
  local plan={source={appearance=candidate},entries={},manager={_PlEquipPack={_InventoryIndexList={}}},current={},slot=0,hunter_slot=0}
  plan.entries[1]=service:prepare(candidate,plan)
  if fault=="reserved" then box.colors[1]=99 end
  return plan
 end
 function w:assert_context(plan) service:assert_context(candidate,plan) end
 return w,calls,function() return box,initial end
end
test("外观通过生产 Writer 的 apply、verify 与当前外观检查",function()
 local w,calls,state=fixture();assert(w:execute({source={key="a"}}).ok);assert(calls.apply==1 and calls.restore==0 and state().used)
end)
for _,fault in ipairs({"invalid","full","changed"}) do
 test("外观预提交拒绝零写入："..fault,function()
  local w,calls,state=fixture(fault);local r=w:execute({source={key="a"}});assert(not r.ok and r.code=="failed");assert(calls.apply==0 and calls.restore==0)
  local actual,before=state();assert(A.same(actual,before))
 end)
end
for _,fault in ipairs({"partial","readback","current"}) do
 test("外观失败经生产 Writer 恢复："..fault,function()
  local w,calls,state=fixture(fault);local r=w:execute({source={key="a"}});assert(not r.ok and r.code=="failed",r.error)
  assert(calls.apply==1 and calls.restore==1);local actual,before=state();assert(A.same(actual,before))
 end)
end
test("外观恢复失败锁定后续事务",function()
 local w,calls=fixture("restore");local r=w:execute({source={key="a"}});assert(r.code=="recovery_failed")
 assert(w:execute({source={key="a"}}).code=="locked" and calls.apply==1)
end)
test("外部抢占外观槽时不以旧备份覆盖新数据",function()
 local w,calls,state=fixture("reserved");local r=w:execute({source={key="a"}})
 assert(not r.ok and r.code=="failed" and calls.apply==0 and calls.restore==0)
 assert(state().colors[1]==99)
end)
test("外观服务拒绝缺少回读或恢复方法的适配器",function()
 assert(not pcall(Service.new,{},{}))
end)
test("未注入实机适配器时 Writer 拒绝外观请求",function()
 local w=Writer.new({});local ok,err=pcall(w.prepare,w,{options={copy_appearance=true},items={}})
 assert(not ok and tostring(err):find("外观候选未就绪",1,true) and w.write_count==0)
end)
test("外观候选不得绕过关闭的选项",function()
 local w=Writer.new({});local ok,err=pcall(w.prepare,w,{options={copy_appearance=false},appearance={},items={}})
 assert(not ok and tostring(err):find("不一致",1,true) and w.write_count==0)
end)
test("Planner 在读取目录和目标前拒绝未开放的外观请求",function()
 local Planner=require("LoadoutClone.planner")
 local calls=0
 local p=Planner.new({capture=function() calls=calls+1 end})
 local ok,err=pcall(p.prepare,p,"a",{copy_appearance=true})
 assert(not ok and tostring(err):find("未开放",1,true) and calls==0)
end)
print(total.." appearance transaction tests passed")
