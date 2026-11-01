local function clone(v)if type(v)~='table'then return v end;local o={};for k,x in pairs(v)do o[k]=clone(x)end;return o end
local function equal(a,b)if type(a)~=type(b)then return false end;if type(a)~='table'then return a==b end;for k,v in pairs(a)do if not equal(v,b[k])then return false end end;for k in pairs(b)do if a[k]==nil then return false end end;return true end
package.loaded['LoadoutClone.native']={field=function(o,k)return o[k]end,array=function(a)return a end}
local W={equal=equal,equipment_state=function(o)return clone(o.state)end,set_state=function(o)return clone(o.state)end}
W.new=function()return {native={},copy=function(_,_,dest,src)
 if src.state._IdType==0 then dest.state._IdType=0 -- 模拟原生复制后某字段保留，不能冒充该语义已实机证实。
 else dest.state=clone(src.state)end
end}end
package.loaded['LoadoutClone.writer']=W
package.loaded['LoadoutClone.character_identity']={current=function()return 'character'end}
local C=require('LoadoutClone.petalace_cleanup')
local store={};json={load_file=function(p)return clone(store[p])end,dump_file=function(p,v)store[p]=clone(v);return true end}
local c=C.new();local before={_IdType=4,_IdVal=777};local dest={state=clone(before),['<InventoryIndex>k__BackingField']=9}
local e={kind='flower',index=9,dest=dest,before=before,expected={_IdType=0,_IdVal=0},object={state={_IdType=0,_IdVal=0}},backup={state=clone(before)}}
c.prepare=function()return {entries={e}}end;c.assert_context=function()end
local result=c:execute({})
assert(not result.ok and result.code=='failed' and equal(dest.state,before),'failure must restore')
local journal=assert(store['LoadoutClone/petalace-cleanup-transaction.json'])
local f=assert(journal.failure,'missing exact failing entry evidence')
assert(f.phase=='apply' and f.kind=='flower' and f.index==9)
assert(f.differences[1].path=='$._IdVal' and f.differences[1].expected==0 and f.differences[1].actual==777)
assert(result.error:find('flower',1,true) and result.error:find('_IdVal',1,true))
assert(journal.status=='restored' and journal.restores==1)
-- 定位记录失败仍不能跳过回滚；限长并保留 false/类型差异。
local many={};for i=1,30 do many[i]=i end
local ok=pcall(function()c:check({kind='current',dest=many}, {},'test mismatch','verify')end)
assert(not ok and #c.failure.differences<=8)
print('PASS 写入回读失败记录具体条目/字段/期望与实际，仍执行真实事务回滚，差异数量有界')
-- 恢复也失败时保留首次写入差异，并单独记录恢复差异；不能用后者覆盖前者。
store={};local broken=C.new()
broken.writer.copy=function(_,_,target,source)target.state={_IdType=source.state._IdType,_IdVal=888}end
local target={state=clone(before),['<InventoryIndex>k__BackingField']=9}
local entry={kind='flower',index=9,dest=target,before=before,expected={_IdType=0,_IdVal=0},object={state={_IdType=0,_IdVal=0}},backup={state=clone(before)}}
broken.prepare=function()return {entries={entry}}end;broken.assert_context=function()end
local failed=broken:execute({})
local saved=store['LoadoutClone/petalace-cleanup-transaction.json']
assert(failed.code=='recovery_failed' and saved.status=='recovery_failed')
assert(saved.failure.phase=='apply' and saved.recovery_failure.phase=='restore')
assert(saved.failure.differences[1].expected==0 and saved.recovery_failure.differences[1].expected==777)
assert(broken:execute({}).ok==false,'recovery lock must remain')
print('PASS 恢复失败独立留证，保留原始失败，不解除事务锁')
