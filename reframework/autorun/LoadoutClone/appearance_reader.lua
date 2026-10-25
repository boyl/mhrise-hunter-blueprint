-- 已由只读探针验证的远端外观读取。调用方仍须绑定成员身份并在提交前重读。
-- 仅创建离线候选对象；不修改玩家、库存、组合或存档。
local Native=require("LoadoutClone.native")
local Appearance=require("LoadoutClone.appearance")
local M={}
local field=Native.field
local function elements(value,size,label)
 local count,get=Native.array_access(value,size)
 assert(count==size,label.."尚未完整加载")
 return get
end
local function read_color(enabled,value)
 enabled=Native.scalar(enabled)
 assert(type(enabled)=="boolean","染色启用状态无效")
 local out={enabled=enabled}
 if enabled then
  assert(value,"染色数据缺失")
  out.rgba={x=value.x,y=value.y,z=value.z}
 end
 return out
end
function M.capture(index,native)
 assert(type(index)=="number" and index%1==0 and index>=0,"大厅索引无效")
 native=native or Native.new()
 local params=assert(sdk.get_managed_singleton("snow.gui.EquipStatusParamManager"),"大厅装备尚未加载")
 local count,get=Native.array_access(field(params,"_lobbyParam"),16)
 assert(index<count,"大厅索引已失效")
 local packet=assert(get(index),"目标装备尚未加载")
 local source={weapon_id=field(field(packet,"_overwearWeaponParam"),"Id"),armor_ids={},colors={{},{}}}
 local armor=elements(field(packet,"_overwearParam"),5,"防具外观")
 for i=0,4 do source.armor_ids[i+1]=field(armor(i),"Id") end
 local lobby=assert(sdk.get_managed_singleton("snow.LobbyManager"),"大厅尚未加载")
 local info_count,get_info=Native.array_access(field(lobby,"_equipInfo"),16)
 assert(index<info_count,"大厅外观索引已失效")
 local send=field(assert(get_info(index),"目标外观尚未加载"),"_CharaCreate")
 local base_type="snow.player.PlayerManager.PlayerCreateBaseData"
 local base=assert(sdk.create_instance(base_type,true)):add_ref()
 native:call(base_type,".ctor()",base)
 native:call("snow.player.PlayerCreateSendData","copyTo",send,base)
 for channel=1,2 do
  local flags=elements(field(base,"_IsEnableSymbolColor"..channel),5,"染色状态")
  local colors=elements(field(base,"_SymbolColor"..channel),5,"染色数据")
  for part=0,4 do source.colors[channel][part+1]=read_color(flags(part),colors(part)) end
 end
 source.weapon_hidden=field(base,"_IsWeaponOff")
 source.weapon_color=read_color(field(base,"_IsEnableWeaponColor"),field(base,"_WeaponColor"))
 return Appearance.normalize(source)
end
return M
