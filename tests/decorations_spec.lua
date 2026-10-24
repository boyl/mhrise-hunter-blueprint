local D=require("LoadoutClone.decorations")
local c={{id=1,level=2,color=3,skills={10},levels={1}}, {id=2,level=2,color=3,skills={20},levels={1}}}
local function part(ids,levels,flags)
    return {DecoLvType={2,0,0},SlotIconColor={3,0,0},SkillIdList=ids,SkillLv=levels,DecoSkillEquipUp=flags}
end
local r=D.resolve(part({10},{1},{true}),c);assert(r.ids[1]==1)
local _,err=D.resolve(part({10,20},{1,1},{true,true}),c);assert(err=="ambiguous_decoration")
r=D.resolve(part({10,20},{1,1},{false,true}),c);assert(r.ids[1]==2 and r.residual_skills[10]==1)
local p=part({10},{1},{true});p.DecoLvType={2,2,0};p.SlotIconColor={3,3,0}
_,err=D.resolve(p,c);assert(err=="no_solution")
r=D.resolve(part({10,20},{1,1},{true,true}),c,{base_skills={[10]=1}});assert(r.ids[1]==2)
assert(not D.check_slots({4,2,0},{3,2,1}));assert(D.check_slots({4,2,0},{4,2,1}))
print("PASS 珠子联合约束、歧义拒绝、固有技能与基础孔位冲突（6 项）")

local swapped=part({10,20},{1,1},{true,true});swapped.DecoLvType={2,2,0};swapped.SlotIconColor={3,3,0}
r=D.resolve(swapped,c,{base_skills={}});assert(r and r.ids[1]~=r.ids[2])
print("PASS 相同等级孔位交换珠子只计一种组合")
