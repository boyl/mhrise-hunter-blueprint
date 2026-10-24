-- 纯数据求解：单条炼化作用于一个增量维度；最终合法性仍须原生复核。
local M={}
local function copy_append(a,b)
    local out={};for _,v in ipairs(a) do out[#out+1]=v end
    for _,v in ipairs(b) do out[#out+1]=v end;return out
end
function M.solve(candidates,target,max_count,budget,accept)
    assert(type(max_count)=="number" and max_count%1==0 and max_count>=0 and max_count<=7,"invalid augment capacity")
    local dimensions,groups,seen={},{},{}
    for key,value in pairs(target) do
        assert(type(value)=="number" and value%1==0 and math.abs(value)<=1000,"invalid target delta")
        dimensions[#dimensions+1]=key;groups[key]={};seen[key]=true
    end
    table.sort(dimensions)
    for _,c in ipairs(candidates) do
        assert(type(c.cost)=="number" and c.cost%1==0 and math.abs(c.cost)<=1000,"invalid cost")
        assert(type(c.value)=="number" and c.value%1==0 and math.abs(c.value)<=1000,"invalid candidate")
        if seen[c.dimension] and c.value~=0 then groups[c.dimension][#groups[c.dimension]+1]=c end
    end
    local steps=0
    local function tick()
        steps=steps+1
        if steps%2000==0 and coroutine.isyieldable() then coroutine.yield({phase="augment_search",steps=steps}) end
        assert(steps<=1000000,"炼化求解超过计算预算")
    end
    local combined={[0]={cost=0,entries={}}}
    for _,dimension in ipairs(dimensions) do
        local states={[0]={sum=0,cost=0,entries={}}}
        local choices={}
        if target[dimension]==0 then choices[0]=states[0] end
        for count=1,max_count do
            local next_states={}
            for _,previous in pairs(states) do
                for _,candidate in ipairs(groups[dimension]) do
                    tick()
                    local next_sum=previous.sum+candidate.value
                    local cost=previous.cost+candidate.cost
                    local key=accept and (next_sum..":"..cost) or next_sum
                    if not next_states[key] or cost<next_states[key].cost then
                        next_states[key]={sum=next_sum,cost=cost,entries=copy_append(previous.entries,{candidate})}
                    end
                end
            end
            states=next_states
            if accept then
                for _,state in pairs(states) do
                    if state.sum==target[dimension] then choices[count..":"..state.cost]={count=count,cost=state.cost,entries=state.entries} end
                end
            else choices[count]=states[target[dimension]] end
        end
        local next_combined={}
        for used_key,a in pairs(combined) do
            local used=a.count or used_key
            for count_key,b in pairs(choices) do
                local count=b.count or count_key
                if used+count<=max_count then
                    local n=used+count;local cost=a.cost+b.cost
                    local key=accept and (n..":"..cost) or n
                    if not next_combined[key] or cost<next_combined[key].cost then
                        next_combined[key]={count=n,cost=cost,entries=copy_append(a.entries,b.entries)}
                    end
                end
            end
        end
        combined=next_combined
    end
    if accept then
        local best
        for _,r in pairs(combined) do
            if (budget==nil or r.cost<=budget) and accept(r) and (not best or #r.entries<#best.entries or (#r.entries==#best.entries and r.cost<best.cost)) then best=r end
        end
        if best then best.steps=steps;return best end
        return nil,"no_equivalent_combination"
    end
    for count=0,max_count do
        local result=combined[count]
        if result and (budget==nil or result.cost<=budget) then result.steps=steps;return result end
    end
    return nil,"no_equivalent_combination"
end
-- 映射依据本地 Qurious Cheating 的条目含义，与当前原生表交叉核对。
function M.armor_candidates(catalog,base,target_skills,allow_illegal)
    local lot,skill_costs={},{}
    for _,r in ipairs(catalog.armor_lottery) do if r.table==base._CustomTableNo and r.weight>0 then lot[r.id]=true end end
    for _,r in ipairs(catalog.skill_costs) do skill_costs[r.skill]=r.cost end
    local out={}
    for _,r in ipairs(catalog.augments) do
        if r.table==base._CustomTableNo and (allow_illegal or lot[r.id]) then
            local dimension
            if r.id>=59 and r.id<=88 then dimension="defense"
            elseif r.id>=89 and r.id<=138 then dimension="resist"..(math.floor((r.id-89)/10)+1)
            elseif r.id>=139 and r.id<=143 then dimension="slots" end
            for index,value in ipairs(r.values) do
                if value~=0 then
                    if dimension then
                        out[#out+1]={id=r.id,value_index=index-1,skill=0,dimension=dimension,value=value,cost=r.cost}
                    elseif r.id>=144 and r.id<=149 then
                        for skill,delta in pairs(target_skills) do
                            local permitted=allow_illegal or (r.id~=149 and skill_costs[skill]==r.cost) or r.id==149
                            if permitted and delta*value>0 then
                                out[#out+1]={id=r.id,value_index=index-1,skill=skill,dimension="skill"..skill,value=value,cost=r.cost}
                            end
                        end
                    end
                end
            end
        end
    end
    return out
end
function M.legal_armor(catalog,base,vector,deltas)
    local original={};local types=0
    for _,id in ipairs(base._SkillList) do if id>0 and not original[id] then original[id]=true;types=types+1 end end
    for id,lv in pairs(deltas) do if lv>0 and not original[id] then types=types+1 end end
    if types>5 then return nil,"炼化技能种类超过正常生成上限" end
    local candidates={}
    for _,c in ipairs(M.armor_candidates(catalog,base,deltas,false)) do
        -- 游戏会撤销合计为零的同类条目；不以零和条目填满六次抽选。
        if vector[c.dimension] and vector[c.dimension]~=0 then candidates[#candidates+1]=c end
    end
    -- 常规抽选最多六条；预算正好耗尽可提前结束。
    local direct=M.solve(candidates,vector,6,base._CustomCost,function(r)
        local remaining=base._CustomCost-r.cost
        return remaining==0 or (#r.entries==6 and remaining==1)
    end)
    if direct then
        table.sort(direct.entries,function(a,b) return a.cost<b.cost end)
        return direct
    end
    -- 最后一条只能使用剩余预算的正防御补偿，不允许第七条继续加技能。
    local compensations={}
    for _,row in ipairs(catalog.augments) do
        if row.table==base._CustomTableNo and row.id>=70 and row.id<=72 and row.cost>0 then
            for index,value in ipairs(row.values) do if value>0 then
                compensations[#compensations+1]={id=row.id,value_index=index-1,skill=0,dimension="defense",value=value,cost=row.cost}
            end end
        end
    end
    for _,last in ipairs(compensations) do
        local prefix_target={};for k,v in pairs(vector) do prefix_target[k]=v end
        prefix_target.defense=prefix_target.defense-last.value
        local prefix=M.solve(candidates,prefix_target,6,base._CustomCost-last.cost,function(r)
            return #r.entries==6 and last.cost==math.min(4,base._CustomCost-r.cost)
        end)
        if prefix then
            local remaining=base._CustomCost-prefix.cost
            local best_cost=0
            for _,c in ipairs(compensations) do if c.cost<=remaining and c.cost>best_cost then best_cost=c.cost end end
            if last.cost==best_cost then
                table.sort(prefix.entries,function(a,b) return a.cost<b.cost end)
                prefix.entries[#prefix.entries+1]=last;prefix.cost=prefix.cost+last.cost
                return prefix
            end
        end
    end
    return nil,"无法证明存在符合正常生成限制的等效炼化"
end
function M.relaxed_armor(catalog,base,vector,deltas)
    -- 仅用于用户显式选择放宽规则时；优先保留正常条目池和预算。
    local candidates=M.armor_candidates(catalog,base,deltas,false)
    local result=M.solve(candidates,vector,7,base._CustomCost)
    if result then return result end
    return M.solve(M.armor_candidates(catalog,base,deltas,true),vector,7,nil)
end
function M.weapon(catalog,base,part,slot_bonuses,allow_illegal)
    if not part.CustomEnable then return {entries={},open_ids={},cost=0} end
    local capacity=part.CustomBuildupCapacity
    assert(type(capacity)=="number" and capacity%1==0 and capacity>=base.cost and capacity<=base.cost+base.max_add_cost,"武器炼化容量无效")
    local map={[1]="CustomAddAtk",[2]="CustomAddCriticalRate",[3]="CustomAddMainElementVal",[4]="CustomAddMainElementVal",[5]="CustomAddSharpness",[6]="CustomAddSlot",[9]="CustomAddFireLv"}
    local remaining={}
    for _,key in pairs(map) do remaining[key]=part[key] end
    local rows,allowed,opens={},{},{}
    for _,r in ipairs(catalog.augments) do if r.table==base.table then rows[r.id]=r end end
    for _,group in ipairs(catalog.weapon_tables) do
        if group.table==base.table then
            for _,id in ipairs(group.ids) do if id>0 then allowed[id]=true end end
        end
    end
    local to_open=capacity-base.cost
    for id=49,55 do
        if to_open>0 then
            assert(allowed[id] and rows[id],"武器扩容条目缺失")
            opens[#opens+1]=id;to_open=to_open-1
            for _,bonus in ipairs(slot_bonuses) do
                if bonus.table==base.table and bonus.id==id then
                    for i,category in ipairs(bonus.categories) do
                        if category>0 then
                            local key=assert(map[category],"未知扩容加成类别")
                            remaining[key]=remaining[key]-bonus.values[i]
                        end
                    end
                end
            end
        end
    end
    assert(to_open==0,"不支持的武器扩容数")
    local entries,cost={},0
    local done={}
    for _,category in ipairs({1,2,3,4,5,6,9}) do
        local key=map[category]
        if not done[key] and remaining[key]~=0 then
            local best
            for _,r in pairs(rows) do
                if allowed[r.id] and map[r.category]==key and r.values[1]==remaining[key] then
                    if not best or r.cost<best.cost or (r.cost==best.cost and r.id<best.id) then best=r end
                end
            end
            if not best then return nil,"武器炼化效果无对应条目："..key end
            entries[#entries+1]={id=best.id,value_index=0,skill=0}
            cost=cost+best.cost
            for _,r in pairs(rows) do if allowed[r.id] and r.category==best.category and r.level<=best.level then opens[#opens+1]=r.id end end
        end
        done[key]=true
    end
    if not allow_illegal and cost>capacity then return nil,"武器炼化超出预算" end
    table.sort(opens)
    return {entries=entries,open_ids=opens,cost=cost}
end
return M
