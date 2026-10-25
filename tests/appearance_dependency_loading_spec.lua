local phase="startup"
package.loaded["LoadoutClone.native"]={}
package.loaded["LoadoutClone.hunter"]={}
package.loaded["LoadoutClone.appearance_objects"]={}
package.loaded["LoadoutClone.appearance_visibility"]={}
package.preload["LoadoutClone.character_identity"]=function()
 assert(phase=="startup","运行时不能首次加载身份模块")
 return {current=function()return "0:local-guid"end}
end
local B=require("LoadoutClone.appearance_binding")
phase="callback";package.path="";package.cpath=""
assert(B.character({})=="0:local-guid")
print("PASS 身份依赖在启动期加载，运行回调搜索路径清空后仍可读取")
