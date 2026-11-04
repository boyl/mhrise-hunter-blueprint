local C=require("LoadoutClone.controller")
local c=C.new({supports_appearance=function()return true end,supports_weapon_visibility=function()return false end,
 weapon_visibility_warning=function()return "unsupported" end})
c:set_copy_appearance(true)
assert(c.appearance_available and not c.weapon_visibility_available and c.visibility_warning=="unsupported")
assert(c:set_copy_weapon_visibility(true)==false and not c.copy_weapon_visibility)
local S=require("LoadoutClone.appearance_service")
local calls=0
local service=setmetatable({weapon_visibility_available=false,adapter={binding={prepare=function()calls=calls+1;return {}end}}},{__index=S})
local ok,err=pcall(service.prepare_binding,service,{source={options={copy_weapon_visibility=true}}})
assert(not ok and tostring(err):find("停止写入",1,true) and calls==0)
assert(service:prepare_binding({source={options={copy_weapon_visibility=false}}}) and calls==1)
print("PASS 不支持显示同步时面板不能勾选，事务准备拒绝强制选项，普通外观绑定仍可清理旧记录")
