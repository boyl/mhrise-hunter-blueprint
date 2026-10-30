-- 只在独立对象上执行原生排序；实际库存只读，逐项核对前后相同。
return {run=function(_,_,report)
 local N=assert(package.loaded['LoadoutClone.native'])
 local W=assert(package.loaded['LoadoutClone.writer'])
 local data=assert(sdk.get_managed_singleton('snow.data.DataManager'))
 local live=N.field(data,'_PlEquipBox');local list=N.field(live,'_LvBuffCageInventoryList')
 local size=N.field(list,'mSize');assert(size>=0 and size<=50)
 local _,get=N.array_access(N.field(list,'mItems'),50)
 local list_type=list:get_type_definition();local ctor=assert(list_type:get_method('.ctor()'));local add=assert(list_type:get_method('Add'))
 local sort=assert(sdk.find_type_definition('snow.data.EquipBox'):get_method('sortLvBuffCage()'))
 local writer=W.new({});local objects,before,by_object={},{},{}
 local clone_method=assert(sdk.find_type_definition('System.Object'):get_method('MemberwiseClone()'))
 local temp_list=assert(clone_method:call(list)):add_ref();assert(temp_list~=list)
 local temp_array=assert(sdk.create_managed_array('snow.data.EquipmentInventoryData',size)):add_ref()
 temp_list:set_field('mItems',temp_array);temp_list:set_field('mSize',0)
 for i=0,size-1 do
  local original=get(i);before[i+1]={index=N.field(original,'<InventoryIndex>k__BackingField'),state=W.equipment_state(original)}
  writer.native.game_method_calls=0
  local copy=writer:backup('snow.data.EquipmentInventoryData',original);assert(copy~=original)
  copy:set_field('<InventoryIndex>k__BackingField',before[i+1].index)
  objects[#objects+1]=copy;by_object[copy]=i;add:call(temp_list,copy)
  if i%5==4 then coroutine.yield()end
 end
 assert(N.field(temp_list,'mItems')~=N.field(list,'mItems'))
 local box=assert(sdk.create_instance('snow.data.EquipBox',true)):add_ref();assert(box~=live)
 box:set_field('_LvBuffCageInventoryList',temp_list)
 assert(N.field(box,'_LvBuffCageInventoryList')==temp_list)
 report.before={};for i,v in ipairs(before)do if v.state._IdType~=0 then report.before[#report.before+1]={position=i-1,index=v.index,id=v.state._IdVal}end end
 sort:call(box)
 local _,sorted=N.array_access(N.field(temp_list,'mItems'),50);report.after={};local seen={}
 for i=0,size-1 do
  local o=sorted(i);local origin=assert(by_object[o]);assert(not seen[origin]);seen[origin]=true
  assert(W.equal(W.equipment_state(o),before[origin+1].state),'sort changed equipment attributes')
  assert(N.field(o,'<InventoryIndex>k__BackingField')==i,'sort index mismatch')
  if N.field(o,'_IdType')~=0 then report.after[#report.after+1]={position=i,index=i,id=N.field(o,'_IdVal'),old_position=origin}end
  local original=get(i)
  assert(W.equal(W.equipment_state(original),before[i+1].state),'LIVE INVENTORY CHANGED')
  assert(N.field(original,'<InventoryIndex>k__BackingField')==before[i+1].index,'LIVE INDEX CHANGED')
 end
 report.actual_inventory_unchanged=true;report.temporary_items=size;report.writes=0;report.status='complete'
end}
