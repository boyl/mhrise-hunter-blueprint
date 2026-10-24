local D=require("LoadoutClone.decorations")
-- 本次远端武器的最小数据，不包含玩家标识。等级 4 的两种同色珠子分别提供 2/3 级技能。
local part={DecoLvType={4,4,4},SlotIconColor={11,9,2},EquipSkill={49,116,54},EquipSkillLv={2,2,3}}
local catalog={
 {id=203,level=4,color=11,skills={49,0},levels={2,0}},
 {id=238,level=4,color=9,skills={116,0},levels={2,0}},
 {id=159,level=4,color=2,skills={54,0},levels={3,0}},
 {id=224,level=4,color=2,skills={54,0},levels={2,0}},
}
local _,old_error=D.resolve(part,catalog)
assert(old_error=="ambiguous_decoration","必须复现旧的宽松剩余技能判定")
local result=D.resolve_weapon(part,catalog)
assert(result and result.ids[1]==203 and result.ids[2]==238 and result.ids[3]==159)
assert(next(result.residual_skills)==nil)
print("PASS 武器珠子完整解释技能总量，消除 2/3 级同色伪歧义")
part.EquipSkillLv[3]=4
local result,reason=D.resolve_weapon(part,catalog);assert(not result and reason=="no_solution")
print("PASS 武器未知剩余技能仍拒绝，不猜测补足")
part.EquipSkillLv[3]=3
catalog[#catalog+1]={id=999,level=4,color=2,skills={54,0},levels={3,0}}
result,reason=D.resolve_weapon(part,catalog);assert(not result and reason=="ambiguous_decoration")
print("PASS 真正不同珠子 ID 同效果时仍拒绝伪造精确复制")
