-- 游戏适配器：规则读取和未入库的候选对象。库存提交由 writer 独立负责。
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
local function array_access(v,max)
    -- 原生数组可能以普通 REManagedObject 包装返回，没有 Lua get_size/get_element。
    -- 临时返回数组还可能是 -1 引用；读取前持有，再用已验证的原生数组契约。
    v:add_ref()
    local td=v:get_type_definition();assert(td:is_array(),"expected native array")
    local length=assert(sdk.find_type_definition("System.Array"):get_method("get_Length()"))
    local get=assert(td:get_method("Get(System.Int32)"),td:get_full_name())
    local n=scalar(length:call(v));assert(n>=0 and n<=max,"array too large")
    return n,function(i) return get:call(v,i) end
end
local function array(v)
    local n,get=array_access(v,512)
    local out={};for i=0,n-1 do out[i+1]=scalar(get(i)) end;return out
end
function M.new()
    return setmetatable({game_method_calls=0},{__index=M})
end
function M:call(type_name,signature,owner,...)
    self.game_method_calls=self.game_method_calls+1
    assert(self.game_method_calls<=4096,"native operation budget")
    local t=assert(sdk.find_type_definition(type_name),type_name)
    local method=assert(t:get_method(signature),signature)
    return method:call(owner,...)
end
M.field=field
M.array=array
M.array_access=array_access
M.scalar=scalar
function M.skills(native)
    local out={}
    local skills=field(native,"<AllSkillDataList>k__BackingField")
    local count,get=array_access(skills,64)
    for i=0,count-1 do
        local skill=get(i)
        if skill then
            local id=field(skill,"<EquipSkillId>k__BackingField")
            if id>0 then
                local sum=0;for _,lv in ipairs(array(field(skill,"<LvList>k__BackingField"))) do sum=sum+lv end
                if sum>0 then out[id]=(out[id] or 0)+sum end
            end
        end
    end
    return out
end
function M:armor_base(id)
    local base=self:call("snow.data.DataShortcut","getArmorBaseData(snow.data.DataDef.PlArmorId)",nil,id)
    local p=field(base,"<BaseUserDataParam>k__BackingField")
    assert(field(p,"_Id")==id and field(p,"_IsValid"),"invalid armor base")
    local out={}
    for _,key in ipairs({"_Id","_CustomTableNo","_CustomCost"}) do out[key]=field(p,key) end
    for _,key in ipairs({"_SkillList","_SkillLvList","_DecorationsNumList"}) do out[key]=array(field(p,key)) end
    return out
end
function M:weapon_base(id)
    local native=self:call("snow.data.DataShortcut","getPlainWeaponData(snow.data.ContentsIdSystem.WeaponId)",nil,id)
    assert(native,"weapon base missing")
    -- 工厂返回新建对象；Lua 局部变量不保证 RE 引用计数存活。
    native:add_ref()
    return {id=id,table=self:call("snow.data.WeaponData","get_CustomTableNo()",native),
        cost=self:call("snow.data.WeaponData","get_CustomCost()",native),
        max_add_cost=self:call("snow.data.WeaponData","get_CustomAddCostMax()",native),
        slots=array(self:call("snow.data.WeaponData","get_DecorationSlotNumList()",native))}
