-- 只读清理扫描；复用生产代码的原生数组解箱契约。
local M={}
function M.run(N,P,report)
 local field,array=N.field,N.array

 local data=assert(sdk.get_managed_singleton("snow.data.DataManager"))
 local manager=assert(sdk.get_managed_singleton("snow.data.EquipDataManager"))
 local box=field(data,"_PlEquipBox")
 local list=field(box,"_LvBuffCageInventoryList");local rows=field(list,"mItems");local size=field(list,"mSize")
 assert(size>=0 and size<=5000,"inventory bound")
 local capacity,get_row=N.array_access(rows,5000);assert(size<=capacity)
 for i=0,size-1 do
  local o=get_row(i);local kind=field(o,"_IdType")
  if kind~=0 then report.items[#report.items+1]={index=field(o,"<InventoryIndex>k__BackingField"),position=i,kind=kind,id=field(o,"_IdVal"),locked=field(o,"_IsLock"),guild_card=field(o,"_IsSetGuildCard")} end
  if i%32==31 then coroutine.yield() end
 end
 local current=array(field(field(manager,"_PlEquipPack"),"_InventoryIndexList"));report.current=current[7];report.current_indices=current
 local sets=field(manager,"_PlEquipMySetList");local n,get_set=N.array_access(sets,1024)
 for i=0,n-1 do
  local set=get_set(i)
  if field(set,"_IsUsing") then
   local indices=array(field(set,"_InventoryIndexList"))
   report.references[#report.references+1]={owner="equipment:"..i,index=assert(indices[7])}
  end
  if i%32==31 then coroutine.yield() end
 end
 report.backup={}
 local pack=manager:get_field("BackupPlEquipPack")
 if pack then
  local indices=pack:get_field("_InventoryIndexList")
  if indices then report.backup.pack=array(indices) end
 end
 for _,key in ipairs({"BackupLvBuffCageInventoryList","BackupLvBuffCageInventoryRef"}) do
  local values=box:get_field(key)
  local out={};report.backup[key]=out
  if values then
   local n,get=N.array_access(values,5000)
   for i=0,n-1 do
    local o=get(i)
    if o then out[#out+1]={position=i,kind=field(o,"_IdType"),id=field(o,"_IdVal"),index=field(o,"<InventoryIndex>k__BackingField")} end
   end
  end
 end
 report.plan=P.plan(report)
 report.status="complete"
end
return M
