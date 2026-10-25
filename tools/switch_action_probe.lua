local M={}
function M.run(request,report,checkpoint)
 local N=require("LoadoutClone.native")
 local native=N.new();local f=N.field
 local reader=require("LoadoutClone.reader").new()
 local snapshot=reader:capture(assert(request.key))
 report.actions=snapshot.data._equipStatusParam.switchActionId
 report.red=snapshot.data._equipStatusParam.switchActionId_MR_1
 report.blue=snapshot.data._equipStatusParam.switchActionId_MR_2
 local manager=assert(sdk.get_managed_singleton("snow.data.EquipDataManager"))
 local count,get=N.array_access(f(manager,"_PlEquipMySetList"),1024)
 report.existing_lengths={};report.examples={};report.writes=0
 for i=0,count-1 do
  local set=get(i)
  if f(set,"_IsUsing") then
   local values=N.array(f(set,"_ActionIdList"));local key=tostring(#values)
   report.existing_lengths[key]=(report.existing_lengths[key] or 0)+1
   if #report.examples<8 then report.examples[#report.examples+1]={slot=i,actions=values} end
  end
  if i%16==0 then checkpoint("inspect existing action lengths "..i);coroutine.yield() end
 end
 local function fresh()
  local set=assert(sdk.create_instance("snow.equip.PlEquipMySetData",true)):add_ref()
  native:call("snow.equip.PlEquipMySetData",".ctor()",set)
  return set
 end
 report.zero_enum={}
 local td=assert(sdk.find_type_definition("snow.data.DataDef.PlWeaponActionId"))
 for _,field in ipairs(td:get_fields()) do
  if field:is_static() and N.scalar(field:get_data(nil))==0 then report.zero_enum[#report.zero_enum+1]=field:get_name() end
 end
 report.copy_cases={}
 for _,values in ipairs({{}, {50}, {50,54}, {49,51,54}}) do
  checkpoint("detached action array copy length "..#values)
  local source,dest=fresh(),fresh()
  report.constructor_actions=N.array(f(source,"_ActionIdList"))
  -- 原生 copy 按三项读取；短输入先按 ActionId_None 规范化，不再交付短数组。
  local array=assert(sdk.create_managed_array("snow.data.DataDef.PlWeaponActionId",3)):add_ref()
  for i=1,3 do native:call("snow.data.DataDef.PlWeaponActionId[]","Set",array,i-1,values[i] or 0) end
  source:set_field("_ActionIdList",array)
  native:call("snow.equip.PlEquipMySetData","copy(snow.equip.PlEquipMySetData)",dest,source)
  local copied=N.array(f(dest,"_ActionIdList"))
  report.copy_cases[#report.copy_cases+1]={source=values,copied=copied}
  assert(#copied==3)
  for i=1,3 do assert(copied[i]==(values[i] or 0)) end
  coroutine.yield()
 end
 report.game_method_calls=native.game_method_calls
 checkpoint("native variable action array copy passed; no inventory writes")
end
return M
