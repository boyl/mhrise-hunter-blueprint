local M={}
function M.run(request,report,checkpoint)
    local N=require("LoadoutClone.native")
    local native=N.new()
    local field=N.field
    local journal=assert(json.load_file("LoadoutClone/transaction.json"))
    assert(journal.status=="complete" and journal.result.ok,"latest transaction not complete")
    local slot=journal.result.result.slot-1
    local manager=assert(sdk.get_managed_singleton("snow.data.EquipDataManager"))
    local set=field(manager,"_PlEquipMySetList"):get_element(slot)
    local indices=N.array(field(set,"_InventoryIndexList"))
    local data=assert(sdk.get_managed_singleton("snow.data.DataManager"))
    local box=field(field(data,"_PlEquipBox"),"_WeaponArmorInventoryList")
    local function inventory(obj,provided)
        local out={id=field(obj,"_IdVal"),index=field(obj,"<InventoryIndex>k__BackingField")}
        out.id_type=field(obj,"_IdType")
        for _,key in ipairs({"_TalismanDecoSlotNumList","_TalismanSkillIdList","_TalismanSkillLvList","_DecoIdList"}) do out[key]=N.array(field(obj,key)) end
        out.effective_slot_counts=N.array(native:call("snow.data.EquipmentInventoryData","getTalismanDecoSlotNumList()",obj))
        out.effective_skill_ids=N.array(native:call("snow.data.EquipmentInventoryData","getTalismanSkillIdList()",obj))
        out.effective_skill_levels=N.array(native:call("snow.data.EquipmentInventoryData","getTalismanSkillLvList()",obj))
        local charm=provided or native:call("snow.data.EquipmentInventoryData","getPlTalismanData()",obj)
        out.native_reference_count=charm:get_reference_count()
        charm:add_ref()
        out.native_inventory_matches=field(charm,"<RefInventory>k__BackingField")==obj
        out.native_reference_id=field(charm,"<RefId>k__BackingField")
        out.native_skills=N.skills(charm)
        out.slots={}
        local list=field(charm,"<DecoSlotList>k__BackingField")
        local size=field(list,"mSize");assert(size<=3,"talisman slots limit")
        local items=field(list,"mItems")
        for i=0,size-1 do
            local s=items:get_element(i)
            local deco=s:get_field("<DecorationsData>k__BackingField")
            out.slots[i+1]={enabled=field(s,"<IsEnable>k__BackingField"),level=field(s,"<SlotLv>k__BackingField"),decoration=deco and field(deco,"<Id>k__BackingField") or 0}
        end
        return out
    end
    checkpoint("new inventory talisman")
    report.slot=slot+1
    report.new_inventory=inventory(field(box,"mItems"):get_element(indices[8]))
    checkpoint("loadout cached talisman")
    report.loadout_cached=inventory(field(set,"<InventoryDataList>k__BackingField"):get_element(7))
    local backup=field(set,"_BackupDataList"):get_element(7)
    report.backup={id=field(backup,"IdVal"),decorations=N.array(field(backup,"DecoIdList"))}
    checkpoint("currently equipped talisman")
    report.equipped=inventory(field(field(manager,"_PlEquipPack"),"<InventoryDataList>k__BackingField"):get_element(7))
    if request.experiment=="repair_order" then
        local target=field(box,"mItems"):get_element(indices[8])
        local before=report.new_inventory
        assert(before.index==request.expected_index and before.id==269484049,"repair target changed")
        assert(before._TalismanSkillIdList[1]==22 and before._TalismanSkillIdList[2]==137 and before._TalismanSkillLvList[1]==3 and before._TalismanSkillLvList[2]==2,"repair source evidence mismatch")
        local function set_order(ids,levels)
            for i=0,1 do
                native:call("snow.data.DataDef.PlEquipSkillId[]","Set",field(target,"_TalismanSkillIdList"),i,ids[i+1])
                native:call("System.UInt32[]","Set",field(target,"_TalismanSkillLvList"),i,levels[i+1])
            end
            native:call("snow.data.EquipmentInventoryData","updateCheatBitFlag()",target)
        end
        checkpoint("repair cloned talisman primary/secondary skill order")
        local equal=require("LoadoutClone.writer").equal
        local ok,err=xpcall(function()
            set_order({137,22},{2,3})
            report.repaired=inventory(target)
            assert(equal(report.repaired.effective_slot_counts,before._TalismanDecoSlotNumList),"effective slots not restored")
            assert(equal(report.repaired.effective_skill_ids,{137,22}) and equal(report.repaired.effective_skill_levels,{2,3}),"effective skills not restored")
            assert(equal(report.repaired._DecoIdList,before._DecoIdList),"stored decorations changed")
            assert(#report.repaired.slots==3,"effective slots missing")
            for i,s in ipairs(report.repaired.slots) do assert(s.decoration==before._DecoIdList[i],"effective decoration missing") end
        end,debug.traceback)
        if not ok then set_order(before._TalismanSkillIdList,before._TalismanSkillLvList);error(err) end
        report.order_repaired=true
    end
    if request.experiment=="refresh_latest" then
        local target=field(box,"mItems"):get_element(indices[8])
        assert(report.new_inventory.id==report.backup.id,"loadout/inventory changed")
        local charm=native:call("snow.data.EquipmentInventoryData","getPlTalismanData()",target)
        report.refresh_reference_before=charm:get_reference_count()
        charm:add_ref()
        checkpoint("refresh latest cloned talisman runtime cache")
        native:call("snow.data.PlTalismanData","setReference(snow.data.EquipmentInventoryData)",charm,target)
        native:call("snow.data.PlTalismanData","initDeco()",charm)
        native:call("snow.data.PlTalismanData","initEquipSkill()",charm)
        native:call("snow.data.PlTalismanData","updateDeco()",charm)
        native:call("snow.data.PlTalismanData","updateSkillDataList()",charm)
        report.direct_repaired=inventory(target,charm)
        local fetched=native:call("snow.data.EquipmentInventoryData","getPlTalismanData()",target)
        report.same_runtime_object=fetched==charm
        report.repaired=inventory(target,fetched)
        local equal=require("LoadoutClone.writer").equal
        for _,key in ipairs({"id","index","_TalismanDecoSlotNumList","_TalismanSkillIdList","_TalismanSkillLvList","_DecoIdList"}) do
            assert(equal(report.new_inventory[key],report.repaired[key]),"persistent field changed: "..key)
        end
        local counts={0,0,0,0,0}
        for i,s in ipairs(report.repaired.slots) do
            if s.enabled then counts[s.level+1]=counts[s.level+1]+1 end
            assert(s.decoration==report.repaired._DecoIdList[i],"effective decoration mismatch")
        end
        assert(equal(counts,report.repaired._TalismanDecoSlotNumList),"effective slot mismatch")
        report.cache_updates=5
    end
    if request.experiment=="detached_copy" or request.experiment=="validate_order" then
        local source=field(box,"mItems"):get_element(indices[8])
        local copied=assert(sdk.create_instance("snow.data.EquipmentInventoryData",true)):add_ref()
        native:call("snow.data.EquipmentInventoryData",".ctor()",copied)
        native:call("snow.data.EquipmentInventoryData","setId(snow.data.DataDef.PlTalismanId)",copied,field(source,"_IdVal"))
        report.detached_warm=inventory(copied)
        checkpoint("copy to detached inventory")
        native:call("snow.data.EquipmentInventoryData","copy(snow.data.EquipmentInventoryData)",copied,source)
        report.detached_before=inventory(copied)
        local charm=native:call("snow.data.EquipmentInventoryData","getPlTalismanData()",copied)
        checkpoint("refresh detached talisman decoration cache")
        native:call("snow.data.PlTalismanData","setReference(snow.data.EquipmentInventoryData)",charm,copied)
        native:call("snow.data.PlTalismanData","initDeco()",charm)
        native:call("snow.data.PlTalismanData","initEquipSkill()",charm)
        native:call("snow.data.PlTalismanData","updateDeco()",charm)
        native:call("snow.data.PlTalismanData","updateSkillDataList()",charm)
        report.detached_after=inventory(copied)
        if request.experiment=="validate_order" then
            checkpoint("native cheat validation of detached original skill order")
            native:call("snow.data.EquipmentInventoryData","updateCheatBitFlag()",copied)
            report.original_order_checked=inventory(copied)
            local ids=N.array(field(copied,"_TalismanSkillIdList"))
            local levels=N.array(field(copied,"_TalismanSkillLvList"))
            assert(#ids==2 and #levels==2,"expected two skills")
            for i=0,1 do
                native:call("snow.data.DataDef.PlEquipSkillId[]","Set",field(copied,"_TalismanSkillIdList"),i,ids[2-i])
                native:call("System.UInt32[]","Set",field(copied,"_TalismanSkillLvList"),i,levels[2-i])
            end
            checkpoint("native cheat validation of detached swapped skill order")
            native:call("snow.data.EquipmentInventoryData","updateCheatBitFlag()",copied)
            report.swapped_order_checked=inventory(copied)
        end
    end
    checkpoint("decoration slot metadata")
    local td=assert(sdk.find_type_definition("snow.data.equip.param.DecorationsSlotData"))
    report.slot_fields={}
    for _,f in ipairs(td:get_fields()) do
        assert(#report.slot_fields<32,"slot metadata bound")
        report.slot_fields[#report.slot_fields+1]={name=f:get_name(),type=f:get_type():get_full_name(),static=f:is_static()}
    end
    report.writes=report.order_repaired and 4 or 0
end
return M
