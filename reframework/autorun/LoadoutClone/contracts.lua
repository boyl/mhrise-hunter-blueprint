-- debug 库在部分运行环境不可用；错误处理自身不能阻断绘制或回滚。
local native_traceback=type(debug)=="table" and type(debug.traceback)=="function" and debug.traceback
local function traceback(value,message)
    if native_traceback then
        if type(value)=="thread" then return native_traceback(value,message) end
        return native_traceback(value)
    end
    return tostring(type(value)=="thread" and message or value)
end
-- 开发用：只调用已核实签名的原生读取器，独立统计调用次数。
local M={}
local function field(obj,key)
    assert(obj,"missing owner: "..key)
    local v=obj:get_field(key);assert(v~=nil,"missing field: "..key);return v
end
local function scalar(v)
    if type(v)~="userdata" then return v end
    local t=v:get_type_definition()
    local f=t:get_field("value__") or t:get_field("mValue")
    assert(f,"unknown scalar: "..t:get_full_name());return f:get_data(v)
end
local function array(v)
    local n=v:get_size();assert(n<=512,"array too large")
    local out={};for i=0,n-1 do out[i+1]=scalar(v:get_element(i)) end;return out
end
function M.run(request,report)
    local function call(type_name,signature,owner,...)
        assert(report.game_method_calls<64,"native call budget")
        local t=assert(sdk.find_type_definition(type_name),type_name)
        local m=assert(t:get_method(signature),signature)
        report.game_method_calls=report.game_method_calls+1
        return m:call(owner,...)
    end
    if request.action=="reload_view" then
        local previous=package.loaded["LoadoutClone.view"]
        if not previous then return {reloaded=false,reason="view module is in another script state"} end
        package.loaded["LoadoutClone.view"]=nil
        local current=require("LoadoutClone.view")
        for k,v in pairs(current) do previous[k]=v end
        package.loaded["LoadoutClone.view"]=previous
        local old_controller=package.loaded["LoadoutClone.controller"]
        if old_controller then
            package.loaded["LoadoutClone.controller"]=nil
            local updated=require("LoadoutClone.controller")
            for k,v in pairs(updated) do old_controller[k]=v end
            old_controller.copy_appearance=false
            old_controller.copy_weapon_visibility=false
            package.loaded["LoadoutClone.controller"]=old_controller
        end
        return {reloaded=true}
    elseif request.action=="ui_capabilities" then
        local out={}
        for _,key in ipairs({"radio_button","push_id","pop_id","checkbox","button","begin_window","end_window","text_colored","spacing","new_line","begin_group","end_group","calc_text_size","get_window_size","push_style_color","pop_style_color","begin_rect","end_rect"}) do out[key]=type(imgui[key]) end
        return out
    elseif request.action=="weapon_id_names" then
        local enum=assert(sdk.find_type_definition("snow.data.ContentsIdSystem.WeaponId"))
        local fields=enum:get_fields();assert(#fields<=16000,"weapon enum bound")
        local out={}
        for i,f in ipairs(fields) do
            local n=f:get_name()
            if i<=12 or n:lower():find("gunlance",1,true) or n:lower():find("insect",1,true) then
                if f:is_static() and f:is_literal() then out[#out+1]={name=n,id=f:get_data(nil)} end
            end
        end
        return {weapons=out,total=#fields}
    elseif request.action=="hunter_layout" then
        local manager=assert(sdk.get_managed_singleton("snow.data.EquipDataManager"))
        local hunters=field(manager,"_HunterMySetList");assert(hunters:get_size()<=1024)
        local out={count=hunters:get_size(),used={},empty=0}
        local function state(obj)
            local result={}
            for _,k in ipairs({"_IsUsing","_ItemMysetIndex","_EquipMysetIndex","_OverwearMysetIndex"}) do result[k]=field(obj,k) end
            result._Name=obj:get_field("_Name") or "";return result
        end
        for i=0,hunters:get_size()-1 do
            local obj=hunters:get_element(i)
            if field(obj,"_IsUsing") then if #out.used<5 then out.used[#out.used+1]=state(obj) end
            else out.empty=out.empty+1;out.last_empty=i end
        end
        local staged=assert(sdk.create_instance("snow.data.HunterMySetData",true)):add_ref()
        call("snow.data.HunterMySetData",".ctor()",staged)
        out.defaults=state(staged)
        local equip=field(manager,"_PlEquipMySetList"):get_element(215)
        out.equipment216={used=field(equip,"_IsUsing"),name=equip:get_field("_Name"),indices=array(field(equip,"_InventoryIndexList")),red=array(field(equip,"_ActionIdListMR_Red")),blue=array(field(equip,"_ActionIdListMR_Blue"))}
        call("snow.data.HunterMySetData","setupParam",staged,-1,215,-1)
        out.staged=state(staged)
        out.item_absent=call("snow.data.HunterMySetData","get_ItemMysetData()",staged)==nil
        out.overwear_absent=call("snow.data.HunterMySetData","get_OverwearMysetData()",staged)==nil
        out.equip_link_matches=call("snow.data.HunterMySetData","get_EquipMysetData()",staged)==equip
        report.transient_objects=1;report.transient_mutations=1
        return out
    elseif request.action=="insect_pair_contract" then
        local Native=require("LoadoutClone.native")
        local native=Native.new()
        local ids={}
        for _,f in ipairs(assert(sdk.find_type_definition("snow.data.ContentsIdSystem.WeaponId")):get_fields()) do
            if f:is_static() and f:is_literal() and f:get_name():match("^W_InsectGlaive_%d+$") then ids[f:get_data(nil)]=true end
        end
        local list=field(field(sdk.get_managed_singleton("snow.data.DataManager"),"_PlEquipBox"),"_WeaponArmorInventoryList")
        local size=field(list,"mSize");assert(size<=10000)
        local items=field(list,"mItems");local source
        for i=0,size-1 do local obj=items:get_element(i);if ids[field(obj,"_IdVal")] then source=obj;break end end
        assert(source,"no owned insect glaive")
        local original_pair=field(source,"_PairInsectInventoryIndex")
        local insect=native:build_simple("insect",149946473)
        local copy=assert(sdk.create_instance("snow.data.EquipmentInventoryData",true)):add_ref()
        native:call("snow.data.EquipmentInventoryData",".ctor()",copy)
        native:call("snow.data.EquipmentInventoryData","copy(snow.data.EquipmentInventoryData)",copy,source)
        native:call("snow.data.EquipmentInventoryData","setPairInsectInventory(snow.data.EquipmentInventoryData)",copy,insect)
        assert(field(source,"_PairInsectInventoryIndex")==original_pair,"source altered")
        report.game_method_calls=native.game_method_calls;report.transient_objects=2;report.transient_mutations=1
        return {weapon_id=field(copy,"_IdVal"),insect_id=field(insect,"_IdVal"),pair_index=field(copy,"_PairInsectInventoryIndex"),insect_index=field(insect,"<InventoryIndex>k__BackingField"),source_unchanged=true}
    elseif request.action=="owned_weapon_variants" then
        local Native=require("LoadoutClone.native")
        local native=Native.new()
        local enum=assert(sdk.find_type_definition("snow.data.ContentsIdSystem.WeaponId"))
        local wanted={}
        for _,f in ipairs(enum:get_fields()) do
            local n=f:get_name()
            if f:is_static() and f:is_literal() and (n:match("^W_GunLance_%d+$") or n:match("^W_Insect_%d+$")) then wanted[f:get_data(nil)]=n end
        end
        local list=field(field(sdk.get_managed_singleton("snow.data.DataManager"),"_PlEquipBox"),"_WeaponArmorInventoryList")
        local size=field(list,"mSize");assert(size<=10000)
        local items=field(list,"mItems");local out={};local seen={}
        for i=0,size-1 do
            local obj=items:get_element(i);local id=field(obj,"_IdVal")
            if wanted[id] and not seen[id] and #out<32 then
                seen[id]=true
                local row={id=id,name=wanted[id]}
                if row.name:match("^W_GunLance_") then row.base=native:weapon_base(id) end
                out[#out+1]=row
            end
        end
        report.game_method_calls=native.game_method_calls
        return {weapons=out}
    elseif request.action=="prepare_plan" then
        for _,name in ipairs({"native","planner","decorations","augments","writer"}) do package.loaded["LoadoutClone."..name]=nil end
        local reader=require("LoadoutClone.reader").new()
        local members=reader:list_members().members
        local target=assert(members[(request.member or 1)],"no selected member")
        local planner=require("LoadoutClone.planner").new(reader)
        local ok,plan=xpcall(function() return planner:prepare(target.key,{copy_augments=request.copy_augments~=false,allow_illegal_augments=request.allow_illegal==true}) end,traceback)
        report.game_method_calls=planner.native.game_method_calls
        report.transient_objects=8;report.transient_mutations=1
        assert(ok,plan)
        local out={source_index=target.index,items={},red=plan.red,blue=plan.blue}
        for i,item in ipairs(plan.items) do out.items[i]={kind=item.kind,id=field(item.object,"_IdVal"),verification=item.verification} end
        if request.transaction_test then
            local backup=json.load_file("LoadoutClone/development-backup.json")
            assert(backup and backup.backup_verified==true,"verified offline backup required")
            local writer=require("LoadoutClone.writer").new(reader)
            local prepared=writer:prepare(plan)
            writer.prepare=function() return prepared end
            if request.fault_stage then
                assert(request.fault_stage=="equipment" or request.fault_stage=="decoration" or request.fault_stage=="loadout" or request.fault_stage=="verify","invalid failure stage")
                if request.fault_stage=="verify" then writer.fault_on_verify=true
                else
                    for i,entry in ipairs(prepared.entries) do if entry.kind==request.fault_stage then writer.fault_after=i;break end end
                    assert(writer.fault_after,"requested failure stage absent")
                end
            else assert(request.commit==true,"explicit development commit required") end
            local result=writer:execute(plan)
            report.game_method_calls=report.game_method_calls+writer.native.game_method_calls
            report.writes=writer.write_count;report.restores=writer.restore_count
            out.transaction=result;out.slot=prepared.slot+1;out.entry_count=#prepared.entries
            if request.fault_stage then assert(not result.ok and result.code=="failed","rollback test failed: "..tostring(result.code)) end
        end
        if request.preflight then
            local writer=require("LoadoutClone.writer").new(reader)
            local success,prepared=pcall(function() return writer:prepare(plan) end)
            report.game_method_calls=report.game_method_calls+writer.native.game_method_calls
            assert(success,prepared)
            out.preflight={slot=prepared.slot+1,entries=#prepared.entries,indices={}}
            for i,obj in ipairs(prepared.allocated) do out.preflight.indices[i]=field(obj,"<InventoryIndex>k__BackingField") end
        end
        return out
    end
    if request.action=="validate_talisman" then
        local candidate=assert(request.candidate);local target=candidate.target
        local obj=assert(sdk.create_instance("snow.data.EquipmentInventoryData",true)):add_ref()
        report.transient_objects=1;report.transient_mutations=1
        call("snow.data.EquipmentInventoryData",".ctor()",obj)
        call("snow.data.EquipmentInventoryData","setId(snow.data.DataDef.PlTalismanId)",obj,target.id)
        for _,skill in ipairs(candidate.skills) do
            call("snow.data.EquipmentInventoryData","addTalismanEquipSkill",obj,skill.id,skill.level)
        end
        for _,level in ipairs(target.SlotLvType) do if level>0 then call("snow.data.EquipmentInventoryData","addTalismanDecoSlot",obj,level) end end
        local decos=field(obj,"_DecoIdList")
        for i,id in ipairs(candidate.decorations) do call("snow.equip.DecorationsId[]","Set",decos,i-1,id) end
        local native=call("snow.data.EquipmentInventoryData","getPlTalismanData()",obj)
        call("snow.data.PlTalismanData","updateDeco()",native)
        call("snow.data.PlTalismanData","updateSkillDataList()",native)
        local skills=field(native,"<AllSkillDataList>k__BackingField")
        local out={ids=array(field(obj,"_TalismanSkillIdList")),levels=array(field(obj,"_TalismanSkillLvList")),slots=array(field(obj,"_TalismanDecoSlotNumList")),skills={}}
        for i=0,skills:get_size()-1 do
            local skill=skills:get_element(i)
            if skill then
                local id=field(skill,"<EquipSkillId>k__BackingField")
                if id>0 then out.skills[tostring(id)]=array(field(skill,"<LvList>k__BackingField")) end
            end
        end
        return out
    end
    if request.action=="copy_contract" then
        local manager=assert(sdk.get_managed_singleton("snow.data.EquipDataManager"))
        local pack=field(manager,"_PlEquipPack")
        local own=field(pack,"<InventoryDataList>k__BackingField"):get_element(1)
        local detached=assert(sdk.create_instance("snow.data.EquipmentInventoryData",true)):add_ref()
        call("snow.data.EquipmentInventoryData",".ctor()",detached)
        local before=field(detached,"<InventoryIndex>k__BackingField")
        call("snow.data.EquipmentInventoryData","copy(snow.data.EquipmentInventoryData)",detached,own)
        local native=call("snow.data.EquipmentInventoryData","getArmorData()",detached)
        local result={index_before=before,index_after=field(detached,"<InventoryIndex>k__BackingField"),source_index=field(own,"<InventoryIndex>k__BackingField"),
            own_reference=field(native,"<RefInventory>k__BackingField")==own,
            detached_reference=field(native,"<RefInventory>k__BackingField")==detached,
            shared_augments=field(detached,"_CustomBuildup")==field(own,"_CustomBuildup"),
            shared_decorations=field(detached,"_DecoIdList")==field(own,"_DecoIdList")}
        local set=assert(sdk.create_instance("snow.equip.PlEquipMySetData",true)):add_ref()
        call("snow.equip.PlEquipMySetData",".ctor()",set)
        local refs=field(set,"<InventoryDataList>k__BackingField")
        local indexes=field(set,"_InventoryIndexList")
        local source=field(pack,"<InventoryDataList>k__BackingField")
        for i=0,7 do
            local item=source:get_element(i)
            call("snow.data.EquipmentInventoryData[]","Set",refs,i,item)
            call("System.Int32[]","Set",indexes,i,field(item,"<InventoryIndex>k__BackingField"))
        end
        set:set_field("_IsUsing",true)
        call("snow.equip.PlEquipMySetData","setupParam()",set)
        local backup=field(set,"_BackupDataList")
        result.backup_ids={}
        for i=0,7 do result.backup_ids[i+1]=field(backup:get_element(i),"IdVal") end
        result.weapon_id=field(source:get_element(0),"_IdVal")
        report.transient_objects=2;report.transient_mutations=20
        return result
    end
    if request.action=="loadout_layout" then
        local manager=assert(sdk.get_managed_singleton("snow.data.EquipDataManager"))
        local sets=field(manager,"_PlEquipMySetList")
        local out={type=sets:get_type_definition():get_full_name(),size=sets:get_size(),examples={}}
        local empty=0
        for i=0,sets:get_size()-1 do
            local item=sets:get_element(i)
            if not field(item,"_IsUsing") then empty=empty+1 end
            if i<2 or i==sets:get_size()-1 then
                local row={index=i,used=field(item,"_IsUsing"),arrays={}}
                for _,key in ipairs({"_InventoryIndexList","<InventoryDataList>k__BackingField","_BackupDataList","_ActionIdList","_ActionIdListMR_Red","_ActionIdListMR_Blue"}) do
                    local a=field(item,key);row.arrays[key]={type=a:get_type_definition():get_full_name(),size=a:get_size()}
                    if key~="<InventoryDataList>k__BackingField" and key~="_BackupDataList" then row.arrays[key].values=array(a) end
                end
                out.examples[#out.examples+1]=row
            end
        end
        out.empty=empty
        return out
    end
    if request.action=="weapon_bases" then
        local Reader=require("LoadoutClone.reader");local reader=Reader.new()
        local ids,seen={},{}
        for _,member in ipairs(reader:list_members().members) do
            local id=reader:capture(member.key).data._weaponParam.WeaponId
            if not seen[id] then seen[id]=true;ids[#ids+1]=id end
        end
        local manager=assert(sdk.get_managed_singleton("snow.data.EquipDataManager"))
        local own=field(field(manager,"_PlEquipPack"),"<InventoryDataList>k__BackingField"):get_element(0)
        local id=field(own,"_IdVal");if not seen[id] then ids[#ids+1]=id end
        assert(#ids<=4,"weapon limit")
        local out={weapons={}}
        for _,id in ipairs(ids) do
            local native=call("snow.data.DataShortcut","getPlainWeaponData(snow.data.ContentsIdSystem.WeaponId)",nil,id)
            assert(native,"weapon base missing"):add_ref()
            out.weapons[#out.weapons+1]={id=id,
                table=call("snow.data.WeaponData","get_CustomTableNo()",native),
                cost=call("snow.data.WeaponData","get_CustomCost()",native),
                max_add_cost=call("snow.data.WeaponData","get_CustomAddCostMax()",native),
                slots=array(call("snow.data.WeaponData","get_DecorationSlotNumList()",native))}
        end
        local module=assert(sdk.get_managed_singleton("snow.data.CustomBuildupModule"))
        local list=field(field(module,"_SlotBonusUserData"),"_Param")
        assert(list:get_size()<1024,"bonus table limit")
        out.slot_bonuses={}
        for i=0,list:get_size()-1 do
            local row=list:get_element(i)
            out.slot_bonuses[#out.slot_bonuses+1]={table=field(row,"_TableNo"),id=field(row,"_Id"),categories=array(field(row,"_CategoryId")),values=array(field(row,"_ValueTable"))}
        end
        return out
    end
    if request.action=="validate_weapon" then
        local candidate=assert(request.candidate);local target=assert(candidate.target)
        assert(#candidate.entries<=7 and #candidate.open_ids<=32,"weapon candidate limit")
        local detached=assert(sdk.create_instance("snow.data.EquipmentInventoryData",true)):add_ref()
        report.transient_objects=1;report.transient_mutations=1
        call("snow.data.EquipmentInventoryData",".ctor()",detached)
        call("snow.data.EquipmentInventoryData","setId(snow.data.ContentsIdSystem.WeaponId)",detached,target.WeaponId)
        detached:set_field("_CustomEnable",target.CustomEnable)
        detached:set_field("_BowgunCustomizeType",target.CustomizeType)
        detached:set_field("_HyakuryuDecoId",target.HyakuryuDecorationsId)
        local opens=assert(sdk.create_managed_array("snow.data.DataDef.CustomBuildupId",#candidate.open_ids)):add_ref()
        for i,id in ipairs(candidate.open_ids) do call("snow.data.DataDef.CustomBuildupId[]","Set",opens,i-1,id) end
        detached:set_field("_CustomOpenIdArray",opens)
        local entries=field(detached,"_CustomBuildup")
        for i,row in ipairs(candidate.entries) do
            local item=assert(entries:get_element(i-1))
            item:set_field("_Id",row.id);item:set_field("_ValueIndex",row.value_index);item:set_field("_SkillId",row.skill)
        end
        local decos=field(detached,"_DecoIdList")
        for i,id in ipairs(candidate.decorations) do call("snow.equip.DecorationsId[]","Set",decos,i-1,id) end
        local native=call("snow.data.EquipmentInventoryData","getWeaponData()",detached)
        call("snow.data.WeaponData","updateCustom()",native)
        call("snow.data.WeaponData","updateDeco()",native)
        call("snow.data.WeaponData","updateHyakuryuDeco()",native)
        call("snow.data.WeaponData","updateSkillDataList()",native)
        local out={}
        for _,key in ipairs({"CustomAddAtk","CustomAddCriticalRate","CustomAddMainElementVal","CustomAddSubElementVal","CustomAddSlot","CustomAddSharpness","CustomAddFireLv"}) do
            out[key]=call("snow.data.WeaponData","get_"..key.."()",native)
        end
        out.cost=call("snow.data.WeaponData","getCustomSpendCost(snow.data.DataDef.CustomBuildupCategoryId)",native,0)
        out.capacity=call("snow.data.WeaponData","get_CustomCost()",native)
        out.atk=call("snow.data.WeaponData","get_Atk()",native)
        out.critical=call("snow.data.WeaponData","get_CriticalRate()",native)
        out.cheat_check=call("snow.data.EquipmentInventoryData","checkCustomBuildUpCheat()",detached)
        return out
    end
    if request.action=="validate_armor" then
        local candidate=assert(request.candidate)
        local target=assert(candidate.target)
        assert(type(candidate.entries)=="table" and #candidate.entries<=7,"candidate limit")
        local base=call("snow.data.DataShortcut","getArmorBaseData(snow.data.DataDef.PlArmorId)",nil,target.ArmorId)
        assert(field(field(base,"<BaseUserDataParam>k__BackingField"),"_IsValid"),"invalid armor")
        local detached=assert(sdk.create_instance("snow.data.EquipmentInventoryData",true)):add_ref()
        report.transient_objects=1;report.transient_mutations=0
        call("snow.data.EquipmentInventoryData",".ctor()",detached)
        call("snow.data.EquipmentInventoryData","setId(snow.data.DataDef.PlArmorId)",detached,target.ArmorId)
        local native=call("snow.data.EquipmentInventoryData","getArmorData()",detached)
        local points=call("snow.data.ArmorData","getBuildupPointFromArmorLv(System.UInt32)",native,target.armorLv)
        detached:set_field("_BuildupPoint",points)
        detached:set_field("_CustomEnable",target.CustomEnable)
        detached:set_field("_CustomBuildupType",target.CustomBuildupType)
        local entries=field(detached,"_CustomBuildup")
        for i,row in ipairs(candidate.entries) do
            assert(row.id>=1 and row.id<165 and row.value_index>=0 and row.value_index<20 and row.skill>=0 and row.skill<256,"invalid augment row")
            local item=assert(entries:get_element(i-1))
            item:set_field("_Id",row.id);item:set_field("_ValueIndex",row.value_index);item:set_field("_SkillId",row.skill)
        end
        local decos=field(detached,"_DecoIdList")
        assert(#candidate.decorations==3,"invalid deco count")
        for i,id in ipairs(candidate.decorations) do assert(id>=0 and id<1024,"invalid deco");call("snow.equip.DecorationsId[]","Set",decos,i-1,id) end
        call("snow.data.ArmorData","updateCustom()",native)
        call("snow.data.ArmorData","updateDeco()",native)
        call("snow.data.ArmorData","updateSkillDataList()",native)
        report.transient_mutations=5+#candidate.entries*3+3
        local result={id=field(detached,"_IdVal"),points=points,
            defense=call("snow.data.ArmorData","getDefVal()",native),
            custom_defense=call("snow.data.ArmorData","get_CustomAddDef()",native),
            custom_slots=call("snow.data.ArmorData","get_CustomAddSlot()",native),
            slot_counts=array(call("snow.data.ArmorData","get_DecorationSlotNumList()",native)),
            cost=call("snow.data.ArmorData","getCustomSpendCost(snow.data.DataDef.CustomBuildupCategoryId)",native,0),
            resist={},skills={}}
        for i=0,4 do result.resist[i+1]=call("snow.data.ArmorData","getCustomAddReg(snow.data.DataDef.ArmorElementRegistTypes)",native,i) end
        for _,id in ipairs(target.SkillIdList) do
            if id>0 then result.skills[tostring(id)]=call("snow.data.ArmorData","getEquipSkillLevel(snow.data.DataDef.PlEquipSkillId)",native,id) end
        end
        result.cheat_check=call("snow.data.EquipmentInventoryData","checkCustomBuildUpCheat()",detached)
        return result
    end
    if request.action=="isolated_armor" then
        local manager=assert(sdk.get_managed_singleton("snow.data.EquipDataManager"))
        local own=field(field(manager,"_PlEquipPack"),"<InventoryDataList>k__BackingField"):get_element(1)
        local id=field(own,"_IdVal")
        local detached=assert(sdk.create_instance("snow.data.EquipmentInventoryData",true)):add_ref()
        report.transient_objects=1
        call("snow.data.EquipmentInventoryData",".ctor()",detached)
        call("snow.data.EquipmentInventoryData","setId(snow.data.DataDef.PlArmorId)",detached,id)
        report.transient_mutations=2
        local native=call("snow.data.EquipmentInventoryData","getArmorData()",detached)
        assert(native,"detached armor unavailable")
        assert(field(native,"<RefInventory>k__BackingField")==detached,"detached inventory reference mismatch")
        return {id=field(detached,"_IdVal"),type=field(detached,"_IdType"),
            budget=call("snow.data.ArmorData","get_CustomCost()",native),
            points_for_level_29=call("snow.data.ArmorData","getBuildupPointFromArmorLv(System.UInt32)",native,29),
            augment_capacity=field(detached,"_CustomBuildup"):get_size(),
            decoration_capacity=field(detached,"_DecoIdList"):get_size(),
            original_id=field(own,"_IdVal")}
    end
    if request.action=="deco_catalog" then
        local enum=assert(sdk.find_type_definition("snow.equip.DecorationsId"))
        local ids={}
        for _,f in ipairs(enum:get_fields()) do
            if f:is_static() and f:is_literal() and f:get_name():match("^Deco_%d+$") then ids[#ids+1]=f:get_data(nil) end
        end
        table.sort(ids)
        local offset=request.offset or 0
        assert(type(offset)=="number" and offset%1==0 and offset>=0 and offset<=#ids,"bad offset")
        local out={total=#ids,offset=offset,decorations={},unavailable={}}
        for i=offset+1,math.min(offset+24,#ids) do
            local obj=assert(sdk.create_instance("snow.data.DecorationsData",true),"deco allocation failed"):add_ref()
            report.transient_objects=(report.transient_objects or 0)+1
            call("snow.data.DecorationsData",".ctor(snow.equip.DecorationsId)",obj,ids[i])
            local base=obj:get_field("<BaseData>k__BackingField")
            if not base then out.unavailable[#out.unavailable+1]=ids[i] else
            local p=field(base,"_Param")
            local common=field(base,"_ParamBase")
            assert(field(common,"_Id")==ids[i],"deco ID mismatch")
            out.decorations[#out.decorations+1]={id=ids[i],level=field(p,"_DecorationLv"),color=field(common,"_IconColor"),
                skills=array(field(p,"_SkillIdList")),levels=array(field(p,"_SkillLvList"))}
            end
        end
        return out
    end
    assert(request.action=="armor_bases","unsupported contract action")
    local Reader=require("LoadoutClone.reader")
    local reader=Reader.new()
    local members=reader:list_members()
    local ids,seen={},{}
    for _,member in ipairs(members.members) do
        local snapshot=reader:capture(member.key)
        for _,part in ipairs(snapshot.data._armorParam) do
            if not seen[part.ArmorId] then seen[part.ArmorId]=true;ids[#ids+1]=part.ArmorId end
        end
    end
    local equip=assert(sdk.get_managed_singleton("snow.data.EquipDataManager"),"equipment manager missing")
    local pack=field(equip,"_PlEquipPack")
    local own=field(pack,"<InventoryDataList>k__BackingField")
    for i=1,5 do
        local id=scalar(field(own:get_element(i),"_IdVal"))
        if not seen[id] then seen[id]=true;ids[#ids+1]=id end
    end
    assert(#ids<=25,"armor id budget")
    local result={armors={},members=#members.members}
    for _,id in ipairs(ids) do
        local base=call("snow.data.DataShortcut","getArmorBaseData(snow.data.DataDef.PlArmorId)",nil,id)
        local p=field(base,"<BaseUserDataParam>k__BackingField")
        local row={}
        for _,key in ipairs({"_Id","_IsValid","_CustomTableNo","_CustomCost","_DefVal","_BuildupTable","_FireRegVal","_WaterRegVal","_ThunderRegVal","_IceRegVal","_DragonRegVal"}) do row[key]=scalar(field(p,key)) end
        for _,key in ipairs({"_SkillList","_SkillLvList","_DecorationsNumList"}) do row[key]=array(field(p,key)) end
        assert(row._Id==id and row._IsValid,"armor base mismatch")
        result.armors[#result.armors+1]=row
    end
    local inventory=assert(sdk.find_type_definition("snow.data.EquipmentInventoryData"))
    result.max_results=inventory:get_field("<CustomBuildupResultMax>k__BackingField"):get_data(nil)
    result.max_count=inventory:get_field("<CustomCountMax>k__BackingField"):get_data(nil)
    return result
end
return M
