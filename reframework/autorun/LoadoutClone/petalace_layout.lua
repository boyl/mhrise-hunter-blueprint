-- 先在完全独立的候选列表上执行原生排序，再事务化迁移原对象。
local N=require("LoadoutClone.native")
local W=require("LoadoutClone.writer")
local M={}
function M.prepare(inventory,removed,writer)
 local size=N.field(inventory,"mSize");assert(size>=0 and size<=50,"花链容量异常")
 local array=N.field(inventory,"mItems");local _,get=N.array_access(array,50)
 local lt=inventory:get_type_definition()
 local temp=assert(sdk.find_type_definition("System.Object"):get_method("MemberwiseClone()"):call(inventory)):add_ref()
 assert(temp~=inventory)
 local ta=assert(sdk.create_managed_array("snow.data.EquipmentInventoryData",size)):add_ref()
 temp:set_field("mItems",ta);temp:set_field("mSize",0)
 local add=assert(lt:get_method("Add"));local copies,originals,ids,old_indices={},{},{},{}
 local before={}
 for i=0,size-1 do
  local o=get(i);assert(not ids[o],"花链对象重复")
  ids[o]=i+1;originals[i+1]=o;old_indices[i+1]=N.field(o,"<InventoryIndex>k__BackingField")
  assert(old_indices[i+1]==i,"花链库存索引异常")
  writer.native.game_method_calls=0
  local c
  if removed[i] then c=assert(sdk.create_instance("snow.data.EquipmentInventoryData",true)):add_ref();writer.native:call("snow.data.EquipmentInventoryData",".ctor()",c)
  else c=writer:backup("snow.data.EquipmentInventoryData",o) end
  assert(c~=o);copies[c]=i+1;add:call(temp,c)
  before[i+1]={identity=i+1,index=i}
 end
 local box=assert(sdk.create_instance("snow.data.EquipBox",true)):add_ref()
 box:set_field("_LvBuffCageInventoryList",temp)
 sdk.find_type_definition("snow.data.EquipBox"):get_method("sortLvBuffCage()"):call(box)
 local _,sorted=N.array_access(N.field(temp,"mItems"),50)
 local order,expected,final,seen={},{},{},{};local moved=0
 for i=0,size-1 do
  local identity=assert(copies[sorted(i)],"未知排序对象");assert(not seen[identity]);seen[identity]=true
  order[i+1]=originals[identity];final[identity-1]=i;expected[i+1]={identity=identity,index=i}
  if identity-1~=i and N.field(originals[identity],"_IdType")~=0 and not removed[identity-1] then moved=moved+1 end
 end
 return {kind="layout",array=array,size=size,ids=ids,originals=originals,order=order,before=before,expected=expected,final=final,moved=moved,
  setter=assert(array:get_type_definition():get_method("Set"))}
end
function M.state(e)
 local _,get=N.array_access(e.array,50);local rows={}
 for i=0,e.size-1 do local o=get(i);rows[i+1]={identity=assert(e.ids[o],"花链对象被替换"),index=N.field(o,"<InventoryIndex>k__BackingField")}end
 return rows
end
function M.write(e,restore)
 local order=restore and e.originals or e.order
 for i,o in ipairs(order)do e.setter:call(e.array,i-1,o);o:set_field("<InventoryIndex>k__BackingField",i-1)end
end
return M
