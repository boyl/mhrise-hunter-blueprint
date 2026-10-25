local C=require("LoadoutClone.appearance_color")
local function object(options)
 options=options or {}
 local writes={};local values={[20]=30,[24]=90,[28]=47,[32]=123456}
 local flags={_IsEnable=true,_IsDefault=false}
 local vt={get_full_name=function() return "via.Int3" end,get_size=function() return 28 end,
 get_valuetype_size=function() return 12 end,get_field=function(_,key)
  return {get_offset_from_base=function() return ({x=16,y=20,z=24})[key]+(options.bad_component and 4 or 0) end}
 end}
 local td={get_full_name=function() return options.type or "snow.data.SymbolColorData" end,
 get_field=function() return {get_type=function() return vt end,get_offset_from_base=function() return 20 end} end}
 local obj={get_type_definition=function() return td end,get_object_size=function() return options.size or 32 end,
 get_field=function(_,key) return flags[key] end,set_field=function(_,key,v)
  assert(key~="_Color","禁止整块写入 Int3");writes[#writes+1]=key;flags[key]=v
 end,read_dword=function(_,offset) return values[offset] end,
 write_dword=function(_,offset,value) writes[#writes+1]=offset;values[offset]=value end}
 return obj,writes,values
end
local obj,writes,values=object()
C.write(obj,{enabled=true,default=false,hsv={360,100,100}})
assert(#writes==5 and values[32]==123456 and values[28]==100)
local actual=C.read(obj);assert(actual.hsv[1]==360 and actual.enabled)
print("PASS 染色只写入 12 字节，保留紧邻对象哨兵，禁止通用 Int3 写入")
for _,options in ipairs({{size=31},{bad_component=true},{type="Other"}}) do
 local o,w=object(options)
 assert(not pcall(C.write,o,{enabled=false,default=true,hsv={0,0,0}}) and #w==0)
end
print("PASS 对象边界、分量布局和类型错误均零写入拒绝")
for _,hsv in ipairs({{361,0,0},{0,-1,0},{0,0,101},{0,0,0.5},{0,0},{0,0,0,1}}) do
 local o,w=object();assert(not pcall(C.write,o,{enabled=true,default=false,hsv=hsv}) and #w==0)
end
print("PASS HSV 范围、整数、缺项及多项错误均零写入拒绝")
local o=object();C.write(o,{enabled=false,default=false,hsv={30,90,47}})
local old=C.read(o);assert(not old.enabled and not old.default and old.hsv[1]==30)
local blank=C.from_snapshot({enabled=false});assert(blank.default and blank.hsv[1]==0)
print("PASS 备份保留禁用通道的原始值，来源禁用通道使用明确默认值")
