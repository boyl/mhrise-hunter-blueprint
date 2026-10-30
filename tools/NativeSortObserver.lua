-- 原生整理只读观察器：在主线程注册；回调只计数，不读对象、不改参数。
local _,main=coroutine.running();assert(main,"sort observer requires main Lua thread")
local N=require("LoadoutClone.native")
local owner=assert(sdk.find_type_definition("snow.data.EquipBox"))
local gui=assert(sdk.find_type_definition("snow.gui.fsm.equipchange.GuiItemBoxEquipChangeWindow"))
local signatures={"sortLvBuffCage()","sortInventoryList(snow.data.InventoryData.SortType)","invokeSortInventory()"}
local methods={}
for _,s in ipairs(signatures)do methods[s]=assert(owner:get_method(s),s)end
local gui_signature="routineEquipChangeSortEquipmentYN"
methods[gui_signature]=assert(gui:get_method(gui_signature),gui_signature)
signatures[#signatures+1]=gui_signature
local report={session=tostring(os.time()).."-"..tostring(os.clock()),read_only=true,calls={},events={},snapshots={}}
local generation,last,settle=0,-1,0
for _,signature in ipairs(signatures)do
 local name=signature
 report.calls[name]={pre=0,post=0}
 sdk.hook(methods[name],function()
  report.calls[name].pre=report.calls[name].pre+1;generation=generation+1
  if #report.events<100 then report.events[#report.events+1]={method=name,phase="pre"}end
 end,function(value)
  report.calls[name].post=report.calls[name].post+1;generation=generation+1
  if #report.events<100 then report.events[#report.events+1]={method=name,phase="post"}end
  return value
 end)
end
local function snapshot()
 local data=assert(sdk.get_managed_singleton("snow.data.DataManager"))
 local manager=assert(sdk.get_managed_singleton("snow.data.EquipDataManager"))
 local box=N.field(data,"_PlEquipBox")
 local list=N.field(box,"_LvBuffCageInventoryList")
 local size=N.field(list,"mSize");assert(size>=0 and size<=5000)
 local _,get=N.array_access(N.field(list,"mItems"),5000)
 local rows={}
 for i=0,size-1 do
  local o=get(i);rows[#rows+1]={position=i,index=N.field(o,"<InventoryIndex>k__BackingField"),kind=N.field(o,"_IdType"),id=N.field(o,"_IdVal")}
 end
 return {generation=generation,items=rows,current=N.array(N.field(N.field(manager,"_PlEquipPack"),"_InventoryIndexList")),time=os.clock()}
end
re.on_application_entry("UpdateBehavior",function()
 if generation==last and settle==0 then return end
 if generation~=last then last=generation;settle=3 end
 settle=settle-1
 if settle>0 then return end
 local ok,value=pcall(snapshot)
 if ok then
  if #report.snapshots<30 then report.snapshots[#report.snapshots+1]=value end
  report.error=nil
 else report.error=tostring(value) end
 json.dump_file("LoadoutClone/native-sort-observer.json",report)
end)
json.dump_file("LoadoutClone/native-sort-observer.json",report)
