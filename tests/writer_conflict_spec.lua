local function obj(id,n)
 return {_Id=id,_Num=n,get_field=function(self,k) return self[k] end}
end
package.loaded["LoadoutClone.native"]={field=function(o,k) return o[k] end,array=function(v) return v end,new=function() return {} end}
local Writer=require("LoadoutClone.writer")
local w=Writer.new({})
local first,second=obj(1,1),obj(2,9)
local function entry(dest,id,before,after)
 return {kind="decoration",dest=dest,before={id=id,count=before},backup=obj(id,before),object=obj(id,after),expected={id=id,count=after}}
end
local entries={entry(first,1,1,2),entry(second,2,3,4)}
w.prepare=function() return {entries=entries} end
w.assert_context=function() end
w.copy=function(_,_,dest,source) dest._Id=source._Id;dest._Num=source._Num end
local result=w.transaction:execute({})
assert(not result.ok and result.code=="failed")
assert(first._Num==1,"之前已写入的条目必须恢复")
assert(second._Num==9,"尚未写入的冲突条目不得覆盖外部更新")
print("PASS 预留珠子库存冲突保留外部更新，并恢复之前已写入条目")
first._Num=1;entries={entry(first,1,1,2)}
w.prepare=function() return {entries=entries} end
local count=0
w.copy=function(_,_,dest,source)
 count=count+1;dest._Num=source._Num
 if count==1 then error("partial native copy") end
end
result=w.transaction:execute({})
assert(not result.ok and result.code=="failed" and first._Num==1 and count==2)
print("PASS 原生 copy 部分修改后失败仍执行恢复")
