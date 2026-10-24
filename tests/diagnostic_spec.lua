local files,request,callback={},nil,nil
local calls=0
local clock=1
os.clock=function() return clock end
json={dump_file=function(path,data) files[path]=data end,load_file=function() return request end}
re={on_application_entry=function(_,fn) callback=fn end}
sdk={find_type_definition=function() calls=calls+1;error("intentional native lookup failure") end}
local main=assert(package.searchpath("LoadoutClone",package.path))
local root=main:gsub("reframework/autorun/LoadoutClone.lua$","")
assert(loadfile(root.."tools/LoadoutCloneDiagnostic.lua"))()
callback();assert(calls==0,"诊断启动不得访问 SDK")
request={id="old",session_id="old",operation="weapon_arrays",weapon_id=1}
clock=3;callback();assert(calls==0,"不得重放旧请求")
request.session_id=files["LoadoutClone-diagnostic-session.json"].session_id
clock=5;callback();callback();assert(calls==1)
local report=files["LoadoutClone-diagnostic-report.json"]
assert(report.status=="failed" and report.error:find("intentional native lookup failure",1,true))
assert(report.stage:find(":before",1,true),"应保留失败原生调用前阶段")
clock=7;callback();assert(calls==1,"失败请求不得自动重试")
print("PASS 独立诊断启动零调用、旧请求拒绝、调用前落盘、异常保留、禁止重试（5 项）")
local box={}
local original_type=type
type=function(v) if v==box then return "userdata" end;return original_type(v) end
function box:get_type_definition() return {
    get_full_name=function() return "System.UInt32" end,
    get_field=function(_,key) if key=="mValue" then return {get_data=function() return 2 end} end end,
} end
local array={get_type_definition=function() return {get_full_name=function() return "System.UInt32[]" end} end,
    get_size=function() return 1 end,get_element=function() return box end}
local weapon={add_ref=function() end,get_reference_count=function() return 1 end,get_type_definition=function() return {get_full_name=function() return "snow.data.WeaponData" end} end}
sdk.find_type_definition=function() return {get_method=function(_,signature) return {call=function()
    if signature:find("getPlainWeaponData",1,true) then return weapon end
    if signature:find("DecorationSlot",1,true) then return array end
    return 3
end} end} end
request.id="boxed";clock=10;callback();callback()
report=files["LoadoutClone-diagnostic-report.json"]
assert(report.status=="complete" and report.slots.values[1]==2)
assert(report.array.element_type=="System.UInt32")
type=original_type
print("PASS 诊断装箱数值解包与真实元素类型记录（2 项）")
