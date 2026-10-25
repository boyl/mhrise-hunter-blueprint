-- 从 autorun 主 Lua 线程建立长期回调；不能由复制协程或诊断任务初始化。
local M={}
function M.new(reader)
 local _,main=coroutine.running()
 assert(main,"外观服务必须在主 Lua 线程初始化")
 local binding=require("LoadoutClone.appearance_binding").new(reader)
 local adapter=require("LoadoutClone.appearance_adapter").new(binding)
 local service=require("LoadoutClone.appearance_service").new(reader,adapter)
 require("LoadoutClone.appearance_hooks").install(binding,false)
 return service
end
return M
