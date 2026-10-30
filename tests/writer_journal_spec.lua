package.loaded["LoadoutClone.native"]={new=function() return {} end}
local W=require("LoadoutClone.writer")
for _,failure in ipairs({"before","after","throw"}) do
 local w=W.new({});local calls=0;local saves=0
 w.transaction.execute=function() calls=calls+1;return {ok=true,result={name="test"}} end
 json={load_file=function() return nil end,dump_file=function()
  saves=saves+1
  if failure=="throw" then error("disk error") end
  return not ((failure=="before" and saves==1) or (failure=="after" and saves==2))
 end}
 local r=w:execute({source={key="a"},options={}})
 assert(not r.ok)
 assert(calls==(failure=="after" and 1 or 0),"日志失败不得继续写入装备")
 if failure=="after" then
  assert(w.transaction.locked)
  local again=w:execute({source={key="a"}})
  assert(not again.ok and calls==1,"结果落盘失败后必须阻止重复复制")
 end
end
print("PASS 事务开始记录失败零写入、结果记录失败锁定、IO 异常明确返回")
