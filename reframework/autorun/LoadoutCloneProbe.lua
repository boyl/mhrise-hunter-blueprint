-- 独立开发探针：只读采样及受备份门禁保护的事务验收；不进入发布包。
local VERSION = "0.4.1-update-probe"
local FILE = "LoadoutClone-probe"
local script_package_path=package.path
local last_id, next_poll = nil, 0
local status = "Ready (development validation)"
local SESSION=string.format("%d-%.6f",os.time(),os.clock())
json.dump_file(FILE.."-session.json",{session_id=SESSION,version=VERSION})
local function name(t) return t and t:get_full_name() or "<nil>" end

local function describe(type_name)
    local t = sdk.find_type_definition(type_name)
    if not t then return {name=type_name, found=false} end
    local result = {name=name(t), parent=name(t:get_parent_type()), found=true, fields={}, methods={}}
    for i, f in ipairs(t:get_fields()) do
        if i > 1024 then error("field metadata limit") end
        local info={name=f:get_name(), type=name(f:get_type()), static=f:is_static()}
        if f:is_static() and f:is_literal() then
            local value=f:get_data(nil)
            if type(value)=="number" or type(value)=="boolean" or type(value)=="string" then info.value=value end
        end
        result.fields[#result.fields+1] = info
    end
    for i, m in ipairs(t:get_methods()) do
        if i > 2048 then error("method metadata limit") end
        local parameters, names = {}, m:get_param_names()
        for j, p in ipairs(m:get_param_types()) do
            parameters[#parameters+1] = {type=name(p), name=names[j]}
        end
        result.methods[#result.methods+1] = {name=m:get_name(), returns=name(m:get_return_type()), static=m:is_static(), parameters=parameters}
    end
    return result
end

-- 只展开已通过元数据探测的业务类型；父类另行探测，不自动猜测。
local allowed = {
    ["snow.LobbyManager.HunterInfo"]=true,
    ["System.Guid"]=true,
    ["snow.gui.EquipStatusParamManager.ParamPacket"]=true,
    ["snow.gui.define.EquipStatusParam"]=true,
    ["snow.gui.define.WeaponDataParam"]=true,
    ["snow.gui.define.ArmorDataParam"]=true,
    ["snow.gui.define.PlTalismanParam"]=true,
    ["snow.gui.define.LvBuffDataParam"]=true,
    ["snow.data.EquipmentInventoryData"]=true,
    ["snow.data.EquipmentInventoryData.CustomBuildupResult"]=true,
    ["snow.equip.PlEquipPack"]=true,
    ["snow.equip.PlEquipMySetData"]=true,
    ["snow.equip.PlEquipMySetData.BackupData"]=true,
}
local function snapshot()
    local budget=16000
    local function plain(value, depth)
        budget=budget-1
        if budget<0 then error("snapshot node budget exhausted") end
        if value==nil then return {missing=true} end
        local kind=type(value)
        if kind=="number" or kind=="boolean" or kind=="string" then return value end
        local t=value:get_type_definition()
        local type_name=name(t)
        if type_name=="System.Int32" or type_name=="System.UInt32" or type_name=="System.Boolean" or type_name=="System.Single" or type_name=="System.Byte" or type_name=="System.UInt16" then
            return value:get_field("mValue")
        end
        if depth>8 then return {type=type_name, omitted="depth limit"} end
        if type_name:sub(-2)=="[]" then
            local size=value:get_size()
            if size>512 then return {type=type_name, size=size, omitted="array limit"} end
            local result={type=type_name, size=size, values={}}
            for i=0,size-1 do result.values[i+1]=plain(value:get_element(i), depth+1) end
            return result
        end
        local enum=t:get_field("value__")
        if enum and not enum:is_static() then return enum:get_data(value) end
        if not allowed[type_name] then return {type=type_name, omitted="type not reviewed"} end
        local result={type=type_name, fields={}}
        for _,field in ipairs(t:get_fields()) do
            if not field:is_static() then
                local key=field:get_name()
                -- 不收集平台账号标识、位置和无关个人信息。
                if key~="<_NsaId>k__BackingField" and key~="_customLobbyMusicData" then
                    result.fields[key]=plain(field:get_data(value),depth+1)
                end
            end
        end
        return result
    end
    local lobby=sdk.get_managed_singleton("snow.LobbyManager")
    local params=sdk.get_managed_singleton("snow.gui.EquipStatusParamManager")
    local equips=sdk.get_managed_singleton("snow.data.EquipDataManager")
    assert(lobby and params and equips,"game managers not ready")
    local function read(obj, key) return obj:get_field(key) end
    local result={my_index=read(lobby,"_myselfIndex"), hunters=plain(read(lobby,"_hunterInfo"),0),
        lobby_packets=plain(read(params,"_lobbyParam"),0), quest_packets=plain(read(params,"_questParam"),0),
        own_equipment=plain(read(equips,"_PlEquipPack"),0)}
    result.nodes_read=16000-budget
    return result
end

local function object_fields(request)
    local current = sdk.get_managed_singleton(request.singleton)
    if not current then return {available=false, reason="singleton unavailable"} end
    local result = {available=true, chain={}}
    for _, field_name in ipairs(request.path or {}) do
        if #result.chain >= 6 then error("field path limit") end
        local t = current:get_type_definition()
        local f = t:get_field(field_name)
        if not f then error("missing field: " .. name(t) .. "." .. field_name) end
        if f:is_static() then error("instance path cannot read static fields") end
        current = f:get_data(current)
        result.chain[#result.chain+1] = {field=field_name, declared_type=name(f:get_type()), present=current~=nil}
        if current == nil then result.available=false; return result end
    end
    local kind = type(current)
    if kind == "number" or kind == "string" or kind == "boolean" then result.value=current
    else result.type=name(current:get_type_definition()) end
    return result
end

local function run(request)
    assert(type(request.id)=="string" and #request.id<=100, "invalid request id")
    assert(request.mode=="metadata" or request.mode=="fields" or request.mode=="snapshot" or request.mode=="reader" or request.mode=="contract", "unsupported mode")
    if request.mode=="contract" then
        local report={id=request.id,version=VERSION,mode=request.mode,writes=0,game_method_calls=0,results={},errors={}}
        local old_path=package.path;package.path=script_package_path
        local ok,value=pcall(function()
            package.loaded["LoadoutClone.contracts"]=nil
            return require("LoadoutClone.contracts").run(request,report)
        end)
        package.path=old_path
        if ok then report.results={value} else report.errors={{message=tostring(value)}} end
        return report
    end
    if request.mode=="reader" then
        -- 固定只读模块，开发时按请求重新加载，避免反复重置全部游戏脚本。
        package.loaded["LoadoutClone.reader"]=nil
        local old_path=package.path
        package.path=script_package_path
        local loaded,Reader=pcall(require,"LoadoutClone.reader")
        package.path=old_path
        assert(loaded,Reader)
        local reader=Reader.new()
        local members=reader:list_members()
        local result={members=members,packets={}}
        if request.catalog and reader.read_catalog then result.catalog=reader:read_catalog() end
        for _,member in ipairs(members.members) do
            local ok,value=pcall(function() return reader:capture(member.key) end)
            result.packets[#result.packets+1]={key=member.key,ok=ok,data=ok and value or nil,error=not ok and tostring(value) or nil}
        end
        return {id=request.id, version=VERSION, mode=request.mode, writes=0, game_method_calls=0, results={result}, errors={}}
    end
    if request.mode=="snapshot" then
        return {id=request.id, version=VERSION, mode=request.mode, writes=0, game_method_calls=0, results={snapshot()}, errors={}}
    end
    local entries=request.mode=="metadata" and request.types or request.objects
    assert(type(entries)=="table" and #entries<=16, "request entry limit")
    local report={id=request.id, version=VERSION, mode=request.mode, writes=0, game_method_calls=0, results={}, errors={}}
    for _, entry in ipairs(entries) do
        if #report.errors>=3 then report.stopped="error budget exhausted"; break end
        local ok, value = pcall(function()
            if request.mode=="metadata" then
                assert(type(entry)=="string" and #entry<=250, "invalid type name")
                return describe(entry)
            end
            assert(type(entry)=="table" and type(entry.singleton)=="string", "invalid object request")
            return object_fields(entry)
        end)
        if ok then report.results[#report.results+1]={request=entry, data=value}
        else report.errors[#report.errors+1]={request=entry, message=tostring(value)} end
    end
    return report
end

re.on_application_entry("LateUpdateBehavior",function()
    if os.clock()<next_poll then return end
    next_poll=os.clock()+1
    local ok, err=pcall(function()
        local request=json.load_file(FILE.."-request.json")
        if not request or request.id==last_id then return end
        last_id=request.id
        -- 重启或重载后拒绝上一轮遗留的请求，不能在加载角色期间自动重放。
        if request.session_id~=SESSION then status="Ignored request from another development session";return end
        local report=run(request)
        json.dump_file(FILE.."-report.json", report)
        status="Request "..tostring(last_id)..": "..#report.results.." results, "..#report.errors.." errors"
        log.info("[LoadoutCloneProbe "..VERSION.."] "..status)
    end)
    if not ok then status=tostring(err); log.error("[LoadoutCloneProbe] "..status) end
end)

re.on_draw_ui(function()
    if imgui.tree_node("Loadout Clone - development validation") then
        imgui.text("Version: "..VERSION)
        imgui.text("Read/write/restore counts are recorded per request in the report")
        imgui.text(status)
        imgui.tree_pop()
    end
end)
log.info("[LoadoutCloneProbe "..VERSION.."] loaded; guarded development validation")
