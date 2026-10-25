-- 真实原生字段与数组形状的测试替身；不冒充 SDK 实机验证。
local calls=0
local base={_IsWeaponOff=false,_IsEnableWeaponColor=false,_WeaponColor={}}
for c=1,2 do
 base["_IsEnableSymbolColor"..c]={false,false,false,false,false}
 base["_SymbolColor"..c]={{},{},{},{},{}}
end
base._IsEnableSymbolColor1[1]=true
base._SymbolColor1[1]={x=0.8,y=0,z=0}
function base:add_ref() self.held=true;return self end
local packet={_overwearWeaponParam={Id=134217728},_overwearParam={}}
for i=1,5 do packet._overwearParam[i]={Id=(i-1)*4096} end
local managers={
 ["snow.gui.EquipStatusParamManager"]={_lobbyParam={packet}},
 ["snow.LobbyManager"]={_equipInfo={{_CharaCreate={}}}},
}
sdk={get_managed_singleton=function(name) return managers[name] end,
 create_instance=function() return base end}
local native={call=function(_,_,method)
 calls=calls+1;assert(base.held,"临时对象必须持有引用")
 assert(method==".ctor()" or method=="copyTo","禁止未知或写入调用")
end}
package.loaded["LoadoutClone.native"]={
 field=function(o,k) return assert(o)[k] end,scalar=function(v) return v end,
 array_access=function(t,max)
  assert(type(t)=="table" and #t<=max)
  return #t,function(i) return t[i+1] end
 end,
}
local R=require("LoadoutClone.appearance_reader")
local result=R.capture(0,native)
assert(result.armor_ids[5]==16384 and result.colors[1][1].hsv[3]==100)
assert(calls==2 and result.weapon_hidden==false)
print("PASS 外观只读适配器保留部位、染色及隐藏状态")
local before=calls
assert(not pcall(R.capture,1,native));assert(calls==before)
assert(not pcall(R.capture,-1,native));assert(calls==before)
print("PASS 失效大厅索引在创建候选前拒绝")
packet._overwearParam[5]=nil
assert(not pcall(R.capture,0,native));assert(calls==before)
print("PASS 不完整防具外观在创建候选前拒绝")
packet._overwearParam[5]={Id=16384}
base._SymbolColor2[5]=nil
assert(not pcall(R.capture,0,native))
print("PASS 不完整第二染色通道不返回部分结果")
