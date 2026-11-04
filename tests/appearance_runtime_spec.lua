local created=0;local installed=0
thread={get_hook_storage=function()end}
package.loaded["LoadoutClone.appearance_binding"]={new=function(reader)created=created+1;return {reader=reader}end}
package.loaded["LoadoutClone.appearance_adapter"]={new=function(binding)return binding end}
package.loaded["LoadoutClone.appearance_service"]={new=function(reader,adapter)return {reader=reader,adapter=adapter}end}
package.loaded["LoadoutClone.appearance_hooks"]={install=function(binding,observe)assert(observe==false);installed=installed+1 end}
local R=require("LoadoutClone.appearance_runtime")
local co=coroutine.create(function()R.new({})end);assert(not coroutine.resume(co));assert(created==0 and installed==0)
local reader={};local service=R.new(reader);assert(service.reader==reader and created==1 and installed==1)
print("PASS 外观运行时主线程初始化，协程拒绝且不注册任何回调")
thread=nil
local fallback=R.new(reader)
assert(fallback.weapon_visibility_available==false and installed==1)
assert(fallback.visibility_warning:find("幻化与染色",1,true))
thread={get_hook_storage=function()end}
assert(R.new(reader).weapon_visibility_available==true and installed==2)
package.loaded["LoadoutClone.appearance_hooks"].install=function()error("unexpected hook failure")end
local success,message=pcall(R.new,reader)
assert(not success and tostring(message):find("unexpected hook failure",1,true))
print("PASS 缺少接口保留外观服务，支持接口正常安装，其他钩子异常不吞掉")
