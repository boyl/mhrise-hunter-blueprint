local guid={mData1=123456789,mData2=12345,mData3=23456,mData4_0=183,mData4_1=69,mData4_2=63,mData4_3=56,mData4_4=177,mData4_5=243,mData4_6=230,mData4_7=224}
local save={_CurrentHunterSlotNo=0};local card={GuildCardID=guid,HunterName="a"}
local guild={_GuildCard={MyData=card}}
package.loaded["LoadoutClone.native"]={field=function(o,k)assert(o and o[k]~=nil,k);return o[k]end}
sdk={get_managed_singleton=function(name)
 if name=="snow.SnowSaveService" then return save end
 assert(name=="snow.GuildCardManager","不得访问大厅或网络状态")
 return guild
end}
local I=require("LoadoutClone.character_identity")
local expected="0:123456789-12345-23456-183-69-63-56-177-243-230-224"
assert(I.current()==expected);card.HunterName="b";assert(I.current()==expected)
save._CurrentHunterSlotNo=1;assert(I.current()~=expected);save._CurrentHunterSlotNo=-1;assert(not pcall(I.current))
save._CurrentHunterSlotNo=0;guid.mData1=-1;assert(not pcall(I.current))
for key in pairs(guid) do guid[key]=0 end
assert(not pcall(I.current));guild=nil;assert(not pcall(I.current))
print("PASS 离线本地身份保持旧绑定格式，改名不变，槽位分离，未初始化／缺失身份拒绝")
