local Scan=assert(loadfile(test_root.."tools/petalace_cleanup_scan.lua"))()
local P=require("LoadoutClone.petalace_cleanup_plan")
local function array(values) return {values=values} end -- 无 get_size/get_element
local function indices(n) return array({0,0,0,0,0,0,n,0}) end
local rows={}
for i=0,39 do rows[#rows+1]={_IdType=4,_IdVal=123,["<InventoryIndex>k__BackingField"]=i,_IsLock=false,_IsSetGuildCard=false} end
local data={_PlEquipBox={_LvBuffCageInventoryList={mItems=array(rows),mSize=#rows}}}
local manager={_PlEquipPack={_InventoryIndexList=indices(2)},_PlEquipMySetList=array({{_IsUsing=true,_InventoryIndexList=indices(0)}})}
manager.get_field=function(self,k)return self[k]end
data._PlEquipBox.get_field=manager.get_field
sdk={get_managed_singleton=function(name) return name=="snow.data.DataManager" and data or manager end}
local reads=0
local N={field=function(o,k)return assert(o[k]~=nil) and o[k]end,array_access=function(a,max)
 reads=reads+1;assert(#a.values<=max);return #a.values,function(i)return a.values[i+1]end
end,array=function(a)
 reads=reads+1;local out={};for i,v in ipairs(a.values) do assert(type(v)=="number");out[i]=v end;return out
end}
local report={items={},references={},writes=0}
local job=coroutine.create(function()Scan.run(N,P,report)end)
repeat local ok,err=coroutine.resume(job);assert(ok,err) until coroutine.status(job)=="dead"
assert(report.status=="complete" and report.current==2 and #report.plan.remove==39)
assert(report.plan.references[1].before==0 and report.plan.references[1].after==2)
assert(report.writes==0 and #rows==40 and reads==4)
print("PASS 清理扫描复用数组适配器，不调用包装器 get_size；分帧读取引用及规划零写入")
