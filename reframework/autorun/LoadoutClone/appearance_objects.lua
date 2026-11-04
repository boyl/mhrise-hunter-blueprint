-- 经临时对象实测的外观复制边界。尚未由正式 Backend 启用。
local N=require("LoadoutClone.native")
local A=require("LoadoutClone.appearance")
local C=require("LoadoutClone.appearance_color")
local M={}
local T="snow.equip.PlOverwearMySetData"
function M.new(native) return setmetatable({native=native or N.new()},{__index=M}) end
function M:fresh(t)
 local obj=assert(sdk.create_instance(t,true)):add_ref()
 self.native:call(t,".ctor()",obj);return obj
end
local function colors(set)
 local n,parts=N.array_access(N.field(N.field(set,"_OverwearSymbolColor"),"_Parts"),5)
 assert(n==5,"外观染色部位不完整")
 local out={}
 for part=0,4 do
  local n,get=N.array_access(N.field(parts(part),"_ColorData"),2)
  assert(n==2,"外观染色通道不完整")
  out[part+1]={assert(get(0)):add_ref(),assert(get(1)):add_ref()}
 end
 return out
end
function M:state(set)
 local out={used=N.field(set,"_IsUsing"),name=set:get_field("_Name") or "",
  weapon=N.scalar(N.field(set,"_OverwearWeaponId")),armor=N.array(N.field(set,"_PlOverwearIdList")),colors={}}
 for part,channels in ipairs(colors(set)) do
  out.colors[part]={C.read(channels[1]),C.read(channels[2])}
 end
 return out
end
function M:copy(dest,source)
 local expected=self:state(source)
 -- 原生组合 copy 未复制颜色，必须逐通道恢复；不得使用 PlayerSymbolColor.copy。
 self.native:call(T,"copy",dest,source)
 for part,channels in ipairs(colors(dest)) do
  for channel=1,2 do C.write(channels[channel],expected.colors[part][channel]) end
 end
 assert(A.same(self:state(dest),expected),"外观组合副本回读不一致")
end
function M:clone(source)
 local result=self:fresh(T);self:copy(result,source);return result
end
function M:build(snapshot,name)
 assert(type(name)=="string" and #name>0,"外观组合名称缺失")
 assert(type(snapshot)=="table" and snapshot.schema==1,"外观快照版本错误")
 assert(type(snapshot.armor_ids)=="table" and #snapshot.armor_ids==5,"外观部位缺失")
 for part,id in ipairs(snapshot.armor_ids) do
  assert(type(id)=="number" and id%1==0 and id>=0,"防具外观 ID 无效")
  if id~=(part-1)*4096 then
   assert(self.native:call("snow.equip.EquipShortcut","isValid(snow.equip.PlOverwearId)",nil,id),"防具外观不存在")
   assert(N.scalar(self.native:call("snow.equip.EquipShortcut","getArmorPartsType(snow.equip.PlOverwearId)",nil,id))==part-1,"防具外观部位不匹配")
  end
 end
 assert(type(snapshot.weapon_id)=="number" and snapshot.weapon_id%1==0 and snapshot.weapon_id>=0,"武器外观 ID 无效")
 if snapshot.weapon_id~=134217728 then
  assert(self.native:call("snow.equip.EquipShortcut","isValid(snow.data.ContentsIdSystem.OverwearWeaponId)",nil,snapshot.weapon_id),"武器外观不存在")
 end
 local desired={}
 for part=1,5 do
  desired[part]={}
  for channel=1,2 do desired[part][channel]=C.from_snapshot(snapshot.colors[channel][part]) end
 end
 local result=self:fresh(T)
 self.native:call(T,"setName(System.String)",result,sdk.create_managed_string(name))
 self.native:call(T,"set_IsUsing",result,true)
 self.native:call(T,"setWeaponOverwearId",result,snapshot.weapon_id)
 for _,id in ipairs(snapshot.armor_ids) do self.native:call(T,"setPlOverwearId",result,id) end
 for part,channels in ipairs(colors(result)) do
  for channel=1,2 do C.write(channels[channel],desired[part][channel]) end
 end
 local actual=self:state(result)
 assert(actual.used and actual.name==name and actual.weapon==snapshot.weapon_id
  and A.same(actual.armor,snapshot.armor_ids) and A.same(actual.colors,desired),"外观候选回读不一致")
 return result
end
function M:detach_weapon_color(weapon)
 -- EquipmentInventoryData.copy 共享颜色引用；创建独立对象后再交给候选。
 local before=C.read(N.field(weapon,"_HyakuryuColorData"))
 local color=self:fresh("snow.data.SymbolColorData");C.write(color,before)
 self.native:call("snow.data.EquipmentInventoryData","set_HyakuryuColorData",weapon,color)
 assert(A.same(C.read(N.field(weapon,"_HyakuryuColorData")),before),"武器染色独立副本回读不一致")
 return color
end
return M
