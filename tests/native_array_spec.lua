local Native=require("LoadoutClone.native")
local retained=false
local values={0,2,0,0,1}
local td={is_array=function() return true end,get_full_name=function() return "System.UInt32[]" end}
function td:get_method(name)
    if name=="Get(System.Int32)" then return {call=function(_,owner,i) assert(retained);return values[i+1] end} end
end
sdk={find_type_definition=function(name)
    assert(name=="System.Array")
    return {get_method=function(_,signature)
        assert(signature=="get_Length()")
        return {call=function() assert(retained);return #values end}
    end}
end}
local obj={add_ref=function() retained=true end,get_type_definition=function() return td end}
local out=Native.array(obj)
assert(#out==5 and out[2]==2 and out[5]==1,"无 Lua 数组包装时仍须完整读取孔位")
values={};assert(#Native.array(obj)==0)
values={};for i=1,513 do values[i]=0 end
assert(not pcall(Native.array,obj),"超界必须拒绝")
td.is_array=function() return false end
assert(not pcall(Native.array,obj),"非数组必须拒绝")
print("PASS 原生数组无包装读取、持有引用、空数组、长度上限与类型拒绝（5 项）")
