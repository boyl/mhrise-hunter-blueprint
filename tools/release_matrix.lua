-- 开发验收：正式包不包含此模块；只在当次诊断会话显式运行。
local M={}
function M.run(request,report,checkpoint)
    local Reader=require("LoadoutClone.reader")
    local folder=assert(debug.getinfo(1,"S").source:sub(2):match("^(.*[/\\])"))
    local Planner=assert(loadfile(folder.."planner.lua"))()
    local Writer=assert(loadfile(folder.."writer.lua"))()
    local reader=Reader.new()
    if request.insect_pair then
        local backup=json.load_file("LoadoutClone/development-backup.json")
        assert(backup and backup.backup_verified,"verified backup required")
        local Native=require("LoadoutClone.native")
        local writer=Writer.new(reader)
        local native=writer.native
        local manager=assert(sdk.get_managed_singleton("snow.data.EquipDataManager"))
        local box=Native.field(assert(sdk.get_managed_singleton("snow.data.DataManager")),"_PlEquipBox")
        local list=Native.field(box,"_WeaponArmorInventoryList")
        local size=Native.field(list,"mSize");assert(size<=5000)
        local _,get=Native.array_access(Native.field(list,"mItems"),8192)
        local dest={}
        for i=0,size-1 do if Native.field(get(i),"_IdType")==0 then dest[#dest+1]=get(i);if #dest==2 then break end end end
        assert(#dest==2,"needs two empty equipment slots")
        local weapon=native:build_weapon({target={WeaponId=144703504,CustomEnable=false,CustomizeType=0,HyakuryuDecorationsId=1048576},entries={},open_ids={},decorations={0,0,0}})
        local insect=native:build_simple("insect",149946368)
        local plan={entries={},manager=manager,current=Native.array(Native.field(Native.field(manager,"_PlEquipPack"),"_InventoryIndexList")),allocated={dest[1]},insect=dest[2],slot=0,hunter_slot=0}
        for i,obj in ipairs({weapon,insect}) do plan.entries[i]={kind="equipment",object=obj,dest=dest[i],before=Writer.equipment_state(dest[i]),backup=writer:backup("snow.data.EquipmentInventoryData",dest[i]),index=Native.field(dest[i],"<InventoryIndex>k__BackingField")} end
        local adapter={prepare=function() return plan end,assert_context=function() end}
        function adapter:apply(e) writer:apply(e) end
        function adapter:verify(p)
            native:call("snow.data.EquipmentInventoryData","setPairInsectInventory(snow.data.EquipmentInventoryData)",dest[1],dest[2])
            report.pair=Native.field(dest[1],"_PairInsectInventoryIndex")
            report.expected_pair=plan.entries[2].index
            local linked=dest[1]:get_field("<PairInsectInventory>k__BackingField")
            report.linked=linked and {id=Native.field(linked,"_IdVal"),index=Native.field(linked,"<InventoryIndex>k__BackingField"),same=linked==dest[2]} or {missing=true}
            assert(report.linked.same and report.linked.index==report.expected_pair,"insect pair index mismatch")
            writer:verify(p);report.pair_verified=true
            if request.commit then return {weapon_index=plan.entries[1].index,insect_index=plan.entries[2].index} end
            error("insect pair rollback checkpoint")
        end
        function adapter:restore(e) writer:restore(e) end
        function adapter:verify_restored(e) writer:verify_restored(e) end
        checkpoint("insect pair transaction and rollback")
        local result=require("LoadoutClone.transaction").new(adapter):execute(plan)
        report.transaction=result;report.writes=writer.write_count;report.restores=writer.restore_count
        if request.commit then assert(report.pair_verified and result.ok and report.writes==2 and not report.restores,"insect commit failed")
        else
            assert(report.pair_verified and result.code=="failed" and result.error:find("insect pair rollback checkpoint",1,true),"insect pair validation failed")
            assert(report.writes==2 and report.restores==2,"insect rollback mismatch")
        end
        return
    end
    if request.inspect_pair then
        local Native=require("LoadoutClone.native")
        local box=Native.field(assert(sdk.get_managed_singleton("snow.data.DataManager")),"_PlEquipBox")
        local list=Native.field(box,"_WeaponArmorInventoryList")
        local _,get=Native.array_access(Native.field(list,"mItems"),8192)
        local index=assert(request.inspect_pair.weapon_index);assert(index>=0 and index<Native.field(list,"mSize"))
        local weapon=get(index);local linked=weapon:get_field("<PairInsectInventory>k__BackingField")
        report.pair={weapon_id=Native.field(weapon,"_IdVal"),stored=Native.field(weapon,"_PairInsectInventoryIndex"),effective=Writer.pair_index(weapon),insect_id=linked and Native.field(linked,"_IdVal")}
        assert(report.pair.weapon_id==144703504 and report.pair.insect_id==149946368 and report.pair.effective==request.inspect_pair.insect_index,"persisted insect mismatch")
        report.writes=0;return
    end
    if request.insect_inventory then
        local Native=require("LoadoutClone.native")
        local box=Native.field(assert(sdk.get_managed_singleton("snow.data.DataManager")),"_PlEquipBox")
        local list=Native.field(box,"_WeaponArmorInventoryList")
        local size=Native.field(list,"mSize");assert(size<=5000)
        local _,get=Native.array_access(Native.field(list,"mItems"),8192)
        local names={}
        for _,f in ipairs(assert(sdk.find_type_definition("snow.data.ContentsIdSystem.WeaponId")):get_fields()) do
            if f:is_static() and f:is_literal() and f:get_name():find("Insect",1,true) then names[f:get_data(nil)]=f:get_name() end
        end
        report.insects={};report.writes=0
        for i=0,size-1 do
            local id=Native.field(get(i),"_IdVal")
            if names[id] and not names[id]:find("Glaive",1,true) then report.insects[#report.insects+1]={id=id,name=names[id],index=i} end
        end
        return
    end
    if request.saved_slots then
        local Native=require("LoadoutClone.native")
        local manager=assert(sdk.get_managed_singleton("snow.data.EquipDataManager"))
        local _,get_set=Native.array_access(Native.field(manager,"_PlEquipMySetList"),1024)
        local _,get_hunter=Native.array_access(Native.field(manager,"_HunterMySetList"),1024)
        local box=Native.field(assert(sdk.get_managed_singleton("snow.data.DataManager")),"_PlEquipBox")
        local inventories={}
        for _,key in ipairs({"_WeaponArmorInventoryList","_LvBuffCageInventoryList"}) do
            local list=Native.field(box,key)
            local _,get=Native.array_access(Native.field(list,"mItems"),8192)
            local size=Native.field(list,"mSize");assert(size<=5000)
            inventories[key]={get=get,size=size}
        end
        report.saved={};report.writes=0
        assert(#request.saved_slots<=8)
        for _,pair in ipairs(request.saved_slots) do
            assert(pair.equipment>=1 and pair.equipment<=224 and pair.hunter>=1 and pair.hunter<=224)
            local set=get_set(pair.equipment-1)
            local row={equipment_slot=pair.equipment,hunter_slot=pair.hunter,name=set:get_field("_Name"),used=Native.field(set,"_IsUsing"),arrays={},items={}}
            for _,key in ipairs({"_InventoryIndexList","_ActionIdList","_ActionIdListMR_Red","_ActionIdListMR_Blue"}) do row.arrays[key]=Native.array(Native.field(set,key)) end
            row.hunter=require("LoadoutClone.hunter").state(get_hunter(pair.hunter-1))
            assert(row.used and row.hunter._IsUsing and row.hunter._EquipMysetIndex==pair.equipment-1)
            for i,index in ipairs(row.arrays._InventoryIndexList) do
                local list=inventories[i==7 and "_LvBuffCageInventoryList" or "_WeaponArmorInventoryList"]
                assert(index>=0 and index<list.size)
                local obj=list.get(index)
                local item={index=index}
                for _,key in ipairs({"_IdVal","_BuildupPoint","_CustomEnable","_CustomBuildupType","_PairInsectInventoryIndex","_HyakuryuDecoId","_BowgunCustomizeType"}) do item[key]=Native.field(obj,key) end
                for _,key in ipairs({"_DecoIdList","_CustomOpenIdArray","_TalismanDecoSlotNumList","_TalismanSkillIdList","_TalismanSkillLvList"}) do item[key]=Native.array(Native.field(obj,key)) end
                local n,get=Native.array_access(Native.field(obj,"_CustomBuildup"),7)
                item.augments={};for j=0,n-1 do local a=get(j);item.augments[j+1]={Native.field(a,"_Id"),Native.field(a,"_ValueIndex"),Native.field(a,"_SkillId")} end
                row.items[i]=item
            end
            report.saved[#report.saved+1]=row
        end
        return
    end
    if request.weapon_families then
        local Native=require("LoadoutClone.native")
        local native=Native.new()
        local box=Native.field(assert(sdk.get_managed_singleton("snow.data.DataManager")),"_PlEquipBox")
        local list=Native.field(box,"_WeaponArmorInventoryList")
        local size=Native.field(list,"mSize");assert(size<=5000)
        local count,get=Native.array_access(Native.field(list,"mItems"),8192)
        assert(size<=count)
        local ids={}
        for i=0,size-1 do
            local obj=get(i);local id=Native.field(obj,"_IdVal")
            local family=id>>20
            if family>=129 and family<=142 and not ids[family] and (id & 0xfffff)>0 then ids[family]=id end
        end
        report.families={};report.writes=0
        local names={}
        for _,f in ipairs(assert(sdk.find_type_definition("snow.data.ContentsIdSystem.WeaponId")):get_fields()) do
            if f:is_static() and f:is_literal() then names[f:get_data(nil)]=f:get_name() end
        end
        for family=129,142 do
            local id=ids[family];local row={family=family,id=id,name=id and names[id]};report.families[#report.families+1]=row
            if id then
                checkpoint("weapon family "..family)
                local ok,result=xpcall(function()
                    native.game_method_calls=0
                    local candidate={target={WeaponId=id,CustomEnable=false,CustomizeType=0,HyakuryuDecorationsId=1048576},entries={},open_ids={},decorations={0,0,0}}
                    local obj,values=native:build_weapon(candidate)
                    local writer=Writer.new(reader)
                    local copied=writer:backup("snow.data.EquipmentInventoryData",obj)
                    assert(Native.field(copied,"_IdVal")==id)
                    row.result=values
                    return true
                end,debug.traceback)
                row.ok=ok;row.error=not ok and tostring(result) or nil
            else row.missing=true end
            coroutine.yield({phase="weapon families",done=family-128})
        end
        return
    end
    local members=reader:list_members().members
    assert(#members>0,"需要有效大厅成员")
    if request.inspect_actions then
        local Native=require("LoadoutClone.native")
        local native=Native.new()
        local obj=assert(sdk.create_instance("snow.equip.PlEquipMySetData",true)):add_ref()
        native:call("snow.equip.PlEquipMySetData",".ctor()",obj)
        report.template={};report.sources={};report.writes=0
        for _,key in ipairs({"_ActionIdList","_ActionIdListMR_Red","_ActionIdListMR_Blue"}) do report.template[key]=Native.array(Native.field(obj,key)) end
        for _,member in ipairs(members) do
            local snapshot=reader:capture(member.key)
            report.sources[#report.sources+1]={index=member.index,status=snapshot.data._equipStatusParam}
        end
        return
    end
    report.cases={};report.writes=0;report.restores=0
    local modes={{name="base",copy_augments=false,allow_illegal_augments=false},
        {name="normal",copy_augments=true,allow_illegal_augments=false},
        {name="relaxed",copy_augments=true,allow_illegal_augments=true}}
    if request.commit then
        assert(type(request.member_index)=="number" and type(request.mode)=="string","explicit commit selection required")
        local selected={};for _,member in ipairs(members) do if member.index==request.member_index then selected[1]=member end end
        assert(#selected==1,"selected member left");members=selected
        local chosen={};for _,mode in ipairs(modes) do if mode.name==request.mode then chosen[1]=mode end end
        assert(#chosen==1,"unknown mode");modes=chosen
    end
    for _,member in ipairs(members) do
        for _,options in ipairs(modes) do
            options.copy_appearance=false
            local row={member_index=member.index,mode=options.name}
            report.cases[#report.cases+1]=row
            checkpoint("prepare "..member.index.." "..options.name)
            local ok,result=xpcall(function()
                local source=Planner.new(reader):prepare(member.key,options)
                row.weapon_id=source.items[1].candidate.target.WeaponId
                row.insect=source.insect~=nil
                row.red=source.red;row.blue=source.blue
                local writer=Writer.new(reader)
                if request.rollback or request.commit then
                    local backup=json.load_file("LoadoutClone/development-backup.json")
                    assert(backup and backup.backup_verified,"verified save backup required")
                    writer.fault_on_verify=request.rollback==true
                    local tx=writer:execute(source)
                    row.transaction=tx;row.writes=writer.write_count;row.restores=writer.restore_count
                    report.writes=report.writes+row.writes;report.restores=report.restores+row.restores
                    if request.rollback then
                        assert(not tx.ok and tx.code=="failed" and tx.error:find("development verification failure",1,true),"unexpected rollback result")
                        assert(row.writes>0 and row.writes==row.restores,"rollback count mismatch")
                    else
                        assert(tx.ok,"commit failed: "..tostring(tx.error))
                        row.expected={actions=source.actions,red=source.red,blue=source.blue,items={}}
                        for i,item in ipairs(source.items) do row.expected.items[i]={kind=item.kind,candidate=item.candidate,verification=item.verification} end
                    end
                else
                    local plan=writer:prepare(source)
                    writer:assert_context(plan)
                    row.entries=#plan.entries;row.hunter_slot=plan.hunter_slot+1;row.equipment_slot=plan.slot+1
                    assert(writer.write_count==0)
                end
                return true
            end,debug.traceback)
            row.ok=ok;row.error=not ok and tostring(result) or nil
            checkpoint("finished "..member.index.." "..options.name)
            if row.transaction and row.transaction.code=="recovery_failed" then error("回滚失败，停止矩阵") end
            coroutine.yield({phase="matrix",done=#report.cases})
        end
    end
end
return M
