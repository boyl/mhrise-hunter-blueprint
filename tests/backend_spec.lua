package.loaded["LoadoutClone.reader"]={new=function() return {} end}
package.loaded["LoadoutClone.planner"]={new=function() return {} end}
local calls=0
package.loaded["LoadoutClone.writer"]={new=function() return {execute=function() calls=calls+1;return {ok=true} end} end}
local Backend=require("LoadoutClone.backend")
local config
json={load_file=function() return config end}
local b=Backend.new()
assert(b:commit({}).ok and calls==1,"首次安装没有开发配置也可使用")
config={write_enabled=false};assert(not pcall(b.commit,b,{}));assert(calls==1)
config={};assert(not pcall(b.commit,b,{}));assert(calls==1)
config={write_enabled=true};assert(b:commit({}).ok and calls==2)
print("PASS 首次安装、显式禁用、配置缺字段与启用写入（4 项）")
assert(not b:supports_appearance())
assert(not pcall(Backend.new,true),"不能用布尔配置绕过外观适配器")
local created_reader,service={},{}
package.loaded["LoadoutClone.planner"].new=function(r,a) created_reader=r;assert(a==service);return {} end
package.loaded["LoadoutClone.writer"].new=function(r,a) assert(r==created_reader and a==service);return {} end
local enabled=Backend.new(function(r) service.reader=r;return service end)
assert(enabled:supports_appearance() and service.reader==created_reader)
local Controller=require("LoadoutClone.controller")
assert(not Controller.new(b).appearance_available)
local c=Controller.new(enabled);assert(c.appearance_available and c.copy_appearance==false)
print("PASS 外观服务共用实例、默认门禁及控制器能力传递（3 项）")