end
function M:read_catalog()
    local catalog=require("LoadoutClone.reader").new():read_catalog()
    catalog.decorations={}
    local enum=assert(sdk.find_type_definition("snow.equip.DecorationsId"))
    local count=0
    for _,f in ipairs(enum:get_fields()) do
        if f:is_static() and f:is_literal() and f:get_name():match("^Deco_%d+$") then
            count=count+1;assert(count<=1024,"decoration catalogue limit")
            local id=f:get_data(nil)
            local obj=assert(sdk.create_instance("snow.data.DecorationsData",true)):add_ref()
            self:call("snow.data.DecorationsData",".ctor(snow.equip.DecorationsId)",obj,id)
            local base=obj:get_field("<BaseData>k__BackingField")
            if base then
                local p=field(base,"_Param");local common=field(base,"_ParamBase")
                assert(field(common,"_Id")==id,"decoration ID mismatch")
                catalog.decorations[#catalog.decorations+1]={id=id,level=field(p,"_DecorationLv"),color=field(common,"_IconColor"),
                    skills=array(field(p,"_SkillIdList")),levels=array(field(p,"_SkillLvList"))}
            end
            if count%8==0 and coroutine.isyieldable() then coroutine.yield({phase="catalog",done=count}) end
        end
    end
    local module=assert(sdk.get_managed_singleton("snow.data.CustomBuildupModule"))
    local bonuses=field(field(module,"_SlotBonusUserData"),"_Param")
    catalog.slot_bonuses={}
    local count,get=array_access(bonuses,1024)
    for i=0,count-1 do
        local row=get(i)
        catalog.slot_bonuses[#catalog.slot_bonuses+1]={table=field(row,"_TableNo"),id=field(row,"_Id"),categories=array(field(row,"_CategoryId")),values=array(field(row,"_ValueTable"))}
    end
    return catalog
end
function M:build_armor(candidate)
    local report={}
    local function call(...) return self:call(...) end

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
        local _,get_entry=array_access(entries,7)
        for i,row in ipairs(candidate.entries) do
            assert(row.id>=1 and row.id<165 and row.value_index>=0 and row.value_index<20 and row.skill>=0 and row.skill<256,"invalid augment row")
            local item=assert(get_entry(i-1))
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
        result.all_skills=M.skills(native)
        return detached,result
end
function M:build_weapon(candidate)
    local report={}
    local function call(...) return self:call(...) end
        local target=assert(candidate.target)
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
        local _,get_entry=array_access(entries,7)
        for i,row in ipairs(candidate.entries) do
            local item=assert(get_entry(i-1))
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
        out.all_skills=M.skills(native)
        return detached,out
end
function M:check_talisman(obj)
    self:call("snow.data.EquipmentInventoryData","updateCheatBitFlag()",obj)
    for _,pair in ipairs({{"_TalismanDecoSlotNumList","getTalismanDecoSlotNumList()"},
        {"_TalismanSkillIdList","getTalismanSkillIdList()"},{"_TalismanSkillLvList","getTalismanSkillLvList()"}}) do
        local expected=array(field(obj,pair[1]))
        local effective=array(self:call("snow.data.EquipmentInventoryData",pair[2],obj))
        assert(#expected==#effective,"护石有效数据长度不一致")
        for i,value in ipairs(expected) do assert(value==effective[i],"护石主副技能或孔位未通过游戏校验") end
    end
end
function M:build_talisman(candidate)
    local report={}
    local function call(...) return self:call(...) end
        local target=candidate.target
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
        self:check_talisman(obj)
        local native=call("snow.data.EquipmentInventoryData","getPlTalismanData()",obj)
        native:add_ref()
        call("snow.data.PlTalismanData","updateDeco()",native)
        call("snow.data.PlTalismanData","updateSkillDataList()",native)
        local skills=field(native,"<AllSkillDataList>k__BackingField")
        local out={ids=array(field(obj,"_TalismanSkillIdList")),levels=array(field(obj,"_TalismanSkillLvList")),slots=array(field(obj,"_TalismanDecoSlotNumList")),skills={}}
        local count,get=array_access(skills,64)
        for i=0,count-1 do
            local skill=get(i)
            if skill then
                local id=field(skill,"<EquipSkillId>k__BackingField")
                if id>0 then out.skills[tostring(id)]=array(field(skill,"<LvList>k__BackingField")) end
            end
        end
        out.all_skills=M.skills(native)
        return obj,out
end
function M:build_simple(kind,id)
    assert(type(id)=="number" and id>0 and id%1==0,"invalid equipment ID")
    local obj=assert(sdk.create_instance("snow.data.EquipmentInventoryData",true)):add_ref()
    self:call("snow.data.EquipmentInventoryData",".ctor()",obj)
    local enum=kind=="petalace" and "snow.data.ContentsIdSystem.LvBuffCageId" or "snow.data.ContentsIdSystem.WeaponId"
    self:call("snow.data.EquipmentInventoryData","setId("..enum..")",obj,id)
    local method=kind=="petalace" and "getLvBuffCageData()" or "getInsectData()"
    local native=self:call("snow.data.EquipmentInventoryData",method,obj)
    assert(native,"附属装备 ID 无效")
    if kind=="petalace" then assert(field(native,"<ValidFlag>k__BackingField"),"花链无效") end
    return obj
end
return M
