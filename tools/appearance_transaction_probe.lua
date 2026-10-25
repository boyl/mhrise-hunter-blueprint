-- 独立的开发事务入口。真实写入要求明确模式及已验证备份，不加入只读验证包。
local M={}
local function next_frame()
 if coroutine.isyieldable() then coroutine.yield({phase="appearance_contract"}) end
end
function M.run(request,report,checkpoint)
 if request.mode=="local_identity_audit" then
  report.types={};report.writes=0
  local guild=sdk.get_managed_singleton("snow.GuildCardManager")
  if guild then
   local card=guild:get_field("_GuildCard"):get_field("MyData")
   local guid=card:get_field("GuildCardID");local parts={}
   for _,key in ipairs({"mData1","mData2","mData3","mData4_0","mData4_1","mData4_2","mData4_3","mData4_4","mData4_5","mData4_6","mData4_7"}) do parts[#parts+1]=tostring(guid:get_field(key)) end
   report.card_guid=table.concat(parts,"-");report.card_name=card:get_field("HunterName")
  end
  local system=sdk.get_managed_singleton("snow.data.SystemDataManager")
  if system then
   local guid=system:get_field("<CharaConsistencyId>k__BackingField")
   report.consistency_fields={}
   if guid then
    for _,f in ipairs(guid:get_type_definition():get_fields()) do
     if not f:is_static() then
      report.consistency_fields[#report.consistency_fields+1]={name=f:get_name(),type=f:get_type():get_full_name(),value=guid:get_field(f:get_name())}
     end
    end
   end
  end
  local save=assert(sdk.get_managed_singleton("snow.SnowSaveService"))
  local classes=assert(save:get_field("_CharaSaveClassList"))
  local count=classes:call("get_Count")
  assert(count>=0 and count<=128)
  report.save_classes={}
  for i=0,count-1 do
   local obj=classes:call("get_Item",i)
   local td=obj:get_type_definition();local fields={}
   for _,f in ipairs(td:get_fields()) do
    local key=f:get_name():lower()
    if key:find("save") or key:find("unique") or key:find("hunter") or key:find("guid") or key:find("player") then
     fields[#fields+1]={name=f:get_name(),type=f:get_type():get_full_name()}
    end
   end
   report.save_classes[#report.save_classes+1]={name=td:get_full_name(),fields=fields}
  end
  for _,name in ipairs({"snow.GuildCardManager.GuildCardSaveData","snow.data.GuildCardData","snow.network.SaveData","snow.data.SystemDataManager"}) do
   local td=sdk.find_type_definition(name)
   local row={name=name,found=td~=nil,fields={}}
   if td then
    for _,f in ipairs(td:get_fields()) do
     row.fields[#row.fields+1]={name=f:get_name(),type=f:get_type():get_full_name()}
    end
   end
   report.types[#report.types+1]=row
  end
  local lobby=sdk.get_managed_singleton("snow.LobbyManager")
  local mine=lobby and lobby:get_field("_myHunterInfo")
  if mine then
   report.local_name=mine:get_field("_name")
   local guid=mine:get_field("_HunterUniqueId");local values={}
   for _,key in ipairs({"mData1","mData2","mData3","mData4_0","mData4_1","mData4_2","mData4_3","mData4_4","mData4_5","mData4_6","mData4_7"}) do values[#values+1]=tostring(guid:get_field(key)) end
   report.local_guid=table.concat(values,"-")
  end
  return
 end
 assert(request.mode=="transaction_prepare" or request.mode=="transaction_rollback" or request.mode=="transaction_commit" or request.mode=="hook_install" or request.mode=="hook_state" or request.mode=="read_saved" or request.mode=="visibility_roundtrip" or request.mode=="bind_existing_visibility" or request.mode=="option_matrix","transaction mode required")
 -- 协程永远不得安装回调。原生外观对照必须与显示状态写入隔离。
 if request.mode~="read_saved" and request.mode~="hook_state" and request.mode~="visibility_roundtrip" and request.mode~="bind_existing_visibility" and request.mode~="option_matrix" then
  error("外观实验已隔离：武器模型和随从幻化副作用待定位，禁止新增写入")
 end
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
 if request.mode=="option_matrix" then
  local binding=isolated("LoadoutClone.appearance_binding").new(reader)
  local service=isolated("LoadoutClone.appearance_service").new(reader,isolated("LoadoutClone.appearance_adapter").new(binding))
  report.cases={};report.writes=0;report.restores=0
  assert(request.phase=="prepare" or request.phase=="rollback")
  if request.phase=="rollback" then assert(json.load_file("LoadoutClone/development-backup.json").backup_verified) end
  for _,aug in ipairs(request.appearance_only and {{false,false}} or {{false,false},{true,false},{true,true}}) do
   for _,visual in ipairs(request.appearance_only and {{true,false},{true,true}} or {{false,false},{true,false},{true,true}}) do
    local options={appearance_only=request.appearance_only==true,copy_augments=aug[1],allow_illegal_augments=aug[2],copy_appearance=visual[1],copy_weapon_visibility=visual[2]}
    checkpoint("option matrix "..(#report.cases+1).." "..request.phase)
    local planner=isolated("LoadoutClone.planner").new(reader,service)
    local writer=isolated("LoadoutClone.writer").new(reader,service)
    local source=planner:prepare(assert(request.key),options)
    if request.phase=="prepare" then
     local plan=writer:prepare(source);writer:assert_context(plan)
     assert(writer.write_count==0)
    else
     writer.fault_on_verify=true
     local result=writer:execute(source)
     assert(not result.ok and tostring(result.error):find("development verification failure",1,true),"unexpected matrix outcome: "..tostring(result.error))
     assert(writer.write_count>0 and writer.write_count==writer.restore_count,"matrix rollback incomplete")
    end
    report.cases[#report.cases+1]={options=options,writes=writer.write_count,restores=writer.restore_count or 0}
    report.writes=report.writes+writer.write_count;report.restores=report.restores+(writer.restore_count or 0)
    next_frame()
   end
  end
  return
 end
 if request.mode=="bind_existing_visibility" then
  local state=assert(_G.HunterBlueprintAppearanceHookState)
  assert(state.version==2 and state.observe_only and state.calls>0 and state.errors==0)
  assert(type(request.hidden)=="boolean" and type(request.expected_fingerprint)=="table")
  local binding=isolated("LoadoutClone.appearance_binding").new(reader)
  local manager=assert(sdk.get_managed_singleton("snow.data.EquipDataManager"))
  local n,get=N.array_access(N.field(manager,"_HunterMySetList"),1024)
  assert(type(request.hunter_slot)=="number" and request.hunter_slot%1==0 and request.hunter_slot>=0 and request.hunter_slot<n)
  local hunter=get(request.hunter_slot)
  report.hunter=isolated("LoadoutClone.hunter").state(hunter)
  report.recent_hunters={}
  for i=math.max(0,n-24),n-1 do
   local value=isolated("LoadoutClone.hunter").state(get(i))
   if value._IsUsing then report.recent_hunters[#report.recent_hunters+1]={slot=i,data=value} end
  end
  assert(binding:character()==request.character,"角色已变化")
  assert(A.same(binding:fingerprint(manager,hunter),request.expected_fingerprint),"组合已变化")
  local before=N.scalar(N.field(manager,"_VisiblePartsFlag"))
  local entry=binding:prepare({manager=manager,hunter_slot=request.hunter_slot,source={appearance={snapshot={weapon_hidden=request.hidden}}}})
  local ok,err=pcall(function()binding:apply(entry);binding:verify(entry)end)
  if not ok then binding:restore(entry);binding:verify_restored(entry);error(err) end
  assert(N.scalar(N.field(manager,"_VisiblePartsFlag"))==before,"登记时改变了当前显示状态")
  state.pending=nil;state.observe_only=false
  report.bound_hidden=binding:selection(manager,hunter);report.before_flags=before
  report.inventory_writes=0;report.sidecar_writes=1;report.hook_enabled=true;return
 end
 if request.mode=="visibility_roundtrip" then
  local observed=assert(_G.HunterBlueprintAppearanceHookState)
  assert(observed.version==2 and observed.observe_only and observed.errors==0 and observed.calls>0,"只读回调对照未通过")
  local binding=isolated("LoadoutClone.appearance_binding").new(reader)
  local manager=assert(sdk.get_managed_singleton("snow.data.EquipDataManager"))
  local before=N.scalar(N.field(manager,"_VisiblePartsFlag"))
  local hidden=(before&1)==0
  report.before=before;report.character=binding:character();report.writes=0
  checkpoint("single visibility setter and immediate restoration")
  local ok,err=pcall(function()
   binding:apply_hidden(manager,not hidden)
   report.toggled=N.scalar(N.field(manager,"_VisiblePartsFlag"));report.writes=1
  end)
  local restored,restore_err=pcall(function()
   binding:apply_hidden(manager,hidden)
   report.after=N.scalar(N.field(manager,"_VisiblePartsFlag"))
   assert(report.after==before,"完整显示位未恢复")
  end)
  report.restored=restored;report.restore_error=restore_err;report.restores=restored and 1 or 0
  assert(restored,restore_err);assert(ok,err)
  report.inventory_writes=0;return
 end
 if request.mode=="hook_install" then
  local binding=isolated("LoadoutClone.appearance_binding").new(reader)
  local state=isolated("LoadoutClone.appearance_hooks").install(binding,request.observe_only~=false)
  report.hook={calls=state.calls,applied=state.applied,errors=state.errors,observe_only=state.observe_only}
  report.writes=0;return
 end
 if request.mode=="hook_state" then
  local state=assert(_G.HunterBlueprintAppearanceHookState,"hooks not installed")
  report.hook={calls=state.calls,applied=state.applied,errors=state.errors,last_hidden=state.last_hidden,last_error=state.last_error,observe_only=state.observe_only}
  report.writes=0;return
 end
 if request.mode=="read_saved" then
  local binding=isolated("LoadoutClone.appearance_binding").new(reader)
  if request.refresh_identity and _G.HunterBlueprintAppearanceHookState then
   _G.HunterBlueprintAppearanceHookState.binding.character=binding.character
  end
  local manager=assert(sdk.get_managed_singleton("snow.data.EquipDataManager"))
  local n,get=N.array_access(N.field(manager,"_HunterMySetList"),1024)
  assert(type(request.hunter_slot)=="number" and request.hunter_slot%1==0 and request.hunter_slot>=0 and request.hunter_slot<n)
  local hunter=get(request.hunter_slot)
  report.hunter=isolated("LoadoutClone.hunter").state(hunter)
  report.recent_hunters={}
  for i=math.max(0,n-24),n-1 do
   local value=isolated("LoadoutClone.hunter").state(get(i))
   if value._IsUsing then report.recent_hunters[#report.recent_hunters+1]={slot=i,data=value} end
  end
  report.hunter_registered=N.field(hunter,"_IsUsing")
  report.experimental_hooks_loaded=_G.HunterBlueprintAppearanceHookState~=nil
  report.character=binding:character()
  if not report.hunter_registered then report.writes=0;return end
  if report.hunter._OverwearMysetIndex<0 then report.writes=0;report.has_appearance=false;return end
  report.fingerprint=binding:fingerprint(manager,hunter)
  report.character=binding:character()
  report.stored_hidden=binding:selection(manager,hunter)
  report.current_flags=N.scalar(N.field(manager,"_VisiblePartsFlag"))
  local lobby=assert(sdk.get_managed_singleton("snow.LobbyManager"))
  if reader:list_members().session then report.current_appearance=R.capture(N.field(lobby,"_myselfIndex"),native) end
  report.current_native_appearance=binding.objects:state(N.field(manager,"_PlOverwearMySetData"))
  report.current_equipment=N.array(N.field(N.field(manager,"_PlEquipPack"),"_InventoryIndexList"))
  if request.audit_appearance then
   report.appearance_audit={types={}}
   for _,name in ipairs({"snow.data.HunterMySetData","snow.equip.PlOverwearMySetData","snow.data.OtomoData","snow.data.OtomoDataManager"}) do
    local td=sdk.find_type_definition(name)
    local fields={}
    if td then
    for _,f in ipairs(td:get_fields()) do
     fields[#fields+1]={name=f:get_name(),type=f:get_type():get_full_name()}
    end
    end
    report.appearance_audit.types[#report.appearance_audit.types+1]={name=name,fields=fields}
   end
   report.appearance_audit.active_set=binding.objects:state(N.field(manager,"_PlOverwearMySetData"))
   local id=report.current_appearance.weapon_id
   report.appearance_audit.weapon_name=native:call("snow.equip.EquipShortcut","getName(snow.data.ContentsIdSystem.OverwearWeaponId)",nil,id)
   report.appearance_audit.weapon_model=N.scalar(native:call("snow.equip.EquipShortcut","getModelId(snow.data.ContentsIdSystem.OverwearWeaponId)",nil,id))
   report.appearance_audit.weapon_owned=native:call("snow.equip.EquipShortcut","hasOverwearWeapon",nil,id)
   local function scalar_fields(obj)
    local out={}
    if not obj then return out end
    for _,f in ipairs(obj:get_type_definition():get_fields()) do
     if not f:is_static() then
      local t=f:get_type();local name=t:get_full_name()
      local row={name=f:get_name(),type=name}
      if t:is_enum() or name=="System.Int32" or name=="System.UInt32" or name=="System.Boolean" or name=="System.String" then
       row.value=N.scalar(f:get_data(obj))
      end
      out[#out+1]=row
     end
    end
    return out
   end
   local data=assert(sdk.get_managed_singleton("snow.data.DataManager"))
   local count,get_buddy=N.array_access(N.field(data,"<AttendantOtomoDataList>k__BackingField"),4)
   report.appearance_audit.buddies={}
   for i=0,count-1 do
    local buddy=get_buddy(i)
    if buddy then
     local info=N.field(buddy,"<EquipInfo>k__BackingField")
     local parts,overwear=N.array_access(N.field(info,"<OverwearArmorDataInventory>k__BackingField"),4)
     local layered={}
     for part=0,parts-1 do layered[#layered+1]={part=part,fields=scalar_fields(overwear(part))} end
     report.appearance_audit.buddies[#report.appearance_audit.buddies+1]={slot=i,
      layered=layered,
      equipment_indices=N.array(N.field(buddy,"<EquipIndex>k__BackingField")),
      equipment=scalar_fields(N.field(buddy,"<EquipInfo>k__BackingField")),
      appearance=scalar_fields(N.field(buddy,"_AppearanceInfo")),
      identity=scalar_fields(N.field(buddy,"_BaseParamInfo"))}
    end
   end
  end
  report.writes=0;return
 end
 if request.mode=="transaction_prepare" or request.mode=="transaction_rollback" or request.mode=="transaction_commit" then
  local binding=request.with_visibility and isolated("LoadoutClone.appearance_binding").new(reader) or nil
  local service=isolated("LoadoutClone.appearance_service").new(reader,isolated("LoadoutClone.appearance_adapter").new(binding))
  local planner=isolated("LoadoutClone.planner").new(reader,service)
  local writer=isolated("LoadoutClone.writer").new(reader,service)
  checkpoint("prepare complete equipment and appearance candidates")
  local source=planner:prepare(assert(request.key),{copy_augments=true,allow_illegal_augments=true,copy_appearance=true})
  report.appearance_source=source.appearance.snapshot
  if request.mode=="transaction_prepare" then
   local plan=writer:prepare(source)
   writer:assert_context(plan)
   report.entries={}
   for _,entry in ipairs(plan.entries) do report.entries[#report.entries+1]={kind=entry.kind,slot=entry.slot,with_color=entry.with_color} end
   report.slot=plan.slot;report.hunter_slot=plan.hunter_slot;report.overwear_slot=plan.overwear_slot
   report.inventory_writes=writer.write_count;report.writes=writer.write_count
   assert(writer.write_count==0)
  else
   local backup=json.load_file("LoadoutClone/development-backup.json")
   assert(backup and backup.backup_verified,"verified backup required")
   writer.fault_on_verify=request.mode=="transaction_rollback"
   checkpoint(writer.fault_on_verify and "appearance fault injection and rollback" or "commit complete appearance blueprint")
   local result=writer:execute(source)
   report.result=result;report.writes=writer.write_count;report.restores=writer.restore_count
   if writer.fault_on_verify then
    assert(not result.ok and result.code=="failed" and tostring(result.error):find("development verification failure",1,true),"unexpected rollback outcome")
    assert(writer.write_count>0 and writer.write_count==writer.restore_count,"incomplete appearance rollback")
   else assert(result.ok,"appearance commit failed") end
  end
  report.ready_for_inventory=false
  checkpoint("appearance transaction validation complete")
  return
 end
end
return M
