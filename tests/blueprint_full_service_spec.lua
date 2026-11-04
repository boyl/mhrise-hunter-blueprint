local B=require('LoadoutClone.blueprints')
local S=require('LoadoutClone.blueprint_service')
local Planner=require('LoadoutClone.planner')
local old_new=Planner.new
local appearance={schema=1,weapon_id=134217728,weapon_hidden=false,armor_ids={0,4096,8192,12288,16384},colors={{},{}} ,weapon_color={enabled=false}}
for c=1,2 do for p=1,5 do appearance.colors[c][p]={enabled=false}end end
local entry={id=7,name='完整配装',snapshot=appearance,origin={name='来源',sex=0,weapon_type=3},equipment={schema=1,data={_equipStatusParam={isMRRelease=true,switchActionId={1,2,3},switchActionId_MR_1={1,2,3,4,5},switchActionId_MR_2={1,2,3,4,5}}}}}
local current={identity='target',origin={name='目标',sex=1,weapon_type=8},snapshot=appearance}
local mr=true;local imported=0;local planned
local n={capture=function()return B.copy(current)end,progression_state=function()return mr end,adapt=function(_,s)return B.copy(s),{}end,describe=function()return {weapon='无',armor={}}end}
local lib={find=function()return B.copy(entry)end}
Planner.new=function(reader,service)return {prepare=function(_,key,options)
 local snapshot=reader:capture(key);assert(reader:progression_state() and snapshot.source.key==key)
 planned=B.copy(options)
 return {options=options,source=snapshot.source,session=snapshot.session,snapshot=snapshot}
end}end
local service=S.new(lib,n,{adapter={binding={}},weapon_visibility_available=true},function(a,reader)
 assert(reader)
 return {execute=function(_,plan)imported=imported+1;assert(plan.name==entry.name);return {ok=true,result={name=plan.name,hunter_slot=9}}end}
end)
for _,aug in ipairs({{true,false},{true,true},{false,false}})do
 for _,look in ipairs({{false,false},{true,false},{true,true}})do
  local options={copy_augments=aug[1],allow_illegal_augments=aug[2],copy_appearance=look[1],copy_weapon_visibility=look[2]}
  local preview=service:preview(7,options);assert(preview.full)
  assert(service:import(preview).ok)
  for k,v in pairs(options)do assert(planned[k]==v)end
 end
end
assert(imported==9)
mr=false;assert(not pcall(service.preview,service,7,{copy_appearance=true}));assert(imported==9)
assert(service:preview(7,{appearance_only=true,include_weapon=false}).full==nil)
mr=true;local preview=service:preview(7,{copy_appearance=false});current.identity='changed';assert(not pcall(service.import,service,preview));assert(imported==9)
Planner.new=old_new
print('PASS 完整蓝图九组导入选项复用原规划器与写入器、跨进度及身份变化零提交拒绝')
