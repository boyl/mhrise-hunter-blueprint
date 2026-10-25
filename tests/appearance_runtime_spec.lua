local created=0;local installed=0
package.loaded["LoadoutClone.appearance_binding"]={new=function(reader)created=created+1;return {reader=reader}end}
package.loaded["LoadoutClone.appearance_adapter"]={new=function(binding)return binding end}
package.loaded["LoadoutClone.appearance_service"]={new=function(reader,adapter)return {reader=reader,adapter=adapter}end}
package.loaded["LoadoutClone.appearance_hooks"]={install=function(binding,observe)assert(observe==false);installed=installed+1 end}
local R=require("LoadoutClone.appearance_runtime")
local co=coroutine.create(function()R.new({})end);assert(not coroutine.resume(co));assert(created==0 and installed==0)
local reader={};local service=R.new(reader);assert(service.reader==reader and created==1 and installed==1)
print("PASS 外观运行时主线程初始化，协程拒绝且不注册任何回调")
