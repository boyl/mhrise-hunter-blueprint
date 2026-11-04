-- 只读边界：基于本机 build 17920865 元数据；不调用游戏写入方法。
local M={}
local scalar={['System.Boolean']=true,['System.Int32']=true,['System.UInt32']=true,
    ['System.Single']=true,['System.Byte']=true,['System.SByte']=true,['System.UInt16']=true}
local packet_types={
    ['snow.gui.EquipStatusParamManager.ParamPacket']=true,
    ['snow.gui.define.EquipStatusParam']=true,
    ['snow.gui.define.WeaponDataParam']=true,
    ['snow.gui.define.ArmorDataParam']=true,
    ['snow.gui.define.PlTalismanParam']=true,
    ['snow.gui.define.LvBuffDataParam']=true,
}
local function required(obj,key)
    assert(obj,"对象尚未加载: "..key)
    local value=obj:get_field(key)
    assert(value~=nil,"字段尚未加载: "..key)
    return value
end
local function scalar_value(value)
    if type(value)~="userdata" then return value end
    local t=value:get_type_definition()
    if scalar[t:get_full_name()] then return required(value,"mValue") end
    local field=t:get_field("value__")
    assert(field,"不支持的数值类型: "..t:get_full_name())
    return field:get_data(value)
end
local function array_size(value,max)
    local size=value:get_size()
    assert(size>=0 and size<=max,"数组长度超出已验证范围: "..tostring(size).." > "..max)
    return size
