local A=require("LoadoutClone.augments")
local candidates={
    {id=1,dimension="defense",value=-6,cost=-3},
    {id=2,dimension="defense",value=2,cost=1},
    {id=3,dimension="skill",value=1,cost=9},
}
local r=A.solve(candidates,{defense=-12,skill=1},7,3)
assert(r and r.cost==3 and #r.entries==3)
assert(not A.solve(candidates,{defense=-12,skill=1},2,3))
assert(not A.solve(candidates,{defense=-12,skill=1},7,2))
r=A.solve(candidates,{defense=0,skill=1},7,nil);assert(r and #r.entries==1)
assert(not A.solve(candidates,{defense=1},7,nil))
local c={{id=1,dimension="x",value=1,cost=-1},{id=2,dimension="x",value=-1,cost=-1},{id=3,dimension="y",value=1,cost=5}}
r=A.solve(c,{x=0,y=1},3,3);assert(r and #r.entries==3 and r.cost==3)
print("PASS 炼化精确增量、负成本、条数、无解、非法预算与零和组合（6 项）")
-- 严格生成不能只保留最低成本：同样效果的高成本条目可能才满足终止条件。
r=A.solve({{dimension="x",value=1,cost=1},{dimension="x",value=1,cost=2}},{x=1},1,2,function(v) return v.cost==2 end)
assert(r and r.cost==2)
local catalog={armor_lottery={{table=1,id=69,weight=1}},skill_costs={},augments={
    {table=1,id=69,category=13,cost=1,values={1}},
    {table=1,id=70,category=13,cost=2,values={1}},
    {table=1,id=71,category=13,cost=3,values={2}},
    {table=1,id=72,category=13,cost=4,values={2}},
}}
local base={_CustomTableNo=1,_CustomCost=10,_SkillList={1,2,3}}
r=A.legal_armor(catalog,base,{defense=8},{})
assert(r and #r.entries==7 and r.entries[7].id==72 and r.cost==10)
assert(not A.legal_armor(catalog,base,{defense=4},{})) -- 不足六次不能提前加补偿
assert(not A.legal_armor(catalog,base,{defense=8},{[4]=1,[5]=1,[6]=1}))
print("PASS 严格预算保留、六次后补偿、提前补偿拒绝、技能种类上限（4 项）")
local weapon={CustomEnable=true,CustomBuildupCapacity=3,CustomAddAtk=0,CustomAddCriticalRate=0,CustomAddMainElementVal=0,CustomAddSharpness=0,CustomAddSlot=0,CustomAddFireLv=1}
local wc={weapon_tables={{table=45,ids={160}}},augments={{table=45,id=160,category=9,level=1,cost=2,values={1}}}}
r=A.weapon(wc,{table=45,cost=3,max_add_cost=7},weapon,{},false)
assert(r and r.entries[1].id==160 and r.cost==2 and r.open_ids[1]==160)
weapon.CustomAddFireLv=2
assert(not A.weapon(wc,{table=45,cost=3,max_add_cost=7},weapon,{},false))
print("PASS 炮击炼化条目与不可用等级拒绝（2 项）")
local relaxed_catalog={armor_lottery={{table=1,id=59,weight=1},{table=1,id=144,weight=1}},skill_costs={{skill=9,cost=10}},augments={
    {table=1,id=59,cost=-4,values={-1}},
    {table=1,id=60,cost=-1,values={-2}},
    {table=1,id=144,cost=10,values={1}},
}}
local relaxed_base={_CustomTableNo=1,_CustomCost=2,_SkillList={}}
r=A.relaxed_armor(relaxed_catalog,relaxed_base,{defense=-2,skill9=1},{[9]=1})
assert(r and r.cost==2 and #r.entries==3,"放宽模式应优先不超预算的组合")
r=A.relaxed_armor(relaxed_catalog,relaxed_base,{defense=0,skill9=1},{[9]=1})
assert(r and r.cost==10 and #r.entries==1,"无预算内解时允许显式放宽")
print("PASS 放宽模式预算优先与无解后放宽（2 项）")
