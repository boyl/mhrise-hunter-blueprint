local function clone(v)if type(v)~="table"then return v end;local o={};for k,x in pairs(v)do o[k]=clone(x)end;return o end
local function equal(a,b)if type(a)~=type(b)then return false end;if type(a)~="table"then return a==b end;for k,v in pairs(a)do if not equal(v,b[k])then return false end end;for k in pairs(b)do if a[k]==nil then return false end end;return true end
local W={equal=equal,set_state=function(o)return clone(o.state)end,equipment_state=function(o)return clone(o.state)end}
W.new=function()return {native={},copy=function(_,_,dest,src)dest.state=clone(src.state)end}end
package.loaded["LoadoutClone.writer"]=W
package.loaded["LoadoutClone.native"]={field=function(o,k)return o[k]end,array=function(v)return v end}
package.loaded["LoadoutClone.character_identity"]={current=function()return "character"end}
local Cleanup=require("LoadoutClone.petalace_cleanup")
for _,fault in ipairs({0,1,2,3,4,99})do
 local store={};json={load_file=function(p)return clone(store[p])end,dump_file=function(p,v)store[p]=clone(v);return true end}
 local c=Cleanup.new();c.writes=0;c.restores=0
 local flower={state={id=123},["<InventoryIndex>k__BackingField"]=6}
 local set={state={index=6}}
 local side="LoadoutClone/appearance-visibility.json";store[side]={index=6}
 local entries={
 {kind="set",dest=set,object={state={index=0}},before={index=6},expected={index=0},backup={state={index=6}}},
 {kind="visibility",before={index=6},expected={index=0}},
 {kind="flower",dest=flower,object={state={id=0}},before={id=123},expected={id=0},backup={state={id=123}},index=6}}
 local indices={0,0,0,0,0,0,6}
 entries[#entries+1]={kind="current",dest=indices,before={0,0,0,0,0,0,6},expected={0,0,0,0,0,0,0},setter={call=function(_,a,i,v)a[i+1]=v end}}
 local plan={entries=entries,character="character",manager={_PlEquipPack={_InventoryIndexList=indices}},current={0,0,0,0,0,0,0},preview={plan={remove={6},references={1}}}}
 c.prepare=function()return plan end;c.assert_context=function()end
 c.fault_after=fault;c.fault_on_verify=fault==99
 local result=c:execute({})
 if fault==0 then assert(indices[7]==0);assert(result.ok and flower.state.id==0 and set.state.index==0 and store[side].index==0)
 else assert(indices[7]==6);assert(not result.ok and result.code=="failed" and c.writes==c.restores);assert(flower.state.id==123 and set.state.index==6 and store[side].index==6)end
end
print("PASS 花链清理真实事务代码：正常完成、每阶段故障及最终验证失败均恢复组合/绑定/花链")
-- 只改花链字段，禁止原生整套 copy 重算其他槽位；缓存写入中途失败也恢复。
package.loaded['LoadoutClone.native'].array_access=function(a)return #a,function(i)return a[i+1]end end
for _,fault in ipairs({0,1,99})do
 local store={};json={load_file=function(p)return clone(store[p])end,dump_file=function(p,v)store[p]=clone(v);return true end}
 local c=Cleanup.new();c.writer.copy=function()error('whole-set copy must not run')end
 local old,new={},{};local refs={false,false,false,false,false,false,old};local indices={1354,1355,1356,1357,1358,1359,43,1360}
 local set={state={arrays={_InventoryIndexList=indices},other='unchanged'},['<InventoryDataList>k__BackingField']=refs}
 local before=clone(set.state);local expected=clone(before);expected.arrays._InventoryIndexList[7]=1
 local calls=0
 local e={kind='set',dest=set,indices=indices,refs=refs,before=before,expected=expected,cached_before=old,cached_expected=new,
 index_setter={call=function(_,a,i,v)a[i+1]=v end},ref_setter={call=function(_,a,i,v)a[i+1]=v;calls=calls+1;if fault==1 and calls==1 then error('partial reference write')end end}}
 c.prepare=function()return {entries={e},character='character',manager={_PlEquipPack={_InventoryIndexList={}}},current={},preview={plan={remove={},references={1}}}}end
 c.assert_context=function()end;c.fault_on_verify=fault==99
 local result=c:execute({})
 if fault==0 then assert(result.ok and indices[7]==1 and refs[7]==new)
 else assert(not result.ok and result.code=='failed' and equal(set.state,before) and refs[7]==old)end
 assert(indices[1]==1354 and indices[8]==1360)
end
print('PASS 花链字段写入不调用整套copy，保留其他装备索引；部分缓存写入及终验失败完整回滚')