end
local function guid(obj)
    local parts={}
    for _,key in ipairs({'mData1','mData2','mData3','mData4_0','mData4_1','mData4_2','mData4_3','mData4_4','mData4_5','mData4_6','mData4_7'}) do
        parts[#parts+1]=tostring(required(obj,key))
    end
    return table.concat(parts,"-")
end
local function identity(hunter)
    return tostring(required(hunter,"_NetworkId"))..":"..guid(required(hunter,"_HunterUniqueId"))
end
function M.new() return setmetatable({},{__index=M}) end
function M:progression_state()
    local lobby=assert(sdk.get_managed_singleton("snow.LobbyManager"),"当前角色尚未就绪")
    local mine=required(lobby,"_myselfIndex")
    local hunters=required(lobby,"_hunterInfo")
    assert(mine>=0 and mine<array_size(hunters,16),"当前角色索引无效")
    local hunter=required(hunters:get_element(mine),"_name")
    local manager=assert(sdk.get_managed_singleton("snow.gui.EquipStatusParamManager"))
    local packets=required(manager,"_lobbyParam")
    assert(mine<array_size(packets,16),"当前角色配装尚未加载")
    local status=required(packets:get_element(mine),"_equipStatusParam")
    assert(required(status,"name")==hunter,"当前角色状态尚未对应")
    local enabled=scalar_value(required(status,"isMRRelease"))
    assert(type(enabled)=="boolean","当前角色大师等级状态无效")
    return enabled
end
function M:list_members()
    local lobby=sdk.get_managed_singleton("snow.LobbyManager")
    if not lobby then return {session=nil,members={}} end
    local hunters=required(lobby,"_hunterInfo")
    local mine=required(lobby,"_myselfIndex")
    local size=array_size(hunters,16)
    if mine<0 or mine>=size then return {session=nil,members={}} end
    local local_hunter=hunters:get_element(mine)
    if not local_hunter then return {session=nil,members={}} end
    local session=identity(local_hunter)
    local result={session=session,members={}}
    for i=0,size-1 do
        local hunter=hunters:get_element(i)
        -- 实机确认离开后该槽为 nil；currentAliveLobbyPlayer 会排除正在任务中的成员。
        if i~=mine and hunter~=nil then
            local member_index=required(hunter,"_memberIndex")
            assert(member_index==i,"大厅成员索引不一致")
            result.members[#result.members+1]={key=session.."/"..identity(hunter),index=i,
                name=required(hunter,"_name"),rank=required(hunter,"_hunterRank"),master_rank=required(hunter,"_masterRank")}
        end
    end
    return result
end
function M.plain(value)
    local budget=6000
    local function plain(value,depth)
        budget=budget-1
        assert(budget>=0 and depth<=8,"配装数据超出读取预算")
        if value==nil then return {unavailable=true} end
        if type(value)~="userdata" then return value end
        local t=value:get_type_definition()
        local name=t:get_full_name()
        if scalar[name] or t:get_field("value__") then return scalar_value(value) end
        if name:sub(-2)=="[]" then
            local result={}
            for i=0,array_size(value,512)-1 do result[i+1]=plain(value:get_element(i),depth+1) end
            return result
        end
        if not packet_types[name] then return {unavailable=true,type=name} end
        local result={}
        for _,field in ipairs(t:get_fields()) do
            if not field:is_static() then
                local field_name=field:get_name()
                -- 外观与非配装项不进入快照。
                if not field_name:find("overwear") then result[field_name]=plain(field:get_data(value),depth+1) end
            end
        end
        return result
    end
    return plain(value,0)
end
function M:capture(key)
    local list=self:list_members()
    local target
    for _,member in ipairs(list.members) do if member.key==key then target=member;break end end
    assert(target,"目标玩家已离开大厅")
    local manager=sdk.get_managed_singleton("snow.gui.EquipStatusParamManager")
    local packets=required(manager,"_lobbyParam")
    assert(target.index<array_size(packets,16),"目标装备数据未加载")
    local packet=packets:get_element(target.index)
    assert(packet,"目标装备数据未加载")
    local data=M.plain(packet)
    -- 完整配装包中空护石对象表示未装备；保留空位，不凭空制造护石。
    if packet:get_field("_talismanParam")==nil then data._talismanParam={empty=true} end
    local status=data._equipStatusParam
    assert(status and not status.unavailable and status.name==target.name,"装备缓存与选中玩家尚未对应")
    local still_present=false
    for _,member in ipairs(self:list_members().members) do if member.key==key then still_present=true end end
    assert(still_present,"读取期间目标玩家已离开")
    local missing={"普通珠子原始 ID", "装备实例与炼化原始条目"}
    local red=status.switchActionId_MR_1
    local blue=status.switchActionId_MR_2
    if type(red)~="table" or #red~=5 or type(blue)~="table" or #blue~=5 then missing[#missing+1]="完整朱／苍书替换技" end
    return {schema=1,source=target,session=list.session,data=data,complete=false,missing=missing,
        message="已读取显示数据；尚不能保证完整克隆。"}
end

-- 仅由开发探针显式调用：读取原生珠子／炼化规则，评估能否唯一重建。
function M:read_catalog()
    local function numbers(array)
        local out={}
        for i=0,array_size(array,1024)-1 do out[i+1]=scalar_value(array:get_element(i)) end
        return out
    end
    local manager=sdk.get_managed_singleton("snow.data.DataManager")
    local box=required(manager,"_PlDecorationsBox")
    local list=required(box,"<UiDecorationDataList>k__BackingField")
    local size=required(list,"mSize")
    assert(size>=0 and size<=1024,"珠子目录超出预算")
    local items=required(list,"mItems")
    local result={decorations={},augments={}}
    for i=0,size-1 do
        local item=items:get_element(i)
        local base=required(item,"<BaseData>k__BackingField")
        local normal=base:get_field("_Param")
        if normal then
            local common=required(base,"_ParamBase")
            result.decorations[#result.decorations+1]={id=required(common,"_Id"),level=required(normal,"_DecorationLv"),
                color=required(common,"_IconColor"),skills=numbers(required(normal,"_SkillIdList")),levels=numbers(required(normal,"_SkillLvList"))}
        end
    end
    local custom=sdk.get_managed_singleton("snow.data.CustomBuildupModule")
    -- 类型及字段已由 metadata-013 实机确认；只读资源，不调用抽选函数。
    local function rows(resource, columns)
        local array=required(required(custom,resource),"_Param")
        local out={}
        for i=0,array_size(array,4096)-1 do
            local item=array:get_element(i)
            local row={}
            for _,column in ipairs(columns) do
                local value=required(item,column[2])
                row[column[1]]=column[3] and numbers(value) or scalar_value(value)
            end
            out[#out+1]=row
        end
        return out
    end
    result.armor_lottery=rows("_ArmorUserData",{{"table","_TableNo"},{"category","_CategoryId"},{"id","_Id"},{"weight","_LotNum"}})
    result.category_lottery=rows("_ArmorCategoryLotUserData",{{"table","_TableNo"},{"weights","_LotNum",true}})
    result.skill_costs=rows("_EquipSkillDetailUserData",{{"skill","_SkillId"},{"cost","_Cost"}})
    result.weapon_tables=rows("_WeaponUserData",{{"table","_TableNo"},{"category","_CategoryId"},{"ids","_IdTable",true}})
    local groups=required(custom,"<BaseDataList>k__BackingField")
    for g=0,array_size(groups,165)-1 do
        local group=groups:get_element(g)
        if group then
            for i=0,array_size(group,256)-1 do
                local item=group:get_element(i)
                if item then
                    local p=required(item,"_BaseParam")
                    result.augments[#result.augments+1]={table=required(p,"_TableNo"),id=required(p,"_Id"),
                        category=required(p,"_CategoryId"),level=required(p,"_Lv"),cost=required(p,"_Cost"),
                        values=numbers(required(p,"_ValueTable"))}
                end
            end
        end
    end
    return result
end
return M
