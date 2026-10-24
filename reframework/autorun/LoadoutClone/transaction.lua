-- 事务协调器不认识游戏对象。适配器负责已验证的读写、身份和容量契约。
-- 仅覆盖 Lua 可恢复错误，不能保证原生崩溃或进程退出后的原子性。
local M={}
function M.new(adapter)
    return setmetatable({adapter=adapter,busy=false,locked=false},{__index=M})
end
function M:execute(target)
    if self.locked then return {ok=false,code="locked"} end
    if self.busy then return {ok=false,code="busy"} end
    self.busy=true
    local applied={}
    local ok,result=xpcall(function()
        local plan=self.adapter:prepare(target)
        assert(type(plan)=="table" and type(plan.entries)=="table" and #plan.entries>0,"invalid empty plan")
        self.adapter:assert_context(plan)
        for _,entry in ipairs(plan.entries) do
            -- 先登记再写入，以覆盖 apply 部分修改后抛错。
            applied[#applied+1]=entry
            self.adapter:apply(entry)
        end
        return self.adapter:verify(plan)
    end,debug.traceback)
    if ok then self.busy=false; return {ok=true,result=result} end
    local failures={}
    for i=#applied,1,-1 do
        local restored,reason=xpcall(function()
            self.adapter:restore(applied[i])
            self.adapter:verify_restored(applied[i])
        end,debug.traceback)
        if not restored then failures[#failures+1]=tostring(reason) end
    end
    self.busy=false
    if #failures>0 then
        self.locked=true
        return {ok=false,code="recovery_failed",error=result,recovery_errors=failures}
    end
    return {ok=false,code="failed",error=result}
end
return M
