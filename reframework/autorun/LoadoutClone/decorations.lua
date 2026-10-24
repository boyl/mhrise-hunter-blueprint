-- 从孔位等级、颜色和技能联合求解；多解不能冒充精确复制。
local M={}
local function integer(v,min,max)
    return type(v)=="number" and v%1==0 and v>=min and v<=max
end
function M.resolve(part,catalog,options)
    options=options or {}
    local levels,colors=part.DecoLvType,part.SlotIconColor
    assert(type(levels)=="table" and #levels==3 and type(colors)=="table" and #colors==3,"珠子孔位数据不完整")
    local ids=part.SkillIdList or part.EquipSkill or {}
    local lvs=part.SkillLv or part.EquipSkillLv or {}
    local total,allowed={},{}
    for i,id in ipairs(ids) do
        assert(integer(id,0,65535) and integer(lvs[i],0,255),"技能数值无效")
        if id>0 then
            total[id]=(total[id] or 0)+lvs[i]
            if not part.DecoSkillEquipUp or part.DecoSkillEquipUp[i] then allowed[id]=true end
        end
    end
    local candidates={}
    for slot=1,3 do
        assert(integer(levels[slot],0,4),"珠子等级无效")
        candidates[slot]={}
        if levels[slot]==0 then candidates[slot][1]={id=0,skills={},levels={}}
        else
            for _,d in ipairs(catalog) do
                if d.level==levels[slot] and d.color==colors[slot] then
                    local fits=true
                    for i,id in ipairs(d.skills) do
                        if id>0 and (not allowed[id] or (total[id] or 0)<d.levels[i]) then fits=false end
                    end
                    if fits then candidates[slot][#candidates[slot]+1]=d end
                end
            end
        end
        if #candidates[slot]==0 then return nil,"missing_decoration" end
    end
    local solutions,chosen,spent={}, {}, {}
    local signatures={}
    local nodes=0
    local function search(slot)
        nodes=nodes+1
        if nodes>4096 then error("珠子求解超过计算预算") end
        if #solutions>1 then return end
        if slot==4 then
            local residual={};local skill_count=0
            for id,lv in pairs(total) do
                local remaining=lv-(spent[id] or 0)
                if remaining>0 then residual[id]=remaining;skill_count=skill_count+1 end
                if options.base_skills and remaining~=(options.base_skills[id] or 0) then return end
            end
            if options.base_skills then
                for id,lv in pairs(options.base_skills) do if (residual[id] or 0)~=lv then return end end
            end
            if options.max_residual_skills and skill_count>options.max_residual_skills then return end
            local sorted={chosen[1],chosen[2],chosen[3]};table.sort(sorted)
            local signature=table.concat(sorted,",")
            if not signatures[signature] then
                signatures[signature]=true
                solutions[#solutions+1]={ids={chosen[1],chosen[2],chosen[3]},residual_skills=residual}
            end
            return
        end
        for _,d in ipairs(candidates[slot]) do
            local fits=true
            for i,id in ipairs(d.skills) do
                if id>0 and (spent[id] or 0)+d.levels[i]>(total[id] or 0) then fits=false end
            end
            if fits then
                chosen[slot]=d.id
                for i,id in ipairs(d.skills) do if id>0 then spent[id]=(spent[id] or 0)+d.levels[i] end end
                search(slot+1)
                for i,id in ipairs(d.skills) do if id>0 then spent[id]=spent[id]-d.levels[i] end end
            end
        end
    end
    search(1)
    if #solutions==0 then return nil,"no_solution" end
    if #solutions>1 then return nil,"ambiguous_decoration" end
    return solutions[1]
end
function M.check_slots(deco_levels,slot_levels)
    assert(#deco_levels==3 and #slot_levels==3,"slot count")
    for i=1,3 do
        if not integer(deco_levels[i],0,4) or not integer(slot_levels[i],0,4) then return false end
        if deco_levels[i]>slot_levels[i] then return false end
    end
    return true
end
return M
