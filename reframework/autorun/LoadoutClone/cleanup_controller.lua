-- 与配装复制共享主线程调度，但清理拥有独立预览和回滚门禁。
local M={}
function M.new(adapter) return setmetatable({adapter=adapter,state="initial"},{__index=M}) end
function M:start(action)
 if self.job or self.external_busy then return end
 self.error=nil;self.result=nil;self.state=action
 self.job=coroutine.create(function()
  if action=="scan" then self.preview=self.adapter:scan();self.validated=false;return end
  assert(self.preview,"请先扫描")
  if action=="cleanup" then assert(self.validated,"请先完成回滚验证") end
  self.adapter.fault_on_verify=action=="validate"
  local result=self.adapter:execute(self.preview)
  self.adapter.fault_on_verify=false
  if action=="validate" then
   assert(not result.ok and result.code=="failed" and tostring(result.error):find("cleanup verification failure",1,true),result.error or "未完成预期回滚验证")
   assert(self.adapter.writes>0 and self.adapter.writes==self.adapter.restores,"清理回滚计数不一致")
   self.validated=true;self.result="回滚验证通过，原花链及组合已恢复。"
  else
   assert(result.ok,result.error or "清理未完成")
   self.result="已清理 "..result.result.removed.." 件重复花链，更新 "..result.result.updated.." 套组合，整理 "..(result.result.moved or 0).." 件花链的位置。"
   self.preview=nil;self.validated=false
  end
 end)
end
function M:step()
 if not self.job then return end
 local ok,err=coroutine.resume(self.job)
 if not ok then self.adapter.fault_on_verify=false;self.error=tostring(err);self.job=nil;self.validated=false;self.state="error"
 elseif coroutine.status(self.job)=="dead" then self.job=nil;self.state="ready" end
end
return M
