-- 实机就位后显式调用。只读游戏状态或修改新建的临时对象，不注册组合。
local M={}
local function next_frame()
 if coroutine.isyieldable() then coroutine.yield({phase="appearance_contract"}) end
end
function M.run(request,report,checkpoint)
 assert(request.mode=="members" or request.mode=="read" or request.mode=="detached_colors" or request.mode=="detached_set" or request.mode=="detached_fixture" or request.mode=="visibility_metadata","外观验证模式必须明确指定")
 local folder=assert(debug.getinfo(1,"S").source:sub(2):match("^(.*[/\\])"))
 -- 使用同目录验证副本，避免污染正式模块缓存。
 local loaded={}
 local function isolated(name)
  local short=assert(name:match("^LoadoutClone%.([a-z_]+)$"),"unexpected module")
  if loaded[name] then return loaded[name] end
  local env=setmetatable({require=isolated},{__index=_G})
  loaded[name]=assert(loadfile(folder..short..".lua","t",env))()
  return loaded[name]
 end
 local N=isolated("LoadoutClone.native")
 local A=isolated("LoadoutClone.appearance")
 local C=isolated("LoadoutClone.appearance_color")
 local R=isolated("LoadoutClone.appearance_reader")
 local reader=isolated("LoadoutClone.reader").new()
 local native=N.new()
 if request.mode=="visibility_metadata" then
  report.types={}
  for _,name in ipairs({"snow.data.EquipDataManager.VisiblePartsFlag","snow.SaveServiceUtility","snow.SnowSaveService","snow.player.PlayerData"}) do
   checkpoint("visibility metadata "..name)
   local td=sdk.find_type_definition(name)
   local row={name=name,found=td~=nil,fields={},methods={}}
   if td then
    for _,f in ipairs(td:get_fields()) do
     assert(#row.fields<512,"metadata field bound")
     local item={name=f:get_name(),type=f:get_type():get_full_name(),static=f:is_static()}
     if td:is_enum() and f:is_static() then item.value=N.scalar(f:get_data(nil)) end
     row.fields[#row.fields+1]=item
    end
    for _,m in ipairs(td:get_methods()) do
     local lower=m:get_name():lower()
     if lower:find("save",1,true) or lower:find("slot",1,true) or lower:find("unique",1,true) then
      local params={};for _,p in ipairs(m:get_param_types()) do params[#params+1]=p:get_full_name() end
      row.methods[#row.methods+1]={name=m:get_name(),parameters=params,returns=m:get_return_type():get_full_name()}
     end
    end
   end
   report.types[#report.types+1]=row
  end
  if request.live_context then
   local save=assert(sdk.get_managed_singleton("snow.SnowSaveService"))
   local slot=N.field(save,"_CurrentHunterSlotNo")
   assert(slot==N.scalar(native:call("snow.SnowSaveService","getSlotNo",save)),"save slot getter mismatch")
   local manager=assert(sdk.get_managed_singleton("snow.data.EquipDataManager"))
   local flags=N.scalar(N.field(manager,"_VisiblePartsFlag"))
   local lobby=assert(sdk.get_managed_singleton("snow.LobbyManager"))
   local mine=R.capture(N.field(lobby,"_myselfIndex"),native)
   report.context={slot=slot,identity=reader:list_members().session,flags=flags,weapon_hidden=mine.weapon_hidden,is_mr=reader:progression_state()}
   assert(((flags & 1)==0)==mine.weapon_hidden,"weapon visibility semantics mismatch")
  end
  report.inventory_writes=0;report.writes=0;report.ready_for_inventory=false;return
 end
 if request.mode=="detached_fixture" then
  checkpoint("detached fixture: no live source or inventory writes")
  local objects=isolated("LoadoutClone.appearance_objects").new(native)
  local candidate=objects:build(assert(request.snapshot),"外观样本验证")
  local expected=objects:state(candidate)
  local copied=objects:clone(candidate)
  native:call("snow.equip.PlOverwearMySetData","clear",candidate)
  assert(A.same(objects:state(copied),expected),"fixture clone independence mismatch")
  local weapon=objects:fresh("snow.data.EquipmentInventoryData")
  C.write(N.field(weapon,"_HyakuryuColorData"),{enabled=true,default=false,hsv={270,55,88}})
  local weapon_copy=objects:fresh("snow.data.EquipmentInventoryData")
  native:call("snow.data.EquipmentInventoryData","copy",weapon_copy,weapon)
  objects:detach_weapon_color(weapon_copy)
  C.write(N.field(weapon,"_HyakuryuColorData"),{enabled=false,default=true,hsv={0,0,0}})
  assert(A.same(C.read(N.field(weapon_copy,"_HyakuryuColorData")),{enabled=true,default=false,hsv={270,55,88}}),"fixture weapon independence mismatch")
  report.fixture=true;report.object_adapter_verified=true;report.state=expected
  report.writes=0;report.inventory_writes=0;report.ready_for_inventory=false
  checkpoint("detached fixture verified; not a live player copy")
  return
 end
 local list=reader:list_members();local target
 if request.mode=="members" then
  report.members=list.members;report.lobby_session=list.session
  report.writes=0;report.inventory_writes=0;report.ready_for_inventory=false
  checkpoint("current lobby members; no inventory writes")
  return
 end
 for _,m in ipairs(list.members) do if m.key==request.key then target=m end end
 assert(target,"目标猎人不在当前大厅")
 checkpoint("capture bounded appearance snapshot")
 local snapshot=R.capture(target.index,native)
 report.snapshot=snapshot;report.id_checks={};report.color_checks={};report.inventory_writes=0
 for part,id in ipairs(snapshot.armor_ids) do
  checkpoint("native armor ID "..part)
  local empty=id==(part-1)*4096
  local row={part=part,id=id,empty=empty}
  if not empty then
   row.valid=native:call("snow.equip.EquipShortcut","isValid(snow.equip.PlOverwearId)",nil,id)
   if row.valid then row.native_part=N.scalar(native:call("snow.equip.EquipShortcut","getArmorPartsType(snow.equip.PlOverwearId)",nil,id)) end
  end
  report.id_checks[#report.id_checks+1]=row
  next_frame()
 end
 if snapshot.weapon_id~=134217728 then
  checkpoint("native weapon appearance ID")
  report.weapon_valid=native:call("snow.equip.EquipShortcut","isValid(snow.data.ContentsIdSystem.OverwearWeaponId)",nil,snapshot.weapon_id)
 end
 local function int3(values)
  local out=ValueType.new(assert(sdk.find_type_definition("via.Int3")))
  for i,key in ipairs({"x","y","z"}) do out:set_field(key,values[i]) end
  return out
 end
 local function forward(color,label)
  if not color.enabled then return end
  checkpoint("native material forward "..label)
  local actual=native:call("snow.gui.SnowGuiCommonUtility","HSV2ColorToMaterial(via.Int3)",nil,int3(color.hsv))
  local expected=A.hsv_to_material(color.hsv)
  local error=0
  for _,k in ipairs({"x","y","z"}) do error=math.max(error,math.abs(actual[k]-expected[k])) end
  assert(error<=1e-5,"原生材质颜色与离线公式不一致")
  report.color_checks[#report.color_checks+1]={label=label,max_error=error}
  next_frame()
 end
 for channel=1,2 do for part=1,5 do forward(snapshot.colors[channel][part],channel..":"..part) end end
 forward(snapshot.weapon_color,"weapon")
 if request.mode=="detached_colors" then
  local function fresh(name)
   checkpoint("detached ctor "..name)
   local obj=assert(sdk.create_instance(name,true)):add_ref()
   native:call(name,".ctor()",obj);return obj
  end
  report.flag_cases={}
  for _,enabled in ipairs({false,true}) do for _,default in ipairs({false,true}) do
   local set=fresh("snow.equip.PlOverwearMySetData")
   local base=fresh("snow.player.PlayerManager.PlayerCreateBaseData")
   local count,parts=N.array_access(N.field(N.field(set,"_OverwearSymbolColor"),"_Parts"),5)
   assert(count==5,"detached color parts")
   local part=assert(parts(0)):add_ref()
   local colors=N.field(part,"_ColorData"):add_ref()
   local n,get=N.array_access(colors,2);assert(n==2,"detached color channels")
   for channel=0,1 do
    checkpoint("detached color channel "..channel)
    local color=assert(get(channel)):add_ref()
    color:set_field("_IsEnable",enabled);color:set_field("_IsDefault",default)
    -- 此运行时通用 ValueType set_field 按 boxed size 复制（28 而非 12 字节）。
    -- 只在临时对象内，按反射验证的三个 Int32 边界写入。
    local t=color:get_type_definition()
    local f=assert(t:get_field("_Color"));local vt=f:get_type()
    assert(vt:get_full_name()=="via.Int3" and vt:get_valuetype_size()==12,"unexpected color layout")
    local offset=f:get_offset_from_base()
    assert(offset>=16 and offset+12<=color:get_object_size(),"color field outside owner")
    local header=vt:get_size()-vt:get_valuetype_size()
    local values=channel==0 and {30,90,47} or {120,100,50}
    for i,key in ipairs({"x","y","z"}) do
     local component=assert(vt:get_field(key)):get_offset_from_base()-header
     assert(component==(i-1)*4,"unexpected Int3 component offset")
     color:write_dword(offset+component,values[i])
     assert(color:read_dword(offset+component)==values[i],"color component readback")
    end
   end
   checkpoint("applyColorSub to detached base")
   local apply
   for _,method in ipairs(sdk.find_type_definition("snow.equip.PlArmorColorMySetData"):get_methods()) do
    if method:get_name()=="applyColorSub" then
     assert(not apply,"ambiguous applyColorSub")
     local p=method:get_param_types()
     assert(#p==3 and p[1]:get_full_name()=="snow.equip.PlArmorPartsTypes"
      and p[2]:get_full_name()=="snow.player.PlayerManager.PlayerCreateBaseData"
      and p[3]:get_full_name()=="snow.data.SymbolColorData[]","unexpected applyColorSub signature")
     apply=method
    end
   end
   assert(apply):call(nil,0,base,colors)
   local row={enabled=enabled,default=default,channels={}}
   for channel=1,2 do
    local _,flags=N.array_access(N.field(base,"_IsEnableSymbolColor"..channel),5)
    local _,rgb=N.array_access(N.field(base,"_SymbolColor"..channel),5)
    local value=rgb(0)
    row.channels[channel]={enabled=N.scalar(flags(0)),rgb={value.x,value.y,value.z}}
    assert(row.channels[channel].enabled==enabled,"native color enable mismatch")
    local expected=A.hsv_to_material(channel==1 and {30,90,47} or {120,100,50})
    for _,key in ipairs({"x","y","z"}) do
     assert(math.abs(value[key]-expected[key])<=1e-5,"native color material mismatch")
    end
   end
   report.flag_cases[#report.flag_cases+1]=row
   next_frame()
  end end
 end
 if request.mode=="detached_set" then
  local set_type="snow.equip.PlOverwearMySetData"
  local function fresh(t)
   local obj=assert(sdk.create_instance(t,true)):add_ref()
   native:call(t,".ctor()",obj);return obj
  end
  local function put_color(color,source)
   color:add_ref()
   C.write(color,C.from_snapshot(source))
  end
  local function color_state(color)
   return C.read(color)
  end
  local function state(set)
   local out={used=N.field(set,"_IsUsing"),name=N.field(set,"_Name"),weapon=N.scalar(N.field(set,"_OverwearWeaponId")),armor=N.array(N.field(set,"_PlOverwearIdList")),colors={}}
   local n,parts=N.array_access(N.field(N.field(set,"_OverwearSymbolColor"),"_Parts"),5);assert(n==5)
   for part=0,4 do
    local count,get=N.array_access(N.field(parts(part),"_ColorData"),2);assert(count==2)
    out.colors[part+1]={color_state(get(0)),color_state(get(1))}
   end
   return out
  end
  checkpoint("construct detached full appearance set")
  local candidate=fresh(set_type)
  native:call(set_type,"setName",candidate,"外观临时验证")
  native:call(set_type,"set_IsUsing",candidate,true)
  native:call(set_type,"setWeaponOverwearId",candidate,snapshot.weapon_id)
  for _,id in ipairs(snapshot.armor_ids) do native:call(set_type,"setPlOverwearId",candidate,id) end
  local _,parts=N.array_access(N.field(N.field(candidate,"_OverwearSymbolColor"),"_Parts"),5)
  for part=0,4 do
   local _,get=N.array_access(N.field(parts(part),"_ColorData"),2)
   for channel=0,1 do put_color(get(channel),snapshot.colors[channel+1][part+1]) end
  end
  local expected=state(candidate)
  assert(expected.weapon==snapshot.weapon_id and A.same(expected.armor,snapshot.armor_ids),"appearance IDs mismatch")
  for part=1,5 do for channel=1,2 do
   local got=expected.colors[part][channel];local wanted=snapshot.colors[channel][part]
   assert(got.enabled==wanted.enabled and got.default==not wanted.enabled,"appearance flags mismatch")
   if wanted.enabled then assert(A.same(got.hsv,wanted.hsv),"appearance HSV mismatch") end
  end end
  next_frame();collectgarbage("collect")
  checkpoint("native copy detached appearance set")
  local copied=fresh(set_type);native:call(set_type,"copy",copied,candidate)
  -- 组合 copy 不复制染色；逐通道复制经过验证的纯数据。
  local _,copy_parts=N.array_access(N.field(N.field(copied,"_OverwearSymbolColor"),"_Parts"),5)
  for part=0,4 do
   local _,get=N.array_access(N.field(copy_parts(part),"_ColorData"),2)
   for channel=0,1 do
    local value=expected.colors[part+1][channel+1]
    put_color(get(channel),value)
    get(channel):set_field("_IsDefault",value.default)
   end
  end
  report.copy_expected=expected;report.copy_actual=state(copied)
  assert(A.same(state(copied),expected),"native appearance copy mismatch")
  native:call(set_type,"clear",candidate)
  assert(A.same(state(copied),expected),"appearance copy aliases original")
  report.detached_set={state=expected,copy_verified=true,independent=true}
  checkpoint("native copy detached weapon color")
  local weapon=fresh("snow.data.EquipmentInventoryData")
  put_color(N.field(weapon,"_HyakuryuColorData"),snapshot.weapon_color)
  local weapon_copy=fresh("snow.data.EquipmentInventoryData")
  native:call("snow.data.EquipmentInventoryData","copy",weapon_copy,weapon)
  assert(A.same(color_state(N.field(weapon,"_HyakuryuColorData")),color_state(N.field(weapon_copy,"_HyakuryuColorData"))),"weapon color copy mismatch")
  report.weapon_color_copy=color_state(N.field(weapon_copy,"_HyakuryuColorData"))
  put_color(N.field(weapon,"_HyakuryuColorData"),{enabled=true,hsv={270,55,88}})
  native:call("snow.data.EquipmentInventoryData","copy",weapon_copy,weapon)
  local custom=color_state(N.field(weapon_copy,"_HyakuryuColorData"))
  assert(custom.enabled and not custom.default and A.same(custom.hsv,{270,55,88}),"custom weapon color copy mismatch")
  local independent=fresh("snow.data.SymbolColorData")
  C.write(independent,custom)
  native:call("snow.data.EquipmentInventoryData","set_HyakuryuColorData",weapon_copy,independent)
  put_color(N.field(weapon,"_HyakuryuColorData"),{enabled=false})
  assert(A.same(color_state(N.field(weapon_copy,"_HyakuryuColorData")),custom),"weapon color copy aliases original")
  report.synthetic_weapon_color={state=custom,independent=true}
  checkpoint("reusable appearance object adapter")
  local objects=isolated("LoadoutClone.appearance_objects").new(native)
  local built=objects:build(snapshot,"外观临时验证")
  assert(A.same(objects:state(built),expected),"reusable builder mismatch")
  local clone=objects:clone(built)
  native:call(set_type,"clear",built)
  assert(A.same(objects:state(clone),expected),"reusable clone independence mismatch")
  objects:detach_weapon_color(weapon_copy)
  assert(A.same(C.read(N.field(weapon_copy,"_HyakuryuColorData")),custom),"reusable weapon color mismatch")
  report.object_adapter_verified=true
 end
 checkpoint("recheck target identity and appearance")
 local after=reader:list_members();assert(after.session==list.session,"会话已变化")
 local found=false
 for _,m in ipairs(after.members) do if m.key==target.key and m.index==target.index then found=true end end
 assert(found,"猎人身份或位置已变化")
 assert(A.same(snapshot,R.capture(target.index,native)),"验证期间目标外观已变化")
 report.game_method_calls=native.game_method_calls
 report.writes=0;report.ready_for_inventory=false -- 此检查不能授予真实写入资格。
 checkpoint("appearance contract complete; no inventory writes")
end
return M
