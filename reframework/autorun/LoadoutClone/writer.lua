-- 只提交到原生空槽；所有候选必须先经 planner 完整验证。
local Native=require("LoadoutClone.native")
local Transaction=require("LoadoutClone.transaction")
local Hunter=require("LoadoutClone.hunter")
local M={}
-- 蓝图每次导入创建独立写入器；同会话故障锁必须跨实例保留。
local session_locked=false
local field,array=Native.field,Native.array
function M.pair_index(obj)
    local linked=obj:get_field("<PairInsectInventory>k__BackingField")
    return linked and field(linked,"<InventoryIndex>k__BackingField") or field(obj,"_PairInsectInventoryIndex")
end
local function equal(a,b)
    if type(a)~=type(b) then return false end
    if type(a)~="table" then return a==b end
    for k,v in pairs(a) do if not equal(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end
    return true
end
local function list(obj,max)
    local size=field(obj,"mSize");assert(size>=0 and size<=max,"inventory list bound")
    return field(obj,"mItems"),size
end
local function equipment_state(obj,with_color)
    local out={}
    for _,key in ipairs({"_IdType","_IdVal","_BuildupPoint","_CustomEnable","_CustomCount","_CustomBuildupType","_BowgunCustomizeType","_PairInsectInventoryIndex","_HyakuryuDecoId","_IsLock","_IsSetGuildCard"}) do out[key]=field(obj,key) end
    out._PairInsectInventoryIndex=M.pair_index(obj)
    for _,key in ipairs({"_DecoIdList","_CustomOpenIdArray","_TalismanDecoSlotNumList","_TalismanSkillIdList","_TalismanSkillLvList","_HyakuryuSkillIdList","_PrevHyakuryuSkillId"}) do out[key]=array(field(obj,key)) end
    out.augments={};local rows=field(obj,"_CustomBuildup")
    local count,get=Native.array_access(rows,7)
    for i=0,count-1 do
        local row=get(i);out.augments[i+1]={field(row,"_Id"),field(row,"_ValueIndex"),field(row,"_SkillId")}
    end
    if with_color then out.color=require("LoadoutClone.appearance_color").read(field(obj,"_HyakuryuColorData")) end
    return out
end
local function set_state(obj)
    local out={used=field(obj,"_IsUsing"),name=obj:get_field("_Name") or "",arrays={},backup={}}
    for _,key in ipairs({"_InventoryIndexList","_ActionIdList","_ActionIdListMR_Red","_ActionIdListMR_Blue"}) do out.arrays[key]=array(field(obj,key)) end
    local backup=field(obj,"_BackupDataList")
    local count,get=Native.array_access(backup,16)
    for i=0,count-1 do
        local item=get(i)
        out.backup[i+1]={id=field(item,"IdVal"),insect=field(item,"InsectIdVal"),insect_index=field(item,"InsectInventoryIndex"),bowgun=field(item,"BowgunCustomizeType"),decos=array(field(item,"DecoIdList")),hyakuryu=field(item,"HyakuryuDecoId")}
    end
    return out
end
function M.new(reader,appearance)
    local self=setmetatable({reader=reader,native=Native.new(),write_count=0,appearance=appearance},{__index=M})
    self.transaction=Transaction.new(self)
    return self
end
function M:copy(type_name,dest,source)
    self.native:call(type_name,"copy("..type_name..")",dest,source)
end
function M:backup(type_name,source)
    local out=assert(sdk.create_instance(type_name,true)):add_ref()
    self.native:call(type_name,".ctor()",out)
    self:copy(type_name,out,source)
    return out
end
function M:prepare(source)
    if source.mode=="appearance_only" then
        assert(source.options.appearance_only and source.options.copy_appearance and self.appearance and source.appearance,"仅外观候选不完整")
        self.native.game_method_calls=0
        local manager=assert(sdk.get_managed_singleton("snow.data.EquipDataManager"))
        local plan={source=source,entries={},manager=manager,current=array(field(field(manager,"_PlEquipPack"),"_InventoryIndexList"))}
        local appearance=self.appearance:prepare(source.appearance,plan)
        plan.overwear_slot=appearance.slot;plan.entries[#plan.entries+1]=appearance
        local hunter=Hunter.prepare(self.native,manager,-1,appearance.slot,source.name)
        hunter.backup=self:backup(Hunter.type_name,hunter.dest)
        plan.entries[#plan.entries+1]=hunter;plan.hunter_slot=hunter.slot
        if self.appearance.prepare_binding then
            local binding=self.appearance:prepare_binding(plan)
            if source.options.copy_weapon_visibility then assert(binding,"显示状态绑定不可用") end
            if binding then plan.entries[#plan.entries+1]=binding end
        elseif source.options.copy_weapon_visibility then error("显示状态绑定不可用") end
        return plan
    end
    local wants_appearance=source.options and source.options.copy_appearance==true
    local wants_visibility=source.options and source.options.copy_weapon_visibility==true
    assert(not wants_visibility or wants_appearance,"复制武器显示状态需要开启复制外观")
    assert(not wants_appearance or (self.appearance and source.appearance),"外观候选未就绪，未写入任何装备")
    assert(wants_appearance or source.appearance==nil,"外观选项与候选不一致")
    assert(#source.items==8,"完整装备候选缺失")
    for i=1,8 do
        local item=source.items[i]
        assert(type(item)=="table" and item.candidate,"装备候选包含空项")
        if item.empty then
            assert(i==8 and item.kind=="talisman" and not item.object and source.snapshot.data._talismanParam.empty==true,"空装备候选缺少来源证据")
        else assert(item.object,"装备候选包含空项") end
    end
    self.native.game_method_calls=0
    if wants_appearance and self.appearance.prepare_equipment then self.appearance:prepare_equipment(source) end
    local data=assert(sdk.get_managed_singleton("snow.data.DataManager"))
    local manager=assert(sdk.get_managed_singleton("snow.data.EquipDataManager"))
    local box=field(data,"_PlEquipBox")
    local plan={source=source,entries={},manager=manager,allocated={},current=array(field(field(manager,"_PlEquipPack"),"_InventoryIndexList"))}
    local reserved={}
    plan.reused={}
    local function existing_petalace(candidate)
        local inventory=field(box,"_LvBuffCageInventoryList")
        local items,size=list(inventory,5000)
        local kind,id=field(candidate,"_IdType"),field(candidate,"_IdVal")
        if kind==0 then return nil end
        for i=0,size-1 do
            local obj=items:get_element(i)
            if field(obj,"_IdType")==kind and field(obj,"_IdVal")==id then
                assert(not self.native:call("snow.data.EquipmentInventoryData","isEmpty()",obj),"已有花链状态不一致")
                plan.reused[#plan.reused+1]={inventory=inventory,position=i,dest=obj,kind=kind,id=id,index=field(obj,"<InventoryIndex>k__BackingField")}
                return obj
            end
        end
    end
    local function reserve(list_name)
        local items,size=list(field(box,list_name),5000)
        for i=0,size-1 do
            local obj=items:get_element(i)
            if field(obj,"_IdType")==0 and not reserved[list_name..":"..i] then
                assert(self.native:call("snow.data.EquipmentInventoryData","isEmpty()",obj),"空装备槽判定不一致")
                reserved[list_name..":"..i]=true;return obj
            end
        end
        error("装备箱空间不足")
    end
    for i,item in ipairs(source.items) do
      if not item.empty then
        local existing=item.kind=="petalace" and existing_petalace(item.object)
        local dest=existing or reserve(item.kind=="petalace" and "_LvBuffCageInventoryList" or "_WeaponArmorInventoryList")
        plan.allocated[i]=dest
        if not existing then
        local with_color=wants_appearance and i==1 and self.appearance.tracks_weapon_color==true
        local backup=self:backup("snow.data.EquipmentInventoryData",dest)
        if with_color then require("LoadoutClone.appearance_objects").new(self.native):detach_weapon_color(backup) end
        plan.entries[#plan.entries+1]={kind="equipment",equipment_kind=item.kind,with_color=with_color,dest=dest,object=item.object,before=equipment_state(dest,with_color),backup=backup,index=field(dest,"<InventoryIndex>k__BackingField")}
        end
      end
    end
    if source.insect then
        local dest=reserve("_WeaponArmorInventoryList")
        plan.insect=dest
        plan.entries[#plan.entries+1]={kind="equipment",dest=dest,object=source.insect.object,before=equipment_state(dest),backup=self:backup("snow.data.EquipmentInventoryData",dest),index=field(dest,"<InventoryIndex>k__BackingField")}
    end
    local counts={}
    for _,item in ipairs(source.items) do
        for _,id in ipairs(item.candidate.decorations or {}) do if id>0 then counts[id]=(counts[id] or 0)+1 end end
    end
    local hyakuryu=source.items[1].candidate.target.HyakuryuDecorationsId
    if hyakuryu~=0 and hyakuryu~=1048576 then counts[hyakuryu]=(counts[hyakuryu] or 0)+1 end
    local deco_box=field(data,"_PlDecorationsBox")
    local items,size=list(field(deco_box,"_InventoryDataList"),1024)
    local max_count=self.native:call("snow.data.DecorationsData","get_MaxCountInBox()",nil)
    for id,count in pairs(counts) do
        local dest,empty,dest_index,empty_index
        for i=0,size-1 do
            local obj=items:get_element(i)
            if field(obj,"_Id")==id then dest=obj;dest_index=i;break end
            if not empty and not reserved["deco:"..i] and field(obj,"_Num")==0 and self.native:call("snow.data.DecorationsInventoryData","isEmpty()",obj) then empty=obj;empty_index=i end
        end
        dest=dest or empty;dest_index=dest_index or empty_index;assert(dest,"珠子箱空间不足")
        reserved["deco:"..dest_index]=true
        local before={id=field(dest,"_Id"),count=field(dest,"_Num")}
        assert(before.count+count<=max_count,"珠子数量将超过上限")
        local object=self:backup("snow.data.DecorationsInventoryData",dest)
        self.native:call("snow.data.DecorationsInventoryData","setId(snow.equip.DecorationsId)",object,id)
        object:set_field("_Num",before.count+count)
        plan.entries[#plan.entries+1]={kind="decoration",dest=dest,object=object,before=before,backup=self:backup("snow.data.DecorationsInventoryData",dest),expected={id=id,count=before.count+count}}
    end
    local sets=field(manager,"_PlEquipMySetList")
    local count,get_set=Native.array_access(sets,1024)
    for i=count-1,0,-1 do if not field(get_set(i),"_IsUsing") then plan.slot=i;break end end
    assert(plan.slot,"配装列表没有空位")
    local dest=get_set(plan.slot)
    plan.entries[#plan.entries+1]={kind="loadout",dest=dest,before=set_state(dest),backup=self:backup("snow.equip.PlEquipMySetData",dest),plan=plan}
    if wants_appearance then
        local entry=self.appearance:prepare(source.appearance,plan)
        assert(entry.kind=="appearance" and type(entry.slot)=="number" and entry.slot%1==0 and entry.slot>=0,"外观事务候选无效")
        plan.overwear_slot=entry.slot
        plan.entries[#plan.entries+1]=entry
    end
    local hunter=Hunter.prepare(self.native,manager,plan.slot,plan.overwear_slot,source.name)
    hunter.backup=self:backup(Hunter.type_name,hunter.dest)
    plan.entries[#plan.entries+1]=hunter;plan.hunter_slot=hunter.slot
    if wants_visibility then assert(type(self.appearance.prepare_binding)=="function","武器显示状态服务未就绪") end
    if wants_appearance and self.appearance.prepare_binding then
        local entry=self.appearance:prepare_binding(plan)
        if wants_visibility then assert(entry and entry.kind=="visibility","武器显示状态绑定未就绪") end
        if entry then plan.entries[#plan.entries+1]=entry end
    end
    return plan
end
function M:verify_reused(plan)
    for _,ref in ipairs(plan.reused or {}) do
        local items,size=list(ref.inventory,5000)
        assert(ref.position<size and items:get_element(ref.position)==ref.dest
            and field(ref.dest,"_IdType")==ref.kind and field(ref.dest,"_IdVal")==ref.id
            and field(ref.dest,"<InventoryIndex>k__BackingField")==ref.index,"复用花链已变化，请重试")
    end
end
function M:assert_context(plan)
    self:verify_reused(plan)
    if plan.source.mode=="appearance_only" then
        assert(sdk.get_managed_singleton("snow.data.EquipDataManager")==plan.manager,"装备管理器已变化")
        self.appearance:assert_context(plan.source.appearance,plan)
        return
    end
    assert(self.reader:progression_state()==plan.source.progression,"当前角色大师等级开放状态已变化")
    local list=self.reader:list_members()
    assert(list.session==plan.source.session,"角色或大厅会话已变化")
    local current=self.reader:capture(plan.source.source.key)
    for _,key in ipairs({"_weaponParam","_armorParam","_talismanParam","_lvBuffParam"}) do assert(equal(current.data[key],plan.source.snapshot.data[key]),"目标配装已变化，请重试") end
    for _,key in ipairs({"isMRRelease","switchActionId","switchActionId_MR_1","switchActionId_MR_2"}) do assert(equal(current.data._equipStatusParam[key],plan.source.snapshot.data._equipStatusParam[key]),"目标替换技或大师等级开放状态已变化") end
    assert(sdk.get_managed_singleton("snow.data.EquipDataManager")==plan.manager,"装备管理器已变化")
    if plan.source.appearance then self.appearance:assert_context(plan.source.appearance,plan) end
end
function M:apply(entry)
    local function begin_write()
        entry.write_started=true
        self.write_count=self.write_count+1
    end
    if entry.kind=="equipment" then
        assert(equal(equipment_state(entry.dest,entry.with_color),entry.before),"预留装备槽已变化")
        begin_write()
        self:copy("snow.data.EquipmentInventoryData",entry.dest,entry.object)
        if entry.with_color then require("LoadoutClone.appearance_objects").new(self.native):detach_weapon_color(entry.dest) end
        if entry.equipment_kind=="talisman" then self.native:check_talisman(entry.dest) end
        assert(field(entry.dest,"<InventoryIndex>k__BackingField")==entry.index,"库存下标被改变")
    elseif entry.kind=="decoration" then
        assert(field(entry.dest,"_Id")==entry.before.id and field(entry.dest,"_Num")==entry.before.count,"珠子库存已变化")
        begin_write()
        self:copy("snow.data.DecorationsInventoryData",entry.dest,entry.object)
    elseif entry.kind=="appearance" then
        assert(self.appearance,"外观事务适配器缺失"):apply(entry)
        self.write_count=self.write_count+1
    elseif entry.kind=="visibility" then
        self.appearance:apply_binding(entry)
        self.write_count=self.write_count+1
    elseif entry.kind=="hunter" then
        assert(equal(Hunter.state(entry.dest),entry.before),"预留猎人组合已变化")
        begin_write()
        self:copy(Hunter.type_name,entry.dest,entry.object)
    elseif entry.kind=="loadout" then
        self:verify_reused(entry.plan)
        assert(equal(set_state(entry.dest),entry.before),"配装槽已变化")
        begin_write()
        local plan=entry.plan
        if plan.insect then self.native:call("snow.data.EquipmentInventoryData","setPairInsectInventory(snow.data.EquipmentInventoryData)",plan.allocated[1],plan.insect) end
        local staged=assert(sdk.create_instance("snow.equip.PlEquipMySetData",true)):add_ref()
        self.native:call("snow.equip.PlEquipMySetData",".ctor()",staged)
        for i,obj in ipairs(plan.allocated) do
            self.native:call("snow.data.EquipmentInventoryData[]","Set",field(staged,"<InventoryDataList>k__BackingField"),i-1,obj)
            self.native:call("System.Int32[]","Set",field(staged,"_InventoryIndexList"),i-1,field(obj,"<InventoryIndex>k__BackingField"))
        end
        staged:set_field("_IsUsing",true)
        -- 不截断玩家名称的 UTF-8 字节；配装名使用短固定前缀与槽位。
        staged:set_field("_Name",sdk.create_managed_string(plan.source.name or ("大厅复制 "..(plan.slot+1))))
        self.native:call("snow.equip.PlEquipMySetData","setupParam()",staged)
        for key,values in pairs({_ActionIdList=plan.source.actions,_ActionIdListMR_Red=plan.source.red,_ActionIdListMR_Blue=plan.source.blue}) do
            local target=field(staged,key);assert(#array(target)==#values,"替换技数组长度不一致")
            for i,id in ipairs(values) do self.native:call("snow.data.DataDef.PlWeaponActionId[]","Set",target,i-1,id) end
        end
        entry.expected=set_state(staged)
        self:copy("snow.equip.PlEquipMySetData",entry.dest,staged)
    else error("未知写入条目类型："..tostring(entry.kind))
    end
    if self.fault_after and self.write_count==self.fault_after then error("development injected failure") end
end
function M:verify(plan)
    self:verify_reused(plan)
    if self.fault_on_verify then error("development verification failure") end
    for _,entry in ipairs(plan.entries) do
        if entry.kind=="equipment" then
            local expected=equipment_state(entry.object,entry.with_color)
            local actual=equipment_state(entry.dest,entry.with_color)
            if plan.insect and entry.dest==plan.allocated[1] then expected._PairInsectInventoryIndex=field(plan.insect,"<InventoryIndex>k__BackingField") end
            assert(equal(actual,expected),"新增装备回读不一致")
        elseif entry.kind=="decoration" then
            assert(field(entry.dest,"_Id")==entry.expected.id and field(entry.dest,"_Num")==entry.expected.count,"珠子回读不一致")
        elseif entry.kind=="appearance" then self.appearance:verify(entry)
        elseif entry.kind=="visibility" then self.appearance:verify_binding(entry)
        elseif entry.kind=="hunter" then assert(equal(Hunter.state(entry.dest),entry.expected),"猎人组合回读不一致")
        else assert(equal(set_state(entry.dest),entry.expected),"配装登记回读不一致") end
    end
    assert(equal(array(field(field(plan.manager,"_PlEquipPack"),"_InventoryIndexList")),plan.current),"当前穿戴被改变")
    if plan.source and plan.source.appearance then self.appearance:verify_current(plan) end
    return {slot=plan.slot and plan.slot+1 or nil,hunter_slot=plan.hunter_slot+1,name=plan.source.name or ("大厅复制 "..(plan.hunter_slot+1)),overwear_slot=plan.overwear_slot and plan.overwear_slot+1 or nil,options=plan.source.options}
end
function M:restore(entry)
    if not entry.write_started then return end
    self.restore_count=(self.restore_count or 0)+1
    if entry.kind=="appearance" then return assert(self.appearance,"外观恢复适配器缺失"):restore(entry) end
    if entry.kind=="visibility" then return self.appearance:restore_binding(entry) end
    self:copy(entry.type_name or (entry.kind=="equipment" and "snow.data.EquipmentInventoryData" or entry.kind=="decoration" and "snow.data.DecorationsInventoryData" or "snow.equip.PlEquipMySetData"),entry.dest,entry.backup)
    if entry.with_color then require("LoadoutClone.appearance_objects").new(self.native):detach_weapon_color(entry.dest) end
    if entry.equipment_kind=="talisman" then self.native:check_talisman(entry.dest) end
end
function M:verify_restored(entry)
    if not entry.write_started then return end
    if entry.kind=="visibility" then self.appearance:verify_binding_restored(entry)
    elseif entry.kind=="appearance" then self.appearance:verify_restored(entry)
    elseif entry.kind=="equipment" then assert(equal(equipment_state(entry.dest,entry.with_color),entry.before),"装备恢复回读失败")
    elseif entry.kind=="decoration" then assert(field(entry.dest,"_Id")==entry.before.id and field(entry.dest,"_Num")==entry.before.count,"珠子恢复回读失败")
    elseif entry.kind=="hunter" then assert(equal(Hunter.state(entry.dest),entry.before),"猎人组合恢复回读失败")
    else assert(equal(set_state(entry.dest),entry.before),"配装恢复回读失败") end
end
function M:execute(plan)
    self.native.game_method_calls=0
    local previous=json.load_file("LoadoutClone/transaction.json")
    local cleanup=json.load_file("LoadoutClone/petalace-cleanup-transaction.json")
    if cleanup and (cleanup.status=="in_progress" or cleanup.status=="recovery_failed") then return {ok=false,code="locked",error="花链清理尚未确认恢复，复制已锁定"} end
    if session_locked or self.transaction.locked or (previous and (previous.status=="in_progress" or previous.status=="recovery_failed")) then
        return {ok=false,code="locked",error="上次写入未确认恢复，已锁定。请先检查备份与恢复记录。"}
    end
    self.write_count=0;self.restore_count=0
    local saved,ok=pcall(json.dump_file,"LoadoutClone/transaction.json",{status="in_progress",source=plan.source.key,options=plan.options})
    if not saved or ok~=true then
        return {ok=false,code="journal_failed",error="无法保存事务记录，未写入装备。请检查磁盘空间和目录权限。"}
    end
    local result=self.transaction:execute(plan)
    if self.transaction.locked then session_locked=true end
    saved,ok=pcall(json.dump_file,"LoadoutClone/transaction.json",{status=result.ok and "complete" or result.code=="recovery_failed" and "recovery_failed" or "restored",writes=self.write_count,restores=self.restore_count,result=result,options=plan.options})
    if not saved or ok~=true then
        self.transaction.locked=true;session_locked=true
        return {ok=false,code="journal_failed",error=result.ok and "装备已写入，但事务结果保存失败。已锁定，请勿重复复制；保留日志检查恢复记录。" or "复制失败且事务结果无法保存。已锁定，请保留日志检查恢复记录。",transaction_result=result}
    end
    return result
end
M.equal=equal
M.equipment_state=equipment_state
M.set_state=set_state
return M
