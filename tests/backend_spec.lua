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
