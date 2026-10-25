-- 当前角色的本地存档身份；不依赖联机成员列表、网络 ID 或角色名称。
local N=require("LoadoutClone.native")
local M={}
local keys={"mData1","mData2","mData3","mData4_0","mData4_1","mData4_2","mData4_3","mData4_4","mData4_5","mData4_6","mData4_7"}
function M.current()
 local save=assert(sdk.get_managed_singleton("snow.SnowSaveService"),"存档会话未就绪")
 local slot=N.field(save,"_CurrentHunterSlotNo")
 assert(type(slot)=="number" and slot%1==0 and slot>=0 and slot<=2,"角色存档槽无效")
 local manager=assert(sdk.get_managed_singleton("snow.GuildCardManager"),"本地角色身份未加载")
 local card=N.field(N.field(manager,"_GuildCard"),"MyData")
 local guid=N.field(card,"GuildCardID")
 local parts={};local nonzero=false
 for i,key in ipairs(keys) do
  local n=N.field(guid,key)
  local limit=i==1 and 4294967295 or (i<=3 and 65535 or 255)
  assert(type(n)=="number" and n%1==0 and n>=0 and n<=limit,"本地角色 GUID 无效")
  parts[i]=tostring(n);nonzero=nonzero or n~=0
 end
 assert(nonzero,"本地角色身份尚未初始化")
 return slot..":"..table.concat(parts,"-")
end
return M
