local N={field=function(o,k)return o[k]end,array_access=function(a)return #a,function(i)return a[i+1]end end}
package.loaded['LoadoutClone.native']=N
local L=require('LoadoutClone.petalace_layout')
local T=require('LoadoutClone.transaction')
local function eq(a,b)if type(a)~=type(b)then return false end;if type(a)~='table'then return a==b end;for k,v in pairs(a)do if not eq(v,b[k])then return false end end;for k in pairs(b)do if a[k]==nil then return false end end;return true end
for fault=0,3 do
 local a,b,c={},{},{};local originals={a,b,c};local array={a,b,c}
 for i,o in ipairs(originals)do o['<InventoryIndex>k__BackingField']=i-1;o.set_field=function(self,k,v)self[k]=v end end
 local calls=0
 local e={array=array,size=3,originals=originals,order={c,a,b},ids={[a]=1,[b]=2,[c]=3},
 before={{identity=1,index=0},{identity=2,index=1},{identity=3,index=2}},expected={{identity=3,index=0},{identity=1,index=1},{identity=2,index=2}},
 setter={call=function(_,arr,i,o)arr[i+1]=o;calls=calls+1;if calls==fault then error('partial array write')end end}}
 local adapter={prepare=function()return {entries={e}}end,assert_context=function()end,
 apply=function(_,entry)entry.started=true;L.write(entry,false)end,
 verify=function()assert(eq(L.state(e),e.expected));return true end,
 restore=function(_,entry)if entry.started then L.write(entry,true)end end,
 verify_restored=function()assert(eq(L.state(e),e.before))end}
 local r=T.new(adapter):execute({})
 assert(r.ok==(fault==0))
 if fault~=0 then assert(r.code=='failed' and array[1]==a and array[2]==b and array[3]==c)end
end
local P=require('LoadoutClone.petalace_cleanup_plan')
local r=P.plan({items={{index=0,kind=4,id=1},{index=43,kind=4,id=2}},references={},current=43})
assert(#r.remove==0 and r.needs_layout)
assert(not P.plan({items={{index=0,kind=4,id=1},{index=1,kind=4,id=2}},references={},current=1}).needs_layout)
print('PASS 无重复空位识别、整理幂等、列表各阶段部分写入失败恢复原对象及索引')
