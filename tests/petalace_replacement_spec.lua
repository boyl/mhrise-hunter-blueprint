local function clone(v)if type(v)~='table'then return v end;local o={};for k,x in pairs(v)do o[k]=clone(x)end;return o end
local function equal(a,b)if type(a)~=type(b)then return false end;if type(a)~='table'then return a==b end;for k,v in pairs(a)do if not equal(v,b[k])then return false end end;for k in pairs(b)do if a[k]==nil then return false end end;return true end
local function obj(kind,id,tag)
 local o={state={_IdType=kind,_IdVal=id,retained_field=tag or 0},['<InventoryIndex>k__BackingField']=-1}
 o.add_ref=function(self)return self end;o.set_field=function(self,k,v)self[k]=v end
 return o
end
local fault,calls=0,0
local function array(a)
 a.add_ref=function(self)return self end
 a.get_type_definition=function()return {get_method=function()return {call=function(_,dest,i,o)dest[i+1]=o;calls=calls+1;if fault>0 and calls==fault then error('partial list write')end end}end}end
 return a
end
local list_type={get_method=function(_,name)
 assert(name=='Add');return {call=function(_,list,o)list.mSize=list.mSize+1;list.mItems[list.mSize]=o end}
end}
local function list(a)return {mItems=array(a),mSize=#a,get_type_definition=function()return list_type end,set_field=function(self,k,v)self[k]=v end,add_ref=function(self)return self end}end
package.loaded['LoadoutClone.native']={field=function(o,k)if o[k]~=nil then return o[k]end;return o.state[k]end,array_access=function(a)return #a,function(i)return a[i+1]end end}
package.loaded['LoadoutClone.writer']={equal=equal,equipment_state=function(o)return clone(o.state)end}
sdk={create_managed_array=function()return array({})end,create_instance=function(name)
 if name=='snow.data.EquipBox'then return {set_field=function(self,k,v)self[k]=v end,add_ref=function(self)return self end}end
 return obj(0,0)
end,find_type_definition=function(name)return {get_method=function(_,method)
 if name=='System.Object'then return {call=function(_,source)return list(source.mItems)end}end
 assert(method=='sortLvBuffCage()');return {call=function(_,box)
  local a=box._LvBuffCageInventoryList.mItems
  table.sort(a,function(x,y)if x.state._IdType==0 then return false end;if y.state._IdType==0 then return true end;return x.state._IdVal<y.state._IdVal end)
  for i,o in ipairs(a)do o['<InventoryIndex>k__BackingField']=i-1 end
 end}
end}end}
local L=require('LoadoutClone.petalace_layout')
local P=require('LoadoutClone.petalace_cleanup_plan')
local T=require('LoadoutClone.transaction')
for _,current in ipairs({-1,0,2})do
 for fail_at=0,5 do
  local a,b,c,d,z=obj(4,10,91),obj(4,20,92),obj(4,10,91),obj(4,20,92),obj(0,0)
  local inventory=list({a,b,c,d,z});local originals={a,b,c,d,z};local saved={}
  for i,o in ipairs(originals)do o['<InventoryIndex>k__BackingField']=i-1;saved[i]=clone(o.state)end
  local proposal=P.plan({items={{index=0,kind=4,id=10},{index=1,kind=4,id=20},{index=2,kind=4,id=10},{index=3,kind=4,id=20,locked=true}},references={},current=current})
  local remove={};for _,i in ipairs(proposal.remove)do remove[i]=true end
  local writer={native={game_method_calls=0,call=function()end},backup=function(_,_,source)local copy=obj(source.state._IdType,source.state._IdVal,source.state.retained_field);return copy end}
  fault=0;calls=0;local e=L.prepare(inventory,remove,writer)
  for _,o in ipairs(e.order)do for i,original in ipairs(originals)do if remove[i-1]then assert(o~=original,'removed original must be replaced, not copied into')end end end
  assert(equal(L.state(e),e.before));for i,o in ipairs(originals)do assert(equal(o.state,saved[i]))end
  fault=fail_at;calls=0
  local adapter={prepare=function()return {entries={e}}end,assert_context=function()end,apply=function()L.write(e,false)end,verify=function()assert(equal(L.state(e),e.expected));return true end,restore=function()L.write(e,true)end,verify_restored=function()assert(equal(L.state(e),e.before))end}
  local result=T.new(adapter):execute({})
  assert(result.ok==(fail_at==0))
  for i,o in ipairs(originals)do assert(equal(o.state,saved[i]),'original attributes changed')end
  if fail_at>0 then for i,o in ipairs(originals)do assert(inventory.mItems[i]==o and o['<InventoryIndex>k__BackingField']==i-1)end end
 end
end
print('PASS 重复删除与整理组合：新空对象替换，当前/锁定保留，旧对象属性不变，各槽部分失败恢复原对象和索引')
-- 组合验收：真实 cleanup.prepare + 扫描/规划/替换布局 + 提交/恢复；原生反射以模型代替。
local N=package.loaded['LoadoutClone.native'];local W=package.loaded['LoadoutClone.writer']
local function values(a)local out={};for i=1,#a do out[i]=a[i]end;return out end
N.array=values
W.set_state=function(o)return {used=o._IsUsing,name='legacy loadout',arrays={_InventoryIndexList=values(o._InventoryIndexList),_ActionIdList={1,2,3},_ActionIdListMR_Red={1,2,3,4,5},_ActionIdListMR_Blue={1,2,3,4,5}},backup={id=42}}end
W.new=function()return {native={game_method_calls=0,call=function()end},backup=function(_,name,source)
 assert(name=='snow.data.EquipmentInventoryData');return obj(source.state._IdType,source.state._IdVal,source.state.retained_field)
end,copy=function()error('no live EquipmentInventoryData.copy is allowed')end}end
package.loaded['LoadoutClone.character_identity']={current=function()return 'legacy-character'end}
local C=require('LoadoutClone.petalace_cleanup')
local function owner(t)t.get_field=function(self,k)return self[k]end;return t end
local function make_set(index,flower)
 local indices=array({100,200,300,400,500,600,index,800})
 return owner({_IsUsing=true,_InventoryIndexList=indices,['<InventoryDataList>k__BackingField']=array({false,false,false,false,false,false,flower,false})})
end
for _,scenario in ipairs({'success','verify','set0','set1','binding','layout','current','partial1','partial2','partial3','partial4','partial5','partial6','partial7','partial8','partial9','partial10'})do
 fault=0;calls=0
 local a,b,c,d,z=obj(4,10,91),obj(4,20,92),obj(4,10,91),obj(4,20,92),obj(0,0)
 d.state._IsLock=true;b.state._IsLock=true -- 同款要保留两件锁定项；a/c 是可合并的历史重复。
 a.state._IsLock=false;c.state._IsLock=false;z.state._IsLock=false
 local inventory=owner(list({a,b,c,d,z}));local original={a,b,c,d,z};local before_states={}
 for i,o in ipairs(original)do o['<InventoryIndex>k__BackingField']=i-1;before_states[i]=clone(o.state)end
 local set0,set1=make_set(0,a),make_set(3,d)
 local manager=owner({_PlEquipPack={_InventoryIndexList=array({100,200,300,400,500,600,2,800})},_PlEquipMySetList=array({set0,set1})})
 local data={_PlEquipBox=owner({_LvBuffCageInventoryList=inventory})}
 sdk.get_managed_singleton=function(name)if name=='snow.data.DataManager'then return data end;assert(name=='snow.data.EquipDataManager');return manager end
 local side='LoadoutClone/appearance-visibility.json'
 local doc={schema=1,record_count=1,records={{character='legacy-character',fingerprint={hunter={_EquipMysetIndex=1},equipment=W.set_state(set1)}}}}
 local store={[side]=clone(doc)}
 json={load_file=function(path)return clone(store[path])end,dump_file=function(path,v)store[path]=clone(v);return true end}
 local cleanup=C.new();local preview=cleanup:scan();local before0,before1=W.set_state(set0),W.set_state(set1)
 assert(#preview.plan.remove==1 and preview.plan.remove[1]==0)
 local stage={set0=1,set1=2,binding=3,layout=4,current=5}
 cleanup.fault_after=stage[scenario];cleanup.fault_on_verify=scenario=='verify'
 local partial=scenario:match('partial(%d+)');if partial then fault=tonumber(partial)end
 local result=cleanup:execute(preview)
 if scenario=='success'then
  assert(result.ok and result.result.removed==1 and result.result.updated==2)
  assert(manager._PlEquipPack._InventoryIndexList[7]==0)
  assert(set0._InventoryIndexList[7]==0 and set0['<InventoryDataList>k__BackingField'][7]==c,'unchanged numeric index still needs reference migration')
  assert(set1._InventoryIndexList[7]==2 and set1['<InventoryDataList>k__BackingField'][7]==d)
  assert(store[side].records[1].fingerprint.equipment.arrays._InventoryIndexList[7]==2)
  local scan=cleanup:scan();assert(#scan.items==3 and #scan.plan.remove==0 and not scan.plan.needs_layout,'second scan must be idempotent')
 else
  assert(not result.ok and result.code=='failed',scenario..': '..tostring(result.error))
  assert(equal(W.set_state(set0),before0)and equal(W.set_state(set1),before1))
  assert(set0['<InventoryDataList>k__BackingField'][7]==a and set1['<InventoryDataList>k__BackingField'][7]==d)
  assert(equal(store[side],doc)and manager._PlEquipPack._InventoryIndexList[7]==2)
  for i,o in ipairs(original)do assert(inventory.mItems[i]==o and o['<InventoryIndex>k__BackingField']==i-1)end
  local after=cleanup:scan();assert(equal(after.items,preview.items)and equal(after.references,preview.references))
 end
 for i,o in ipairs(original)do assert(equal(o.state,before_states[i]),'legacy object fields must not change')end
end
print('PASS 历史重复完整清理链：引用/显示绑定/当前佩戴同步，逐项与部分写入故障恢复，重复扫描幂等')
local layout=package.loaded['LoadoutClone.petalace_layout'];local schema=layout.replacement_schema;layout.replacement_schema=nil
local mixed=C.new();local saved={};json={load_file=function()end,dump_file=function(k,v)saved[k]=clone(v);return true end}
local result=mixed:execute({})
assert(not result.ok and result.error:find('清理模块版本不一致',1,true))
assert(mixed.writes==0 and mixed.restores==0,'mixed modules must stop before writes')
assert(saved['LoadoutClone/petalace-cleanup-transaction.json'].cleanup_build=='petalace-replacement-1')
layout.replacement_schema=schema
print('PASS 新旧清理模块混用在零写入时拦截，诊断记录携带清理构建标识')
