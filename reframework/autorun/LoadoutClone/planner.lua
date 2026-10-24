local Native=require("LoadoutClone.native")
local Decorations=require("LoadoutClone.decorations")
local Augments=require("LoadoutClone.augments")
local M={}
local function clone(t)
    if type(t)~="table" then return t end
    local out={};for k,v in pairs(t) do out[k]=clone(v) end;return out
end
local function skill_map(ids,levels)
    local out={}
    for i,id in ipairs(ids or {}) do if id>0 then out[id]=(out[id] or 0)+levels[i] end end
    return out
end
local function same_skills(a,b)
    for id,lv in pairs(a) do assert(lv==(b[id] or 0),"重建后的技能等级不一致："..id) end
    for id,lv in pairs(b) do assert(lv==(a[id] or 0),"重建后出现额外技能："..id) end
end
local function slot_counts(levels,zero_index)
    local out=zero_index and {0,0,0,0,0} or {0,0,0,0}
    for _,lv in ipairs(levels) do
        assert(lv%1==0 and lv>=0 and lv<=4,"孔位等级无效")
        if lv>0 then local i=lv+(zero_index and 1 or 0);out[i]=out[i]+1 end
    end
    return out
end
local function same_array(a,b,label)
    assert(#a==#b,label.."长度不一致")
    for i,v in ipairs(a) do assert(v==b[i],label.."不一致") end
end
local function yield_phase(phase,part)
    if coroutine.isyieldable() then coroutine.yield({phase=phase,part=part}) end
end
function M.new(reader)
    return setmetatable({reader=reader,native=Native.new()},{__index=M})
end
function M.validate_actions(status,local_mr)
    assert(type(local_mr)=="boolean" and type(status.isMRRelease)=="boolean","大师等级开放状态尚未完整加载")
    assert(local_mr==status.isMRRelease,"无法复制：双方大师等级开放状态不同（仅支持相同类型的猎人）")
    local legacy=status.switchActionId
    assert(type(legacy)=="table" and not legacy.unavailable and #legacy<=3,"目标旧版替换技数据缺失或无效")
    for key,id in pairs(legacy) do
        assert(type(key)=="number" and key%1==0 and key>=1 and key<=#legacy,"旧版替换技数组不连续")
        assert(type(id)=="number" and id%1==0 and id>=0,"目标替换技数据无效")
    end
    for i=1,#legacy do assert(type(legacy[i])=="number","旧版替换技数组不连续") end
    if not local_mr then
        for _,key in ipairs({"switchActionId_MR_1","switchActionId_MR_2"}) do
            local values=status[key]
            assert(values==nil or (type(values)=="table" and (values.unavailable==true or next(values)==nil)),"未开放大师等级但收到两书配置，状态不一致")
        end
        return {legacy[1] or 0,legacy[2] or 0,legacy[3] or 0}
    end
    for _,pair in ipairs({{"switchActionId_MR_1",5},{"switchActionId_MR_2",5}}) do
        local values=status[pair[1]]
        assert(type(values)=="table" and #values==pair[2],"目标替换技数据尚未完整加载，请稍后重试")
        for i=1,pair[2] do local id=values[i];assert(type(id)=="number" and id%1==0 and id>=0,"目标替换技数据无效") end
    end
    -- GUI 的旧版列表可少于三项；原生配装固定三项，0 已实机确认是 ActionId_None。
    -- 先规范化固定长度，绝不把短数组交给原生 copy（该方法按三项读取）。
    return {legacy[1] or 0,legacy[2] or 0,legacy[3] or 0},clone(status.switchActionId_MR_1),clone(status.switchActionId_MR_2)
end
function M.talisman_skills(source_ids,residual)
    local skills,seen={},{}
    for _,id in ipairs(source_ids) do
        if id>0 and residual[id] and residual[id]>0 and not seen[id] then
            skills[#skills+1]={id=id,level=residual[id]};seen[id]=true
        end
    end
    for id,level in pairs(residual) do assert(level<=0 or seen[id],"护石主副技能顺序缺失") end
    assert(#skills<=2,"护石固有技能超过两种")
    return skills
end
function M:prepare(key,options)
    self.native.game_method_calls=0
    local snapshot=self.reader:capture(key)
    assert(snapshot.schema==1,"不支持的快照版本")
    assert(type(snapshot.data._armorParam)=="table" and #snapshot.data._armorParam==5,"目标五件防具尚未完整加载")
    for i=1,5 do assert(type(snapshot.data._armorParam[i])=="table" and not snapshot.data._armorParam[i].unavailable,"目标防具数据缺失") end
    local data=snapshot.data
    local status=data._equipStatusParam
    local progression=self.reader:progression_state()
    local actions,red,blue=M.validate_actions(status,progression)
    if not self.catalog then self.catalog=self.native:read_catalog() end
    local plan={source=snapshot.source,session=snapshot.session,options=clone(options),items={},snapshot=snapshot,red=red,blue=blue,actions=actions,progression=progression}
    local weapon=clone(data._weaponParam)
    local gems,reason=Decorations.resolve_weapon(weapon,self.catalog.decorations)
    assert(gems,"武器珠子无法唯一还原："..tostring(reason))
    local base=self.native:weapon_base(weapon.WeaponId)
    if not options.copy_augments then weapon.CustomEnable=false end
    local candidate,err=Augments.weapon(self.catalog,base,weapon,self.catalog.slot_bonuses,options.allow_illegal_augments)
    assert(candidate,err)
    candidate.target=weapon;candidate.decorations=gems.ids
    local object,result=self.native:build_weapon(candidate)
    same_skills(result.all_skills,skill_map(weapon.EquipSkill,weapon.EquipSkillLv))
    if options.copy_augments then
        for _,field in ipairs({"CustomAddAtk","CustomAddCriticalRate","CustomAddMainElementVal","CustomAddSharpness","CustomAddSlot","CustomAddFireLv"}) do assert(result[field]==weapon[field],"武器炼化重建不一致："..field) end
        -- 无副属性的远端包将副属性增量置零，而原生 getter 仍返回潜在加成。
        if weapon.SubElementValue>0 then assert(result.CustomAddSubElementVal==weapon.CustomAddSubElementVal,"武器副属性不一致") end
        assert(result.atk==weapon.Atk and result.critical==weapon.CriticalRate,"武器基础属性不一致")
        if weapon.CustomEnable then assert(result.capacity==weapon.CustomBuildupCapacity,"武器容量不一致") end
    end
    assert(options.allow_illegal_augments or not result.cheat_check,"游戏判定武器炼化异常")
    plan.items[1]={kind="weapon",object=object,candidate=candidate,verification=result}
    yield_phase("armor",1)
    for i,original in ipairs(data._armorParam) do
        local target=clone(original)
        local base=self.native:armor_base(target.ArmorId)
        local intrinsic=skill_map(base._SkillList,base._SkillLvList)
        local deltas=skill_map(target.CustomSkillIdList,target.CustomSkillLvList)
        for id,lv in pairs(deltas) do intrinsic[id]=(intrinsic[id] or 0)+lv;assert(intrinsic[id]>=0,"炼化移除技能超过固有等级") end
        local gems,reason=Decorations.resolve(target,self.catalog.decorations,{base_skills=intrinsic})
        assert(gems,"防具珠子无法唯一还原："..tostring(reason))
        local expected_skills=skill_map(target.SkillIdList,target.SkillLv)
        local entries={}
        if options.copy_augments and target.CustomEnable then
            local vector={defense=target.CustomAddDef,slots=target.CustomAddSlot}
            for j,lv in ipairs(target.CustomAddReg) do vector["resist"..j]=lv end
            for id,lv in pairs(deltas) do vector["skill"..id]=lv end
            local solution,reason
            if options.allow_illegal_augments then
                solution,reason=Augments.relaxed_armor(self.catalog,base,vector,deltas)
            else solution,reason=Augments.legal_armor(self.catalog,base,vector,deltas) end
            assert(solution,({"头部","胸部","腕部","腰部","腿部"})[i].."："..(reason or "找不到效果一致的防具炼化组合"))
            entries=solution.entries
            -- 重建采用普通炼化条目池，内部炼化方式允许不同。
            target.CustomBuildupType=0
        elseif not options.copy_augments then
            target.CustomEnable=false;target.CustomBuildupType=0
            target.defValue=target.defValue-target.CustomAddDef
            target.CustomAddDef=0;target.CustomAddSlot=0;target.CustomAddReg={0,0,0,0,0}
            target.SlotLvType=target.OrgSlotLvType
            assert(Decorations.check_slots(target.DecoLvType,target.SlotLvType),"取消炼化后，基础孔位装不下原珠子")
            for id,lv in pairs(deltas) do expected_skills[id]=(expected_skills[id] or 0)-lv end
        end
        local candidate={target=target,entries=entries,decorations=gems.ids}
        local object,result=self.native:build_armor(candidate)
        assert(result.defense==target.defValue and result.custom_defense==target.CustomAddDef and result.custom_slots==target.CustomAddSlot,"防具属性重建不一致")
        same_array(result.resist,target.CustomAddReg,"炼化耐性")
        same_array(result.slot_counts,slot_counts(target.SlotLvType),"防具孔位")
        same_skills(result.all_skills,expected_skills)
        assert(options.allow_illegal_augments or not result.cheat_check,"游戏判定防具炼化异常")
        plan.items[i+1]={kind="armor",object=object,candidate=candidate,verification=result}
        yield_phase("armor",i+1)
    end
    local charm=data._talismanParam
    if charm and charm.empty==true then
        plan.items[8]={kind="talisman",empty=true,candidate={}}
    else
    local gems,reason=Decorations.resolve(charm,self.catalog.decorations,{max_residual_skills=2})
    assert(gems,"护石无法唯一还原："..tostring(reason))
    local skills=M.talisman_skills(charm.SkillIdList,gems.residual_skills)
    local candidate={target=charm,skills=skills,decorations=gems.ids}
    local object,result=self.native:build_talisman(candidate)
    same_array(result.slots,slot_counts(charm.SlotLvType,true),"护石孔位")
    same_skills(result.all_skills,skill_map(charm.SkillIdList,charm.SkillLv))
    plan.items[8]={kind="talisman",object=object,candidate=candidate,verification=result}
    end
    plan.petalace_id=assert(data._lvBuffParam.id)
    plan.items[7]={kind="petalace",object=self.native:build_simple("petalace",plan.petalace_id),candidate={}}
    plan.insect_id=weapon.insectId
    if weapon.isEnabledInsect then
        assert(weapon.insectId>0,"猎虫数据缺失")
        plan.insect={kind="insect",object=self.native:build_simple("insect",weapon.insectId),candidate={}}
    end
    return plan
end
return M
