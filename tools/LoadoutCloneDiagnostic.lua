-- 独立只读诊断；不加载生产模块，不注册写入功能，不重放上次启动请求。
local prefix="LoadoutClone-diagnostic"
local session=tostring(os.time()).."-"..tostring(os.clock())
local last_id,next_poll,job=nil,0,nil
local module_root=assert(debug.getinfo(1,"S").source:sub(2):match("^(.*[/\\])")).."../diagnostics/"
local report
local function checkpoint(stage)
    report.stage=stage
    json.dump_file(prefix.."-report.json",report)
end
local function describe(value,label)
    checkpoint(label..":type")
    assert(value~=nil,label..": nil")
    local td=assert(value:get_type_definition(),label..": no type")
    local result={type=td:get_full_name()}
    report.array=result
    assert(result.type:sub(-2)=="[]",label..": expected array, got "..result.type)
    checkpoint(label..":size ("..result.type..")")
    result.size=value:get_size()
    assert(result.size>=0 and result.size<=64,label..": unexpected size")
    result.values={}
    for i=0,result.size-1 do
        checkpoint(label..":element "..i)
        local v=value:get_element(i)
        if type(v)=="userdata" then
            local element_type=v:get_type_definition()
            result.element_type=element_type:get_full_name()
            local field=element_type:get_field("value__") or element_type:get_field("mValue")
            assert(field,label..": unknown boxed value "..result.element_type)
            v=field:get_data(v)
        end
        assert(type(v)=="number",label..": expected numeric element")
        result.values[#result.values+1]=v
    end
    return result
end
local function run(request)
    if request.operation=="extended" then
        package.loaded["LoadoutClone.diagnostic_steps"]=nil
        return require("LoadoutClone.diagnostic_steps").run(request,report,checkpoint)
    end
    if request.operation=="catalog" or request.operation=="members" or request.operation=="prepare_readonly" then
        local Reader=require("LoadoutClone.reader")
        local Native=require("LoadoutClone.native")
        local reader=Reader.new()
        if request.operation=="members" then
            checkpoint("reader:list_members")
            report.lobby=reader:list_members()
            return
        end
        local native=Native.new()
        local original_call=native.call
        function native:call(owner_type,signature,owner,...)
            checkpoint(owner_type.."."..signature..":before")
            local value=original_call(self,owner_type,signature,owner,...)
            if signature=="getPlainWeaponData(snow.data.ContentsIdSystem.WeaponId)" and value then
                local before=value:get_reference_count()
                value:add_ref()
                report.weapon_reference={before=before,after=value:get_reference_count()}
            end
            report.game_method_calls=self.game_method_calls
            checkpoint(owner_type.."."..signature..":after")
            return value
        end
        if request.operation=="catalog" then
            checkpoint("native:read_catalog")
            local catalog=native:read_catalog()
            report.counts={}
            for k,v in pairs(catalog) do if type(v)=="table" then report.counts[k]=#v end end
        else
            assert(type(request.key)=="string","member key required")
            local planner=require("LoadoutClone.planner").new(reader)
            planner.native=native
            checkpoint("planner:prepare (no writer loaded)")
            local plan=planner:prepare(request.key,{copy_augments=true,allow_illegal_augments=false,copy_appearance=false})
            report.items={}
            for i,item in pairs(plan.items) do report.items[i]={kind=item.kind,verification=item.verification} end
            report.red=plan.red;report.blue=plan.blue
        end
        return
    end
    assert(request.operation=="weapon_arrays","unsupported diagnostic operation")
    assert(type(request.weapon_id)=="number" and request.weapon_id>0 and request.weapon_id%1==0,"invalid weapon ID")
    local function call(owner_type,method,owner,...)
        checkpoint(owner_type.."."..method..":before")
        local td=assert(sdk.find_type_definition(owner_type),owner_type)
        local fn=assert(td:get_method(method),method)
        local result=fn:call(owner,...)
        checkpoint(owner_type.."."..method..":after")
        return result
    end
    local weapon=assert(call("snow.data.DataShortcut","getPlainWeaponData(snow.data.ContentsIdSystem.WeaponId)",nil,request.weapon_id))
    checkpoint("weapon:add_ref")
    report.reference_before=weapon:get_reference_count()
    weapon:add_ref()
    report.reference_after=weapon:get_reference_count()
    report.weapon_type=weapon:get_type_definition():get_full_name()
    report.table=call("snow.data.WeaponData","get_CustomTableNo()",weapon)
    report.cost=call("snow.data.WeaponData","get_CustomCost()",weapon)
    report.max_add_cost=call("snow.data.WeaponData","get_CustomAddCostMax()",weapon)
    local slots=call("snow.data.WeaponData","get_DecorationSlotNumList()",weapon)
    report.slots=describe(slots,"weapon slots")
end
json.dump_file(prefix.."-request.json",{})
json.dump_file(prefix.."-session.json",{session_id=session,version=4})
re.on_application_entry("UpdateBehavior",function()
    if job then
        local old_path=package.path
        package.path=module_root.."?.lua;"..old_path
        local ok,result=coroutine.resume(job)
        package.path=old_path
        if not ok then
            report.status="failed";report.error=debug.traceback(job,tostring(result));job=nil
        elseif coroutine.status(job)=="dead" then report.status="complete";job=nil
        else report.progress=result end
        checkpoint(report.stage)
        return
    end
    if os.clock()<next_poll then return end
    next_poll=os.clock()+1
    local request=json.load_file(prefix.."-request.json")
    if not request or request.session_id~=session or request.id==last_id then return end
    last_id=request.id
    report={id=request.id,session_id=session,status="running",weapon_id=request.weapon_id}
    checkpoint("accepted")
    job=coroutine.create(function() run(request) end)
end)
