-- 固定范围的开发诊断扩展；每个请求只执行一个白名单步骤。
local M={}
function M.run(request,report,checkpoint)
    if request.step=="appearance_contract" then
        package.loaded["LoadoutClone.appearance_contract"]=nil
        return require("LoadoutClone.appearance_contract").run(request,report,checkpoint)
    end
    if request.step=="release_matrix" then
        package.loaded["LoadoutClone.release_matrix"]=nil
        return require("LoadoutClone.release_matrix").run(request,report,checkpoint)
    end
    if request.step=="candidate_arrays" then
        local reader=require("LoadoutClone.reader").new()
        local folder=assert(debug.getinfo(1,"S").source:sub(2):match("^(.*[/\\])"))
        local env=setmetatable({diagnose_array=function(v)
            report.last_array={lua_type=type(v),type=v:get_type_definition():get_full_name(),reference=v:get_reference_count()}
            if not request.fast then checkpoint("native array "..report.last_array.type) end
        end},{__index=_G})
        local Native=assert(loadfile(folder.."diagnostic_native.lua","t",env))()
        local planner_env=setmetatable({require=function(name) if name=="LoadoutClone.native" then return Native end;return require(name) end},{__index=_G})
        local Planner=assert(loadfile(folder.."planner.lua","t",planner_env))()
        checkpoint("prepare detached candidates")
        local planner=Planner.new(reader)
        local plan
        for iteration=1,(request.fast and 5 or 1) do
            report.iteration=iteration
            plan=planner:prepare(assert(request.key),{copy_augments=true,allow_illegal_augments=true,copy_appearance=false})
            if request.fast then collectgarbage("collect");coroutine.yield({phase="candidate iteration",done=iteration}) end
        end
        if request.verify_copy then
            local Writer=assert(loadfile(folder.."writer.lua","t",planner_env))()
            local writer=Writer.new(reader)
            local manager=assert(sdk.get_managed_singleton("snow.data.EquipDataManager"))
            local staged={entries={},manager=manager,current=Native.array(Native.field(Native.field(manager,"_PlEquipPack"),"_InventoryIndexList")),slot=0,hunter_slot=0}
            for _,item in ipairs(plan.items) do
                staged.entries[#staged.entries+1]={kind="equipment",object=item.object,dest=writer:backup("snow.data.EquipmentInventoryData",item.object)}
            end
            checkpoint("verify copied detached equipment, no inventory writes")
            writer:verify(staged)
            report.detached_copy_verified=true
        end
        report.arrays={};report.writes=0
        for pass=1,2 do
            if pass==2 then collectgarbage("collect");coroutine.yield({phase="array lifetime"}) end
            for i,item in ipairs(plan.items) do
                for _,key in ipairs({"_DecoIdList","_CustomOpenIdArray","_TalismanDecoSlotNumList","_TalismanSkillIdList","_TalismanSkillLvList"}) do
                    checkpoint("array "..pass..":"..i..":"..key)
                    local value=item.object:get_field(key)
                    local row={pass=pass,item=i,kind=item.kind,field=key,lua_type=type(value)}
                    local ok,result=pcall(function() return value:get_type_definition():get_full_name() end)
                    row.type=ok and result or tostring(result)
                    local size_ok,size=pcall(function() return value:get_size() end)
                    row.size_ok=size_ok;row.size=size_ok and size or tostring(size)
                    local native_ok,native_values=pcall(Native.array,value)
                    row.native_ok=native_ok;row.native_values=native_values
                    report.arrays[#report.arrays+1]=row
                    assert(native_ok,tostring(native_values))
                end
            end
        end
        return
    end
    if request.step=="refresh_presentation" then
        local current=assert(package.loaded["LoadoutClone.view"],"panel module not loaded")
        local folder=assert(debug.getinfo(1,"S").source:sub(2):match("^(.*[/\\])"))
        local updated=assert(loadfile(folder.."../../autorun/LoadoutClone/view.lua"))()
        -- 只更新绘制函数，不重建窗口、字体、控制器或运行中的请求。
        current.body=updated.body
        report.refreshed=true;report.writes=0;return
    end
    if request.step=="appearance_metadata" then
        report.types={}
        for _,name in ipairs({"snow.equip.PlOverwearBaseUserData.Param","snow.data.DataShortcut","snow.equip.PlArmorColorMySetData","snow.data.OverwearWeaponData","snow.data.OverwearWeaponBaseData","snow.equip.EquipShortcut"}) do
            checkpoint("metadata "..name)
            local td=sdk.find_type_definition(name)
            local row={name=name,found=td~=nil,fields={},methods={}}
            if td then
                for _,f in ipairs(td:get_fields()) do
                    assert(#row.fields<512,"field bound")
                    row.fields[#row.fields+1]={name=f:get_name(),type=f:get_type():get_full_name(),static=f:is_static()}
                end
                for _,m in ipairs(td:get_methods()) do
                    if name~="snow.data.DataShortcut" or m:get_name():lower():find("overwear",1,true) then
                        assert(#row.methods<512,"method bound")
                        local params={};for _,p in ipairs(m:get_param_types()) do params[#params+1]=p:get_full_name() end
                        row.methods[#row.methods+1]={name=m:get_name(),parameters=params,returns=m:get_return_type():get_full_name(),static=m:is_static()}
                    end
                end
            end
            report.types[#report.types+1]=row
        end
        report.writes=0;return
    end
    if request.step=="talisman_build_regression" then
        local folder=assert(debug.getinfo(1,"S").source:sub(2):match("^(.*[/\\])"))
        local Native=assert(loadfile(folder.."native.lua"))()
        local native=Native.new()
        local candidate={target={id=269484049,SlotLvType={4,1,1}},skills={{id=137,level=2},{id=22,level=3}},decorations={139,17,232}}
        checkpoint("new talisman build with original primary/secondary order")
        local obj,result=native:build_talisman(candidate)
        report.correct=result
        candidate.skills={{id=22,level=3},{id=137,level=2}}
        checkpoint("new talisman build rejects invalid sorted order")
        local ok,err=pcall(function() native:build_talisman(candidate) end)
        assert(not ok and tostring(err):find("未通过游戏校验",1,true),"invalid order was not rejected")
        report.invalid_order_rejected=true;report.writes=0;return
    end
    if request.step=="talisman_audit" then
        package.loaded["LoadoutClone.talisman_probe"]=nil
        return require("LoadoutClone.talisman_probe").run(request,report,checkpoint)
    end
    if request.step=="relaxed_preview" then
        local folder=assert(debug.getinfo(1,"S").source:sub(2):match("^(.*[/\\])"))
        local augments=assert(loadfile(folder.."augments.lua"))()
        local env=setmetatable({require=function(name)
            if name=="LoadoutClone.augments" then return augments end
            return require(name)
        end},{__index=_G})
        local Planner=assert(loadfile(folder.."planner.lua","t",env))()
        local reader=require("LoadoutClone.reader").new()
        checkpoint("isolated relaxed prepare, no commit")
        local plan=Planner.new(reader):prepare(assert(request.key),{copy_augments=true,allow_illegal_augments=true,copy_appearance=false})
        report.items={}
        for i,item in ipairs(plan.items) do report.items[i]={kind=item.kind,verification=item.verification,entries=item.candidate.entries} end
        report.writes=0;return
    end
    if request.step=="armor_bases" then
        local native=require("LoadoutClone.native").new()
        local reader=require("LoadoutClone.reader").new()
        local snapshot=reader:capture(assert(request.key))
        report.bases={}
        for i,part in ipairs(snapshot.data._armorParam) do
            checkpoint("armor base "..i)
            report.bases[i]=native:armor_base(part.ArmorId)
        end
        report.writes=0;return
    end
    if request.step=="color_contract" then
        local native=require("LoadoutClone.native").new()
        report.samples={}
        for _,values in ipairs({{0,0,0},{0,100,0},{0,100,100},{120,100,50},{30,90,47}}) do
            local hsv=ValueType.new(assert(sdk.find_type_definition("via.Int3")))
            for i,key in ipairs({"x","y","z"}) do hsv:set_field(key,values[i]) end
            local row={hsv=values}
            for _,method in ipairs({"HSV2RGB","HSV2ColorToMaterial","convertHSV2Float4"}) do
                checkpoint(method..":"..table.concat(values,","))
                local rgb=native:call("snow.gui.SnowGuiCommonUtility",method.."(via.Int3)",nil,hsv)
                row[method]={rgb.x,rgb.y,rgb.z}
            end
            report.samples[#report.samples+1]=row
        end
        report.writes=0;return
    end
    if request.step=="appearance" then
        package.loaded["LoadoutClone.appearance_probe"]=nil
        return require("LoadoutClone.appearance_probe").run(request,report,checkpoint)
    end
    assert(request.step=="preflight" or request.step=="capture" or request.step=="rollback_hunter" or request.step=="commit_hunter","unknown diagnostic step")
    local Reader=require("LoadoutClone.reader")
    local reader=Reader.new()
    assert(type(request.key)=="string","member key required")
    if request.step=="capture" then
        checkpoint("capture")
        report.snapshot=reader:capture(request.key)
        return
    end
    local planner=require("LoadoutClone.planner").new(reader)
    checkpoint("prepare detached equipment")
    local plan=planner:prepare(request.key,{copy_augments=true,allow_illegal_augments=false,copy_appearance=false})
    local Writer=require("LoadoutClone.writer")
    local writer=Writer.new(reader)
    if request.step=="rollback_hunter" or request.step=="commit_hunter" then
        local backup=json.load_file("LoadoutClone/development-backup.json")
        assert(backup and backup.backup_verified and type(backup.backup_path)=="string","verified save backup required")
        writer.fault_on_verify=request.step=="rollback_hunter"
        checkpoint(writer.fault_on_verify and "rollback validation: execute with injected verification failure" or "commit validated hunter loadout")
        local result=writer:execute(plan)
        report.transaction=result;report.writes=writer.write_count;report.restores=writer.restore_count
        if writer.fault_on_verify then
            assert(not result.ok and result.code=="failed" and result.error:find("development verification failure",1,true),"unexpected transaction outcome")
            assert(report.writes>0 and report.writes==report.restores,"rollback count mismatch")
            checkpoint("all entries restored and verified")
        else
            assert(result.ok,"commit did not succeed")
            checkpoint("hunter loadout committed and verified")
        end
        return
    end
    local original=writer.native.call
    function writer.native:call(owner_type,signature,owner,...)
        checkpoint(owner_type.."."..signature..":before")
        local result=original(self,owner_type,signature,owner,...)
        checkpoint(owner_type.."."..signature..":after")
        return result
    end
    checkpoint("writer:prepare (no apply/execute)")
    local prepared=writer:prepare(plan)
    report.equipment_slot=prepared.slot+1
    report.hunter_slot=prepared.hunter_slot+1
    report.entries={}
    for i,entry in ipairs(prepared.entries) do
        report.entries[i]={kind=entry.kind,before=entry.before,expected=entry.expected}
    end
    checkpoint("writer:assert_context")
    writer:assert_context(prepared)
    report.writes=writer.write_count
    assert(report.writes==0,"preflight must not write")
end
return M
