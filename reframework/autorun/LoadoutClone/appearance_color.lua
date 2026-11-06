-- SymbolColorData 的有界读写。禁止对嵌入的 Int3 使用通用 ValueType set_field。
-- 当前 REFramework 的 boxed size 为 28，而字段实际只有 12 字节。
local M={}
local function layout(owner)
 assert(owner,"缺少染色对象")
 local t=owner:get_type_definition()
 assert(t:get_full_name()=="snow.data.SymbolColorData","染色对象类型不匹配")
 local f=assert(t:get_field("_Color"),"缺少颜色字段")
 local vt=f:get_type()
 assert(vt:get_full_name()=="via.Int3" and vt:get_valuetype_size()==12,"颜色字段布局不支持")
 local offset=f:get_offset_from_base()
 assert(offset>=16 and offset+12<=owner:get_object_size(),"颜色字段超出对象边界")
 local header=vt:get_size()-vt:get_valuetype_size()
 for i,key in ipairs({"x","y","z"}) do
  assert(vt:get_field(key):get_offset_from_base()-header==(i-1)*4,"颜色分量布局不支持")
 end
 return offset
end
local function validate(value)
 assert(type(value)=="table" and type(value.enabled)=="boolean" and type(value.default)=="boolean","染色标志无效")
 assert(type(value.hsv)=="table","缺少 HSV")
 local limits={360,100,100}
 for i=1,3 do
  local n=value.hsv[i]
  assert(type(n)=="number" and n==n and n%1==0 and n>=0 and n<=limits[i],"HSV 超出范围")
 end
 for k in pairs(value.hsv) do assert(k==1 or k==2 or k==3,"HSV 包含多余分量") end
end
function M.read(owner)
 local offset=layout(owner)
 local value={enabled=owner:get_field("_IsEnable"),default=owner:get_field("_IsDefault"),hsv={}}
 for i=1,3 do value.hsv[i]=owner:read_dword(offset+(i-1)*4) end
 validate(value);return value
end
function M.write(owner,value)
 validate(value)
 local offset=layout(owner) -- 全部前置检查通过后才写入。
 owner:set_field("_IsEnable",value.enabled)
 owner:set_field("_IsDefault",value.default)
 for i=1,3 do owner:write_dword(offset+(i-1)*4,value.hsv[i]) end
 local actual=M.read(owner)
 assert(actual.enabled==value.enabled and actual.default==value.default,"染色标志回读不一致")
 for i=1,3 do assert(actual.hsv[i]==value.hsv[i],"染色分量回读不一致") end
end
function M.from_snapshot(source)
 assert(type(source)=="table" and type(source.enabled)=="boolean","染色快照无效")
 local value={enabled=source.enabled,default=not source.enabled,hsv={0,0,0}}
 -- 本机快照提供原生 default/HSV；旧远端快照缺少 default 时沿用原约定。
 if source.default~=nil then
  assert(type(source.default)=="boolean","默认染色标志无效")
  value.default=source.default
  assert(type(source.hsv)=="table","原生染色快照缺少 HSV")
 end
 if source.enabled or source.hsv~=nil then
  assert(type(source.hsv)=="table","染色缺少 HSV")
  for k in pairs(source.hsv) do assert(k==1 or k==2 or k==3,"HSV 包含多余分量") end
  for i=1,3 do value.hsv[i]=source.hsv[i] end
 end
 validate(value);return value
end
return M
