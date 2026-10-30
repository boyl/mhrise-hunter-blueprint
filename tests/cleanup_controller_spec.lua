local C=require("LoadoutClone.cleanup_controller")
local adapter={scan=function()return {plan={remove={1},references={}}}end,writes=2,restores=2}
function adapter:execute()
 if self.fault_on_verify then return {ok=false,code="failed",error="cleanup verification failure"} end
 return {ok=true,result={removed=1,updated=0}}
end
local c=C.new(adapter);c:start("cleanup");c:step();assert(c.error and not c.validated)
c:start("scan");c:step();assert(c.preview and not c.validated)
c:start("validate");c:step();assert(c.validated and not adapter.fault_on_verify)
c:start("cleanup");c:step();assert(not c.preview and c.result:find("已清理",1,true))
c.external_busy=true;c:start("scan");assert(not c.job)
c.external_busy=false;c:start("scan");c:step();adapter.restores=1;c:start("validate");c:step();assert(c.error and not c.validated)
print("PASS 清理入口先扫描、实际回滚门禁、与复制互斥、成功清空预览、失败关闭删除")
